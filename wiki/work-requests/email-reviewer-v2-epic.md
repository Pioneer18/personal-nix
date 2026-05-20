# Email Reviewer V2 — Epic

**Status:** planning  
**Slices:** proxy-erv2-01 through proxy-erv2-06  
**Grilled:** 2026-05-20

## Vision

Replace the current urgency-pivot list + raw-detail pane with an Outlook-parity reviewer that organizes by real folder structure, surfaces AI-generated shape-aware action cards, and lets Claude draft replies for human edit and send — all within the PROXY web UI.

## Locked design decisions (D1–D13)

| # | Topic | Decision |
|---|-------|----------|
| D1 | Nav | Inbox / Sent / Deleted / Drafts tabs + Focused / Other toggle (Graph `inferenceClassification`) |
| D2 | Per-row | Shape badge + AI one-liner (2 lines max) + sender + subject; no urgency color bar |
| D3 | Action cards | Per-shape in detail pane: JSM ticket → Jira transitions + reply; calendar invite → Accept / Tentative / Decline; FYI → Archive; needs-reply → Draft reply |
| D4 | Draft | Explicit request only; generated via `claude -p` (counts against Max subscription); inline display below body |
| D5 | Chat | Inline below draft — refine until explicit Send or Discard; no side panel |
| D6 | Auto-advance | After any action (archive, delete, send, Jira transition), move to next unread in current folder view |
| D7 | Snooze | Out of scope |
| D8 | Bulk | Checkboxes on list rows + shift-click range select; bulk toolbar with Archive + Delete |
| D9 | Search | Full-text via Outlook Graph search API (`/me/messages?$search="..."`) — not local metadata filter |
| D10 | Reply identity | Always `jonathan.sells@relymd.com` via Graph `sendMail`; no JSM service account routing |
| D11 | Degraded mode | N/A — always show email body, no BAA gate |
| D12 | Sync window | Last 7 days on first sync; "load previous 7 days" button to extend |
| D13 | AI billing | API key for ingestion/summaries (daemon side); `claude -p` for reply drafts (web server shell-out) |

## Email shapes

Detected at ingestion time, stored in `email_briefings.shape`:

| Shape slug | Detection heuristic |
|------------|---------------------|
| `jira-jsm` | Subject matches `[RMD-\d+]` and sender is Jira notification domain |
| `calendar-invite` | Graph `@odata.type == "microsoft.graph.eventMessage"` |
| `fyi` | AI classifies as informational, no required action |
| `needs-reply` | AI classifies as requiring a response |
| `other` | Fallback |

## Folder model

| Tab | Graph folder name | Notes |
|-----|-------------------|-------|
| Inbox | `inbox` | Default view |
| Sent | `sentitems` | |
| Deleted | `deleteditems` | |
| Drafts | `drafts` | |

Focused / Other toggle reads `inferenceClassification` property on each message (Graph returns `focused` or `other`). Stored in `email_briefings.inference_classification`.

## Slice plan

| Slice | Title | Layer |
|-------|-------|-------|
| proxy-erv2-01 | Nav + folder model + schema | Web + DB |
| proxy-erv2-02 | Ingestion: shape detection + one-liner | Daemon |
| proxy-erv2-03 | Row redesign + action cards | Web |
| proxy-erv2-04 | Bulk select + Outlook search | Web |
| proxy-erv2-05 | Draft reply + inline chat-to-refine | Web + claude-p shell-out |
| proxy-erv2-06 | Sync window (7-day) + load-more + auto-advance | Web + Daemon |

## Key dependencies

- Calendars.ReadWrite scope needed in Azure app registration for calendar accept/decline (currently only Calendars.Read)
- Graph `inferenceClassification` must be included in `$select` on message fetch (daemon `DELTA_SELECT`)
- `sendMail` Graph scope already present via `Mail.Send`
- `claude` CLI must be on PATH inside the web server process for `claude -p` shell-out in proxy-erv2-05
