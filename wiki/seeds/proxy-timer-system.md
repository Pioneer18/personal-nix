---
title: "PROXY timer system with voice/notification modes"
tags: [proxy, timer, pomodoro, voice-mode, notifications, focus]
last_updated: "2026-05-13"
target_repo: "~/Projects/tachikoma-starter"
status: open
---

Add a timer system to PROXY so I can tell PROXY (or invoke a timer skill) to set a timer.

**Capabilities:**
- One-shot timers: "set a 10 minute timer"
- Looping work sessions: pomodoro-style (e.g., 25min focus / 5min break, repeating)
- Selectable alert mode per timer (or as a global preference):
  - **Voice mode** — PROXY speaks to me when the timer ends
  - **macOS notifications** — native notification banner

**Open questions to resolve during grilling:**
- Where does timer state live? (PROXY API, separate daemon, launchd?)
- Skill vs. tool vs. native PROXY primitive?
- Pomodoro: configurable focus/break lengths, or fixed defaults?
- How does "voice mode" hook in? (existing TTS path, or new?)
- Multiple concurrent timers — supported, or one at a time?
- Cancel/pause/resume controls?
- Persistence across PROXY restarts?
