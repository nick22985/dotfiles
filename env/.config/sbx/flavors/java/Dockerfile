# syntax=docker/dockerfile:1
FROM sbx-base:latest

ARG SBX_JAVA_VERSION=21
ARG SBX_MAVEN_VERSION=latest
ARG USER_HOME=/home/dev

USER dev
# ${USER_HOME}/.cache has to exist and belong to dev before the layer below
# mounts a cache at .cache/mise: BuildKit creates a missing parent as root, and
# mise writes elsewhere under .cache while it installs — sigstore-rust puts its
# TUF metadata in .cache/sigstore-rust while verifying a release's attestations.
# Owned by root, that write is EACCES and mise reports it as an attestation
# failure, which reads like a bad artifact rather than a directory permission.
RUN mkdir -p ${USER_HOME}/.cache
RUN --mount=type=cache,target=${USER_HOME}/.cache/mise,uid=1000,gid=1000,sharing=locked \
    /usr/local/bin/mise use --global "java@${SBX_JAVA_VERSION}" "maven@${SBX_MAVEN_VERSION}" \
    && /usr/local/bin/mise which java \
    && /usr/local/bin/mise which mvn

USER root
RUN printf 'export MAVEN_OPTS="${MAVEN_OPTS:--Dmaven.repo.local=%s/.m2/repository}"\nexport MISE_YES=1\neval "$(/usr/local/bin/mise env -s bash 2>/dev/null)" 2>/dev/null || true\n' "$USER_HOME" >> /etc/profile.d/sbx.sh

USER dev

ENV MISE_YES=1 \
    MAVEN_OPTS=-Dmaven.repo.local=${USER_HOME}/.m2/repository
