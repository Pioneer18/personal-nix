---
title: "Agentic shell v1.0 — M1-M7 slice plan"
tags: [agentic-shell, proxy, v1, slice-plan, build-order, milestones]
last_updated: "2026-05-11"
---

# Agentic shell v1.0 — M1-M7 slice plan

The ordered build plan for shipping PROXY v3's agentic shell. Each milestone is dogfood-able on its own. Foundation interleaves with user-visible work so motivation stays high and the substrate benefits from real usage data before being hardened.

**Context**: PROXY v3 expanded PROXY's scope from work-orchestrator to agentic shell. See [`docs/ARCHITECTURE.md`](~/Projects/tachikoma-starter/docs/ARCHITECTURE.md) Part II and [ADR 001](~/Projects/tachikoma-starter/docs/adr/001-proxy-scope-expansion-agentic-shell.md) for the 11 v3 decisions. This recipe is the implementation walk-through.

**Total v1.0**: ~14 weeks sequential. Compressible with parallel Tachikoma jobs if slice isolation holds.

**v1.0 excludes**: computer use + 8-layer gating (→ v2.0, see [ADR 003](~/Projects/tachikoma-starter/docs/adr/003-computer-use-and-8-layer-gating.md)).

---

## Ordering principle

Picked during the 2026-05-11 grilling: **visible-first, foundation middle, web late, polish last.**

- **M1, M2 first** — user-visible wins (boot to PROXY, voice). Dogfood early; the substrate built later (M3) benefits from real usage informing its design.
- **M3 middle** — PROXY Rust daemon foundation. Lands after 3-4 weeks of dogfooding, when "what the daemon needs to do" is concrete.
- **M4 right after M3** — Ink TUI integration; the visual queue surface that completes the chat+queue layout.
- **M5** — fills out the voice modes and ships the bundled notification app.
- **M6** — web UI; the rich-render escape hatch. Late because TUI carries the load until then.
- **M7** — first-run wizard + polish; final integration work, needs everything else present.

---

## M1 — Boot exists

**Weeks**: 1-2

**Goal / dogfood moment**: Log in. See PROXY visually. Type to claude in a fullscreen tmux pane. Claude has macOS Shortcuts as a tool. Memory follows you to your other Mac.

**Slices**:

- [ ] `shell-01` — Boot LaunchAgent: `home-manager` `launchd.user.agents.proxy-boot`. Boot script: `open -a Ghostty` → wait → focus → ⌃⌘F fullscreen → tmux session "proxy" attach.
- [ ] `shell-02` — Tmux preset for "proxy" session: left pane runs `claude`; right pane runs a placeholder `proxy-tui` (Ink TUI scaffolding — full integration in M4). Status bar segment shows the current mode (placeholder until M2 ships the voice daemon).
- [ ] `shell-10` — Shortcuts MCP server: small TypeScript MCP wrapping `shortcuts run "<name>"`. Lists all installed Shortcuts as tools. Add to `personal-nix/mcp.nix`.
- [ ] `shell-13` — Memory iCloud sync: one-time script `personal-nix/scripts/sync-memory.sh` that moves `~/.claude/projects/-Users-pioneer/memory/` to iCloud Drive and symlinks back. Hook into `dev` activation.

**Dependencies**: none (foundation).

**Verification**:
- `dev` from scratch on a fresh Mac → log out → log in → Ghostty appears fullscreen with chat + (placeholder) queue panes
- `claude` in the left pane shows the user's CLAUDE.md, skills, MCP servers including the new Shortcuts MCP
- `ls -la ~/.claude/projects/-Users-pioneer/memory/` shows a symlink to iCloud Drive
- On a second Mac after `dev` + iCloud sync: same `MEMORY.md` content visible

**Out of scope for M1** (deferred to later Ms):
- Voice (M2)
- Real PROXY daemon / sensor / admission (M3)
- Ink TUI feature-complete (M4 — M1 ships a placeholder)
- Web UI (M6)

---

## M2 — Hey PROXY voice

**Weeks**: 3-4

**Goal / dogfood moment**: Say "Hey PROXY, what's queued?" → hear the answer aloud. Wake-word + STT + TTS reply, all local-first.

**Slices**:

- [ ] `shell-04` — `proxy-voice` daemon scaffold (Rust). LaunchAgent. PG client connection. LISTEN/NOTIFY on `voice_mode_changed`. Initial mode: Hey PROXY (the only mode in M2; others ship in M5).
- [ ] `shell-05` — Hey PROXY mode impl:
  - Porcupine wake-word engine wired in. Custom-train "Hey PROXY"; fallback to built-in "Hey Computer" if accuracy degrades.
  - On wake: load whisper.cpp (~150 MB on-demand) + start a 5-second listen window.
  - Transcribe locally; pipe to chat pane via `tmux send-keys -t proxy:0.0 "<transcript>" Enter`.
- [ ] `shell-09` — TTS reply via macOS `say`. Hook into claude's stop event (via Claude Code hooks): when claude finishes a response, read it aloud. Configurable voice + speed.

**Dependencies**: M1 (boot integration exists; chat pane is targeted by `tmux send-keys`).

**Verification**:
- Log in → tmux status bar shows `[mode: Hey PROXY]`
- Say "Hey PROXY, what's the date today?" → see transcript appear in chat pane → claude responds → `say` reads the response
- ⌘Esc aborts mid-response (clean)
- Restart Mac → mode persists (or starts at Hey PROXY if fresh install)

**Out of scope for M2**:
- Other voice modes (M5)
- Mode-switching infrastructure (M5)
- ElevenLabs MCP TTS (optional, anytime)

---

## M3 — Daemon foundation

**Weeks**: 5-7 (or 5-8 with `proxy-fast-dispatch-mode` included; recommended)

**Goal / dogfood moment**: A real work-request, dispatched via `proxy dispatch <slug>` (non-interactive!), runs in an ephemeral Docker container with memory cap. PROXY's admission rule gates it. Sensor shows live metrics. From M4 onwards, slices can be fanned out in parallel via fast-dispatch.

**Slices** (in dependency order):

- [ ] `proxy-01b` — `proxy-daemon` Rust scaffold: LaunchAgent plist, PG client, LISTEN/NOTIFY skeleton, basic CLI subcommands (`proxy queue list`, `proxy status`, `proxy recalibrate`).
- [ ] `proxy-02-extended` — DB schema migrations: `sensor_samples`, `system_recommendations`, `apps_registry`, `host_metrics`, `computer_use_audit` (forward-compat for v2.0 — table exists, no writes yet), `proxy_voice_state`, `proxy_voice_events`. Use sqlx migrations (decision per ADR 004).
- [ ] `proxy-04b` — Sensor + admission rule: Mach API metrics, Docker stats, sysctl, pmset. 4-gate admission (host pressure, reserved budget, host free for VM growth, load5). Plus thermal + Low Power Mode bonus gates.
- [ ] `proxy-04c` — `RunBackend` trait + `LocalDockerBackend` impl: spawn ephemeral container with `--memory=1.5g` (configurable per-repo); bind-mount worktree; stream `claude -p` stdout via SSE; clean up on exit.
- [ ] `proxy-11b` — In-daemon Postgres scheduler: replaces BullMQ. `LISTEN scheduled_due`; processes `runs.run_at` rows when due + admission permits.
- [ ] `proxy-fast-dispatch-mode` — **The parallelism unlock.** Non-interactive `proxy dispatch <slug>` CLI + `POST /api/dispatch` REST endpoint. Reads work-requests directly, validates well-formedness, fires `--afk` in seconds with no prompts. Enables an upstream orchestrator (the user or a claude session) to fan out multiple Tachikomas on small slices economically. See [`proxy-fast-dispatch-mode.md`](../work-requests/proxy-fast-dispatch-mode.md) for the full spec including REST shape, CLI flags, exit codes, and well-formedness checklist.

**Dependencies**: none external (parallel to M1/M2 conceptually; in practice this lands after dogfood). Internally, `proxy-fast-dispatch-mode` depends on `proxy-01b` (CLI scaffold) + `proxy-04c` (loop spawning machinery).

**Verification**:
- `proxy enqueue ~/Projects/healthbite "do a tiny test change"` → loop spawns in OrbStack VM → completes → PR opened
- Push memory pressure to Warn → `proxy queue list` shows new enqueues rejected with reason
- `proxy status` shows live sensor metrics + admission gate states
- `proxy dispatch shell-04-proxy-voice-daemon-scaffold` returns within 20s with worktree path + PID; loop runs in background; no prompts
- `proxy dispatch --batch shell-04 shell-05 shell-09` fans out 3 parallel tachikomas (admission rule gates total memory)

**Out of scope for M3**:
- Ink TUI integration (M4)
- Recommendation engine surfaces (M5)
- Computer use (v2.0)

**Why `proxy-fast-dispatch-mode` is included in M3 (not deferred)**: discovered mid-M1 build that Tachikoma's interactive grill flow makes small-slice parallelism uneconomical (~5-10 min preflight per slice vs ~10-15 min of actual work). M4+ slices have similar small-scope variants; without fast-dispatch, the rest of v1.0 stays sequential. Landing this in M3 unlocks parallel orchestration for M4-M7 and pays for itself within one milestone. See work-request "v3 context" section for the full rationale.

---

## M4 — Ink TUI integration

**Weeks**: 8

**Goal / dogfood moment**: The right tmux pane is no longer a placeholder — it's the live PROXY Ink TUI showing queue, sensor, inbox.

**Slices**:

- [ ] `proxy-16-extended` — Ink TUI feature pass:
  - Queue list with status per work-request
  - Live sensor panel (pages free, pressure, swap rate, load avg)
  - Inbox tab (`system_recommendations` rows)
  - Bottom action bar (enqueue / refresh / details)
- [ ] Tmux status bar wiring: voice mode (from `proxy_voice_state`) + queue depth (from `runs` count) + sensor pressure (from latest sample). Updated via LISTEN/NOTIFY.

**Dependencies**: M3 (daemon must exist and be writing to DB for TUI to read).

**Verification**:
- Right pane shows live queue + sensor + inbox
- New work-request appears in TUI within ~1s of enqueue
- Mode-switch in voice daemon updates tmux status bar < 1s

**Out of scope for M4**:
- Full mode-switching (M5)
- Web UI (M6)

---

## M5 — Full voice modes + notifications

**Weeks**: 9-10

**Goal / dogfood moment**: All 4 voice modes work. Switch via voice, hotkey, CLI, or TUI dropdown. macOS notifications show with action buttons.

**Slices**:

- [ ] `shell-06` — Wispr mode: Karabiner chord (e.g. ⌘⇧Space) → AppleScript focuses chat pane → Wispr Flow PTT activates → transcript goes to focused pane. Mode-switch releases mic from daemon to Wispr.
- [ ] `shell-07` — Open mode: VAD continuous on mic stream → whisper.cpp per utterance → `tmux send-keys`. TTS auto-on.
- [ ] `shell-08` — Off mode + mode-switching:
  - Mode-switch via voice command in active modes ("PROXY, switch to open" / "PROXY mute")
  - Hotkey cycles (⌘⇧V forward, ⌘⇧⌥V backward) via Karabiner
  - CLI: `proxy voice mode <hey|wispr|open|off>`
  - TUI dropdown clickable bottom-bar element
- [ ] `proxy-15-extended` — Bundled signed Mac app for notifications:
  - Swift menubar-less app that exposes the macOS UNUserNotificationCenter API
  - Daemon invokes via XPC or AppleScript bridge to post notifications with action buttons (Approve / Deny / Snooze)
  - Action clicks update `system_recommendations.actioned_at` + `actioned_outcome`

**Dependencies**: M2 (Hey PROXY foundation), M3 (daemon for notifications).

**Verification**:
- Cycle through all 4 modes via hotkey; indicator updates < 500ms
- "PROXY, switch to open" in Hey PROXY mode → switches to Open mode → TTS confirms
- Trigger a recommendation (e.g. force admission rejection) → macOS notification with Approve / Deny buttons; click Approve → row updates

**Out of scope for M5**:
- Web UI (M6)

---

## M6 — Web UI

**Weeks**: 11-13

**Goal / dogfood moment**: `proxy ui` opens Chrome to `localhost:3000`. Visual escape hatch with sensor charts, kanban, notebook, inbox markdown, settings.

**Slices**:

- [ ] `proxy-12-extended` — Next.js app scaffold (Turborepo `apps/web`):
  - Tech: Next.js 14 App Router, TailwindCSS, shadcn/ui, SWR for client mutations
  - Auth: local-only (no users; this is a single-Mac UI)
  - Daemon-managed: `proxy-daemon` spawns it as a child process at boot; restarts on schema migration
  - Port 3000; listens only on `localhost`
- [ ] Sensor charts (Recharts) — pages free, pressure level, swap rate, load avg, Docker VM RSS — windowed time-series
- [ ] Work-request kanban (drag-drop between status columns)
- [ ] Notebook UI (markdown rendering, category filtering, promotion-to-work-request)
- [ ] Inbox UI with full markdown rendering + Approve/Deny/Snooze buttons (POSTs to daemon API)
- [ ] Settings UI: per-repo config editor, voice mode default, TTS voice choice, cost cap, app allowlist (forward-compat for v2.0 computer use)

**Dependencies**: M3 (daemon API exists), M4 (TUI parity informs what web does best).

**Verification**:
- `proxy ui` opens browser; first hit < 1s (warm)
- Charts render last 1h of sensor data
- Drag a work-request between columns → status updates in DB → TUI reflects within 1s

**Out of scope for M6**:
- First-run wizard (M7)

---

## M7 — First-run wizard + polish

**Weeks**: 14

**Goal / dogfood moment**: A fresh Mac can run `bootstrap.sh` and arrive at a working agentic shell, with permission grants walked through and admission defaults set from observed host state.

**Slices**:

- [ ] `proxy-15b` — First-run wizard (interactive TUI flow):
  - Detects: Docker VM size, host RAM, Major's `shell_pool_size_hint`, uptime, free disk
  - Surfaces: one-time fixes (see [mac-pre-proxy-prep](mac-pre-proxy-prep.md))
  - Computes: admission defaults (max concurrent loops, default memory cap)
  - Walks permission grants:
    - Accessibility (System Settings → Privacy & Security → Accessibility): for voice daemon + keyboard event capture
    - Microphone: for voice modes
    - Screen Recording: forward-compat for v2.0 computer use
  - Writes: per-machine `proxy.toml` with computed defaults
- [ ] Edge case fixes: collected during dogfooding M1-M6
- [ ] Doc pass: README, CLAUDE.md, this recipe — final consistency check
- [ ] v1.0 tag + release on `tachikoma-starter`; tag + push on `personal-nix`

**Dependencies**: everything above.

**Verification**:
- `bootstrap.sh` on a fresh Mac → wizard runs → all permissions granted → agentic shell working end-to-end
- Coworker can fork `tachikoma-starter` + clone `personal-nix-template` → run bootstrap → working stack with empty personal layer

**v1.0 SHIP** at end of M7.

---

## Deferred to v1.5

Things that almost made v1.0 but were trimmed for ship pressure. Tackled in v1.5 after v1.0 has a few weeks of real use:

- Voice mode-switching enhancements (e.g. auto-downgrade Open → Hey PROXY on battery)
- Additional MCP servers (Calendar, Mail, Reminders) — added as motivated by real workflows
- Recommendation engine expansion (more recommendation kinds beyond the v1.0 catalog)
- ElevenLabs MCP TTS as opt-in default
- Multi-window tmux orchestration (parallel-track work)
- Email ingestion via in-daemon scheduler
- **Auto-memory pruner** — weekly LaunchAgent that invokes `claude -p` to evaluate memory hygiene and propose archives. See [`auto-memory-pruner.md`](../work-requests/auto-memory-pruner.md). Side-quest; not on the v1.0 critical path, but keeps memory clean over months.

## Deferred to v2.0

Larger scope; needs its own grilling round:

- **Computer use + 8-layer gating** ([ADR 003](~/Projects/tachikoma-starter/docs/adr/003-computer-use-and-8-layer-gating.md))
- **Team-substrate scaffolding polish** — `personal-nix-template` audit + ship inside `tachikoma-starter`; CI personal-data leak check
- **Cross-Mac chat history** — if ever, via some sync mechanism. Currently per-machine.
- **Remote workhorse** (Hetzner AX42) — already deferred ([ADR](../decisions/proxy-defer-remote-workhorse.md)); promotion triggers in that doc

---

## Notes / gotchas (will accumulate during execution)

### 2026-05-11 — slice plan landed

- Recipe written during the agentic-shell grilling synthesis pass. Decisions captured in [ARCH.md Part II](~/Projects/tachikoma-starter/docs/ARCHITECTURE.md), [ADR 001](~/Projects/tachikoma-starter/docs/adr/001-proxy-scope-expansion-agentic-shell.md), [ADR 002](~/Projects/tachikoma-starter/docs/adr/002-voice-daemon-proxy-voice.md), [ADR 003](~/Projects/tachikoma-starter/docs/adr/003-computer-use-and-8-layer-gating.md), [4-tier state decision](../decisions/agentic-shell-4-tier-state.md).
