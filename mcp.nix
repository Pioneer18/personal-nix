# MCP server registration for Claude Code.
# Uses `claude mcp add --scope user` so registrations live in the per-user
# Claude config (~/.claude.json) and apply across all projects.
#
# All servers are run via `npx -y` so we don't have to nix-package each one.
# Node is provided by the team config (modules/home/team.nix → nodejs_22).
{ config, pkgs, lib, ... }:

{
  home.activation.registerMCPServers =
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      # Need claude on PATH and node available for npx.
      export PATH="$HOME/.local/bin:${pkgs.nodejs_22}/bin:$PATH"

      if ! command -v claude >/dev/null 2>&1; then
        echo "personal-nix: claude CLI not found, skipping MCP registration"
        exit 0
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

      # GitHub — GitHub's own server (github/github-mcp-server, packaged in
      # nixpkgs). Richer toolsets than @modelcontextprotocol/server-github;
      # enables org-scoped queries (e.g., 'list MioMarker repos') that the
      # community server flailed on.
      # Reads GITHUB_PERSONAL_ACCESS_TOKEN from env (alias of GITHUB_TOKEN
      # set in ~/.secrets by secrets-from-keychain.sh).
      register_mcp github -- \
        ${pkgs.github-mcp-server}/bin/github-mcp-server stdio \
        --toolsets default,orgs,notifications

      # Filesystem — restrict to safe roots. Add more as needed.
      register_mcp filesystem -- \
        npx -y @modelcontextprotocol/server-filesystem \
        "$HOME/projects" "$HOME/Documents" "$HOME/Desktop"

      # AppleScript — peakmojo's wrapper, the most popular AppleScript MCP.
      # Lets Claude script Mail, Calendar, Music, Safari, Finder, etc.
      register_mcp applescript -- npx -y @peakmojo/applescript-mcp

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
