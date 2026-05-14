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
    && mkdir -p /home/dev/.m2 /workspace /opt/sbx/bin \
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

# mise — polyglot tool-version manager. We pre-install a default Java +
# Maven so the image works out of the box; projects can still pin their
# own versions via mise.toml / .tool-versions.
RUN --mount=type=cache,target=/tmp/sbx-dl,sharing=locked set -eux; \
    if [ ! -f /tmp/sbx-dl/mise-install.sh ]; then \
        curl -fsSL https://mise.run -o /tmp/sbx-dl/mise-install.sh; \
    fi; \
    MISE_INSTALL_PATH=/usr/local/bin/mise sh /tmp/sbx-dl/mise-install.sh; \
    mise --version

COPY wrappers/mvn /opt/sbx/bin/mvn
RUN chmod +x /opt/sbx/bin/mvn \
    && printf 'export PATH=/opt/sbx/bin:/home/dev/.local/share/mise/shims:$PATH\nexport MAVEN_OPTS="${MAVEN_OPTS:--Dmaven.repo.local=/home/dev/.m2/repository}"\nexport MISE_INSTALL_MISSING_TOOLS=1\neval "$(/usr/local/bin/mise activate bash)" 2>/dev/null || true\n' > /etc/profile.d/sbx.sh

ARG SBX_JAVA_VERSION=21
ARG SBX_MAVEN_VERSION=latest

USER dev
WORKDIR /home/dev
RUN --mount=type=cache,target=/home/dev/.cache/mise,uid=1000,gid=1000,sharing=locked \
    /usr/local/bin/mise use --global "java@${SBX_JAVA_VERSION}" "maven@${SBX_MAVEN_VERSION}" \
    && /usr/local/bin/mise which java \
    && /usr/local/bin/mise which mvn

WORKDIR /workspace

ENV SHELL=/bin/bash \
    MISE_INSTALL_MISSING_TOOLS=1 \
    MAVEN_OPTS=-Dmaven.repo.local=/home/dev/.m2/repository \
    PATH=/opt/sbx/bin:/home/dev/.local/share/mise/shims:$PATH

CMD ["/bin/bash"]
