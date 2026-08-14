# syntax=docker/dockerfile:1
FROM sbx-base:latest

ARG SBX_NVIM_VERSION=stable
ARG SBX_NODE_VERSION=lts
ARG SBX_COPILOT_NODE_VERSION=24.13.0
ARG SBX_JAVA_VERSION=21
ARG SBX_MAVEN_VERSION=latest
ARG SBX_RUST_VERSION=stable
ARG USER_HOME=/home/dev
ARG USER_UID=1000

USER root
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        bat \
        chromium \
        cmake \
        fd-find \
        fonts-dejavu-core \
        fzf \
        git-delta \
        gettext \
        imagemagick \
        pkg-config \
        libssl-dev \
        wl-clipboard \
        xclip \
        luarocks \
        lua5.1 \
        liblua5.1-0-dev \
        lua-dkjson \
        unzip \
        python3-pynvim \
        gh

RUN install -Dm644 /usr/share/lua/5.1/dkjson.lua /usr/local/share/lua/5.1/dkjson.lua

RUN mkdir -p "${USER_HOME}/.config/bat/themes" "${USER_HOME}/.cache/bat" \
    && curl -fsSL -o "${USER_HOME}/.config/bat/themes/Catppuccin Mocha.tmTheme" \
        "https://raw.githubusercontent.com/catppuccin/bat/main/themes/Catppuccin%20Mocha.tmTheme" \
    && BAT_CONFIG_DIR="${USER_HOME}/.config/bat" BAT_CACHE_PATH="${USER_HOME}/.cache/bat" batcat cache --build \
    && BAT_CACHE_PATH="${USER_HOME}/.cache/bat" batcat --list-themes | grep -q "Catppuccin Mocha" \
    && chown -R "${USER_UID}:${USER_UID}" "${USER_HOME}/.config" "${USER_HOME}/.cache"

RUN mkdir -p /run/user/${USER_UID} \
    && chown ${USER_UID}:${USER_UID} /run/user/${USER_UID} \
    && chmod 700 /run/user/${USER_UID}

RUN cat > /usr/local/bin/xdg-open <<'EOF' && chmod +x /usr/local/bin/xdg-open
#!/bin/sh
sock="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/sbx-opener.sock"
status=0
for a in "$@"; do
    case "$a" in -*) continue ;; esac
    python3 -c 'import socket,sys
s=socket.socket(socket.AF_UNIX)
s.connect(sys.argv[1])
s.sendall((sys.argv[2].strip()+"\n").encode())
s.close()' "$sock" "$a" 2>/dev/null || {
        echo "xdg-open: sbx host opener unavailable ($sock)" >&2
        status=3
    }
done
exit $status
EOF

RUN printf '%s\n' '{"args":["--no-sandbox"]}' > /etc/sbx-puppeteer.json

USER dev
RUN --mount=type=cache,target=${USER_HOME}/.cache/mise,uid=1000,gid=1000,sharing=locked \
    MISE_RUST_PROFILE=minimal /usr/local/bin/mise use --global \
        "neovim@${SBX_NVIM_VERSION}" \
        "node@${SBX_NODE_VERSION}" \
        "node@${SBX_COPILOT_NODE_VERSION}" \
        "java@${SBX_JAVA_VERSION}" \
        "maven@${SBX_MAVEN_VERSION}" \
        "rust@${SBX_RUST_VERSION}" \
    && PUPPETEER_SKIP_DOWNLOAD=true /usr/local/bin/mise exec "node@${SBX_COPILOT_NODE_VERSION}" -- \
        npm install -g tree-sitter-cli @typescript/native-preview @mermaid-js/mermaid-cli \
    && /usr/local/bin/mise reshim \
    && /usr/local/bin/mise which nvim \
    && /usr/local/bin/mise which node \
    && /usr/local/bin/mise which java \
    && /usr/local/bin/mise which mvn \
    && /usr/local/bin/mise which rustc \
    && /usr/local/bin/mise which cargo \
    && ${USER_HOME}/.local/share/mise/shims/cargo --version \
    && test -x "${USER_HOME}/.local/share/mise/installs/node/${SBX_COPILOT_NODE_VERSION}/bin/node" \
    && /usr/local/bin/mise exec "node@${SBX_COPILOT_NODE_VERSION}" -- tree-sitter --version \
    && /usr/local/bin/mise exec "node@${SBX_COPILOT_NODE_VERSION}" -- tsgo --version \
    && printf 'graph TD\n    A --> B\n' > /tmp/sbx-mermaid-smoke.mmd \
    && PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium /usr/local/bin/mise exec "node@${SBX_COPILOT_NODE_VERSION}" -- \
        mmdc -p /etc/sbx-puppeteer.json -i /tmp/sbx-mermaid-smoke.mmd -o /tmp/sbx-mermaid-smoke.png \
    && test -s /tmp/sbx-mermaid-smoke.png \
    && rm -f /tmp/sbx-mermaid-smoke.mmd /tmp/sbx-mermaid-smoke.png

USER root
RUN mkdir -p "${USER_HOME}/.cache/mise" && chown -R "${USER_UID}:${USER_UID}" "${USER_HOME}/.cache"

RUN printf 'if [ -d %s/.cargo/bin ]; then\n  case ":$PATH:" in *":%s/.cargo/bin:"*) ;; *) PATH="%s/.cargo/bin:$PATH";; esac\n  export PATH\nfi\nexport CARGO_HOME=%s/.cargo\n' "$USER_HOME" "$USER_HOME" "$USER_HOME" "$USER_HOME" > /etc/profile.d/rust.sh \
    && chmod 0644 /etc/profile.d/rust.sh
USER dev

ENV CARGO_HOME=${USER_HOME}/.cargo \
    PATH=/opt/sbx/bin:${USER_HOME}/.local/bin:${USER_HOME}/.local/share/mise/shims:${USER_HOME}/.cargo/bin:/usr/local/bin:/usr/bin:/bin \
    EDITOR=nvim VISUAL=nvim \
    PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium \
    SNACKS_SSH=true \
    MISE_NODE_VERSION=${SBX_COPILOT_NODE_VERSION}
