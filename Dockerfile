FROM ubuntu:24.04

# Prevent interactive prompts during apt installations
ENV DEBIAN_FRONTEND=noninteractive
ENV RUNNER_MANUALLY_TRAP_SIG=1
ENV ACTIONS_RUNNER_PRINT_LOG_TO_STDOUT=1

# Configurable Runner Version (defaults to current release)
ARG RUNNER_VERSION=2.338.0
ARG TARGETARCH=x64

# Install base dependencies, git, docker CLI & tools
RUN apt-get update -y && apt-get install -y --no-install-recommends \
    curl \
    ca-certificates \
    git \
    jq \
    sudo \
    tar \
    unzip \
    libicu-dev \
    liblttng-ust-dev \
    libssl-dev \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Create runner user and add to sudoers
RUN useradd -m -s /bin/bash runner \
    && echo "runner ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

WORKDIR /home/runner

# Download and extract the GitHub Actions Runner binary
RUN ARCH=$(dpkg --print-architecture) \
    && if [ "$ARCH" = "amd64" ]; then RUNNER_ARCH="x64"; elif [ "$ARCH" = "arm64" ]; then RUNNER_ARCH="arm64"; else RUNNER_ARCH="$ARCH"; fi \
    && curl -f -L -o runner.tar.gz https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-${RUNNER_ARCH}-${RUNNER_VERSION}.tar.gz \
    && tar xzf runner.tar.gz \
    && rm runner.tar.gz \
    && ./bin/installdependencies.sh

# Default environment variables (can be overridden at runtime)
ENV REPO_URL="https://github.com/mukeshv-tech/Taskrebulid"
ENV RUNNER_NAME="fly-runner"
ENV RUNNER_LABELS="docker,fly,linux"
ENV RUNNER_REPLACE="true"
ENV RUNNER_EPHEMERAL="false"

# Copy startup script
COPY --chown=runner:runner entrypoint.sh /home/runner/entrypoint.sh
RUN chmod +x /home/runner/entrypoint.sh \
    && chown -R runner:runner /home/runner

USER runner

ENTRYPOINT ["/home/runner/entrypoint.sh"]
