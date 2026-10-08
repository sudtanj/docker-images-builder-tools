# syntax=docker/dockerfile:1

# Paseo (https://github.com/getpaseo/paseo) + Codex CLI + Claude Code CLI.
#
# Paseo's own published image ships NO agent CLIs by default - its docs
# (docs/docker.md, "Installing Agents") document exactly this pattern:
# FROM the base image, USER root, npm install -g whichever agent CLIs you
# want, and leave the child image's user as root (Paseo's own entrypoint
# is the thing that drops privileges to the non-root `paseo` user, for
# both the daemon itself and any agent it launches).
#
# On top of that, this adds this repo's own BYOK support for both agents,
# entirely through env vars (see entrypoint.sh + configure-codex-provider.sh,
# and the `environment:` block in docker-compose.yml / docker-compose.hub.yml
# - all runtime config lives right there in the compose YAML, no .env files):
#   - Codex: point it at any OpenAI-Responses-API-compatible endpoint via
#     CODEX_BASE_URL / CODEX_API_KEY / CODEX_MODEL (generates
#     ~/.codex/config.toml at startup).
#   - Claude Code: ANTHROPIC_API_KEY / ANTHROPIC_AUTH_TOKEN /
#     ANTHROPIC_BASE_URL / ANTHROPIC_MODEL are read natively by Claude Code
#     from the environment on every launch - no config file to generate,
#     Paseo's daemon just inherits and passes them through.
FROM ghcr.io/getpaseo/paseo:latest

USER root

RUN npm install -g @anthropic-ai/claude-code && npm install -g @openai/codex

# GitHub CLI (gh) - so Codex/Claude Code sessions (running as `paseo`, working in
# /workspace) can clone private repos via `gh repo clone` / `gh auth login`
# using GH_TOKEN, rather than needing SSH keys mounted into the container.
# Base image is Debian bookworm-slim (node:22-bookworm-slim) - install from
# GitHub's own apt repo per https://github.com/cli/cli/blob/trunk/docs/install_linux.md.
RUN (type -p wget >/dev/null || (apt-get update && apt-get install -y wget)) \
    && mkdir -p -m 755 /etc/apt/keyrings \
    && wget -nv -O /etc/apt/keyrings/githubcli-archive-keyring.gpg https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    && chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update \
    && apt-get install -y gh \
    && rm -rf /var/lib/apt/lists/*

COPY configure-codex-provider.sh /usr/local/bin/configure-codex-provider
COPY entrypoint.sh /usr/local/bin/paseo-codex-entrypoint
RUN chmod +x /usr/local/bin/configure-codex-provider /usr/local/bin/paseo-codex-entrypoint

# Stays root here on purpose (see comment above) - Paseo's own entrypoint,
# which this wraps and hands off to, handles dropping to the `paseo` user
# itself via gosu.

ENTRYPOINT ["/usr/local/bin/paseo-codex-entrypoint"]
# Explicit empty CMD: guarantees a plain `docker run <this image>` (no
# command) passes zero args to the entrypoint, which is what makes Paseo's
# own entrypoint take its "start the daemon" branch rather than its
# "exec the passed command" branch - regardless of whatever CMD the base
# image happened to inherit further up its own build chain.
CMD []
