---
title: "proxy-sys — one-shot system pressure summary"
tags: [proxy, system, memory, swap, cli, swiftbar, monitoring]
last_updated: "2026-05-15"
link: "~/.local/bin/proxy-sys"
---

CLI summary of memory + swap + load + top RSS hogs. Reads `proxy-daemon sensor latest` + `sysctl vm.swapusage`. Modes: default pretty, `--short` one-line, `--json` structured.

SwiftBar plugin `~/projects/personal-nix/swiftbar/proxy-system.30s.sh` consumes `proxy-sys --json` and renders glanceable header (green/orange/red) + full breakdown in dropdown. 30s refresh.

Flags fire when: kernel `memory_pressure != normal`, OR `avail_mb < 500`, OR `swap_used > 8 GB`, OR `swap_free < 2 GB`.

When PR #52 (auto-tachi-pressure-management) ships, `proxy admission check tachikoma` becomes the go/no-go answer; `proxy-sys` stays as the human-readable summary.
