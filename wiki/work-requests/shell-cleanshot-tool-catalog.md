---
status: done
target_repo: ~/Projects/tachikoma-starter
github_issue: ""
failure_count: 0
last_updated: 2026-05-12
---

# CleanShot X integration into PROXY tool catalog (slice shell-cleanshot)

Wire CleanShot X (installed via nix cask `cleanshot`, see [[cleanshot]]) into PROXY's tool catalog (ARCHITECTURE.md § 18) as a scripted-fast layer for screenshot + screen-record + GIF capture. Lets voice modes and the chat tab trigger captures via natural language without GUI.

## Goal

After this slice ships:
- Chat tab user can say "PROXY, screenshot this error" → CleanShot captures active window → saves to `~/Pictures/Screenshots/` with PROXY-supplied name → path returned to chat for inline reference.
- Voice modes (Hey/Open/Wispr) can trigger same.
- Annotated wiki/notes/ captures become 1-step instead of manual GUI.
- ADR/RFC drafts can request "record a 5s GIF of voice mode flow" → CleanShot records → outputs `~/Pictures/Screenshots/proxy-voice-2026-XX-XX.gif`.

## Integration path

CleanShot supports:
1. **URL scheme** `cleanshot://` — `capture-area`, `capture-window`, `record-screen`, etc. (per CleanShot docs)
2. **Shortcuts actions** — "Capture", "Record Screen", "Pin", etc.
3. **AppleScript** — full automation surface.

PROXY tool catalog already plans Shortcuts MCP (shell-10) + AppleScript layer. **Preferred path: Shortcuts MCP dispatch** — CleanShot exposes Shortcuts actions natively, and `mcp__shortcuts__run` already exists in the MCP catalog.

## Files in scope

- `apps/web/src/lib/tool-catalog/cleanshot.ts` — registration entry (name, description, args schema, dispatcher)
- `apps/tui/src/tool-catalog/cleanshot.ts` — same for TUI
- `docs/ARCHITECTURE.md` § 18 — add CleanShot under "scripted-fast" priority chain
- `daemon/src/tool_catalog/` — Rust-side dispatch helper (calls `shortcuts run "<action>"` via subprocess)
- A pre-built macOS Shortcut `PROXY Capture Area`, `PROXY Record GIF`, etc. — bundled in repo as `.shortcut` files in `assets/shortcuts/` for first-run wizard to install

## Files out of scope

- CleanShot itself (already nix-managed)
- Custom MCP for CleanShot (Shortcuts MCP suffices — no need for a dedicated layer)
- Cloud upload integration (defer to v1.5 — Pro tier dependent + URL handling is a separate ADR)
- Computer-use overlap (CleanShot is scripted-fast; computer-use is the slow fallback for cases not covered by CleanShot's Shortcuts surface)

## Dependencies

- shell-10 Shortcuts MCP must ship first (M1) — provides the dispatch primitive
- CleanShot installed (✓ done 2026-05-12)
- License key migrated to Keychain `cleanshot_license` (user pending)

## Acceptance

1. `claude` CLI in chat tab can call a `cleanshot.capture_area` tool → file saved to `~/Pictures/Screenshots/<name>.png` → returns path
2. Voice command "Hey PROXY, screenshot active window as `auth-bug-2026-05-13.png`" works end-to-end
3. ARCHITECTURE.md § 18 lists CleanShot under scripted-fast layer with example invocations
4. Bundled shortcuts files installable via first-run wizard or manual `shortcuts run PROXY\ Capture\ Area`

## Why this earns a slice

CleanShot was just adopted (2026-05-12). Screenshot/GIF capture is high-frequency for: wiki note milestones, ADR diagrams, bug reports to RelyMD/MioMarker, demo loops. Routing through the tool catalog instead of manual GUI capture means voice + chat can both produce well-named, well-located artifacts — closing the loop between "I want to document X" and "X is documented in the right tier."

## References

- [[cleanshot]] tool stub
- ARCHITECTURE.md § 18 (tool catalog)
- ADR 001 (agentic shell scope) — establishes tool catalog as a v3 surface
