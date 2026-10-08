---
title: "Personal skill missing on another Mac after running dev"
tags: [personal-nix, skills, multi-machine, dev]
last_updated: "2026-10-08"
---

# Personal skill missing on another Mac after `dev`

**Symptom:** a skill such as `/desk` works on one Mac. You run `dev` on the other Mac and the skill is still not there.

**Cause:** `dev` in `~/Projects/dev-environment` installs only team skills. Personal skills live in `~/projects/personal-nix/skills/`. personal-nix's activation script (`default.nix`) symlinks them into `~/.claude/skills/`. If the source Mac did not push personal-nix, the other Mac has nothing to link.

**Fix:**
1. On the source Mac: commit in personal-nix, then `git status -sb` must show no "ahead". Push.
2. On the other Mac: `git pull` in personal-nix, then run `dev`.
3. Skills that keep their own data need that data repo too. Example: `/desk` needs `git clone git@github.com:Pioneer18/desk ~/projects/desk`.

First seen 2026-10-08: `/desk` was committed locally, but personal-nix had 15 commits that were not pushed.
