---
status: done
target_repo: ~/Projects/tachikoma-starter
github_issue: ""
failure_count: 0
last_updated: 2026-05-11
---

# Agentic shell — Open mode (slice shell-07)

Continuous-conversation voice mode. Mic is always live; VAD (Voice Activity Detection) segments speech; every utterance is transcribed by whisper.cpp and piped to the chat pane. No wake-word required — just talk. Most seamless but highest battery + privacy cost.

## Goal

With `proxy voice mode open` active: user speaks naturally; each utterance (separated by ~800ms of silence per VAD) is transcribed and piped to the chat pane via `tmux send-keys`. Claude responds; TTS reads the response aloud (shell-09).

## Files in scope

- `voice/src/modes/open.rs` — Open mode state machine
- `voice/src/vad.rs` — VAD wrapper (use `webrtc-vad` Rust crate or a port of WebRTC VAD)
- `voice/src/audio_stream.rs` — continuous audio stream from coreaudio-sys; chunks fed to VAD
- `voice/Cargo.toml` — add `webrtc-vad`, `coreaudio-rs` deps

## Files out of scope

- Wake-word (shell-05 handles for Hey mode; Open doesn't need it)
- Other modes
- TTS (shell-09)
- Battery-aware auto-downgrade (v1.5)

## Stop condition

- [ ] With `proxy voice mode open` active, mic is live continuously
- [ ] Speak 1 sentence → ~800ms pause → next sentence → both arrive as separate transcripts in chat pane within ~1s each
- [ ] Whisper.cpp model stays loaded (no per-utterance reload, ~150 MB resident while in Open mode)
- [ ] Background noise (typing, traffic) does NOT trigger VAD (sensitivity tuned)
- [ ] CPU usage ~5-7% on M4 Pro while idle-listening; ~15-20% during active speech (acceptable)
- [ ] Battery cost ~5-6W (logged baseline; acceptable for AC-mode use)
- [ ] Mode switch out of Open releases the audio stream + unloads whisper within 2s

## Feedback loops

- `cargo build --release`
- Manual: speak naturally for a few minutes; verify transcripts are coherent; tune VAD sensitivity
- Manual: monitor `top` for CPU usage in idle vs active speech
- Manual: monitor `pmset -g batt` battery drain rate while in Open mode

## Quality bar

production

## v3 context

Slice in M5 (full voice modes). Depends on shell-04 (daemon), shell-09 (TTS since Open should auto-speak responses). See [ADR 002](~/Projects/tachikoma-starter/docs/adr/002-voice-daemon-proxy-voice.md) for the privacy/battery tradeoff rationale.
