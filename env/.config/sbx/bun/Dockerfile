# syntax=docker/dockerfile:1
FROM oven/bun:latest

ARG USER_UID=1000
ARG USER_GID=1000

USER root

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
        vim-tiny

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

RUN mv /usr/local/bin/bun /usr/local/bin/bun.real

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    --mount=type=cache,target=/tmp/sbx-dl,sharing=locked \
    if [ ! -f /tmp/sbx-dl/nodesource-setup.sh ]; then \
        curl -fsSL https://deb.nodesource.com/setup_lts.x -o /tmp/sbx-dl/nodesource-setup.sh; \
    fi \
    && bash /tmp/sbx-dl/nodesource-setup.sh \
    && apt-get install -y --no-install-recommends nodejs \
    && node --version

RUN --mount=type=cache,target=/home/dev/.bun/install/cache,sharing=locked,uid=0,gid=0 \
    mkdir -p /opt/socket-cli \
    && cd /opt/socket-cli \
    && /usr/local/bin/bun.real init -y >/dev/null \
    && /usr/local/bin/bun.real add @socketsecurity/cli \
    && printf '#!/bin/sh\nexec node /opt/socket-cli/node_modules/@socketsecurity/cli/dist/cli.js "$@"\n' > /usr/local/bin/socket \
    && chmod +x /usr/local/bin/socket \
    && chmod -R a+rX /opt/socket-cli \
    && /usr/local/bin/socket --version

COPY wrappers/bun /opt/sbx/bin/bun
RUN chmod +x /opt/sbx/bin/bun \
    && printf 'export PATH=/opt/sbx/bin:/home/dev/.bun/bin:$PATH\n' > /etc/profile.d/sbx.sh

USER dev
WORKDIR /workspace

ENV BUN_INSTALL_CACHE_DIR=/home/dev/.bun/install/cache \
    SHELL=/bin/bash \
    PATH=/opt/sbx/bin:/home/dev/.bun/bin:$PATH

CMD ["/bin/bash"]
