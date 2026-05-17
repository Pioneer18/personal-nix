---
status: open
target_repo: ~/Projects/tachikoma-starter
github_issue: ""
failure_count: 0
last_updated: 2026-05-13
---

# PROXY — Iterative AI compose for emails (slice 23, email vertical)

The killer feature: chat-style iterative email composition with Claude. Preserves original intent, supports tone adjustment, draft history + revert, diff view between revisions, on-demand reflection ("does this answer the original instruction?"). Send always requires explicit user confirmation — no auto-send anywhere.

Works in both structural mode (user pastes thread context manually) and body mode (PROXY auto-supplies thread context once slice 24's flag is ON).

The user's Ashley email example (in the design grilling transcript) is the canonical target UX — preserve the original instruction, adapt tone iteratively, reflect on whether the draft satisfies the original intent.

## Goal

From Reviewer (slice 22), user clicks Reply / Reply-all / Forward / New, or AI > Iterative Compose. Compose panel slides in:

- **Top**: editable current draft (text editor; rich-text not required v1)
- **Bottom**: chat input for instructions to Claude
- **Right pin**: original instruction + thread context (user-typed in structural mode; auto-supplied from thread in body mode)
- **Diff view** appears when Claude revises — highlights changes vs prior draft
- **Draft history** list — every revision a row, revert any
- **Reflect on intent** button — Claude analyzes draft vs pinned original instruction

Streaming responses. Send button is the **only** path to send mail; PROXY never auto-sends.

## Files in scope

- `apps/web/src/app/email/reviewer/components/ComposePanel.tsx` — main UI
- `apps/web/src/app/email/reviewer/components/DraftEditor.tsx` — editable draft area
- `apps/web/src/app/email/reviewer/components/ChatInput.tsx` — instructions to Claude
- `apps/web/src/app/email/reviewer/components/DiffView.tsx` — current vs prior diff
- `apps/web/src/app/email/reviewer/components/DraftHistory.tsx` — version list + revert
- `apps/web/src/app/email/reviewer/components/ReflectionPanel.tsx` — reflect-on-intent output
- `apps/web/src/app/api/email/compose/route.ts` — POST → Claude streaming endpoint
- `apps/web/src/app/api/email/compose/reflect/route.ts` — POST → Claude reflection call
- `apps/web/src/app/api/email/compose/[draft_id]/send/route.ts` — POST → Graph send (on confirm)
- DB migration: `email_drafts` table:
  - `id UUID PK, briefing_id UUID nullable FK, thread_id text, recipients jsonb, cc jsonb, bcc jsonb, subject text, body text, parent_draft_id UUID nullable FK, attached_file_ids jsonb, instruction_pinned text, created_at, sent_at nullable`
- `apps/web/src/lib/email/compose-prompts.ts` — system prompt templates (with prompt caching markers)
- `daemon/src/email/send.rs` — `OutlookGraphClient::send_mail` wrapper that builds Graph payload from draft (extends slice 19's client)

## Files out of scope

- Reviewer infrastructure (slice 22) — this slice slots into the panel
- Briefing engine (slice 20)
- Body-flag mechanism (slice 24) — compose respects flag for thread-context auto-injection only

## Stop condition

- [ ] Compose panel opens from Reviewer action menu: Reply / Reply-all / Forward / New
- [ ] Draft pre-fill based on action:
  - Reply → `Re: {subject}` + auto-quoted latest message body
  - Reply-all → as Reply + To/CC populated from thread
  - Forward → `Fwd: {subject}` + blank to/CC, body has full quoted message
  - New → blank everywhere
- [ ] Recipients editable; basic email-string contact entry (advanced contact lookup in v2)
- [ ] CC / BCC fields toggleable
- [ ] Original instruction pinned in right panel:
  - Structural mode: text area for user to paste the original instruction / context they're working from
  - Body mode (slice 24 flag ON): auto-populated with the thread context (briefing summary + last 3 message bodies)
- [ ] Chat input submits instructions to Claude via `/api/email/compose`; response streams into draft area
- [ ] Each Claude revision saves a new `email_drafts` row with `parent_draft_id` linking the prior; current draft is the latest in the chain
- [ ] Diff view auto-renders on revision; highlights additions (green) and deletions (red strikethrough)
- [ ] Draft history shows N prior versions with timestamps; click any → revert (creates a new row pointing to the reverted-to as parent)
- [ ] "Reflect on intent" button: sends current draft + pinned instruction to Claude, returns analysis: "does this answer the original instruction? what was preserved / softened / omitted?" — rendered in ReflectionPanel
- [ ] Attach files: upload to PROXY local cache → on send, embed via Graph `attachments` field
- [ ] Send button is the ONLY send path; clicking opens "Confirm: send to N recipients?" modal with full recipient list visible
- [ ] On confirm send: POST `/send` → `daemon/email/send` → Graph send_mail; on success, draft row marked `sent_at=now()`, panel closes, briefing `linked_external.sent_reply_id` populated
- [ ] Body-mode awareness: when slice 24 flag is ON, panel auto-pins thread context; when OFF, panel shows empty pin with placeholder "Paste original instruction or context here for Claude"
- [ ] Claude calls use Anthropic SDK with prompt caching (per ADR 005 § D5):
  - Cache: system prompt + folder taxonomy + ok-to-delete list + person-precedence rules
  - Uncached: per-draft content + user instructions
- [ ] API key selection: `proxy.toml` `[email].api_key_source` controls — `"relymd"` uses RelyMD-procured key (post-BAA), `"default"` uses normal Anthropic key
- [ ] `npx tsc --noEmit` passes
- [ ] E2E test: replay the user's Ashley email flow from the design grilling — paste original instruction, get draft, iterate 3+ times with tone adjustments, reflect, confirm send (to a test recipient)

## Feedback loops

- `npx tsc --noEmit`
- `npm test` (component tests for diff, history revert, reflection panel)
- Manual: replay Ashley flow; verify draft quality + tone preservation matches the user's described experience

## Quality bar

production

## v3 context

- See ADR 005 § D4 (compose UI design) — the user's Ashley email example is the canonical UX target, NOT just a sample
- Slice 24's body-flag determines whether thread context is auto-supplied or user-pasted; this slice consumes the flag but does not own it
- Use the `claude-api` skill conventions for prompt caching + Anthropic SDK usage when implementing
