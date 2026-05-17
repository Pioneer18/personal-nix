---
status: open
target_repo: ~/Projects/tachikoma-starter
github_issue: ""
failure_count: 0
last_updated: 2026-05-13
---

# PROXY — Outlook folder + category taxonomy setup (slice 21, email vertical)

One-time setup utility that creates the PROXY folder taxonomy in the connected Outlook mailbox, sets up the 5 categories with their colors via Graph MailboxSettings, and defines the person-axis routing rules used by the briefing engine (slice 20).

## Goal

User runs `proxy email init` and the Outlook mailbox gains:

- Folder tree: `Inbox/Dany/{Priorities,DMs,Meetings}`, `Inbox/RMD Support`, `Inbox/Internal`, `Inbox/External Meetings & Info`, `Inbox/Titled Threads`
- Categories: `Urgent` (red), `Awaiting Reply` (yellow), `New Info` (blue), `Meeting Conflict` (orange), `PHI-Flagged` (purple)
- Idempotent — re-runnable, doesn't duplicate existing folders/categories

Routing rules + person-precedence config land in `proxy.toml`:

```toml
[email.routing]
high_touch_people = [
  { name = "Dany", email = "dany@relymd.com", folder = "Dany" },
]

[email.routing.rules]
rmd_support_senders = ["board-support@relymd.com"]
internal_domain = "relymd.com"
titled_thread_min_count = 5      # ≥5 msgs same subject → Titled Threads
```

`daemon/src/email/routing.rs` exposes `route(message) -> (folder_path, categories[])` consumed by slice 20's briefing engine.

## Files in scope

- `daemon/src/email/folder_setup.rs` — idempotent folder + category creation via Graph (`MailboxSettings.ReadWrite`)
- `daemon/src/email/routing.rs` — per-message route resolver with person-precedence
- CLI: `proxy email init` subcommand wires both
- `~/.config/proxy/proxy.toml` schema: `[email.routing]` section
- Doc: `~/projects/personal-nix/wiki/recipes/outlook-folder-taxonomy.md` — the v1 taxonomy spec (mirrors ADR 005 § D3)

## Files out of scope

- OAuth (slice 19)
- Polling + briefing engine (slice 20) — consumes `routing::route` but doesn't create folders
- Reviewer UI (slice 22)
- Auto-action execution (slice 20's `auto_actions.rs`)

## Stop condition

- [ ] `proxy email init` creates the full folder tree idempotently via Graph; re-run = no-op (checks existence first)
- [ ] All 5 categories created with correct preset colors via Graph `outlookCategory` endpoint
- [ ] `routing::route(message)` signature: takes Graph message, returns `(target_folder_path: String, categories: Vec<String>)`
- [ ] Person-axis precedence: from `high_touch_people` matched by email → `<Folder>/<sub>` based on subject heuristic, NOT content folder. Subject heuristic for Dany:
  - Contains "priority" / "important" / "urgent" → `Dany/Priorities`
  - Direct (Dany is only recipient, no CC list) → `Dany/DMs`
  - Calendar invite or "meeting" in subject → `Dany/Meetings`
  - Default → `Dany/Priorities`
- [ ] Content-axis fallback (non-person-matched):
  - Sender in `rmd_support_senders` → `RMD Support`
  - Sender domain = `internal_domain` → `Internal`
  - Meeting invite (`meetingMessageType: meetingRequest`) → `External Meetings & Info`
  - Long-running threads (`conversationId` count ≥ `titled_thread_min_count`) → `Titled Threads`
  - Default → leave in `Inbox` root (no auto-file)
- [ ] Cross-cut categories applied independently of folder:
  - Subject contains urgency keywords → `Urgent`
  - Calendar conflict detected (slice 26 surfaces this) → `Meeting Conflict`
  - PHI regex match (slice 20's phi_guard) → `PHI-Flagged`
- [ ] Routing logic unit-tested for 7 example cases from `outlook-folder-taxonomy.md` recipe
- [ ] `cargo test`, `cargo clippy --all-targets -- -D warnings`

## Feedback loops

- `cargo test` (routing logic)
- Manual: `proxy email init` against connected RelyMD account → verify in Outlook Web that folders + categories exist; send self test emails matching each routing case → verify slice 20's auto-file places them correctly

## Quality bar

production

## v3 context

- See ADR 005 § D3 for the canonical taxonomy
- Consumed by slice 20 (briefing engine calls `routing::route` for every polled message)
- `high_touch_people` is extensible — add more people as routing needs grow; same person-axis precedence applies
