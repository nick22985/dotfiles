# syntax=docker/dockerfile:1
FROM debian:trixie-slim

ARG USER_UID=1000
ARG USER_GID=1000
ARG USER_HOME=/home/dev
ARG SBX_GUARDDOG=1

ENV DEBIAN_FRONTEND=noninteractive

# `shellcheck` is here for the fleet rather than for a person: a project whose
# verify gate names it can only run it if every sandbox has it, and a gate that
# exits 127 on a missing binary parks the whole queue instead of failing one
# task. It rides in the base flavor so that is true of every flavor at once.
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    rm -f /etc/apt/apt.conf.d/docker-clean \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        git \
        shellcheck \
        gnupg \
        ca-certificates \
        curl \
        less \
        openssh-client \
        ripgrep \
        time \
        util-linux \
        vim-tiny \
        unzip \
        xz-utils \
        python3 \
        python3-pip \
        python3-venv

# Every fetch in this image, and in the flavors built on it, crosses the public
# internet from wherever the build runs, and on the Kubernetes nodes a reset
# mid-transfer from github.com is common enough that a single-shot curl turns a
# flaky minute into a failed build. `--retry-all-errors` is the flag that
# matters: a plain `--retry` sits out a connection reset (curl exit 56), which
# is exactly how these fail.
# `--max-time` bounds one attempt so a stalled socket is retried rather than
# hung on — the reset that prompted this took 151s to surface on its own.
#
# A wrapper rather than an env var of flags: a flavor built against an older
# sbx-base would expand an undefined var to nothing, quietly dropping --fail
# and --location and installing a redirect stub or an error page. A missing
# command stops the build instead.
#
# It also writes `-o FILE` atomically, which is what keeps a cut-off download
# out of the `/tmp/sbx-dl` cache mounts below (see the script). The mode is on
# the COPY for the reason given above the sbx-audit COPY further down.
COPY --chmod=0755 sbx-fetch /usr/local/bin/sbx-fetch
RUN sh -n /usr/local/bin/sbx-fetch

RUN if getent group "$USER_GID" >/dev/null; then \
        EXISTING_GROUP="$(getent group "$USER_GID" | cut -d: -f1)"; \
        if [ "$EXISTING_GROUP" != "dev" ]; then groupmod -n dev "$EXISTING_GROUP"; fi; \
    else \
        groupadd -g "$USER_GID" dev; \
    fi \
    && if getent passwd "$USER_UID" >/dev/null; then \
        EXISTING_USER="$(getent passwd "$USER_UID" | cut -d: -f1)"; \
        if [ "$EXISTING_USER" != "dev" ]; then usermod -l dev -d "$USER_HOME" -m "$EXISTING_USER"; \
        else usermod -d "$USER_HOME" -m dev; fi; \
        usermod -g dev dev; \
    else \
        useradd -m -u "$USER_UID" -g dev -d "$USER_HOME" -s /bin/bash dev; \
    fi \
    && mkdir -p "$USER_HOME" /opt/sbx/bin \
    && chown -R dev:dev "$USER_HOME"

# ~/.config is made here, not left to whatever first needs it. A project mount
# under it (`~/.config/ijfmt`) otherwise has the daemon create it as root, and
# every tool that writes its own config there fails: Chromium aborts with
# SIGTRAP when it cannot make its crash-report database.
RUN install -d -o dev -g dev "$USER_HOME/.config"

RUN --mount=type=cache,target=/tmp/sbx-dl,sharing=locked set -eux; \
    arch="$(dpkg --print-architecture)"; \
    case "$arch" in \
        amd64) osv_arch=linux_amd64 ;; \
        arm64) osv_arch=linux_arm64 ;; \
        *) echo "unsupported arch $arch"; exit 1 ;; \
    esac; \
    if [ ! -f "/tmp/sbx-dl/osv-scanner-$osv_arch" ]; then \
        sbx-fetch -o "/tmp/sbx-dl/osv-scanner-$osv_arch" \
            "https://github.com/google/osv-scanner/releases/latest/download/osv-scanner_$osv_arch"; \
    fi; \
    install -m 0755 "/tmp/sbx-dl/osv-scanner-$osv_arch" /usr/local/bin/osv-scanner; \
    osv-scanner --version

# Trivy's own contrib/install.sh is deliberately not used. Its first act is a
# bare `curl -sL https://github.com/aquasecurity/trivy/releases/latest` to
# resolve "latest" into a tag — no --retry, no --fail — so the reset described
# above surfaces as an empty body, and the script reports it as
# `unable to find ''`, naming a tag nobody asked for instead of the network.
# That took 151s to fail on a Kubernetes node. Pinning the version removes the
# lookup entirely and puts both remaining fetches behind sbx-fetch.
ARG TRIVY_VERSION=0.74.0
RUN --mount=type=cache,target=/tmp/sbx-dl,sharing=locked set -eux; \
    arch="$(dpkg --print-architecture)"; \
    case "$arch" in \
        amd64) trivy_arch=Linux-64bit ;; \
        arm64) trivy_arch=Linux-ARM64 ;; \
        *) echo "unsupported arch $arch"; exit 1 ;; \
    esac; \
    base="https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}"; \
    tarball="trivy_${TRIVY_VERSION}_${trivy_arch}.tar.gz"; \
    sums="trivy_${TRIVY_VERSION}_checksums.txt"; \
    cd /tmp/sbx-dl; \
    if [ -f "$tarball" ] && [ -f "$sums" ] \
        && ! grep " $tarball\$" "$sums" | sha256sum -c --status -; then \
        rm -f "$tarball" "$sums"; \
    fi; \
    if [ ! -f "/tmp/sbx-dl/$tarball" ]; then \
        sbx-fetch -o "/tmp/sbx-dl/$tarball" "$base/$tarball"; \
    fi; \
    if [ ! -f "/tmp/sbx-dl/$sums" ]; then \
        sbx-fetch -o "/tmp/sbx-dl/$sums" "$base/$sums"; \
    fi; \
    grep " $tarball\$" "$sums" | sha256sum -c -; \
    tar -xz -C /tmp -f "/tmp/sbx-dl/$tarball" trivy; \
    install -m 0755 /tmp/trivy /usr/local/bin/trivy; \
    rm -f /tmp/trivy; \
    trivy --version

RUN --mount=type=cache,target=/root/.cache/pip,sharing=locked \
    if [ "$SBX_GUARDDOG" = "1" ]; then \
        python3 -m venv /opt/guarddog \
        && /opt/guarddog/bin/pip install guarddog \
        && ln -s /opt/guarddog/bin/guarddog /usr/local/bin/guarddog \
        && guarddog --version ; \
    fi

RUN --mount=type=cache,target=/tmp/sbx-dl,sharing=locked set -eux; \
    if [ ! -f /tmp/sbx-dl/mise-install.sh ]; then \
        sbx-fetch https://mise.run -o /tmp/sbx-dl/mise-install.sh; \
    fi; \
    MISE_INSTALL_PATH=/usr/local/bin/mise sh /tmp/sbx-dl/mise-install.sh; \
    mise --version

# mise's global tool list lives outside $HOME. A sandbox opened *in* a config
# directory — `cd ~/.config && nvim .` — bind-mounts the host's copy over the
# image's, and the default location (`$HOME/.config/mise/config.toml`) goes with
# it: every shim then fails with "No version is set for shim: nvim" while the
# shims themselves are still on PATH. Nothing under /opt/sbx is ever a workspace.
ENV MISE_GLOBAL_CONFIG_FILE=/opt/sbx/mise/config.toml
RUN mkdir -p /opt/sbx/mise && chown dev:dev /opt/sbx/mise

ARG DOCKER_VERSION=27.4.0
RUN --mount=type=cache,target=/tmp/sbx-dl,sharing=locked set -eux; \
    arch="$(dpkg --print-architecture)"; \
    case "$arch" in \
        amd64) docker_arch=x86_64 ;; \
        arm64) docker_arch=aarch64 ;; \
        *) echo "unsupported arch $arch"; exit 1 ;; \
    esac; \
    tgz="/tmp/sbx-dl/docker-${DOCKER_VERSION}-${docker_arch}.tgz"; \
    if [ -f "$tgz" ] && ! gzip -tq "$tgz"; then rm -f "$tgz"; fi; \
    if [ ! -f "$tgz" ]; then \
        sbx-fetch "https://download.docker.com/linux/static/stable/${docker_arch}/docker-${DOCKER_VERSION}.tgz" \
            -o "$tgz"; \
    fi; \
    tar -xz -C /tmp -f "$tgz" docker/docker; \
    install -m 0755 /tmp/docker/docker /usr/local/bin/docker; \
    rm -rf /tmp/docker; \
    docker --version

RUN printf 'export PATH=/opt/sbx/bin:$HOME/.local/bin:$HOME/.local/share/mise/shims:$PATH\nexport MISE_INSTALL_MISSING_TOOLS=1\neval "$(/usr/local/bin/mise activate bash)" 2>/dev/null || true\n' > /etc/profile.d/sbx.sh

# Every script COPYed in from here down spells its mode out on the COPY itself,
# and nothing below chmods one afterwards. COPY carries the build context's mode
# across, and `chmod +x` only *adds* execute bits to whatever that was — it
# cannot put back a read bit that was never there, and a `#!` script the
# container's user cannot read is one the shell refuses with "Permission
# denied". So a 0700 file in the context becomes 0711 in the image and every
# `bun` in the fleet stops. The context's modes are not ours to rely on: git
# records the execute bit alone, so a checkout rewritten under a restrictive
# umask (a fleet worktree's, say) is where this came from, and
# `scripts/sync-flavors.sh` copies it into the flavor dir with `cp -p`.
COPY --chmod=0755 sbx-audit /opt/sbx/bin/sbx-audit

COPY --chmod=0755 install-browser.sh /opt/sbx/bin/sbx-install-browser
COPY --chmod=0755 browser-mcp.cjs /opt/sbx/browser/mcp.cjs

COPY --chmod=0755 gpg /opt/sbx/bin/gpg

# Every bun-capable leaf resolves `bun` here before its real binary. The
# wrapper selects the LAN registry when it is healthy and keeps the shared
# install cache from growing forever. Its lock and check stamp live in a
# separate named volume; `bun pm cache rm` can empty the cache volume without
# replacing the inode other package-manager commands lock.
#
# A second copy lives one directory over, because /opt/sbx/bin/<tool> is also
# where a fleet worktree binds its build shims
# (orchestra::worktree::build_shim_mounts) and `bun` is the one name in both
# sets. A bind over the PATH name hides whatever the image put there, and the
# shim resolves the real tool by walking PATH with its own directory skipped —
# so a wrapper installed only at the PATH name is a wrapper the fleet steps
# straight past. Keeping a copy at a name no mount covers lets the shim find it
# deliberately: it looks for ../wrappers/<tool> before it walks PATH.
#
# A copy, not a symlink. Docker follows a symlink at a bind target, so a shim
# bound over a PATH name that pointed at ../wrappers/bun landed on the wrapper
# itself and hid the one file it was meant to find.
COPY --chmod=0755 sbx-bun /opt/sbx/wrappers/bun
COPY --chmod=0755 sbx-bun /opt/sbx/bin/bun

RUN printf '\n# sbx: let gpg prompt for passphrases inline on this terminal\nif [ -z "${GPG_TTY:-}" ] && tty -s; then GPG_TTY="$(tty)"; export GPG_TTY; fi\n' >> /etc/bash.bashrc

USER dev
WORKDIR $USER_HOME

ENV SHELL=/bin/bash \
    MISE_INSTALL_MISSING_TOOLS=1 \
    SBX_BUN_REGISTRY=https://registry.nick22985.com/npm/ \
    SBX_BUN_CACHE_MAX_KIB=4194304 \
    SBX_BUN_CACHE_CHECK_SECONDS=86400 \
    PATH=/opt/sbx/bin:$USER_HOME/.local/bin:$USER_HOME/.local/share/mise/shims:/usr/local/bin:/usr/bin:/bin

CMD ["/bin/bash"]
