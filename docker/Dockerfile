FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# Core utilities
RUN apt-get update && apt-get install -y \
    ca-certificates curl gnupg lsb-release \
    iptables ipset jq dnsutils cron openssl \
    git sudo unzip fuse-overlayfs \
    && rm -rf /var/lib/apt/lists/*

# Docker CE (dockerd + CLI + compose plugin)
RUN curl -fsSL https://get.docker.com | sh

# Node.js 22 via NodeSource
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# pnpm via corepack
RUN corepack enable && corepack prepare pnpm@9.15.4 --activate

# AWS CLI v2 (arch-aware)
RUN ARCH=$(uname -m) \
    && if [ "$ARCH" = "x86_64" ]; then AWS_ARCH="x86_64"; \
       elif [ "$ARCH" = "aarch64" ]; then AWS_ARCH="aarch64"; \
       else echo "Unsupported arch: $ARCH" && exit 1; fi \
    && curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-${AWS_ARCH}.zip" -o /tmp/awscliv2.zip \
    && unzip -q /tmp/awscliv2.zip -d /tmp \
    && /tmp/aws/install \
    && rm -rf /tmp/aws /tmp/awscliv2.zip

# Create non-root agent user (Claude refuses --dangerously-skip-permissions as root)
RUN useradd -m -s /bin/bash agent \
    && usermod -aG docker agent \
    && echo "agent ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Claude Code CLI (install as agent user)
USER agent
RUN curl -fsSL https://claude.ai/install.sh | bash
ENV PATH="/home/agent/.local/bin:${PATH}"
USER root

# Copy scripts into image
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY setup-firewall.sh /usr/local/bin/setup-firewall.sh
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/setup-firewall.sh

WORKDIR /workspace

ENTRYPOINT ["entrypoint.sh"]
