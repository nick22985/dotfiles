# syntax=docker/dockerfile:1
FROM sbx-base:latest

ARG USER_HOME=/home/dev

USER root
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        pkg-config \
        libssl-dev

# ${USER_HOME}/.cache has to exist and belong to dev before the layer below
# mounts a cache at .cache/mise: BuildKit creates a missing parent as root, and
# mise writes elsewhere under .cache while it installs — sigstore-rust puts its
# TUF metadata in .cache/sigstore-rust while verifying a release's attestations.
# Owned by root, that write is EACCES and mise reports it as an attestation
# failure, which reads like a bad artifact rather than a directory permission.
RUN install -d -o dev -g dev ${USER_HOME}/.cache

USER dev
RUN --mount=type=cache,target=${USER_HOME}/.cache/mise,uid=1000,gid=1000,sharing=locked \
    MISE_RUST_PROFILE=minimal /usr/local/bin/mise use --global rust@stable \
    && /usr/local/bin/mise which rustc \
    && /usr/local/bin/mise which cargo

RUN --mount=type=cache,target=${USER_HOME}/.cargo/registry,uid=1000,gid=1000,sharing=locked \
    ${USER_HOME}/.local/share/mise/shims/cargo install cargo-audit --locked --no-default-features

# sccache, so that the dependency half of a build is compiled once on this node
# rather than once per worktree. Every fleet task gets a fresh worktree and so a
# fresh target directory, and the crates behind a workspace do not change
# between them; sccache is keyed on the preprocessed source rather than on where
# it sits, so the second worktree fetches what the first compiled. The
# workspace's own crates miss, which is the intended shape rather than a
# shortfall — they are the thing that changed. Nothing here excludes them: a
# filter that tried to would be redundant against a content-addressed key, and
# wrong in the one direction that matters if it ever mis-keyed.
#
# Measured on sbx's own workspace, `cargo test --no-run`, 4 cores:
#
#   636s  cold, no sccache                              (the baseline)
#   666s  cold, empty cache                             (+4.7%, paid once per node)
#   393s  second worktree, same commit, cold target     (-38%, 100% hits: 149/149)
#
# and 78 MiB on disk after three builds. The 243 seconds between the first line
# and the third are what a fleet worker stops paying on every task; what is left
# in the 393 is the workspace's own crates, which no cache can help with. A
# fourth run from a *different* path still hit 93% — the dependency half of the
# cache never cared where it was built, so T-0592's shared path is worth the
# last 7% and not the other 93.
#
# Two placement rules, both of them load-bearing:
#
# It installs into /usr/local/bin and NOT into ${USER_HOME}/.local/share/mise
# with everything else. That directory is a shared named volume at run time
# (`@sbx-mise-rust:.local/share/mise`, below in this flavor's config.toml), and
# docker seeds a volume from the image only on the run that creates it — so a
# node whose volume already exists mounts its older copy over whatever a newer
# image put there. A wrapper installed under mise would be in the image, absent
# from the container, and RUSTC_WRAPPER would still name it: every compile
# failing on a binary the build log above shows being installed. Nothing mounts
# anything over /usr/local. (The same rule, written out at greater length, is
# the preamble `sbx fleet init --provision` puts on a generated Dockerfile.)
#
# And it is fetched as root, into root's mise data directory, which is then
# thrown away. Installing it as dev would leave it in the very directory the
# volume masks even though the copy that matters is the one in /usr/local.
ARG SCCACHE_VERSION=0.17.0
USER root
RUN --mount=type=cache,target=/root/.cache/mise,sharing=locked \
    /usr/local/bin/mise install "sccache@${SCCACHE_VERSION}" \
    && install -m 0755 \
        "$(/usr/local/bin/mise which --tool=sccache@${SCCACHE_VERSION} sccache)" \
        /usr/local/bin/sccache \
    && rm -rf /root/.local/share/mise /root/.local/state/mise \
    && /usr/local/bin/sccache --version

# The cache's own directory, made here and owned by dev so that docker seeds
# `@sbx-sccache-rust` from it: a volume mounted over a path the image does not
# have is created bare and root-owned, and sbx then has to spend a helper
# container handing it over (flavor::ensure_cache_volumes_writable). An empty
# directory with the right owner in the image is the cheaper half of that.
RUN install -d -o dev -g dev ${USER_HOME}/.cache/sccache
USER dev

ENV CARGO_HOME=${USER_HOME}/.cargo \
    PATH=${USER_HOME}/.local/bin:${USER_HOME}/.local/share/mise/shims:${USER_HOME}/.cargo/bin:/opt/sbx/bin:/usr/local/bin:/usr/bin:/bin

# Named by absolute path rather than by bare name: /usr/local/bin is next to
# last on the PATH above, so a shim of that name appearing under mise or
# ~/.local/bin would silently take the wrapper's place.
#
# The wrapper is sccache-sbx and not sccache itself. It is a dozen lines of
# shell that ask the fleet's store once whether it is there and then get out of
# the way with an exec; the whole of why it has to exist is at the bottom of
# this file. SCCACHE_DIR below stays what it always was, and is now the first
# level of a two-level chain rather than the only cache.
#
# The size ceiling is not optional. This volume is shared by every rust
# container on the node, so an unbounded cache is a disk the node loses without
# anything reporting it; sccache's own LRU is the only thing that ever deletes
# from here. 2G is about twenty-five times the 78 MiB measured above, which is
# the headroom the growth actually needs: what accumulates is not the dependency
# set — that one is re-read every build and stays hot — but each task's own
# edited crates, cached once and never asked for again. Those are precisely what
# an LRU evicts first. `sccache --show-stats` prints what it is really using.
#
# One server per container, all of them evicting from the one directory, and
# the ceiling still holds: each measures the directory it shares rather than
# what it put there itself, so N containers converge on 2G total and not on
# N x 2G. What they can race on is a single entry — an eviction landing between
# another server's lookup and its read — and sccache scores that as a miss and
# compiles. Slower, never wrong: entries are content-addressed, so the worst a
# race can do is throw away work.
ENV RUSTC_WRAPPER=/usr/local/bin/sccache-sbx \
    SCCACHE_DIR=${USER_HOME}/.cache/sccache \
    SCCACHE_CACHE_SIZE=2G

# The fleet's shared store, the second level behind that volume. What is here is
# every part of it that is the same on every node: which bucket, which region,
# and that the two levels are chained rather than one replacing the other. What
# is *not* here is the endpoint and the credentials — those arrive as `-e` at run
# time from the node's own private overlay (`[sccache]` in config.private.toml;
# GlobalConfig::sccache_store, flavor::sccache_store_args), because a secret in
# an image is a secret in every registry that image reaches, and the address of
# the store is a fact about a network rather than a fact about rust.
#
# That split is also the off switch. sccache configures an S3 backend only when
# it has an endpoint, so an image on a node that has said nothing reaches no
# bucket at all: the wrapper below drops the chain and the flavor is back to the
# local volume alone, exactly as it was before any of this existed.
#
# `disk,s3` and not `s3`. A plain S3 backend *replaces* the disk cache rather
# than sitting behind it — `Cache location  s3, name: …` — which would trade a
# local hit for a network round trip on every crate. 0.17.0's multilevel chain
# keeps both, reports `Multi-level (2 levels)` with per-level counters in
# `--show-stats`, and backfills L0 from L1: a node that has never built pulls the
# fleet's work down once and hits locally forever after. `l0` is the write-error
# policy — a write that fails at L1 is a store that is unwell, not a build that
# should stop, and only an L0 failure is worth reporting. Measured: with the
# store killed after the server was up, L1 write failures were counted, the L0
# hit still hit, and every compile exited 0.
#
# Measured against a toy S3 on loopback standing in for rustfs, 16 crates, the
# arms alternated. Read the caveat at the end of this block:
#
#                            wall    L0 hits  L1 hits  overall
#   node cold, store warm      40s      0%      94%      100%   <- the point
#   node cold, no store       140s      -       -          0%   (today)
#   both levels warm           37s     94%       0%      100%   (steady state)
#   both levels cold          159s      0%       0%        0%   (fills the store)
#
# The first two lines are the case. A node that has never built this commit
# compiles nothing, because the fleet already did. Wall clock is a poor
# instrument here — readings drift ~30% inside an hour, and the two `no store`
# arms behind that 140s were 158s and 121s — but a 3.5x gap survives drift where
# a 10% one would not. CPU time is not quoted because it cannot be: with sccache
# configured the compiling happens inside its server, which is not a child of
# cargo, so `time` sees only the client stub. The one arm with no sccache at all
# is the only one whose user time means anything (41s, against 6s of stub).
#
# The 94% is 16 reads of 17; the seventeenth is the `.sccache_check` probe the
# server reads at startup. Every crate hit.
#
# Does the round trip make a hit slower than the local volume was? Yes, and
# sccache says by how much: `avg cache read hit` was 0.041-0.049s at L1 against
# 0.002-0.008s at L0. But that is paid once per object, not once per build — the
# same run backfilled all sixteen into L0 (`L0 backfills to  16`), and the warm
# arms afterwards read L1 zero times. Which is the honest bound on the whole
# thing: it buys a cold node's first build, and the first build after every
# image rebuild. It does not make a warm node faster, and it was never going to.
#
# The stand-in matters. That was a single-threaded python object store over
# loopback and not rustfs across the cluster network. It fixes the ordering — an
# L1 hit costs many times an L0 hit, and both are nothing beside a compile — and
# says nothing dependable about the real per-object latency, which has a real
# network under it and a real server on top.
#
# `SCCACHE_IDLE_TIMEOUT=0` ties the server's life to the container's, and it is
# the store's doing rather than a tuning knob. The wrapper below asks the store
# once and remembers the answer for the life of the container; a server that
# retired after its default ten idle minutes would be restarted by the next
# crate *behind* that remembered yes, with the S3 environment still set — and if
# the store had gone away in the meantime that restart is the fail-closed exit 2
# this whole arrangement exists to avoid. Never retiring makes the two lifetimes
# the same one.
ENV SCCACHE_BUCKET=sbx-sccache \
    SCCACHE_REGION=us-east-1 \
    SCCACHE_MULTILEVEL_CHAIN=disk,s3 \
    SCCACHE_MULTILEVEL_WRITE_ERROR_POLICY=l0 \
    SCCACHE_IDLE_TIMEOUT=0

# Why there is no `--dist` here.
#
# sccache can also ship compile units to build servers on other machines rather
# than shipping trees, and that is the obvious next thing to reach for once the
# two levels above have taken what they can: what is left of a fleet task's
# build is the crates that task edited, and no cache can help with those. It
# was measured, against sccache 0.17.0's own dist client with a scheduler up,
# on this workspace, `cargo test --no-run --all-targets`, `CARGO_INCREMENTAL=0`
# as the fleet's verify already sets it (orchestra::verify::wrapper). It does
# not pay, and the counter that says so is sccache's own.
#
# Of 216 compile requests on a cold cache, 135 compiled and every one of those
# was offered to a build server; 47 were never offered at all; the remaining 34
# were served from cache or were not compilations. That split is not a ratio to
# improve — it is the same split the cache above already makes. `CannotCache`
# short-circuits in rust.rs's `parse_arguments` before the dist path is
# reached, so every unit sccache refuses to cache is one it never offers to a
# server, and every unit it would distribute is one it would also cache. Which
# makes the second reading the one that decides it. The same build with the
# store warm:
#
#   Cache hits                       166   (100%)
#   Compilations                       0
#   Failed distributed compilations    0
#
# Nothing left to hand a build server. dist and the store are not two answers
# to the fleet's build cost, they are one answer twice — and the store holds
# the better half of it, because a hit is a compile that happens nowhere rather
# than one that happens somewhere else.
#
# What the store cannot reach, dist cannot reach either. Warm, that build still
# costs 28.5s and 29.7s of wall over two runs with the target directory wiped
# between them, and 102s and 106s of *child* cpu — which is the reading that
# means anything here, since the whole claim of a distributed compile is that
# it moves cpu off this box. (Cold, for scale: 86.6s wall and 136s.) All of
# that 102s is in the 47, and 83s of it is in 11 of them: `cargo test` compiles
# every crate a second time with `--test`, which passes no `--crate-type`, and
# sccache answers `CannotCache(crate-type, No crate-type passed)`. `cargo build`
# over the same warm cache is 19s of child cpu against 36 non-cacheable calls,
# and the 11 units and the 83s are exactly that difference. Compiling and
# linking the test binaries is the expensive half of `cargo test --no-run`, and
# it is permanently outside both mechanisms.
#
# And it would not fail open, which is the one rule the wrapper below exists to
# keep. In 0.17.0 a remote compile that runs and then *fails* is not retried
# locally: `dist_or_local_compile` (compiler/compiler.rs) returns `Ok` carrying
# the server's non-zero exit code with `sccache: Job failed on server` spliced
# into its stderr, and cargo sees a compile error. The local fallback beside it
# fires only on `Err`, and two kinds of `Err` are re-raised rather than fallen
# back on: an `HttpClientError`, and a toolchain archive too large for the
# client's own cache. Upstream's fix for the first of those is
# mozilla/sccache#2777, open at the time of writing. So a build server that
# dies mid-compile fails the verify rather than slowing it, and nothing
# configurable on this side changes that.
#
# The toolchain half, for the record, is the part that does work: sccache packs
# this image's rustc and sysroot in about 4s, caches the 237MiB archive under
# `~/.cache/sccache-dist-client`, and reuses it for every later crate. It was
# never the obstacle.
#
# If this is revisited, the number that has to move first is the 83s, and
# nothing on this side can move it — it needs a `--test` unit to become
# cacheable. Until then the shared store is the whole of what a compile cache
# can do for this fleet, and the coarser answer to a node with no free slot is
# the one the daemon already has: the build gate's offload, which moves a whole
# verify to a peer rather than a crate at a time (orchestra::worktree,
# GATE_SCRIPT).

USER root
RUN printf 'if [ -d %s/.cargo/bin ]; then\n  case ":$PATH:" in *":%s/.cargo/bin:"*) ;; *) PATH="%s/.cargo/bin:$PATH";; esac\n  export PATH\nfi\nexport CARGO_HOME=%s/.cargo\n' "$USER_HOME" "$USER_HOME" "$USER_HOME" "$USER_HOME" > /etc/profile.d/rust.sh \
    && chmod 0644 /etc/profile.d/rust.sh

# Fail open, which sccache will not do on its own.
#
# Before it binds its port, sccache reads a `.sccache_check` probe object out of
# *every* backend it was configured with and refuses to start if one does not
# answer — for a plain S3 backend and for a level of a chain alike. A server that
# will not start is a `RUSTC_WRAPPER` that exits non-zero, and that is a failed
# build rather than a slow one. Measured: with the store unreachable,
# `sccache rustc` exits 2 without compiling anything.
#
# So the store is asked once per container, by this wrapper, and dropped for the
# life of the container if it does not answer. Everything after the first crate
# is a shell builtin and an exec.
#
# Written into the image rather than COPYed: a bundled project Dockerfile then
# has no file beside it whose mode could be wrong, and the mode is stated here
# where it is set. /usr/local/bin for the same reason sccache itself is there.
# (Still root from the layer above.)
RUN cat > /usr/local/bin/sccache-sbx <<'SH'
#!/bin/sh
# Fail-open wrapper around sccache. See the rust flavor's Dockerfile.
if [ -n "${SCCACHE_ENDPOINT:-}" ]; then
    verdict=/tmp/.sccache-store
    if [ ! -f "$verdict" ]; then
        if out=$(/usr/local/bin/sccache --start-server 2>&1); then
            answer=up
        else
            # Another crate won the race and started the server; that it got as
            # far as binding a port means the store answered it.
            case "$out" in
                *'Address in use'*) answer=up ;;
                *)
                    answer=down
                    printf 'sccache: no answer from %s, so this build uses the local cache alone\n' \
                        "$SCCACHE_ENDPOINT" >&2
                    ;;
            esac
        fi
        # Written whole and moved into place: every crate cargo started at once
        # is in here, and a half-written verdict read by the next one is worse
        # than either answer.
        printf '%s\n' "$answer" > "$verdict.$$" 2>/dev/null &&
            mv -f "$verdict.$$" "$verdict" 2>/dev/null
    fi
    IFS= read -r seen < "$verdict" 2>/dev/null || seen=down
else
    seen=down
fi
if [ "$seen" = down ]; then
    # The chain goes with the bucket. A level named in SCCACHE_MULTILEVEL_CHAIN
    # that is not configured is itself a startup error, so half a teardown would
    # fail closed at precisely the point the whole one fails open.
    unset SCCACHE_BUCKET SCCACHE_ENDPOINT SCCACHE_REGION \
        SCCACHE_MULTILEVEL_CHAIN SCCACHE_MULTILEVEL_WRITE_ERROR_POLICY \
        AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY
fi
exec /usr/local/bin/sccache "$@"
SH
RUN chmod 0755 /usr/local/bin/sccache-sbx \
    && sh -n /usr/local/bin/sccache-sbx
USER dev
