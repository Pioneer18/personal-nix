---
name: orient-to-machine
description: Architectural map of Pioneer18's Mac (nix-darwin + home-manager, two layers — team RelyMD `dev-environment` + personal `personal-nix`). Covers where things live, layer ownership, recipes for common modifications (add CLI tool, MCP server, skill, secret, GUI app), the `dev` rebuild command, rollback, and bootstrap on a fresh Mac. Use when a new session needs context about this machine's structure, when asking "where does X live" or "how do I change Y", when planning ANY modification to nix config or MCP servers, when debugging a failed `dev` run, or when starting work that interacts with system config.
---

# Machine map

## TL;DR

This Mac runs a two-layer nix-darwin + home-manager setup. One command — `dev` — rebuilds both layers atomically. The team layer is shared; the personal layer is private and reset-proof via a public personal-nix repo + macOS Keychain (iCloud-synced) for secrets.

## Repo layout

```
~/Projects/dev-environment/                     ← TEAM repo (github.com/relymd/dev-environment)
  flake.nix                                      ← entry point; defines darwinConfigurations
  modules/darwin/common.nix                      ← team-wide system settings
  modules/home/team.nix                          ← team home-manager (nodejs, postgres, zsh, etc.)
  modules/home/defaults.nix                      ← overridable defaults
  hosts/jonathan-sells-darwin.nix                ← MY homebrew casks, dock, launchd agents
  users/jonathan-sells.nix                       ← MY home-manager (eas-cli, claude settings)
  users/jonathan-sells-MacBook-Pro-2-local.nix   ← gitignored slot importing personal-nix

~/projects/personal-nix/                        ← PERSONAL repo (github.com/Pioneer18/personal-nix)
  default.nix                                    ← entry; imports packages.nix + mcp.nix; activations
  packages.nix                                   ← personal CLI packages
  mcp.nix                                        ← MCP server registration via `claude mcp add`
  skills/                                        ← my custom skills (symlinked into ~/.claude/skills/)
  scripts/secrets-from-keychain.sh               ← Keychain → ~/.secrets each `dev` run
  scripts/symlink-skills.sh                      ← standalone version of activation symlinker
  bootstrap.sh                                   ← one-command fresh-Mac setup
  flake.nix                                      ← exposes homeModules.default for non-RelyMD use
```

## The one command

`dev` (wrapper at `~/.local/bin/dev` → `~/Projects/dev-environment/setup.sh`) rebuilds everything. Run from any directory; setup.sh internally cd's. Under the hood: `sudo -E darwin-rebuild switch --impure --flake .#jonathan-sells-MacBook-Pro-2`. The `--impure` + `sudo -E` is required because the team flake reads `PWD` to find the gitignored local slot.

## Layering rules (where to edit what)

| To change... | Edit... | Notes |
|---|---|---|
| Personal CLI tool | `personal-nix/packages.nix` | Don't duplicate team's list |
| Personal MCP server | `personal-nix/mcp.nix` | Uses `claude mcp add --scope user` |
| Custom skill | `personal-nix/skills/<name>/SKILL.md` | Symlinked into `~/.claude/skills/` |
| Personal Keychain secret | `security add-generic-password -A -U -s <name> -a $USER -w '<value>'` then update `secrets-from-keychain.sh` if new var | iCloud-synced |
| GUI app (Homebrew cask) | `dev-environment/hosts/jonathan-sells-darwin.nix` | Per-machine team file, OK to edit |
| Personal git/zsh override | `dev-environment/users/jonathan-sells.nix` | Per-user team file, OK to edit |
| Anything for the whole team | Team repo files outside `users/` and `hosts/` | Coordinate — shared with coworkers |

## Task recipes

### Add a personal CLI tool
1. Verify it's in nixpkgs: `nix eval --raw nixpkgs#<name>.meta.description` (404 = not packaged)
2. Add to `personal-nix/packages.nix`
3. `dev`
4. Verify: `command -v <tool>` (note: some tools install with different binary names, e.g. `switchaudio-osx` → `SwitchAudioSource`)

### Add a personal MCP server
1. Edit `personal-nix/mcp.nix`, add a `register_mcp` line. Use `${pkgs.<package>}/bin/<binary>` for nix-installed servers, or `npx -y <package>` for node-based. Pass any required env vars via `~/.secrets`, not via `--env` to claude mcp add.
2. `dev`
3. Verify: `claude mcp list`

### Add a custom skill
1. `mkdir personal-nix/skills/<name>`
2. Write `personal-nix/skills/<name>/SKILL.md` with frontmatter (`name`, `description` — see ~/.claude/skills/write-a-skill/SKILL.md for full spec)
3. `dev` once to symlink (or `bash personal-nix/scripts/symlink-skills.sh` for faster iteration)
4. Edits to the SKILL.md take effect immediately — symlinks point at the live working tree, no rebuild needed for content changes

### Update / add a Keychain secret
1. `security add-generic-password -A -U -s <keychain-name> -a "$USER" -w '<value>'` (the `-A` allows any-app access)
2. If it's a new var (not just rotating an existing one), also edit `personal-nix/scripts/secrets-from-keychain.sh` to add a `read_keychain` line
3. `dev` to refresh `~/.secrets`
4. `exec zsh -l` to re-source

### Add a GUI app (Homebrew cask)
1. Edit `~/Projects/dev-environment/hosts/jonathan-sells-darwin.nix`, append to `homebrew.casks`
2. `dev`

### Roll back a broken `dev` run
- `sudo darwin-rebuild --rollback` (one generation back)
- Or `sudo darwin-rebuild switch --to-generation N` (find with `darwin-rebuild --list-generations`)

### Verify what's actually installed/registered
- CLI packages: `ls /etc/profiles/per-user/pioneer/bin/`
- MCPs: `claude mcp list`
- Skills: `ls -la ~/.claude/skills/`
- Secrets: `cat ~/.secrets` (file is mode 600)
- Generations: `sudo darwin-rebuild --list-generations`

## Bootstrap on a fresh Mac

```bash
curl -fsSL https://raw.githubusercontent.com/Pioneer18/personal-nix/HEAD/bootstrap.sh | bash
```

The script is idempotent. If iCloud Keychain has already synced from another Mac, secrets restore automatically. See `personal-nix/README.md` for full details.

## Common gotchas

- **Activation scripts have sanitized PATH** — use absolute paths (`/usr/bin/security`, etc.) for system binaries. Plain `security` will fail with "command not found" inside `home.activation.*`.
- **Local slot file is gitignored** — `*-local.nix` matches at any depth. Won't show in `git status` but `nix` may print "uncommitted changes" warnings.
- **`~/.gitconfig.backup`** appears after each `dev` run because team home-manager re-detects the prior file. Safe to delete once you've migrated any custom settings.
- **Some packages are brew-only, not in nixpkgs** (e.g. `displayplacer`). For those, add to `homebrew.brews` in `hosts/jonathan-sells-darwin.nix` instead.
- **MCP changes need a fresh Claude Code session** — `claude mcp add` updates `~/.claude.json` but already-running sessions don't reload.

## When NOT to use this skill

If the user is asking purely about the team's work (RelyMD platform code, shared team conventions, Slack/Linear/Jira workflows) — that's not what this skill covers. This is purely about the machine's nix-managed config substrate.
