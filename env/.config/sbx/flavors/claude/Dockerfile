# syntax=docker/dockerfile:1
FROM sbx-base:latest

ARG USER_HOME=/home/dev

ARG SBX_PLAYWRIGHT=1
ARG SBX_PLAYWRIGHT_VERSION=1.60.0

USER root
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        pkg-config \
        libssl-dev \
        rsync

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

RUN --mount=type=cache,target=/tmp/sbx-dl,sharing=locked set -eux; \
    if [ ! -f /tmp/sbx-dl/bun-install.sh ]; then \
        curl -fsSL https://bun.sh/install -o /tmp/sbx-dl/bun-install.sh; \
    fi; \
    BUN_INSTALL=/opt/bun bash /tmp/sbx-dl/bun-install.sh; \
    ln -s /opt/bun/bin/bun /usr/local/bin/bun.real; \
    /usr/local/bin/bun.real --version

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

USER dev
RUN --mount=type=cache,target=/tmp/sbx-dl,sharing=locked,uid=1000,gid=1000 set -eux; \
    if [ ! -f /tmp/sbx-dl/rustup-init.sh ]; then \
        curl -fsSL https://sh.rustup.rs -o /tmp/sbx-dl/rustup-init.sh; \
    fi; \
    CARGO_HOME=${USER_HOME}/.cargo RUSTUP_HOME=${USER_HOME}/.rustup \
        bash /tmp/sbx-dl/rustup-init.sh -y --no-modify-path --default-toolchain stable --profile minimal; \
    CARGO_HOME=${USER_HOME}/.cargo RUSTUP_HOME=${USER_HOME}/.rustup \
        ${USER_HOME}/.cargo/bin/rustup component add rustfmt clippy; \
    ${USER_HOME}/.cargo/bin/rustc --version

USER root

RUN --mount=type=cache,target=/root/.npm,sharing=locked \
    /usr/bin/npm install -g @socketsecurity/cli \
    && socket --version

USER dev
RUN --mount=type=cache,target=/tmp/sbx-dl,sharing=locked,uid=1000,gid=1000 set -eux; \
    if [ ! -f /tmp/sbx-dl/claude-install.sh ]; then \
        curl -fsSL https://claude.ai/install.sh -o /tmp/sbx-dl/claude-install.sh; \
    fi; \
    HOME=${USER_HOME} bash /tmp/sbx-dl/claude-install.sh; \
    ${USER_HOME}/.local/bin/claude --version
USER root

# install-deps installs trixie's own libnss3, and that is enough: chromium asks
# for at most NSS_3.30, trixie's 3.110 defines through NSS_3.110, firefox ships
# its own nss beside libxul and webkit links none. An out-of-suite sid libnss3
# used to be dpkg -i'd over this by exact pool filename; Debian drops those
# files on every nss upload, so the build 404'd. Do not re-pin one without a
# failure that trixie's nss actually causes.
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    if [ "$SBX_PLAYWRIGHT" = "1" ]; then set -eux; \
        export PATH="/usr/local/sbin:/usr/sbin:/sbin:$PATH"; \
        apt-get update; \
        npx --yes "playwright@${SBX_PLAYWRIGHT_VERSION}" install-deps chromium firefox webkit; \
    fi
USER dev
RUN if [ "$SBX_PLAYWRIGHT" = "1" ]; then set -eux; \
        HOME=${USER_HOME} npx --yes "playwright@${SBX_PLAYWRIGHT_VERSION}" \
            install chromium firefox webkit; \
    fi
USER root

COPY wrappers/entrypoint /opt/sbx/bin/entrypoint
RUN chmod +x /opt/sbx/bin/entrypoint \
    && printf 'export CARGO_HOME=%s/.cargo\nexport RUSTUP_HOME=%s/.rustup\nexport PATH=%s/.cargo/bin:/opt/bun/bin:$PATH\n' "$USER_HOME" "$USER_HOME" "$USER_HOME" >> /etc/profile.d/sbx.sh

USER dev

ENV NPM_CONFIG_CACHE=${USER_HOME}/.npm \
    BUN_INSTALL_CACHE_DIR=${USER_HOME}/.bun/install/cache \
    CARGO_HOME=${USER_HOME}/.cargo \
    RUSTUP_HOME=${USER_HOME}/.rustup \
    PATH=/opt/sbx/bin:${USER_HOME}/.local/bin:${USER_HOME}/.local/share/mise/shims:${USER_HOME}/.cargo/bin:/opt/bun/bin:/usr/local/bin:/usr/bin:/bin

ENTRYPOINT ["/opt/sbx/bin/entrypoint"]
CMD ["/bin/bash"]
