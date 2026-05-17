---
status: open
parent: proxy-v2-5ech-epic
target_repo: ~/Projects/tachikoma-starter
last_updated: 2026-05-14
depends_on: [proxy-v2-04-presets-seed]
quality_bar: production
---

# PROXY v2 — per-proxy TTS voice routing (MV5.15)

Route TTS announcements through different macOS voices based on the emitting callsign. Each callsign has a `tts_voice` field in `proxy_presets` (seeded in proxy-v2-04). When the daemon emits an announcement, it picks the voice based on the source callsign.

## Goal

When Phantom announces "package ready," it uses the macOS voice configured for Phantom (e.g., Alex). When Echo announces "about to commit, confirm?", it uses Echo's voice (e.g., Samantha). System-level announcements (not callsign-attributed) use a default 5ECH operator voice.

## Voice mapping (picks editable in seed slice)

| Callsign | Suggested macOS voice | Character |
|---|---|---|
| Tracer | Daniel | Fast-talking, narration |
| Quill | Karen | Precise, measured |
| Phantom | Alex | Low, slow, monotone |
| Echo | Samantha | Warm, conversational |
| 5ECH (system) | Fred (or any "operator" voice) | Neutral |

User can override mapping at `~/.config/proxy/proxy.toml`:
```toml
[voices]
tracer = "Daniel"
quill = "Karen"
phantom = "Alex"
echo = "Samantha"
operator = "Fred"
```

## Files in scope

- `voice/src/tts.rs` (extend with voice-routing logic)
- `voice/src/voices_map.rs` (new — maps callsign → voice; reads from preset + proxy.toml override)
- `daemon/src/announcements.rs` (existing — when emitting, attach source callsign so voice daemon can pick correct voice)
- proxy.toml schema update (extend with [voices] section)
- Documentation in proxy.toml.example

## Files out of scope

- Command mode (proxy-v2-14)
- Adding new TTS engines (macOS `say` is sufficient for v2)

## Stop condition

- [ ] `tts_voice` from preset row used for callsign-attributed announcements
- [ ] proxy.toml `[voices]` section can override preset defaults
- [ ] All 4 callsign voices verifiably distinct via `say -v <voice>`
- [ ] System announcements use the operator voice
- [ ] Unit test: voice picker returns correct voice for each callsign
- [ ] Manual e2e: trigger each callsign to announce → distinct voices heard

## Feedback loops

- `say -v Daniel "Tracer reporting"` — confirm voice exists and sounds right
- `cd voice && cargo build && cargo test tts::`
- E2E: run proxy with all 4 callsigns active, observe distinct voices for each

## Quality bar

production
