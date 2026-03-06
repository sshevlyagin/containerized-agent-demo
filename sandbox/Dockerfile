FROM docker/sandbox-templates:claude-code
USER root
RUN apt-get update && apt-get install -y openssl unzip && rm -rf /var/lib/apt/lists/*
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*
RUN ARCH=$(uname -m) \
    && if [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then \
         AWS_URL="https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip"; \
       else \
         AWS_URL="https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip"; \
       fi \
    && curl -fsSL "$AWS_URL" -o /tmp/awscliv2.zip \
    && unzip -q /tmp/awscliv2.zip -d /tmp \
    && /tmp/aws/install \
    && rm -rf /tmp/awscliv2.zip /tmp/aws
RUN npm install -g pnpm@9.15.4
USER agent
