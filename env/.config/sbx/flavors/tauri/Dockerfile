# syntax=docker/dockerfile:1
# sbx-tauri — Rust toolchain + Bun/Node + Tauri Linux system deps.
# Layered on top of sbx-rust so cargo is already wired up.
FROM sbx-rust:latest

ARG SBX_BUN_VERSION=latest
ARG SBX_NODE_VERSION=lts
ARG USER_HOME=/home/dev

USER root
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update \
    && apt-get install -y --no-install-recommends \
        libwebkit2gtk-4.1-dev \
        libgtk-3-dev \
        libsoup-3.0-dev \
        libjavascriptcoregtk-4.1-dev \
        librsvg2-dev \
        libayatana-appindicator3-dev \
        libssl-dev \
        file \
        wget \
        xdg-utils

USER dev
RUN --mount=type=cache,target=${USER_HOME}/.cache/mise,uid=1000,gid=1000,sharing=locked \
    /usr/local/bin/mise use --global "bun@${SBX_BUN_VERSION}" "node@${SBX_NODE_VERSION}" \
    && /usr/local/bin/mise which bun \
    && /usr/local/bin/mise which node

USER root
RUN printf 'if [ -d %s/.cargo/bin ]; then\n  case ":$PATH:" in *":%s/.cargo/bin:"*) ;; *) PATH="%s/.cargo/bin:$PATH";; esac\n  export PATH\nfi\nexport CARGO_HOME=%s/.cargo\n' "$USER_HOME" "$USER_HOME" "$USER_HOME" "$USER_HOME" > /etc/profile.d/rust.sh \
    && chmod 0644 /etc/profile.d/rust.sh
USER dev

ENV BUN_INSTALL_CACHE_DIR=${USER_HOME}/.bun/install/cache
