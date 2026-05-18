---
title: "proxy-tutorial — handler-facing PROXY walkthrough"
tags: [proxy, skill, tutorial, onboarding, 5ech]
last_updated: "2026-05-18"
link: "~/Projects/tachikoma-starter/.claude/skills/proxy-tutorial/SKILL.md"
---

Plain-English walkthrough of PROXY for handlers. Parallels [[tachikoma-tutorial]] but scoped to the daemon, queue, callsigns, standby gate, exfil, and Operations. 7-stage guided tour + "what's shipped recently" section + quick-jump section + gotchas.

State as of 2026-05-18 PM: all v2 CLI verbs (`status`, `comms`, `grant`, `deny`, `exfil`, `burn`, `drops`, `archive`, `infil`) are registered in `proxy --help`. Schema is applied. Presets are seeded (4 callsign rows). PR #152 shipped the `dossiers.slug` column, unblocking `status`/`comms`/`grant`/`deny` runtime. `OPERATIONS.yaml` was renormalized to match the parser's expected shape (flat map of theater name → list of `{slug: ...}`), unblocking `proxy op list`. Remaining stubs: `infil`/`exfil`/`burn`/`drops`/`archive` runtime layers — clean "registered but not implemented yet" errors today, the next slice spawns them.

What works fully: `proxy queue *`, `proxy runs list`, `proxy status / comms / grant / deny`, `proxy op / obj / fu`, `proxy provider *`, `proxy timer *`, `proxy cron *`, `proxy email *`, `proxy sensor *`, `proxy admission *`, `proxy wizard`, `proxy dispatch`. Day-to-day handler work routes through `/tachikoma`, `/op`, `/brief`, `/op-next` skills + `mcp__tachikoma__tachikoma_status` — all using the v1 substrate end-to-end.

See [[proxy-v2-cutover-deferred]] for the precise migration / blocker breakdown.

Refresh after MV2.05a-runner-spawn (the slice that un-stubs `proxy infil` execution) + matching terminal-verb runtimes ship.
