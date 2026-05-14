# syntax=docker/dockerfile:1
FROM debian:bookworm-slim

ARG USER_UID=1000
ARG USER_GID=1000

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
    && mkdir -p /home/dev/.bun/install/cache /workspace /opt/sbx/bin \
    && chown -R dev:dev /home/dev /workspace

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

RUN --mount=type=cache,target=/tmp/sbx-dl,sharing=locked \
    curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh \
        | sh -s -- -b /usr/local/bin \
    && trivy --version

ARG SBX_GUARDDOG=1
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    if [ "$SBX_GUARDDOG" = "1" ]; then \
        apt-get update \
        && apt-get install -y --no-install-recommends python3 python3-pip python3-venv ; \
    fi
RUN --mount=type=cache,target=/root/.cache/pip,sharing=locked \
    if [ "$SBX_GUARDDOG" = "1" ]; then \
        python3 -m venv /opt/guarddog \
        && /opt/guarddog/bin/pip install guarddog \
        && ln -s /opt/guarddog/bin/guarddog /usr/local/bin/guarddog \
        && guarddog --version ; \
    fi

# mise — polyglot tool-version manager. Bun + node come from mise; projects
# can pin different versions via mise.toml / .tool-versions. (node is also
# pulled in because @socketsecurity/cli is a node program.)
RUN --mount=type=cache,target=/tmp/sbx-dl,sharing=locked set -eux; \
    if [ ! -f /tmp/sbx-dl/mise-install.sh ]; then \
        curl -fsSL https://mise.run -o /tmp/sbx-dl/mise-install.sh; \
    fi; \
    MISE_INSTALL_PATH=/usr/local/bin/mise sh /tmp/sbx-dl/mise-install.sh; \
    mise --version

COPY wrappers/bun /opt/sbx/bin/bun
RUN chmod +x /opt/sbx/bin/bun \
    && printf 'export PATH=/opt/sbx/bin:/home/dev/.local/share/mise/shims:/home/dev/.bun/bin:$PATH\nexport MISE_INSTALL_MISSING_TOOLS=1\neval "$(/usr/local/bin/mise activate bash)" 2>/dev/null || true\n' > /etc/profile.d/sbx.sh

ARG SBX_BUN_VERSION=latest
ARG SBX_NODE_VERSION=lts

USER dev
WORKDIR /home/dev
RUN --mount=type=cache,target=/home/dev/.cache/mise,uid=1000,gid=1000,sharing=locked \
    /usr/local/bin/mise use --global "bun@${SBX_BUN_VERSION}" "node@${SBX_NODE_VERSION}" \
    && /usr/local/bin/mise which bun \
    && /usr/local/bin/mise which node

RUN --mount=type=cache,target=/home/dev/.bun/install/cache,uid=1000,gid=1000,sharing=locked \
    mkdir -p /home/dev/.sbx/socket-cli \
    && cd /home/dev/.sbx/socket-cli \
    && BUN="$(/usr/local/bin/mise which bun)" \
    && "$BUN" init -y >/dev/null \
    && "$BUN" add @socketsecurity/cli

USER root
RUN printf '#!/bin/sh\nNODE="$(/usr/local/bin/mise which node 2>/dev/null)" || NODE=node\nexec "$NODE" /home/dev/.sbx/socket-cli/node_modules/@socketsecurity/cli/dist/cli.js "$@"\n' > /opt/sbx/bin/socket \
    && chmod +x /opt/sbx/bin/socket

USER dev
WORKDIR /workspace

ENV BUN_INSTALL_CACHE_DIR=/home/dev/.bun/install/cache \
    SHELL=/bin/bash \
    MISE_INSTALL_MISSING_TOOLS=1 \
    PATH=/opt/sbx/bin:/home/dev/.local/share/mise/shims:/home/dev/.bun/bin:$PATH

CMD ["/bin/bash"]
