---
title: Route CleanShot X screenshots to ~/Pictures/Screenshots
tags: [macos, cleanshot, hygiene, tier-3]
---

# Route CleanShot X screenshots to `~/Pictures/Screenshots/`

## Problem

`defaults write com.apple.screencapture location <path>` only redirects **native macOS** screenshots (⌘⇧3 / ⌘⇧4 / ⌘⇧5 without an interceptor). When CleanShot X is installed and intercepting hotkeys, it uses its **own** save-to-disk location, which by default is `~/Desktop/`.

CleanShot stores the save path as a **security-scoped bookmark** (binary blob in `~/Library/Preferences/pl.maketheweb.cleanshotx.plist`). You cannot set it via `defaults write` or by editing the plist — you must use the GUI so macOS can mint a fresh bookmark scoped to the new path.

## Fix

1. Open CleanShot X → menu-bar icon → **Settings** (⌘,)
2. **Quick Access** tab (left sidebar) → **Save to disk** section → folder picker → pick `~/Pictures/Screenshots/`
3. **General** tab → confirm "Save screenshots to" matches (some CleanShot versions split the two)
4. **Quick Access** tab → confirm "After capture: Save to disk" is enabled if you want auto-save
5. Take a test screenshot. Verify the file lands in `~/Pictures/Screenshots/` and **not** `~/Desktop/`

## Native macOS path (already set, but document for completeness)

```bash
defaults write com.apple.screencapture location ~/Pictures/Screenshots
killall SystemUIServer
```

## Maintenance

`~/Pictures/Screenshots/` is **Tier 3 ephemeral** — never back it up, prune on a cadence.

The bulk of space in this folder is screen **recordings** (`.mov`), not screenshots (`.png`). One careless long recording can easily be 10–20 GB. Audit periodically:

```bash
# Top 15 biggest files
find ~/Pictures/Screenshots -maxdepth 1 -type f -exec du -h {} + | sort -rh | head -15

# Delete all .mov files older than 30 days (recover most of the space)
find ~/Pictures/Screenshots -maxdepth 1 -type f -iname "*.mov" -mtime +30 -delete

# Or full nuke of anything older than 30 days
find ~/Pictures/Screenshots -maxdepth 1 -type f -mtime +30 -delete
```

## Historical baseline

- 2026-05-12: Folder was 19 GB / 562 files. Deleted 54 .mov files older than 30 days → 258 MB.
  One single recording (`Screen Recording 2026-03-31 at 11.46.11 AM.mov`) was 16 GB by itself.
  Routing was already correct for native macOS shortcuts but CleanShot was still dropping
  PNGs on `~/Desktop/`.

## Related

- `~/projects/personal-nix/wiki/INDEX.md` — wiki entry point
- `mac-filesystem-hygiene` skill — full filesystem hygiene model (Tier 3 = ephemeral)
