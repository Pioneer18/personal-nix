---
status: done
target_repo: ~/Projects/tachikoma-starter
github_issue: ""
failure_count: 0
last_updated: 2026-05-12
---

# proxy-voice TTS — mode-switch announcements + Stop hook (shell-09, M2)

Wire the existing TTS subsystem (`voice/src/tts/`) into two remaining surfaces:
1. **Mode-switch announcement** — speak a confirmation phrase when the active voice mode changes (e.g. "Hey mode" / "Switching off").
2. **Claude Code Stop hook** — pipe the last assistant message through the TTS engine after each claude-code response so Hey/Open mode reads replies aloud.

TTS infrastructure (engine trait, `say` + ElevenLabs backends, sentence chunker, config) is already implemented in `voice/src/tts/`. This slice is wiring, not new infrastructure.

## Goal

After this slice ships:
- Every mode transition announced via a short spoken label ("Hey mode", "Wispr", "Open", "Off") regardless of which of the four switching paths triggered it.
- In Hey and Open modes, the last assistant reply is read aloud after `claude` exits — users can continue a task without looking at the screen.
- TTS is gated on `proxy.toml [voice.tts] enabled_modes` — default: Hey + Open. Wispr + Off stay silent.

## Files in scope

- `voice/src/announce.rs` — `pub fn announce(mode: VoiceMode, engine: &dyn TtsEngine) -> anyhow::Result<TtsHandle>` — maps each mode to a short phrase and calls `engine.speak()`.
- `voice/src/supervisor.rs` — call `announce()` inside `react_to_transition` after tearing down the prior mode, before spawning the new one. Engine loaded once at startup from config.
- `voice/src/main.rs` — pass engine into supervisor; load config at daemon startup.
- `hooks/stop-tts.sh` — Claude Code Stop hook: reads `CLAUDE_CODE_LAST_RESPONSE` (or stdin), calls `proxy-voice tts` with the text if current voice mode is in enabled_modes. Install path: `~/.claude/hooks/stop.sh`.
- `voice/src/tts/mod.rs` — expose `announce_phrase(mode: VoiceMode) -> &'static str` helper for the announce module to use. (No new engine code — reuse existing `say.rs` and `elevenlabs.rs`.)
- `proxy.toml.example` — add `[voice.tts]` block with engine/voice/rate/enabled_modes documented.

## Files out of scope

- New TTS engine backends (ElevenLabs MCP wiring is already stubbed; leave TODO).
- Notification sounds / non-TTS audio feedback.
- Any changes to `voice/src/tts/chunk.rs`, `say.rs`, `elevenlabs.rs` — only wiring changes.

## Stop condition

- [ ] `cargo build --release` clean for workspace.
- [ ] Mode switch (via CLI `proxy voice mode hey`) plays a spoken announcement audible on macOS.
- [ ] `proxy-voice tts --text "Hello world" --mode hey` speaks via `say`.
- [ ] `hooks/stop-tts.sh` exists and is documented in `proxy.toml.example`.
- [ ] `voice/src/announce.rs` tested: `announce_phrase(VoiceMode::Hey)` returns non-empty str.

## Feedback loops

- `cargo test -p proxy-voice`
- Manual: `proxy voice mode hey` → hear "Hey mode"
- Manual: run `echo "test response" | hooks/stop-tts.sh` → hear speech

## Quality bar

production

## Context refs

- `voice/src/tts/mod.rs` — TtsEngine trait, TtsConfig, init()
- `voice/src/supervisor.rs` — react_to_transition() — integration point
- `voice/src/switch.rs` — FORWARD_CYCLE, source constants
- ADR 002 (`docs/adr/002-voice-daemon-proxy-voice.md`) — voice mode design
