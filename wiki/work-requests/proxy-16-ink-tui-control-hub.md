---
status: done
target_repo: ~/Projects/tachikoma-starter
github_issue: ""
failure_count: 0
last_updated: 2026-05-11
---

# PROXY — Ink TUI Control Hub

A hybrid live dashboard + command bar built with Ink (React for terminals). Shows running loops, recent feed items, and PROXY's BMO ASCII face reacting to system state. Command bar at the bottom for start/stop/queue commands.

## Goal

Running `proxy` in the terminal opens a live TUI that updates in real time, shows PROXY's BMO face, and accepts commands without leaving the terminal. Feels like `htop` but for your agent fleet.

## Files in scope

- `apps/tui/**` (new Turborepo app)
- BMO ASCII face files from `~/Desktop/bmo faces/set/` (copy -small.txt variants into `apps/tui/src/faces/`)
- `turbo.json` (add tui app to pipelines)

## Files out of scope

- Web UI changes

## Stop condition

- [ ] `apps/tui` package with its own `package.json`, built with Ink + TypeScript
- [ ] `proxy` CLI command available via `npm link` or Turborepo bin config
- [ ] Layout: PROXY BMO face top-center (expression driven by system state), running loops pane (left/main), recent feed items pane (right/secondary), command bar at bottom
- [ ] Face expressions: `smile` (no running loops, no unread), `neutral` (loops running normally), `frustrated` (a loop errored or needs-triage), `out-of-wack` (multiple failures)
- [ ] Running loops pane: slug, status, elapsed time, last log line — polls PROXY API every 2s
- [ ] Feed pane: last 5 feed items from `/api/feed?tab=inbox`
- [ ] Command bar: accepts `start <repo>`, `stop <slug>`, `logs <slug>`, `queue`, `status`, `help`, `q` (quit)
- [ ] Keyboard nav: `Tab` to switch panes, `j/k` to select item, `Enter` to drill into a run's log view
- [ ] Log view: streams run logs via SSE from `/api/runs/[id]/logs`, `Esc` to go back
- [ ] All 7 BMO face expressions available and used contextually
- [ ] `npx tsc --noEmit` passes in `apps/tui`

## Feedback loops

- `npx tsc --noEmit` in `apps/tui`
- Manual test: run `proxy`, start a work request from a different terminal, verify the TUI updates live and shows the running loop

## Quality bar

production
