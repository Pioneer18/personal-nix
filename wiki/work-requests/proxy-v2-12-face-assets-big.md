---
status: open
parent: proxy-v2-5ech-epic
target_repo: ~/Projects/tachikoma-starter
last_updated: 2026-05-14
depends_on: [proxy-v2-09-cli-runtime-verbs]
quality_bar: production
---

# PROXY v2 — face assets: big ASCII art + splash (MV4.12)

Create the signature big-ASCII-art for each callsign + a 5ECH splash piece. Used in detail views (`proxy comms <ref>` header), splash screens, voice-mode banners.

## Goal

Each callsign has 1-2 signature big-art ASCII pieces (10-30 lines tall) capturing the callsign's character. Plus one 5ECH station splash piece.

## Per-callsign big art

Each callsign gets:
- `signature.txt` — the resting big-art face (10-30 lines)
- (Optional) `live.txt` — a live-state variant

Design notes:
- Tracer: visually active / loud — could be styled with motion lines or emphatic asymmetry
- Quill: precision / minimal — clean linework, focused
- Phantom: shadow / deep — heavy fill, monochrome
- Echo: warm / conversational — softer curves, friendly

Use block characters (░▒▓█) or pure ASCII (-|+/\) — pick a style and apply consistently.

## 5ECH splash

`splash.txt` — used at boot, empty section state alternative, "5ECH out" sign-off contexts. Should evoke the station/handler-room vibe.

Original draft has a header like:
```
        >_<        o_o        -_-        ◕‿◕
      TRACER     QUILL     PHANTOM      ECHO

                  P R O X Y
                5th Echelon
```
That could be the splash, refined.

## Files in scope

- `apps/tui/src/faces/<callsign>/big/signature.txt` (4 files)
- `apps/tui/src/faces/big/splash.txt` (1 file)
- `apps/web/public/faces/big/<callsign>/signature.txt` (4 files)
- `apps/web/public/faces/big/splash.txt` (1 file)

## Files out of scope

- Small faces (proxy-v2-11)
- Rendering components (proxy-v2-13)

## Stop condition

- [ ] 4 signature big-art files (one per callsign), each 10-30 lines
- [ ] Each big-art matches the callsign's character per design notes
- [ ] Consistent line-art style across all 4 (don't mix block-chars with pure-ASCII)
- [ ] 1 splash file (5ECH banner) usable at boot
- [ ] Files load and display correctly in macOS Terminal, iTerm, Ghostty

## Feedback loops

- Render each big-art via `cat <file>` in terminal — visual review
- Compare across the 4 callsigns side-by-side — characters distinguishable?

## Quality bar

production (visual craft pass)
