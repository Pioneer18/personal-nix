---
status: open
parent: proxy-v2-5ech-epic
target_repo: ~/Projects/tachikoma-starter
last_updated: 2026-05-14
depends_on: [proxy-v2-10-cli-terminal-verbs]
quality_bar: production
---

# PROXY v2 — voice command mode (MV5.14)

Add a `command` mode to the `proxy-voice` daemon, alongside existing chat-dictation modes. Voice transcripts in command mode are parsed by a grammar parser into `proxy <verb>` invocations. Confirmation read-back before destructive verbs.

## Goal

User says "Hey PROXY, infil Quill on PLRM-1222 with commit clearance." proxy-voice transcribes → grammar parser → `proxy infil quill --dossier PLRM-1222 --clearance commit`. TTS reads back "Inserting Quill on PLRM-1222, commit clearance. Confirm?" User says "yes" → command executes.

## Grammar

Verb-noun-modifier:
- `infil <callsign> on <dossier> [with <clearance> clearance]`
- `status` / `status of <callsign>`
- `comms <callsign>` / `comms <callsign> on <dossier>`
- `grant <callsign>` / `grant <callsign> with <clearance>`
- `deny <callsign>`
- `exfil <callsign>` / `exfil <callsign> on <dossier>`
- `recall <callsign>` / `burn <callsign>`
- `drops` / `archive`

Disambiguation: "Quill on PLRM-1222" — if only one live Quill, "Quill" alone works. Multiple Quills → grammar requires "on <dossier>".

Read-back confirmation required for: infil, grant, deny, exfil, recall, burn. Skipped for read-only verbs: status, comms, drops, archive.

## Files in scope

- `voice/src/command_mode.rs` (new mode, sibling to existing chat-dictation modes)
- `voice/src/grammar.rs` (verb grammar parser)
- `voice/src/confirm_loop.rs` (read-back + yes/no detection)
- Voice mode switching code (existing) — add command_mode as a 5th mode

## Files out of scope

- TTS routing per-proxy (proxy-v2-15)
- Wake-word change (none — keep "Hey PROXY")
- Web UI for voice settings

## Stop condition

- [ ] `command` mode selectable via voice mode switch
- [ ] Voice utterance matching grammar parses into proxy CLI invocation
- [ ] Read-back TTS plays before destructive verbs
- [ ] Yes/no detection works (uses existing transcription)
- [ ] Status/comms/drops/archive verbs execute without confirmation
- [ ] Ambiguous refs prompt clarification ("Which Quill? On PLRM-1222 or PLRM-1300?")
- [ ] Cancel verb ("Hey PROXY, cancel") aborts current command before execution
- [ ] Existing chat-dictation modes (Wispr, Open, Off) still work

## Feedback loops

- `cd voice && cargo build`
- `cd voice && cargo test grammar::`
- Manual e2e: switch to command mode, speak each verb form, verify CLI invocation

## Quality bar

production
