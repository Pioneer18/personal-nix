---
status: open
parent: proxy-v2-5ech-epic
target_repo: ~/Projects/tachikoma-starter
last_updated: 2026-05-17
depends_on: [proxy-v2-26-admission-gate-5]
quality_bar: production
---

# PROXY v2 — bilingual chat surface (MV8.27)

The 5ECH boot tmux session gains a second window: window 0 runs `claude`, window 1 runs `codex`. `Ctrl-b 0` / `Ctrl-b 1` switches. tmux status bar adds a `[shell: claude|codex]` segment showing the active window's provider. The voice daemon (`proxy-voice`) becomes aware of the active window so transcripts route to the right shell.

## Goal

Login → fullscreen Ghostty + tmux session with two windows ready. Default window selected by `proxy.toml [provider].chat_default` (falls back to `claude`). Voice transcript in Hey-PROXY mode pipes to whichever window is active. *"Hey PROXY, switch to codex"* changes the active window before sending keys. *"PROXY, what's queued?"* in either window routes to the active shell. Status bar always shows current shell.

## Files in scope

- `shell/boot-script.sh` (or wherever shell-01 lives — bash script that runs at LaunchAgent fire) — amend tmux preset to spawn two windows
- `~/.tmux.conf.proxy` (or the in-repo tmux preset file) — second window + status-bar segment
- `voice/src/window_router.rs` (new) — voice-daemon module that queries tmux for active window and routes transcripts accordingly
- `voice/src/commands.rs` — add `switch_to_provider(provider)` command grammar
- `voice/src/main.rs` (wire window_router)
- `~/.config/proxy/proxy.toml.example` — document `[provider] chat_default = "claude"`

## Files out of scope

- Per-window claude/codex session config (each CLI uses its own config; out of scope for this slice)
- Cross-window memory replication (intentionally not done — separate sessions, separate memory)
- Per-window TTS routing (proxy-v2-15 owns TTS routing; this slice ensures it picks up the active window's provider)

## tmux preset sketch

```tmux
new-session -s 5ech -d
rename-window -t 5ech:0 claude
send-keys   -t 5ech:0 'claude' Enter
split-window -h -t 5ech:0
send-keys   -t 5ech:0.1 'proxy' Enter

new-window  -t 5ech -n codex
send-keys   -t 5ech:1 'codex' Enter
split-window -h -t 5ech:1
send-keys   -t 5ech:1.1 'proxy' Enter

# boot into chat_default
select-window -t 5ech:0          # or :1 — chosen by boot script env

set -g status-right '#[fg=yellow][shell: #W] #[default]#{?client_prefix,•prefix•,}'
```

The status-bar's `#W` interpolates the active window name (`claude` or `codex`). No extra wiring required.

## Voice daemon awareness

`proxy-voice` already pipes transcripts via `tmux send-keys -t 5ech:0.0`. Update to query active window first:

```rust
let active = run("tmux", &["display-message", "-p", "-t", "5ech", "#W"])?.trim();
let pane = format!("5ech:{}.0", if active == "codex" { "1" } else { "0" });
run("tmux", &["send-keys", "-t", &pane, transcript, "Enter"])?;
```

`switch_to_provider(p)` command grammar pattern: matches `"switch to (claude|codex)"` / `"route to (claude|codex)"` / `"go to (claude|codex) shell"`. Effect: `tmux select-window -t 5ech:<idx>` then proceed with the transcript (if any tail).

## Stop condition

- [ ] tmux session starts with two windows on boot
- [ ] `Ctrl-b 0` / `Ctrl-b 1` switches between Claude and Codex shells
- [ ] Each window has the Ink TUI in the right pane (independent processes — no shared state)
- [ ] Status bar shows `[shell: claude]` or `[shell: codex]` matching active window
- [ ] `proxy.toml [provider].chat_default` is honored on boot
- [ ] Voice transcripts route to active window (verified with both windows tested)
- [ ] Voice command `"switch to codex"` selects window 1; subsequent transcript goes there
- [ ] Unit tests on `voice/src/window_router.rs` for grammar matching + tmux command construction
- [ ] Manual e2e: boot, observe two shells; switch via voice; observe transcript flows to right shell

## Feedback loops

- `cargo test -p proxy-voice window_router`
- Manual: reboot session, observe behavior; record transcript handling sample

## Quality bar

production
