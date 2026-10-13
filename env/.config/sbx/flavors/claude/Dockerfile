# syntax=docker/dockerfile:1
FROM sbx-base:latest

ARG USER_HOME=/home/dev

ARG SBX_PLAYWRIGHT=1
ARG SBX_PLAYWRIGHT_VERSION=1.60.0
ARG SBX_PLAYWRIGHT_MCP_VERSION=0.0.83

USER root
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        pkg-config \
        libssl-dev \
        rsync \
        w3m \
        libgtk-3-0t64 libgbm-dev libnotify-dev libnss3 libxss1 \
        libasound2t64 libxtst6 xauth xvfb redis-server

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    --mount=type=cache,target=/tmp/sbx-dl,sharing=locked \
    if [ ! -f /tmp/sbx-dl/nodesource-setup.sh ]; then \
        sbx-fetch https://deb.nodesource.com/setup_lts.x -o /tmp/sbx-dl/nodesource-setup.sh; \
    fi \
    && bash /tmp/sbx-dl/nodesource-setup.sh \
    && apt-get install -y --no-install-recommends nodejs \
    && node --version \
    && npm --version

RUN --mount=type=cache,target=/tmp/sbx-dl,sharing=locked set -eux; \
    if [ ! -f /tmp/sbx-dl/bun-install.sh ]; then \
        sbx-fetch https://bun.sh/install -o /tmp/sbx-dl/bun-install.sh; \
    fi; \
    BUN_INSTALL=/opt/bun bash /tmp/sbx-dl/bun-install.sh; \
    ln -s /opt/bun/bin/bun /usr/local/bin/bun.real; \
    /usr/local/bin/bun.real --version

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    --mount=type=cache,target=/tmp/sbx-dl,sharing=locked \
    set -eux; \
    if [ ! -f /tmp/sbx-dl/adoptium.asc ]; then \
        sbx-fetch https://packages.adoptium.net/artifactory/api/gpg/key/public \
            -o /tmp/sbx-dl/adoptium.asc; \
    fi; \
    install -m 0644 /tmp/sbx-dl/adoptium.asc /etc/apt/trusted.gpg.d/adoptium.asc; \
    echo "deb https://packages.adoptium.net/artifactory/deb bookworm main" \
        > /etc/apt/sources.list.d/adoptium.list; \
    apt-get update; \
    apt-get install -y --no-install-recommends temurin-21-jdk maven; \
    java -version; \
    mvn -version

# A zip cached before sbx-fetch wrote atomically can be a cut-off download,
# and one that fails the test is fetched again rather than skipped forever.
ARG GRADLE_VERSION=8.11.1
RUN --mount=type=cache,target=/tmp/sbx-dl,sharing=locked set -eux; \
    zip="/tmp/sbx-dl/gradle-${GRADLE_VERSION}-bin.zip"; \
    if [ -f "$zip" ] && ! unzip -tq "$zip" >/dev/null 2>&1; then rm -f "$zip"; fi; \
    if [ ! -f "$zip" ]; then \
        sbx-fetch "https://services.gradle.org/distributions/gradle-${GRADLE_VERSION}-bin.zip" \
            -o "$zip"; \
    fi; \
    unzip -q "$zip" -d /opt; \
    ln -s /opt/gradle-${GRADLE_VERSION}/bin/gradle /usr/local/bin/gradle; \
    gradle --version

USER dev
RUN --mount=type=cache,target=/tmp/sbx-dl,sharing=locked,uid=1000,gid=1000 set -eux; \
    if [ ! -f /tmp/sbx-dl/rustup-init.sh ]; then \
        sbx-fetch https://sh.rustup.rs -o /tmp/sbx-dl/rustup-init.sh; \
    fi; \
    CARGO_HOME=${USER_HOME}/.cargo RUSTUP_HOME=${USER_HOME}/.rustup \
        bash /tmp/sbx-dl/rustup-init.sh -y --no-modify-path --default-toolchain stable --profile minimal; \
    CARGO_HOME=${USER_HOME}/.cargo RUSTUP_HOME=${USER_HOME}/.rustup \
        ${USER_HOME}/.cargo/bin/rustup component add rustfmt clippy; \
    ${USER_HOME}/.cargo/bin/rustc --version

USER root

RUN --mount=type=cache,target=/root/.npm,sharing=locked \
    /usr/bin/npm install -g @socketsecurity/cli pm2 \
    && socket --version

USER dev
RUN --mount=type=cache,target=/tmp/sbx-dl,sharing=locked,uid=1000,gid=1000 set -eux; \
    if [ ! -f /tmp/sbx-dl/claude-install.sh ]; then \
        sbx-fetch https://claude.ai/install.sh -o /tmp/sbx-dl/claude-install.sh; \
    fi; \
    HOME=${USER_HOME} bash /tmp/sbx-dl/claude-install.sh; \
    ${USER_HOME}/.local/bin/claude --version
USER root

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    --mount=type=cache,target=/root/.npm,sharing=locked \
    sbx-install-browser

# The mode is on the COPY, for the reason the base image's COPY block gives.
COPY --chmod=0755 wrappers/entrypoint /opt/sbx/bin/entrypoint
RUN printf 'export CARGO_HOME=%s/.cargo\nexport RUSTUP_HOME=%s/.rustup\nexport PATH=%s/.cargo/bin:/opt/bun/bin:$PATH\n' "$USER_HOME" "$USER_HOME" "$USER_HOME" >> /etc/profile.d/sbx.sh

USER dev

ENV BROWSER=w3m \
    NPM_CONFIG_CACHE=${USER_HOME}/.npm \
    BUN_INSTALL_CACHE_DIR=${USER_HOME}/.bun/install/cache \
    CARGO_HOME=${USER_HOME}/.cargo \
    RUSTUP_HOME=${USER_HOME}/.rustup \
    PATH=/opt/sbx/bin:${USER_HOME}/.local/bin:${USER_HOME}/.local/share/mise/shims:${USER_HOME}/.cargo/bin:/opt/bun/bin:/usr/local/bin:/usr/bin:/bin

LABEL dev.sbx.browser-mcp=$SBX_PLAYWRIGHT

ENTRYPOINT ["/opt/sbx/bin/entrypoint"]
CMD ["/bin/bash"]
