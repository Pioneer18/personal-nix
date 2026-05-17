---
status: open
target_repo: ~/Projects/tachikoma-starter
github_issue: ""
failure_count: 0
last_updated: 2026-05-13
---

# PROXY TUI — Face / Layout Redesign

## Problem

The current TUI renders a downsampled version of `big-bmo.txt` (120×67 Unicode block chars) scaled to fill the right tmux pane. This works passably in narrow panes but breaks badly in wide panes (fullscreen Ghostty): the subsample algo upscales a coarse pixel grid into giant blocky squares that look terrible. The face also takes up too much vertical space, crowding the actual useful UI (loops, inbox, status bar).

Screenshots that capture the problem:
- Narrow pane (~93 cols): blocky but recognizable
- Full-screen pane (~170+ cols): huge pixelated mess — the subsample was designed to shrink, not enlarge

## Root cause

`Face.tsx` subsamples `big-bmo.txt` to `termCols - 4` columns. When the pane is wider than the source art (120 cols), it UPSCALES — each source character maps to multiple output characters, creating a blocky magnified look. Block character art only looks good at ≤ 1:1 scale (at most native size, never larger).

## Goals

1. Face art should look good across all pane widths — narrow split AND fullscreen.
2. The overall TUI layout should feel considered and intentional at any size.
3. Open to reconsidering: split layout vs. full-pane layout, face placement, whether to show a face at all in the TUI (vs. just the status/queue info).

## Options to explore (not prescriptive — pick the best)

### Option A — Cap art at native size, center it
Never scale the face wider than its source width (120 cols). On narrow panes, scale down. On wide panes, render at native size and center. The top/bottom UI elements expand to fill remaining space.

**Pro**: Image always looks as intended. **Con**: 120 cols is still large; narrow panes still need downsample.

### Option B — Use a smaller, purpose-built TUI face
Create a 40×20 (or similar) face file that is designed to be read at terminal font sizes rather than pixel-art-at-4px. A simpler ASCII art face (not block-char pixel art) that reads well at 1:1 terminal cell scale. Think classic ASCII art, not pixel art.

**Pro**: Looks sharp at any reasonable pane width. **Con**: Needs new art.

### Option C — Drop the face from the split pane; face goes in the status bar
Show only a small expression glyph (or nothing) in the right pane. Reserve full face rendering for the welcome screen / empty state. The right pane becomes pure queue + sensor + inbox dashboard.

**Pro**: No image scaling problems at all. Cleaner. **Con**: Less personality.

### Option D — Rethink the split entirely: TUI takes the full terminal
Instead of running as a narrow right-pane split, run the Ink TUI in its own full tmux window (tmux window 1). The chat pane stays in tmux window 0. User switches with `Ctrl-b 0/1`. Gives TUI the full terminal width to work with, enabling a richer layout (face on left, queue on right, etc.).

**Pro**: Full terminal width — real estate to do something beautiful. Face looks great at full width with proper cap. **Con**: Can't see chat + queue simultaneously.

## Stop conditions

- [ ] Face (or its absence) looks intentional and clean at both narrow split (~90 cols) and fullscreen (~190 cols).
- [ ] No horizontal wrapping or blocky upscaling artifacts.
- [ ] Loops, inbox, command bar, status bar are all clearly readable.
- [ ] `npx tsc --noEmit` passes in `apps/tui`.
- [ ] If layout changes (Option D), tmux preset in `personal-nix` is updated to match.

## Files in scope

- `apps/tui/src/components/Face.tsx`
- `apps/tui/src/lib/face.ts`
- `apps/tui/src/app.tsx`
- `apps/tui/src/faces/` (may add/replace art files)
- `personal-nix/modules/proxy-boot.nix` (if tmux layout changes)

## Files out of scope

- Web UI face rendering (separate surface, works fine)
- Daemon, voice, DB schema

## Quality bar

production
