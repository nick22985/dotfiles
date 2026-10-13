# syntax=docker/dockerfile:1
FROM sbx-base:latest

ARG USER_HOME=/home/dev
ARG SBX_PLAYWRIGHT=1
ARG SBX_PLAYWRIGHT_VERSION=1.60.0
ARG SBX_PLAYWRIGHT_MCP_VERSION=0.0.83

# Agent flavors never inherit a project's .sbx/Dockerfile: that file names its
# own FROM and layering it here would replace Codex with the project runtime.
# Workers still run targeted tests and the project's cheap check themselves, so
# this image carries the Rust and Bun toolchains those checks use.
USER root
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    --mount=type=cache,target=/tmp/sbx-dl,sharing=locked \
    if [ ! -f /tmp/sbx-dl/nodesource-setup.sh ]; then \
        sbx-fetch https://deb.nodesource.com/setup_lts.x -o /tmp/sbx-dl/nodesource-setup.sh; \
    fi \
    && bash /tmp/sbx-dl/nodesource-setup.sh \
    && apt-get install -y --no-install-recommends \
        build-essential \
        pkg-config \
        libssl-dev \
        nodejs \
        rsync \
        w3m \
        bubblewrap \
        libgtk-3-0t64 libgbm-dev libnotify-dev libnss3 libxss1 \
        libasound2t64 libxtst6 xauth xvfb redis-server \
    && node --version \
    && npm --version

RUN --mount=type=cache,target=/root/.npm,sharing=locked \
    /usr/bin/npm install -g pm2

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    --mount=type=cache,target=/root/.npm,sharing=locked \
    sbx-install-browser

RUN --mount=type=cache,target=/tmp/sbx-dl,sharing=locked set -eux; \
    if [ ! -f /tmp/sbx-dl/bun-install.sh ]; then \
        sbx-fetch https://bun.sh/install -o /tmp/sbx-dl/bun-install.sh; \
    fi; \
    BUN_INSTALL=/opt/bun bash /tmp/sbx-dl/bun-install.sh; \
    /opt/bun/bin/bun --version

USER dev
RUN --mount=type=cache,target=/tmp/sbx-dl,sharing=locked,uid=1000,gid=1000 set -eux; \
    if [ ! -f /tmp/sbx-dl/rustup-init.sh ]; then \
        sbx-fetch https://sh.rustup.rs -o /tmp/sbx-dl/rustup-init.sh; \
    fi; \
    CARGO_HOME=${USER_HOME}/.cargo RUSTUP_HOME=${USER_HOME}/.rustup \
        bash /tmp/sbx-dl/rustup-init.sh -y --no-modify-path --default-toolchain stable --profile minimal; \
    CARGO_HOME=${USER_HOME}/.cargo RUSTUP_HOME=${USER_HOME}/.rustup \
        ${USER_HOME}/.cargo/bin/rustup component add rustfmt clippy; \
    ${USER_HOME}/.cargo/bin/cargo --version

USER root
RUN printf 'export CARGO_HOME=%s/.cargo\nexport RUSTUP_HOME=%s/.rustup\nexport PATH=%s/.npm-global/bin:%s/.cargo/bin:/opt/bun/bin:$PATH\n' "$USER_HOME" "$USER_HOME" "$USER_HOME" "$USER_HOME" >> /etc/profile.d/sbx.sh

COPY --chmod=0755 xdg-open /usr/local/bin/xdg-open

USER dev

ENV BROWSER=xdg-open \
    NPM_CONFIG_CACHE=${USER_HOME}/.npm \
    NPM_CONFIG_PREFIX=${USER_HOME}/.npm-global \
    BUN_INSTALL_CACHE_DIR=${USER_HOME}/.bun/install/cache \
    CARGO_HOME=${USER_HOME}/.cargo \
    RUSTUP_HOME=${USER_HOME}/.rustup \
    PATH=/opt/sbx/bin:${USER_HOME}/.npm-global/bin:${USER_HOME}/.local/bin:${USER_HOME}/.local/share/mise/shims:${USER_HOME}/.cargo/bin:/opt/bun/bin:/usr/local/bin:/usr/bin:/bin

RUN mkdir -p ${USER_HOME}/.codex \
    ${USER_HOME}/.local/state \
    ${USER_HOME}/.cache \
    ${USER_HOME}/.npm-global

RUN --mount=type=cache,target=${USER_HOME}/.npm,uid=1000,gid=1000,sharing=locked \
    npm install -g @openai/codex \
    && codex --version

LABEL dev.sbx.browser-mcp=$SBX_PLAYWRIGHT

CMD ["/bin/bash"]
