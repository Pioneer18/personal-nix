# personal-nix

Portable, reset-proof Claude Code substrate for any of my Macs.

## What this provides

- **CLI tooling** beyond what the RelyMD team config provides (Mac-native automation tools, etc.)
- **MCP servers** wired into Claude Code: GitHub, Postgres, GCP (TODO), AppleScript, Filesystem
- **Custom skills** symlinked into `~/.claude/skills/`
- **`~/.secrets`** populated from macOS Keychain on every rebuild (CLAUDE_CODE_OAUTH_TOKEN, GITHUB_TOKEN)

## Bootstrap on a fresh Mac

```bash
curl -fsSL https://raw.githubusercontent.com/Pioneer18/personal-nix/HEAD/bootstrap.sh | bash
```

The script:
1. Installs Determinate Nix if missing
2. Clones the RelyMD `dev-environment` repo + runs its `setup.sh`
3. Clones this repo to `~/projects/personal-nix`
4. Creates the gitignored local slot file in the team repo that imports this one
5. Pauses for interactive Keychain population (one-time per iCloud account; later Macs inherit via iCloud Keychain sync)
6. Runs `dev` to apply

## Architecture

This repo's `default.nix` is a home-manager module. It's consumed two ways:

- **On RelyMD Macs:** the team flake's gitignored `users/<slug>-<host>-local.nix` slot does `imports = [ ~/projects/personal-nix ]`. Single home-manager activation runs team + personal layers together.
- **On non-RelyMD Macs (TODO):** standalone via this repo's `flake.nix` — `homeModules.default` is exported for any consumer.

Skills under `skills/` are symlinked into `~/.claude/skills/` by the activation script. The symlink target is the **live** working directory (`~/projects/personal-nix/skills/<name>`), not a nix-store path — edit a skill, no rebuild needed.

## Day-to-day

| Want to... | Do... |
|---|---|
| Add a CLI tool | Edit `packages.nix`, run `dev` |
| Add an MCP server | Edit `mcp.nix`, run `dev` |
| Add a custom skill | `mkdir skills/<name>`, write `SKILL.md`, run `dev` once to symlink |
| Update Keychain secret | `security add-generic-password -A -U -s <name> -a $USER -w '<value>'`, then `dev` to regenerate `~/.secrets` (the `-A` is required so the home-manager activation context can read it) |
| Inspect what's set | `cat ~/.secrets`, `claude mcp list`, `ls ~/.claude/skills/` |

## What's NOT in this repo

- Secrets (those live in macOS Keychain, iCloud-synced)
- Third-party skill packs like Matt Pocock's collection (those install into `~/.agents/skills/` via the `setup-matt-pocock-skills` skill)
- Anything the team `dev-environment` already provides — no duplication

## Files

| File | Purpose |
|---|---|
| `default.nix` | Importable home-manager module (entry point) |
| `packages.nix` | Personal CLI packages |
| `mcp.nix` | MCP server registration via `claude mcp add` activation |
| `flake.nix` | Standalone consumer scaffold (non-RelyMD Macs) |
| `bootstrap.sh` | One-command setup for a fresh Mac |
| `scripts/secrets-from-keychain.sh` | Reads Keychain → writes `~/.secrets` |
| `scripts/symlink-skills.sh` | Symlinks `skills/*` → `~/.claude/skills/` (also done in activation) |
| `skills/` | Custom personal skills (each is a directory with `SKILL.md`) |
