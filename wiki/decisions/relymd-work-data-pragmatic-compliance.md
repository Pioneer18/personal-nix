---
title: "RelyMD work-data pragmatic compliance posture"
tags: [proxy, compliance, hipaa, relymd, baa, decision, email-vertical]
date: "2026-05-13"
status: "active"
---

# RelyMD work-data pragmatic compliance posture

**Decision date**: 2026-05-13
**Decided by**: Jonathan Sells (founder + tenant admin, RelyMD)

## Context

RelyMD = telehealth co. Has an Anthropic account but **no BAA in place** as of 2026-05-13. Dev team currently runs PROXY/Tachikoma/code workflows on personal Claude Max subscriptions.

Building PROXY email-management vertical against `jonathan.sells@relymd.com` (RelyMD Outlook). Need to decide compliance posture for processing work email through Claude API.

Email content is dominantly internal ops / engineering / external business — Jonathan reports "never see PHI." Residual risk: forwarded support escalations, calendar invites with patient names, auto-generated reports may carry PHI.

Other RelyMD work data in scope for future PROXY verticals: Jira tickets, internal docs, customer support, etc.

## Options considered

| Option | Description | Tradeoff |
|---|---|---|
| A. BAA first | Pause; procure BAA from Anthropic; then build | Cleanest. Blocks build weeks/months. |
| **B. Body-gated build** ⭐ | Build now. "Body content → Claude API" is a feature flag, default OFF. Structural mode operates without sending bodies. Flip flag when BAA signed. | 60-70% of value immediately, zero PHI exposure. Forcing function for BAA conversation. |
| C. Bodies on, guardrails only defense | Aggressive PHI regex + sender allowlist as sole mitigation | Fastest full feature. Residual HIPAA risk accepted. |
| D. Local LLM only | Ollama / on-device for full email pipeline | Bodies never leave machine. Quality drops, esp. iterative compose. |
| D′. Hybrid (local + Claude-compose-only) | Local 70B for pipeline body summary; Claude API for user-initiated iterative compose w/ pasted context | ~95% feature parity, 2 backends |
| E. Personal Gmail pilot | Build against personal inbox first | Proves UX. Defers actual work-email value. |

## Decision

**Option B**: body-gated build, flag default OFF at ship.

**Compliance posture broadly**: pragmatic-now + tracked-compliance-debt. Ship value first, document the compliance gap as ADRs/TODOs, formalize over time. Move toward conscious compliance, not block on it.

**Precedent invoked**: RelyMD already permits dev team to use personal Claude Max for code work + Jira. Email vertical extends the same posture with stricter architectural guardrails (body-gated flag).

## Consequences

**Accepted residual risk**:
- Even in structural mode (flag OFF), Claude API receives metadata of work email (sender, subject, headers) — not PHI on its own, but subjects/senders can leak identifying info
- Manual user-initiated body-to-Claude (e.g. "summarize this email" while looking at one in Reviewer) bypasses the flag — user's call per email
- User accepts these consciously with intent to formalize compliance over time

**Active mitigations (in v1 PRD scope)**:
- Sender allow/deny list (`proxy.toml`)
- Regex pre-filter on subjects + (when flag ON) bodies for SSN / DOB / MRN / "patient #" / "chart #"
- Send-confirm gate — no auto-send ever, even for one-line acks
- Audit log of every Claude API call (sender, subject, was-body-included, timestamp)
- Encrypted token storage in macOS Keychain (reuse `proxy-07-encrypted-pat-management`)

**Future re-evaluation triggers**:
- BAA signed → flip body flag → re-evaluate guardrail tightness
- Any PHI incident observed → tighten or pause
- New PROXY vertical touches more sensitive RelyMD data → revisit posture
- RelyMD AUP changes re: 3rd-party AI on work data → revisit
- Anthropic ToS changes affecting personal Max use for work data → revisit

## Compliance TODOs

Tracked debt — review at each milestone before activating body flag in production:

1. **Procure BAA from Anthropic.** Path: upgrade RelyMD Anthropic org to Team plan + request BAA via console/sales. Owner: Jonathan. Target: 1-4 weeks.
2. **AUP review.** Confirm RelyMD's privacy policy / acceptable-use permits 3rd-party AI processing of work email. If not, draft AUP amendment. Owner: Jonathan (founder).
3. **Anthropic credential split.** Decide single RelyMD API key (cleanest) vs per-vertical (RelyMD for email, personal Max for code). Personal Max currently powers code work — email vertical body-flag flip requires RelyMD-procured key.
4. **Audit log retention.** Define retention period + storage for Claude-API audit log. Phase 1: indefinite, local DB. Phase 2 (when BAA active): formal retention policy + bulk export for forensic review.
5. **Deep PHI detector (phase 2).** Replace cheap regex guardrails with Microsoft Presidio / AWS Comprehend Medical-style detector before flipping body flag in production.
6. **Body-flag flip checklist.** Write a recipe doc with pre-flip verification: BAA signed, AUP confirmed, audit log working, deep PHI detector active, dry-run on labeled corpus, revocation drill rehearsed.
7. **Per-vertical compliance review.** When the next PROXY vertical lands on RelyMD-owned data (e.g. customer support ingestion, Jira sync, internal docs), re-evaluate posture rather than auto-extending this decision.
8. **Cross-employee data review.** Coworkers' forwarded words hit Claude when threads land in Jonathan's inbox. Confirm internal expectation / disclosure if material.

## Project-level follow-ups

When email-vertical PRD lands, write a project ADR in `~/Projects/tachikoma-starter/docs/adr/` that:
- References this decision as the cross-cutting compliance constraint
- Specifies the body-flag mechanism (env var? `proxy.toml` field? feature flag in DB?)
- Specifies the audit log schema + retention
- Specifies the sender allow/deny + regex guardrail interface

## Related

- [[tenant-admin-relymd-m365]] — Jonathan's M365 tenant admin status (enables self-serve Graph integration)
- [[relymd-anthropic-credentials]] — credential split situation + BAA status
- [[feedback-pragmatic-compliance-debt]] — user's general posture preference
- `~/projects/personal-nix/wiki/decisions/agentic-shell-4-tier-state.md` — adjacent state-tier decision
