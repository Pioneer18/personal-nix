# proxy-erv2-05 — Draft reply + inline chat-to-refine

## Goal

Tachikoma is done when clicking "Draft reply" on an email generates a Claude-authored reply (via `claude -p`), displays it inline below the email body, and allows the user to refine it through a chat interface before sending via Graph `sendMail`.

## Files in scope

- `apps/web/app/api/email/briefings/[id]/draft/route.ts` — new: `POST` → shells out to `claude -p`, streams response
- `apps/web/app/api/email/briefings/[id]/refine/route.ts` — new: `POST {message, currentDraft}` → sends to `claude -p` with draft context
- `apps/web/app/api/email/briefings/[id]/send-reply/route.ts` — new: `POST {body}` → Graph `sendMail`
- `apps/web/app/email/reviewer/components/DraftReply.tsx` — new component: draft display + chat + send/discard
- `apps/web/app/email/reviewer/components/BriefingDetail.tsx` — mount `DraftReply` below body when draft requested

## Files out of scope

- `daemon/` — no changes
- `apps/web/app/api/email/briefings/[id]/actions/route.ts`

## Draft generation

Server-side shell-out: `claude -p "<prompt>"` where prompt includes:
- Email subject, sender, received date
- Full body text (stripped of HTML tags, truncated to 6000 chars)
- Instruction: "Draft a professional reply on behalf of Jonathan Sells. Be direct and concise."

Stream stdout back to client as SSE or chunked response. Display as it arrives.

If `claude` CLI is not on PATH, return 503 with `{ error: "claude_unavailable" }` and show "Claude CLI not found" in UI.

## Refine flow

User types in the chat input below the draft. Each message is sent to `POST /refine` with `{ message, currentDraft, emailContext }`. Server sends to `claude -p` with accumulated history. Streams updated draft back; replaces current draft display.

## Send

"Send" button calls `POST /send-reply` with the final `body` string. Server calls Graph `POST /me/sendMail` with:
```json
{
  "message": {
    "subject": "Re: {original subject}",
    "body": { "contentType": "Text", "content": "{body}" },
    "toRecipients": [{ "emailAddress": { "address": "{original sender email}" } }]
  }
}
```
On success, auto-advance to next email.

"Discard" dismisses the draft; no network call.

## Stop condition

- [ ] "Draft reply" button appears in action cards for `needs-reply` + `jira-jsm` shapes
- [ ] Clicking generates a draft via `claude -p`; streams into inline draft pane
- [ ] User can type in chat input to refine; each message updates the draft
- [ ] "Send" fires Graph sendMail from `jonathan.sells@relymd.com`; auto-advances after
- [ ] "Discard" dismisses without side effects
- [ ] If claude CLI unavailable, shows clear error message (not crash)
- [ ] TypeScript: no `any`, no compile errors

## Feedback loops

```
pnpm exec tsc --noEmit   # from apps/web/
```

## Quality bar

production
