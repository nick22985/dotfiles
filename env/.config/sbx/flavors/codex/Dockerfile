# syntax=docker/dockerfile:1
FROM sbx-base:latest

ARG USER_HOME=/home/dev

USER root
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    --mount=type=cache,target=/tmp/sbx-dl,sharing=locked \
    if [ ! -f /tmp/sbx-dl/nodesource-setup.sh ]; then \
        curl -fsSL https://deb.nodesource.com/setup_lts.x -o /tmp/sbx-dl/nodesource-setup.sh; \
    fi \
    && bash /tmp/sbx-dl/nodesource-setup.sh \
    && apt-get install -y --no-install-recommends nodejs rsync \
    && node --version \
    && npm --version

USER dev

ENV NPM_CONFIG_CACHE=${USER_HOME}/.npm \
    NPM_CONFIG_PREFIX=${USER_HOME}/.npm-global \
    PATH=/opt/sbx/bin:${USER_HOME}/.npm-global/bin:${USER_HOME}/.local/bin:${USER_HOME}/.local/share/mise/shims:/usr/local/bin:/usr/bin:/bin

RUN mkdir -p ${USER_HOME}/.codex \
    ${USER_HOME}/.local/state \
    ${USER_HOME}/.cache \
    ${USER_HOME}/.npm-global

RUN --mount=type=cache,target=${USER_HOME}/.npm,uid=1000,gid=1000,sharing=locked \
    npm install -g @openai/codex \
    && codex --version

CMD ["/bin/bash"]
