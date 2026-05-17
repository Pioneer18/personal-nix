---
status: done
target_repo: ~/Projects/tachikoma-starter
github_issue: ""
failure_count: 0
last_updated: 2026-05-11
---

# Agentic shell — Off mode + mode-switching (slice shell-08)

Off mode is mic-released, zero-cost. This slice also implements the four mode-switching paths: voice command (in active modes), hotkey (Karabiner cycle), CLI, and TUI dropdown. All four paths converge on writing `proxy_voice_state.mode` + LISTEN/NOTIFY propagation.

## Goal

The user can change voice mode via any of four mechanisms; all four write to the same DB row; daemon reacts within 1 second. Mode indicator (tmux status bar + Ink TUI glyph) reflects the new mode immediately.

## Files in scope

- `voice/src/modes/off.rs` — Off mode handler (releases mic, idles)
- `voice/src/switch.rs` — central switch logic invoked by all paths
- `voice/src/voice_cmd.rs` — recognizes "PROXY, switch to <mode>" / "PROXY mute" in active modes (small classifier or pattern match on transcript)
- `voice/src/cli.rs` — CLI `proxy voice mode <name>` (extended from shell-04)
- `personal-nix/dotfiles/karabiner/proxy-voice-cycle.json` — ⌘⇧V cycles forward, ⌘⇧⌥V backward
- `apps/tui/src/components/VoiceModeDropdown.tsx` — Ink TUI clickable bottom-bar element
- `personal-nix/dotfiles/.tmux.conf.d/proxy-status-bar.tmux` — already shows mode (from shell-02), now picks up live updates

## Files out of scope

- Other voice modes' implementation (shell-05/06/07)
- TTS confirmation of mode-switch ("Switched to Open mode") — handled via shell-09

## Stop condition

- [ ] `proxy voice mode off` immediately releases the mic (verify with `lsof | grep -i mic` or similar)
- [ ] Karabiner cycle: ⌘⇧V advances Off → Wispr → Hey → Open → Off; ⌘⇧⌥V reverses
- [ ] Voice command in Hey mode: "PROXY, switch to open" → daemon recognizes, switches, optionally confirms via TTS
- [ ] TUI dropdown clickable + keyboard-navigable
- [ ] All four paths trigger the same DB write + NOTIFY; no path is lossy
- [ ] tmux status bar updates within 1s of mode change
- [ ] Mode persists across reboots (DB row is the source of truth)

## Feedback loops

- `cargo build --release`
- Manual: cycle modes via each of the four paths; verify indicator updates
- Manual: reboot; verify last-mode restored on next login

## Quality bar

production

## v3 context

Final slice of M5 (full voice modes + notifications). Completes the voice surface. Depends on shell-04 (daemon, state machine), shell-05/06/07 (the three active modes). See [ADR 002](~/Projects/tachikoma-starter/docs/adr/002-voice-daemon-proxy-voice.md) § "Mode switching" for the design.
