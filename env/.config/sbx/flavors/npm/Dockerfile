# syntax=docker/dockerfile:1
FROM sbx-base:latest

ARG SBX_NODE_VERSION=lts
ARG USER_HOME=/home/dev

USER root
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
        libgtk-3-0t64 libgbm-dev libnotify-dev libnss3 libxss1 \
        libasound2t64 libxtst6 xauth xvfb redis-server

USER dev
# ${USER_HOME}/.cache has to exist and belong to dev before the layer below
# mounts a cache at .cache/mise: BuildKit creates a missing parent as root, and
# mise writes elsewhere under .cache while it installs — sigstore-rust puts its
# TUF metadata in .cache/sigstore-rust while verifying a release's attestations.
# Owned by root, that write is EACCES and mise reports it as an attestation
# failure, which reads like a bad artifact rather than a directory permission.
RUN mkdir -p ${USER_HOME}/.cache
RUN --mount=type=cache,target=${USER_HOME}/.cache/mise,uid=1000,gid=1000,sharing=locked \
    /usr/local/bin/mise use --global "node@${SBX_NODE_VERSION}" \
    && /usr/local/bin/mise which node \
    && /usr/local/bin/mise which npm

RUN --mount=type=cache,target=${USER_HOME}/.npm,uid=1000,gid=1000,sharing=locked \
    mkdir -p ${USER_HOME}/.sbx/socket-cli \
    && cd ${USER_HOME}/.sbx/socket-cli \
    && NPM="$(/usr/local/bin/mise which npm)" \
    && "$NPM" init -y >/dev/null \
    && "$NPM" install @socketsecurity/cli

RUN --mount=type=cache,target=${USER_HOME}/.npm,uid=1000,gid=1000,sharing=locked \
    mkdir -p ${USER_HOME}/.sbx/ncu \
    && cd ${USER_HOME}/.sbx/ncu \
    && NPM="$(/usr/local/bin/mise which npm)" \
    && "$NPM" init -y >/dev/null \
    && "$NPM" install npm-check-updates

USER root
RUN printf '#!/bin/sh\nNODE="$(/usr/local/bin/mise which node 2>/dev/null)" || NODE=node\nexec "$NODE" %s/.sbx/socket-cli/node_modules/@socketsecurity/cli/dist/cli.js "$@"\n' "$USER_HOME" > /opt/sbx/bin/socket \
    && chmod +x /opt/sbx/bin/socket \
    && printf '#!/bin/sh\nNODE="$(/usr/local/bin/mise which node 2>/dev/null)" || NODE=node\nexec "$NODE" %s/.sbx/ncu/node_modules/npm-check-updates/build/cli.js "$@"\n' "$USER_HOME" > /opt/sbx/bin/ncu \
    && chmod +x /opt/sbx/bin/ncu

USER dev

ENV NPM_CONFIG_CACHE=${USER_HOME}/.npm
