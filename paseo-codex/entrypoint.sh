#!/usr/bin/env bash
set -euo pipefail

# Thin wrapper around Paseo's own entrypoint (docker/base/rootfs/usr/local/
# bin/paseo-docker-entrypoint in https://github.com/getpaseo/paseo, run via
# tini as PID 1 - see its Dockerfile). Runs Codex BYOK config generation
# FIRST, then hands off to Paseo's original entrypoint completely
# unchanged (same tini wrapping, same root -> gosu-to-paseo privilege
# drop, same "exec the passed command" vs. "start the daemon" branching),
# via `exec` so the wrapper's own process gets replaced rather than
# lingering as an extra layer.
#
# This has to run before EITHER of Paseo's own two modes: starting the
# daemon (which will launch Codex and Claude Code sessions on demand) or a
# direct `docker exec --user paseo <container> codex` / `claude` (per
# Paseo's docs) - both need ~/.codex/config.toml already correct.
#
# Claude Code, unlike Codex, needs NO generated config file here: its
# ANTHROPIC_API_KEY / ANTHROPIC_AUTH_TOKEN / ANTHROPIC_BASE_URL /
# ANTHROPIC_MODEL settings are plain env vars it reads natively on every
# launch, and Paseo's daemon inherits them from this same environment when
# it starts (identical to how OPENAI_API_KEY already reaches Codex
# sessions). They therefore also never need to be written into the
# persisted ~/.claude volume - set them in the compose `environment:` block
# (docker-compose.yml / docker-compose.hub.yml, where ALL of this image's
# config lives) and they apply from the next container start with no
# rebuild.

# Match Paseo's own entrypoint defaults (CODEX_HOME is already set in the
# base image's ENV, but default it the same way here too in case this
# entrypoint is ever invoked outside that image, e.g. local testing).
: "${HOME:=/home/paseo}"
: "${CODEX_HOME:=${HOME}/.codex}"
export HOME CODEX_HOME

/usr/local/bin/configure-codex-provider

# configure-codex-provider runs as whatever user this script is currently
# running as - which is root here, since Paseo's own base image never
# sets USER (it stays root at the Dockerfile level and drops privileges
# per-invocation via gosu instead, see docker/base/rootfs). A root-owned
# config.toml would then be unwritable by the actual `paseo` user (uid
# 1000) that the daemon and launched agents run as - the same class of
# bug the claude-code-claudish-happy image hit with its config volumes.
# Fix it the same way Paseo's own entrypoint fixes freshly-created
# directories: chown back to paseo:paseo, only when actually running as
# root (a `docker run --user paseo ...` override needs no fixing at all).
#
# Also covers $HOME/.config (gh's config.yml/hosts.yml included) and
# $HOME/.claude (Claude Code's own config/credentials, written if anyone
# ever runs `claude /login` inside the container) - easy to
# end up root-owned too if anyone ever runs `docker exec` (which defaults
# to root, not `--user paseo`) and invokes `gh` or another tool that writes
# there, permanently breaking it for the `paseo` user afterwards since this
# is all on the persistent paseo-home volume. Self-heals on every restart.
if [ "$(id -u)" = "0" ]; then
    chown -R paseo:paseo "$CODEX_HOME" "$HOME/.config" "$HOME/.claude" 2>/dev/null || true
fi

# gh CLI: if GH_TOKEN (or GITHUB_TOKEN) is set, wire it up as a git
# credential helper so plain `git clone`/`git pull` of private repos in
# /workspace work too, not just `gh` subcommands (which already pick up
# the token from the env on every invocation with no setup needed).
# `gh auth setup-git` just writes gitconfig - the token itself stays in
# the env and is re-read by the helper on every git operation, so this
# only needs to run once per container start, before dropping to `paseo`
# (same gosu Paseo's own entrypoint uses to run everything else as that
# user - see docker/base/rootfs/usr/local/bin/paseo-docker-entrypoint).
if [ "${GH_TOKEN:-${GITHUB_TOKEN:-}}" != "" ] && [ "$(id -u)" = "0" ]; then
    gosu paseo gh auth setup-git 2>/dev/null || true
fi

exec /usr/bin/tini -- /usr/local/bin/paseo-docker-entrypoint "$@"
