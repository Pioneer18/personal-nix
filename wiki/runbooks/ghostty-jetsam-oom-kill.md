---
title: "Ghostty quits without warning + Claude sessions die together = Jetsam OOM"
tags: [ghostty, claude, jetsam, memory, oom, macos, terminal]
last_updated: "2026-05-11"
---

## Symptom

- Ghostty disappears without a warning dialog or crash window.
- Every `claude` session that was running inside Ghostty dies at the same instant.
- No crash report in `~/Library/Logs/DiagnosticReports/` for `ghostty`.

## Diagnosis: it's Jetsam, not a Ghostty bug

macOS Jetsam (the kernel OOM killer) selected `ghostty` as the victim because it had grown into the largest single resident process. No SIGSEGV, no crash dump — just a SIGKILL from the kernel.

Confirm with:

```bash
ls -lt /Library/Logs/DiagnosticReports/JetsamEvent-*.ips | head -5
```

Open the most recent file (today's, ±5 min around the incident). Look at the JSON header:

```json
"largestProcess" : "ghostty",
"memoryStatus" : {
  "compressorSize" : 664736,        // pages — ×16KB ≈ 10GB compressor occupancy
  "uncompressed"   : 5250390,       // pages — ~80GB virtual addressed
  "memoryPages"    : { "free": 12099, ... }   // ~189MB free at moment of kill
}
```

If `largestProcess == "ghostty"` and `memoryPages.free` is < ~20K pages, that's the smoking gun.

**Note**: `.ips` files take 1–2 minutes to materialize after the event. If you investigate immediately and don't see today's file, wait and re-check.

## Why all the Claude sessions die together

Ghostty owns the PTYs. When the kernel SIGKILLs Ghostty:

1. Every child PTY closes.
2. Every shell attached to those PTYs receives `SIGHUP`.
3. `claude` (and any other long-running process started in those shells) exits.

They have no chance to log anything — there's no graceful shutdown path.

## Live memory check

```bash
vm_stat | head -15
ps -axo pid,rss,command | sort -k2 -rn | head -15
```

Danger signals:
- `Pages free` < ~5K (× 16KB = ~80MB free)
- `Pages occupied by compressor` in the millions
- `Swapouts` close to `Swapins` and both > 10^9 (severe thrash)
- `Pages stored in compressor` growing fast

## Mitigations (do in order until pressure drops)

1. **Stop unused VMs.** `com.apple.Virtualization.VirtualMachine.xpc` can sit at 1–2GB resident even when the guest is idle. Quitting the VM is the single biggest single-step recovery.
2. **Close Chrome tabs / quit Teams / quit VS Code** when not actively needed. Each Electron renderer is 150–400MB and they add up fast (Teams WebView alone is ~390MB).
3. **Cap concurrent `claude` sessions** — each is ~300–400MB resident, plus its MCP child processes (each MCP server is another node process at 50–200MB).
4. **Trim Ghostty scrollback** in `~/Library/Application Support/com.mitchellh.ghostty/config` if many tabs are open. Default `scrollback-limit` is 10K lines per surface — across many tabs/splits this is real memory.
5. **Restart Ghostty** to release accumulated scrollback even before pressure builds.

## Pattern on this machine

24GB Mac (MacBook-Pro-2). The recurring trigger has been: VM running (~1.7GB) + many Chrome tabs + Teams + VS Code + 2–4 concurrent `claude` sessions. JetsamEvent files have shown `largestProcess == "ghostty"` multiple times across the week — this is a known repeat, not a one-off.

Each repeat also tends to leave `node-*.ips` reports earlier in the day from Claude MCP child processes — they get jetsam'd first as pressure ramps, before Ghostty itself goes.

## See also

- `vm_stat(1)` for what the page counters mean.
- Apple's Jetsam priority list — terminal apps are not pinned high, so they're fair game when free pages drop below the kernel's threshold.
