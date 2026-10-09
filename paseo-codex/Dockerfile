# syntax=docker/dockerfile:1

ARG PASEO_VERSION=latest

# ---------- Stage 1: build everything that needs tooling ----------
FROM ghcr.io/getpaseo/paseo:${PASEO_VERSION} AS builder
USER root

ARG CLAUDE_CODE_VERSION=latest
ARG CODEX_VERSION=latest
ARG GH_VERSION=2.63.2
ARG TARGETARCH

# Agent CLIs into an isolated prefix so we can copy just this directory
RUN --mount=type=cache,target=/root/.npm \
    npm install -g --no-audit --no-fund --loglevel=error \
      --prefix /opt/agents \
      @anthropic-ai/claude-code@${CLAUDE_CODE_VERSION} \
      @openai/codex@${CODEX_VERSION} \
 && find /opt/agents -type f \( -name "*.map" -o -name "*.md" \) -delete

# gh as a single static binary (no apt repo, no apt layers)
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl \
 && curl -fsSL "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_${TARGETARCH:-amd64}.tar.gz" \
    | tar -xz -C /tmp \
 && install -m 755 /tmp/gh_${GH_VERSION}_linux_${TARGETARCH:-amd64}/bin/gh /usr/local/bin/gh-bin

# ---------- Stage 2: runtime ----------
FROM ghcr.io/getpaseo/paseo:${PASEO_VERSION}
USER root

# Same base image => same Node ABI, so native deps copy over safely.
# Symlinks in /opt/agents/bin are relative, so they survive the move.
COPY --from=builder /opt/agents/ /usr/local/
COPY --from=builder /usr/local/bin/gh-bin /usr/local/bin/gh

# Low-resource Paseo defaults. /home/paseo is a persistent volume, so this is
# only a seed: entrypoint.sh copies it to ~/.paseo/config.json on first start
# and never overwrites an existing config.
# Disable providers you don't use; add "codex": { "enabled": false } if unused.
COPY --chmod=644 <<'EOF' /usr/local/share/paseo/config.default.json
{
  "daemon": {
    "mcp": { "injectIntoAgents": false },
    "browserTools": { "enabled": false }
  },
  "agents": {
    "catalogRefreshTimeoutMs": 30000,
    "metadataGeneration": {
      "providers": [
        { "provider": "claude", "model": "claude-haiku-4-5-20251001", "thinkingOptionId": "low" }
      ]
    },
    "providers": {
      "opencode": { "enabled": false },
      "copilot": { "enabled": false },
      "pi": { "enabled": false }
    }
  }
}
EOF

COPY --chmod=755 configure-codex-provider.sh /usr/local/bin/configure-codex-provider
COPY --chmod=755 entrypoint.sh /usr/local/bin/paseo-codex-entrypoint

# Cap Node's heap so it GCs before the kernel OOM-kills it (lower to 384 if
# needed), and stop Claude Code's background updater/telemetry from doing work.
ENV NODE_OPTIONS=--max-old-space-size=512 \
    DISABLE_AUTOUPDATER=1 \
    DISABLE_TELEMETRY=1 \
    CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1

# Stays root: Paseo's own entrypoint drops to `paseo` via gosu.
ENTRYPOINT ["/usr/local/bin/paseo-codex-entrypoint"]
CMD []
