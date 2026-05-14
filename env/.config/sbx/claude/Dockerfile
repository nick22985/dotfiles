# syntax=docker/dockerfile:1
FROM debian:bookworm-slim

ARG USER_UID=1000
ARG USER_GID=1000

ENV DEBIAN_FRONTEND=noninteractive

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    rm -f /etc/apt/apt.conf.d/docker-clean \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        git \
        ca-certificates \
        curl \
        less \
        ripgrep \
        vim-tiny \
        build-essential \
        pkg-config \
        libssl-dev \
        python3 \
        python3-pip \
        python3-venv \
        unzip \
        xz-utils

RUN if getent group "$USER_GID" >/dev/null; then \
        EXISTING_GROUP="$(getent group "$USER_GID" | cut -d: -f1)"; \
        if [ "$EXISTING_GROUP" != "dev" ]; then groupmod -n dev "$EXISTING_GROUP"; fi; \
    else \
        groupadd -g "$USER_GID" dev; \
    fi \
    && if getent passwd "$USER_UID" >/dev/null; then \
        EXISTING_USER="$(getent passwd "$USER_UID" | cut -d: -f1)"; \
        if [ "$EXISTING_USER" != "dev" ]; then usermod -l dev -d /home/dev -m "$EXISTING_USER"; fi; \
        usermod -g dev dev; \
    else \
        useradd -m -u "$USER_UID" -g dev -s /bin/bash dev; \
    fi \
    && mkdir -p /home/dev/.npm /home/dev/.bun/install/cache /home/dev/.cargo /home/dev/.rustup /workspace /opt/sbx/bin \
    && chown -R dev:dev /home/dev /workspace

# Node.js (LTS) + npm
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    --mount=type=cache,target=/tmp/sbx-dl,sharing=locked \
    if [ ! -f /tmp/sbx-dl/nodesource-setup.sh ]; then \
        curl -fsSL https://deb.nodesource.com/setup_lts.x -o /tmp/sbx-dl/nodesource-setup.sh; \
    fi \
    && bash /tmp/sbx-dl/nodesource-setup.sh \
    && apt-get install -y --no-install-recommends nodejs \
    && node --version \
    && npm --version

# Bun (via official install script, system-wide)
RUN --mount=type=cache,target=/tmp/sbx-dl,sharing=locked set -eux; \
    if [ ! -f /tmp/sbx-dl/bun-install.sh ]; then \
        curl -fsSL https://bun.sh/install -o /tmp/sbx-dl/bun-install.sh; \
    fi; \
    BUN_INSTALL=/opt/bun bash /tmp/sbx-dl/bun-install.sh; \
    ln -s /opt/bun/bin/bun /usr/local/bin/bun.real; \
    /usr/local/bin/bun.real --version

# Java (Eclipse Temurin 21 LTS) + Maven + Gradle
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    --mount=type=cache,target=/tmp/sbx-dl,sharing=locked \
    set -eux; \
    if [ ! -f /tmp/sbx-dl/adoptium.asc ]; then \
        curl -fsSL https://packages.adoptium.net/artifactory/api/gpg/key/public \
            -o /tmp/sbx-dl/adoptium.asc; \
    fi; \
    install -m 0644 /tmp/sbx-dl/adoptium.asc /etc/apt/trusted.gpg.d/adoptium.asc; \
    echo "deb https://packages.adoptium.net/artifactory/deb bookworm main" \
        > /etc/apt/sources.list.d/adoptium.list; \
    apt-get update; \
    apt-get install -y --no-install-recommends temurin-21-jdk maven; \
    java -version; \
    mvn -version

ARG GRADLE_VERSION=8.11.1
RUN --mount=type=cache,target=/tmp/sbx-dl,sharing=locked set -eux; \
    if [ ! -f /tmp/sbx-dl/gradle-${GRADLE_VERSION}-bin.zip ]; then \
        curl -fsSL "https://services.gradle.org/distributions/gradle-${GRADLE_VERSION}-bin.zip" \
            -o /tmp/sbx-dl/gradle-${GRADLE_VERSION}-bin.zip; \
    fi; \
    unzip -q /tmp/sbx-dl/gradle-${GRADLE_VERSION}-bin.zip -d /opt; \
    ln -s /opt/gradle-${GRADLE_VERSION}/bin/gradle /usr/local/bin/gradle; \
    gradle --version

# Rust (via rustup) — installed for the dev user.
USER dev
RUN --mount=type=cache,target=/tmp/sbx-dl,sharing=locked,uid=1000,gid=1000 set -eux; \
    if [ ! -f /tmp/sbx-dl/rustup-init.sh ]; then \
        curl -fsSL https://sh.rustup.rs -o /tmp/sbx-dl/rustup-init.sh; \
    fi; \
    CARGO_HOME=/home/dev/.cargo RUSTUP_HOME=/home/dev/.rustup \
        bash /tmp/sbx-dl/rustup-init.sh -y --no-modify-path --default-toolchain stable --profile minimal; \
    /home/dev/.cargo/bin/rustc --version

USER root

# osv-scanner
RUN --mount=type=cache,target=/tmp/sbx-dl,sharing=locked set -eux; \
    arch="$(dpkg --print-architecture)"; \
    case "$arch" in \
        amd64) osv_arch=linux_amd64 ;; \
        arm64) osv_arch=linux_arm64 ;; \
        *) echo "unsupported arch $arch"; exit 1 ;; \
    esac; \
    if [ ! -f "/tmp/sbx-dl/osv-scanner-$osv_arch" ]; then \
        curl -fsSL -o "/tmp/sbx-dl/osv-scanner-$osv_arch" \
            "https://github.com/google/osv-scanner/releases/latest/download/osv-scanner_$osv_arch"; \
    fi; \
    install -m 0755 "/tmp/sbx-dl/osv-scanner-$osv_arch" /usr/local/bin/osv-scanner; \
    osv-scanner --version

# trivy
RUN --mount=type=cache,target=/tmp/sbx-dl,sharing=locked \
    curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh \
        | sh -s -- -b /usr/local/bin \
    && trivy --version

# guarddog
ARG SBX_GUARDDOG=1
RUN --mount=type=cache,target=/root/.cache/pip,sharing=locked \
    if [ "$SBX_GUARDDOG" = "1" ]; then \
        python3 -m venv /opt/guarddog \
        && /opt/guarddog/bin/pip install guarddog \
        && ln -s /opt/guarddog/bin/guarddog /usr/local/bin/guarddog \
        && guarddog --version ; \
    fi

# socket.dev CLI (Node-based)
RUN --mount=type=cache,target=/root/.npm,sharing=locked \
    /usr/bin/npm install -g @socketsecurity/cli \
    && socket --version

# graphify — knowledge-graph CLI (https://graphify.net). Reads model API
# keys from the AI assistant config (we mount ~/.claude rw), so no setup
# is needed at build time. The PyPI package is `graphifyy`; the CLI
# command is `graphify`.
RUN --mount=type=cache,target=/root/.cache/pip,sharing=locked \
    python3 -m venv /opt/graphify \
    && /opt/graphify/bin/pip install graphifyy \
    && ln -s /opt/graphify/bin/graphify /usr/local/bin/graphify \
    && graphify --version

# Claude Code CLI
RUN --mount=type=cache,target=/root/.npm,sharing=locked \
    /usr/bin/npm install -g @anthropic-ai/claude-code \
    && claude --version

# mise — polyglot tool-version manager. Lets projects pin tool versions
# via mise.toml / .tool-versions; falls back to the FROM-image's tools
# when no config is present.
RUN --mount=type=cache,target=/tmp/sbx-dl,sharing=locked set -eux; \
    if [ ! -f /tmp/sbx-dl/mise-install.sh ]; then \
        curl -fsSL https://mise.run -o /tmp/sbx-dl/mise-install.sh; \
    fi; \
    MISE_INSTALL_PATH=/usr/local/bin/mise sh /tmp/sbx-dl/mise-install.sh; \
    mise --version

# Entrypoint: runs `graphify install` once into the mounted ~/.claude.
COPY wrappers/entrypoint /opt/sbx/bin/entrypoint
RUN chmod +x /opt/sbx/bin/entrypoint \
    && printf 'export PATH=/opt/sbx/bin:/home/dev/.local/share/mise/shims:/home/dev/.cargo/bin:/opt/bun/bin:$PATH\n\
export CARGO_HOME=/home/dev/.cargo\n\
export RUSTUP_HOME=/home/dev/.rustup\n\
export MISE_INSTALL_MISSING_TOOLS=1\n\
eval "$(/usr/local/bin/mise activate bash)" 2>/dev/null || true\n' > /etc/profile.d/sbx.sh

USER dev
WORKDIR /workspace

ENV NPM_CONFIG_CACHE=/home/dev/.npm \
    BUN_INSTALL_CACHE_DIR=/home/dev/.bun/install/cache \
    CARGO_HOME=/home/dev/.cargo \
    RUSTUP_HOME=/home/dev/.rustup \
    MISE_INSTALL_MISSING_TOOLS=1 \
    SHELL=/bin/bash \
    PATH=/opt/sbx/bin:/home/dev/.local/share/mise/shims:/home/dev/.cargo/bin:/opt/bun/bin:/usr/local/bin:/usr/bin:/bin

ENTRYPOINT ["/opt/sbx/bin/entrypoint"]
CMD ["/bin/bash"]
