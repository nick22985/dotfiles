# syntax=docker/dockerfile:1
FROM sbx-base:latest

ARG SBX_GO_VERSION=latest
ARG USER_HOME=/home/dev

USER root
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        pkg-config \
        tmux

# ${USER_HOME}/.cache has to exist and belong to dev before the layer below
# mounts a cache at .cache/mise: BuildKit creates a missing parent as root, and
# mise writes elsewhere under .cache while it installs — sigstore-rust puts its
# TUF metadata in .cache/sigstore-rust while verifying a release's attestations.
# Owned by root, that write is EACCES and mise reports it as an attestation
# failure, which reads like a bad artifact rather than a directory permission.
RUN install -d -o dev -g dev ${USER_HOME}/.cache

USER dev
RUN --mount=type=cache,target=${USER_HOME}/.cache/mise,uid=1000,gid=1000,sharing=locked \
    /usr/local/bin/mise use --global "go@${SBX_GO_VERSION}" \
    && /usr/local/bin/mise which go \
    && ${USER_HOME}/.local/share/mise/shims/go version

ENV GOPATH=${USER_HOME}/go \
    GOMODCACHE=${USER_HOME}/go/pkg/mod \
    GOCACHE=${USER_HOME}/.cache/go-build \
    PATH=${USER_HOME}/.local/bin:${USER_HOME}/.local/share/mise/shims:${USER_HOME}/go/bin:/opt/sbx/bin:/usr/local/bin:/usr/bin:/bin

USER root
RUN printf 'export GOPATH=%s/go\nexport GOMODCACHE=%s/go/pkg/mod\nexport GOCACHE=%s/.cache/go-build\nif [ -d %s/go/bin ]; then\n  case ":$PATH:" in *":%s/go/bin:"*) ;; *) PATH="%s/go/bin:$PATH";; esac\n  export PATH\nfi\n' "$USER_HOME" "$USER_HOME" "$USER_HOME" "$USER_HOME" "$USER_HOME" "$USER_HOME" > /etc/profile.d/go.sh \
    && chmod 0644 /etc/profile.d/go.sh
USER dev
