---
name: desk
description: Jonathan's PERSONAL ledger of tasks, meetings, people, projects, and quick-reference info at ~/projects/desk. Near-zero-friction capture (free text, pasted transcripts, file paths, photos), then prioritization (P0-P3, FIFO), tracking, 1:1 prep, and the Friday leadership report. Use when the user types /desk, says "desk this", "put on my desk", "what's on my desk", "prep me for <person>", or dumps a meeting transcript/notes/photo for capture. Not for team docs (workbench), agent orchestration (PROXY), or generic "note this" (inbox).
---

# /desk

Jonathan is Engineering Program Lead (ApolloMD) + Senior Developer (RelyMD). High meeting and request volume. `/desk` is his personal system for making sure nothing is lost and priorities stay visible. **Personal only.** Not a team tool, not PROXY.

## Hard rules

1. **Data lives only in `~/projects/desk/`** (private GitHub `Pioneer18/desk`). **Never write desk content under `~/Projects/platform`**, no matter the cwd. Never copy desk content into team docs, Jira, Slack, or PRs unless the user asks for that specific text.
2. **PHI redaction on ingest, always.** Before any text is written, replace patient names, DOBs, MRNs, SSNs, addresses, phone numbers, and other patient identifiers with `[redacted]`. Staff/colleague names are fine. Run `desk phi-scan -` on the text (stdin) before writing meetings. Do not keep original .docx/.pdf/.vtt files. Keep a photo only if it shows no patient data.
3. **Never create a person or project without a yes from the user.** The CLI exits 3 on unknown or ambiguous names; ask one short question ("new person 'Mike R', or Michael Ramos?"), then `desk new-person` / `desk new-project`.
4. **Never auto-promote priority.** Suggest, show the reason, and let the user confirm.
5. **Mechanical work goes through the CLI** (IDs, frontmatter, moves, NOW.md, git). Edit files directly only for body prose (meeting sections, project/person notes, ref docs), then run `desk commit "<msg>"`.

CLI: `~/.claude/skills/desk/bin/desk` (below: `desk`). `desk <cmd> -h` for flags. Every mutating command re-renders `NOW.md` and commits; pass `--no-commit` in batches and finish with `desk commit`.

## Model

| Thing | Where | Notes |
|---|---|---|
| Task | `tasks/T-####-slug.md` → `tasks/done/YYYY-MM/` when closed | frontmatter + body + `## Log` |
| Meeting | `meetings/YYYY/MM/YYYY-MM-DD-slug.md` (+ `attachments/`) | Summary, Decisions, Tasks, Key info, Open questions, Raw |
| Person | `people/<slug>.md` | org, role, aliases, emails, `urgency_bias`, Notes, 1:1 log |
| Project | `projects/<slug>.md` | Status, Key facts, Decisions, Links. `misc` = no project |
| Ref | `ref/<topic>.md` | quick-reference facts |
| Report | `reports/YYYY-Www.md` | Friday leadership summary |
| Board | `NOW.md` | generated, never hand-edited |

**Kinds:** `mine` (I owe it) · `delegate` (I must hand it off: file ticket / tell someone) · `waiting` (someone owes me) · `ask` (raise with a person next time).
**Priority** (mine + delegate only): `P?` untriaged · `P0` fire · `P1` important, do now if no fires · `P2` planned · `P3` someday (hidden from NOW). FIFO inside a bucket; `desk top` pins to the front.
**Waiting** items have no priority; they have a `nudge` date (default +3 business days) and appear as "chase X" when it passes. **Ask** items have no priority; they surface in `prep` and via `due`.
**Due dates escalate:** due within 2 business days → "Due soon" strip; past due → 🔴 OVERDUE.
**Lifecycle:** `delegate` → `desk handoff` (to whom, ticket key) → `waiting` → `done`. `done` on a delegate exits 4: ask who it went to and which ticket.

## Capture (the default: infer, write, show a receipt, ask nothing)

Any `/desk <text>` that is not a verb below is a capture. Classify it:

- **Task** (default). Infer title (short, imperative), kind, project, people, due (convert "Fri", "EOW", "next Tue" to a date), jira/pr keys, source. Unknown project → `misc`.
  ```
  desk add "Fix late census feed" --kind delegate --project group-portal --people mike --due 2026-10-02 --source "hallway w/ Star"
  ```
- **Priority:** set `--priority` only if the user said it ("P1", "fire", "whenever"). Otherwise leave it `P?` and pass `--suggest P# --reason "<≤8 words>"`. Suggest P0 only for clear urgency (outage, patient/clinical impact, exec escalation with a deadline, blocker on a live P0) or links to an open P0 (`desk list --priority P0`). Discount people whose `urgency_bias: high` (see people file). If the user often overrides a person's suggestions, write `urgency_bias: high|low` into their file.
- **Meeting / transcript / notes / photo / file path** → Meeting flow (below).
- **Reference fact** ("Ferry's cell is…", "Azure SFTP host is…") → append to the matching `projects/<x>.md` Key facts, `people/<x>.md` Notes, or `ref/<topic>.md`, then `desk commit`.
- **Multiple items in one dump:** capture each one and print all receipts. If there are more than 5, use the meeting-style draft first.

Print the CLI receipt line(s) as-is. The user corrects tersely (`143 → pace, P1`, `143 is waiting on Ian`), and you apply the change with `desk set` / `desk handoff`. A `y` reply to a suggested-P0 receipt → `desk set <id> priority=P0`.

## Updates

| User says | Do |
|---|---|
| `143 <progress text>` / "census thing is unblocked" | `desk log 143 "<text>"` (fuzzy-find by `desk list` if no id; confirm only if ambiguous) |
| `143 done [note]` | `desk done 143 "<note>"` (delegate → ask who/ticket → `desk handoff`) |
| `143 drop` / "forget the X thing" | `desk drop 143 "<why>"` |
| `143 P1` / `143 → pace` / `143 due fri` | `desk set 143 priority=P1` / `project=pace` / `due=YYYY-MM-DD` |
| `150 top` / `150 unpin` | `desk top 150` / `desk unpin 150` |
| "chased Ian on 143" | `desk chased 143 "<note>"` |
| "gave 150 to Tony, GDEV-412" | `desk handoff 150 --to tony --jira GDEV-412` |

## Verbs

- **`/desk`** (no args) → `desk render` and show it. Add a one-line nudge if there are suggested P0s, overdue items, or chases.
- **`/desk triage`** → `desk triage`. Walk the items one at a time: show the receipt + suggestion and accept `0/1/2/3`, `x` (drop), `w <person>` (make waiting), `enter` (accept suggestion), `s` (skip). Apply each with `desk set`/`desk drop`.
- **`/desk prep <person>`** → `desk prep <person>`, then a 5-line brief: what to raise, what to chase, what to hand off, context from recent meetings.
- **`/desk project <name>`** → `desk project <name>` + a short status read.
- **`/desk find <query>`** → `rg -i` over `~/projects/desk` (include `tasks/done`, meeting Raw). Answer the question and cite file paths and dates. Say plainly when nothing is found.
- **`/desk day`** → NOW plus a proposed top 3 for today: P0s first, then overdue/due-soon, then P1 FIFO head, then chases. If the user pastes today's calendar, fit the list around the meetings and list prep needed per meeting (`desk prep`).
- **`/desk week`** → [references/week.md](references/week.md).
- **`/desk report [week|month] [project]`** → [references/report.md](references/report.md).
- **`/desk import <file|paste>`** → Meeting flow's draft step, without a meeting file unless the source is a meeting.
- **`/desk push`** → `desk push`. A launchd job also pushes daily at 18:00.

## Meeting flow

Full procedure: [references/meetings.md](references/meetings.md). Summary: extract text → redact PHI → `phi-scan` → **show a draft** (summary, decisions, extracted tasks with kind/owner/suggested P) → user strikes junk (`x 3,7`) or accepts (enter) → `desk new-meeting` + `desk add --no-commit --source M-…` per task → fill sections → append decisions to project files → `desk commit`.

## External systems (read-only)

- Jira keys and PR refs live on tasks (`jira=`, `pr=`). In `week`/`prep`/`project`, check live status (Atlassian MCP `getJiraIssue` after `getAccessibleAtlassianResources`; `gh pr view <n> -R <repo>`). **Suggest** closing a task whose ticket is Done or PR merged; never auto-close.
- No Jira/Confluence/Slack writes from `/desk`. If the user asks to file a ticket, draft it and hand off to the normal confirmed flow (GDEV for eng work; RMD comments internal-only).

## Maintenance

- `desk lint` validates IDs, folders, references, and PHI patterns. Run it after bulk edits and in `/desk week`.
- Tests: `/usr/bin/python3 -m unittest discover -s ~/.claude/skills/desk/tests`. Keep the CLI stdlib-only and Python 3.9-compatible (launchd runs `/usr/bin/python3`).
- Design decisions: `~/projects/personal-nix/wiki/decisions/desk-personal-ledger.md`.
