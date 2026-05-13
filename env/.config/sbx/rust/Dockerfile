# syntax=docker/dockerfile:1
FROM rust:latest

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
        pkg-config \
        libssl-dev

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
    && mkdir -p /home/dev/.cargo /home/dev/.rustup /workspace /opt/sbx/bin \
    && cp -a /usr/local/cargo/. /home/dev/.cargo/ \
    && cp -a /usr/local/rustup/. /home/dev/.rustup/ \
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

USER dev
RUN --mount=type=cache,target=/home/dev/.cargo/registry,uid=1000,gid=1000,sharing=locked \
    /home/dev/.cargo/bin/cargo install cargo-audit --locked --no-default-features

USER root
RUN mv /home/dev/.cargo/bin/cargo /home/dev/.cargo/bin/cargo.real
COPY wrappers/cargo /opt/sbx/bin/cargo
RUN chmod +x /opt/sbx/bin/cargo \
    && chown dev:dev /home/dev/.cargo/bin/cargo.real \
    && printf 'export CARGO_HOME=/home/dev/.cargo\nexport RUSTUP_HOME=/home/dev/.rustup\nexport PATH=/opt/sbx/bin:/home/dev/.cargo/bin:$PATH\n' > /etc/profile.d/sbx.sh

USER dev
WORKDIR /workspace

ENV CARGO_HOME=/home/dev/.cargo \
    RUSTUP_HOME=/home/dev/.rustup \
    PATH=/opt/sbx/bin:/home/dev/.cargo/bin:$PATH \
    SHELL=/bin/bash

CMD ["/bin/bash"]
