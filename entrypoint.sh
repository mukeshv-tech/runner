#!/usr/bin/env bash
set -e

# Validate repository URL
if [ -z "${REPO_URL}" ]; then
  echo "Error: REPO_URL environment variable is required (e.g. https://github.com/owner/repo or https://github.com/org)"
  exit 1
fi

# Extract owner and repo from REPO_URL
# Supports formats:
#   https://github.com/owner/repo
#   https://github.com/org
REPO_PATH=$(echo "${REPO_URL}" | sed -E 's#^https?://[^/]+/(.+?)(.git)?$#\1#')
IS_ORG=false
if [[ ! "${REPO_PATH}" =~ / ]]; then
  IS_ORG=true
fi

# Function to fetch a new registration token using GH_TOKEN / ACCESS_TOKEN / GITHUB_PAT
fetch_registration_token() {
  local pat="${GH_TOKEN:-${ACCESS_TOKEN:-${GITHUB_PAT}}}"
  if [ -z "${pat}" ]; then
    return 1
  fi

  echo "Requesting a fresh registration token from GitHub API..."
  local api_endpoint
  if [ "${IS_ORG}" = "true" ]; then
    api_endpoint="https://api.github.com/orgs/${REPO_PATH}/actions/runners/registration-token"
  else
    api_endpoint="https://api.github.com/repos/${REPO_PATH}/actions/runners/registration-token"
  fi

  local resp
  resp=$(curl -s -X POST \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer ${pat}" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "${api_endpoint}")

  local token
  token=$(echo "${resp}" | jq -r '.token // empty')

  if [ -n "${token}" ] && [ "${token}" != "null" ]; then
    RUNNER_TOKEN="${token}"
    echo "Successfully fetched registration token."
    return 0
  else
    echo "Warning: Failed to fetch token using GitHub PAT: ${resp}"
    return 1
  fi
}

# Function to fetch a deregistration/remove token
fetch_remove_token() {
  local pat="${GH_TOKEN:-${ACCESS_TOKEN:-${GITHUB_PAT}}}"
  if [ -z "${pat}" ]; then
    return 1
  fi

  local api_endpoint
  if [ "${IS_ORG}" = "true" ]; then
    api_endpoint="https://api.github.com/orgs/${REPO_PATH}/actions/runners/remove-token"
  else
    api_endpoint="https://api.github.com/repos/${REPO_PATH}/actions/runners/remove-token"
  fi

  local resp
  resp=$(curl -s -X POST \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer ${pat}" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "${api_endpoint}")

  echo "${resp}" | jq -r '.token // empty'
}

# Always try to refresh registration token via PAT on startup
if fetch_registration_token; then
  echo "Using dynamic registration token."
elif [ -z "${RUNNER_TOKEN}" ]; then
  echo "Error: Neither GH_TOKEN (Personal Access Token) nor RUNNER_TOKEN is provided!"
  exit 1
fi

RUNNER_NAME="${RUNNER_NAME:-$(hostname)}"
RUNNER_WORKDIR="${RUNNER_WORKDIR:-_work}"
RUNNER_LABELS="${RUNNER_LABELS:-docker}"
RUNNER_GROUP="${RUNNER_GROUP:-}"

EXTRA_ARGS=""
if [ -n "${RUNNER_GROUP}" ]; then
  EXTRA_ARGS="${EXTRA_ARGS} --runnergroup ${RUNNER_GROUP}"
fi

if [ "${RUNNER_EPHEMERAL}" = "true" ] || [ "${RUNNER_EPHEMERAL}" = "1" ]; then
  EXTRA_ARGS="${EXTRA_ARGS} --ephemeral"
fi

if [ "${RUNNER_REPLACE:-true}" = "true" ] || [ "${RUNNER_REPLACE}" = "1" ]; then
  EXTRA_ARGS="${EXTRA_ARGS} --replace"
fi

# Cleanup old configuration if exists
if [ -f ".runner" ]; then
  echo "Existing configuration detected. Removing..."
  REMOVE_TOKEN=$(fetch_remove_token || echo "${RUNNER_TOKEN}")
  ./config.sh remove --token "${REMOVE_TOKEN}" || true
  rm -f .runner .credentials .credentials_rsaparams
fi

echo "Registering runner ${RUNNER_NAME} with ${REPO_URL}..."
./config.sh \
  --url "${REPO_URL}" \
  --token "${RUNNER_TOKEN}" \
  --name "${RUNNER_NAME}" \
  --work "${RUNNER_WORKDIR}" \
  --labels "${RUNNER_LABELS}" \
  --unattended \
  ${EXTRA_ARGS}

cleanup() {
  echo "Shutting down runner and deregistering..."
  local rem_token
  rem_token=$(fetch_remove_token || echo "${RUNNER_TOKEN}")
  ./config.sh remove --token "${rem_token}" || true
}

trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

echo "Starting runner listener..."
./run.sh &
PID=$!
wait $PID
