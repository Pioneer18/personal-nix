# MCP server registration for Claude Code.
# Uses `claude mcp add --scope user` so registrations live in the per-user
# Claude config (~/.claude.json) and apply across all projects.
#
# All servers are run via `npx -y` so we don't have to nix-package each one.
# Node is provided by the team config (modules/home/team.nix → nodejs_22).
{ config, pkgs, lib, ... }:

{
  # Runs after secretsFromKeychain so we can source the just-written ~/.secrets
  # and embed tokens into per-MCP env via `claude mcp add -e KEY=VAL`.
  # Embedding (vs relying on Claude Code inheriting the spawning shell's env)
  # is the only reliable way — Claude Code spawns MCP servers in a context
  # that may not see your interactive shell's exports.
  home.activation.registerMCPServers =
    lib.hm.dag.entryAfter [ "writeBoundary" "secretsFromKeychain" ] ''
      # Need claude on PATH and node available for npx.
      export PATH="$HOME/.local/bin:${pkgs.nodejs_22}/bin:$PATH"

      if ! command -v claude >/dev/null 2>&1; then
        echo "personal-nix: claude CLI not found, skipping MCP registration"
        exit 0
      fi

      # Source ~/.secrets so we have GITHUB_PERSONAL_ACCESS_TOKEN etc. for -e flags
      if [ -f "$HOME/.secrets" ]; then
        set -a
        # shellcheck disable=SC1091
        . "$HOME/.secrets"
        set +a
      fi

      # Helper: register an MCP server, replacing any prior entry with the
      # same name. `claude mcp remove` is idempotent (no-op if missing).
      register_mcp() {
        local name="$1"; shift
        claude mcp remove --scope user "$name" >/dev/null 2>&1 || true
        if claude mcp add --scope user "$name" "$@" >/dev/null 2>&1; then
          echo "personal-nix: registered MCP '$name'"
        else
          echo "personal-nix: failed to register MCP '$name'"
        fi
      }

      # GitHub — GitHub's own server (github/github-mcp-server, from nixpkgs).
      # The -e flag embeds the token into the MCP entry in ~/.claude.json so
      # Claude Code passes it explicitly when spawning the server. Required —
      # without it, the server starts but exits immediately ('no token') and
      # Claude reports the MCP as unavailable in fresh sessions.
      if [ -n "''${GITHUB_PERSONAL_ACCESS_TOKEN:-}" ]; then
        register_mcp github \
          -e "GITHUB_PERSONAL_ACCESS_TOKEN=$GITHUB_PERSONAL_ACCESS_TOKEN" \
          -- ${pkgs.github-mcp-server}/bin/github-mcp-server stdio \
          --toolsets default,orgs,notifications
      else
        echo "personal-nix: GITHUB_PERSONAL_ACCESS_TOKEN not set, skipping github MCP"
      fi

      # Filesystem — restrict to safe roots. Add more as needed.
      register_mcp filesystem -- \
        npx -y @modelcontextprotocol/server-filesystem \
        "$HOME/projects" "$HOME/Documents" "$HOME/Desktop"

      # AppleScript — peakmojo's wrapper, the most popular AppleScript MCP.
      # Lets Claude script Mail, Calendar, Music, Safari, Finder, etc.
      register_mcp applescript -- npx -y @peakmojo/applescript-mcp

      # Tachikoma — local MCP for tachikoma_status and tachikoma_dispatch.
      # Deps are pre-installed into mcps/tachikoma-mcp/node_modules at build time.
      TACHIKOMA_MCP_DIR="$HOME/projects/personal-nix/mcps/tachikoma-mcp"
      if [ -d "$TACHIKOMA_MCP_DIR" ]; then
        (cd "$TACHIKOMA_MCP_DIR" && npm install --quiet 2>/dev/null) || true
        register_mcp tachikoma -- \
          node --experimental-strip-types "$TACHIKOMA_MCP_DIR/index.ts"
      else
        echo "personal-nix: tachikoma-mcp dir not found, skipping"
      fi

      # Shortcuts — wraps macOS Shortcuts.app. Exposes `list` + `run` tools.
      # See: mcps/shortcuts/README.md. v3 agentic-shell slice shell-10.
      SHORTCUTS_MCP_DIR="$HOME/projects/personal-nix/mcps/shortcuts"
      if [ -d "$SHORTCUTS_MCP_DIR" ]; then
        (cd "$SHORTCUTS_MCP_DIR" && npm install --quiet 2>/dev/null) || true
        register_mcp shortcuts -- \
          node --experimental-strip-types "$SHORTCUTS_MCP_DIR/index.ts"
      else
        echo "personal-nix: shortcuts-mcp dir not found, skipping"
      fi

      # Postgres — official server. Connection string is a placeholder;
      # update if you want a real default DB. Per-project DBs are usually
      # better handled with a project-scoped MCP entry instead.
      # register_mcp postgres -- npx -y @modelcontextprotocol/server-postgres "postgresql://localhost/postgres"

      # GCP — no clear winner among GCP MCP servers as of writing.
      # Candidates: @google-cloud/mcp-server-bigquery (BigQuery only),
      # community @ahmadawais/gcp-mcp, etc. Pick one and uncomment.
      # register_mcp gcp -- npx -y <package>
    '';
}
