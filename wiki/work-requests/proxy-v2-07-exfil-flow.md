---
status: open
parent: proxy-v2-5ech-epic
target_repo: ~/Projects/tachikoma-starter
last_updated: 2026-05-16
depends_on: [proxy-v2-05-runner-branching, proxy-v2-05a-liveness-and-reaper]
quality_bar: production
---

# PROXY v2 — EXFIL_RDY + typed package + handler exfil (MV2.07)

When a loop completes successfully, transition infil to EXFIL_RDY (not directly to EXFIL_D). Build a typed package (pr / report / patch / mixed) describing the deliverable. Handler reviews via `proxy exfil <ref>` and approves, which triggers the publish action — strictly handler-gated per lock 8 ("PR create is exfil-controlled").

## Goal

Loop ends → EXFIL_RDY. Handler runs `proxy exfil <ref>` → previews package → approves → daemon executes type-specific exfil action → infil EXFIL_D, dossier `completed_at` set.

## Lifecycle

```
loop (LIVE) emits <promise>COMPLETE</promise>
    ↓
supervisor runs verifier-gate (ADR 008 P1):
  - git status --porcelain clean
  - HEAD has non-empty diff vs base
  - typecheck/test/lint re-run from supervisor — all green
  - cumulative diff scan: no skip()/xit()/.only()/--no-verify/eslint-disable/etc.
  - no test files deleted
    ↓ if PASS:
POST /api/infils/$ID/exfil-ready { package_type, branch, suggested_pr_title, suggested_pr_body, files_changed, commits_count }
  daemon: UPDATE infils SET state='EXFIL_RDY' WHERE id=$1 AND state='LIVE'
  supervisor exits 0; bg heartbeat thread killed by trap
    ↓ if FAIL:
verifier-gate appends REJECTED block to progress.txt; loop continues iterating (no state change)

(handler reviews via web UI / CLI)
  proxy exfil <ref>  (or web "Review & Approve" button)
    ↓
daemon performs type-specific exfil action:
  - package_type='pr':     gh pr create + push branch + queue auto-merge
  - package_type='report': write markdown to ~/Projects/<repo>/reports/<slug>-<infil_id>.md + attach to dossier
  - package_type='patch':  attach diff to dossier (no remote action)
  - package_type='mixed':  both pr + report
  ↓
UPDATE infils SET state='EXFIL_D', ended_at=NOW()
UPDATE dossiers SET completed_at=NOW()  (state stays BRIEFED until handler runs `proxy archive` — lock 9)

(or handler aborts)
  proxy burn <ref>   → state=BURNED, burn_reason='handler-aborted-exfil'
  proxy recall <ref> → state=RECALLED, cancellation_reason='handler-recalled'
```

**Key design points:**

- **Strict handler-gating.** The supervisor process exits at EXFIL_RDY — never auto-ships. Handler is always the trigger for `gh pr create`. Matches lock 8.
- **Daemon owns the publish action.** The supervisor sends *package metadata* in the `/exfil-ready` POST; the daemon (not the loop's ship.md) runs `gh pr create`. This eliminates the loop's ship.md prompt entirely and moves all GitHub-touching code into one Rust module (`daemon/src/exfil/pr.rs`).
- **No post-ship CI poll.** ADR 008 P6's auto-fix-CI-iteration was reverted same-day 2026-05-16 (zero observed firings; speculative without data). State flips to EXFIL_D as soon as the daemon's exfil action returns success; CI red post-merge is handler attention, not daemon attention.
- **EXFIL_RDY persists indefinitely** until handler acts. A handler-asleep scenario leaves the infil in EXFIL_RDY for hours. By design: handler-gating means handler-on-their-own-time. Optional v2.5 hardening: notification ping if EXFIL_RDY > 12h.

## Package types

- `pr` — proxy worked on a feature branch with commits. Exfil action: push branch (if not pushed) + `gh pr create` with title/body from package payload
- `report` — read-only / audit. Exfil action: write report markdown to `~/Projects/<repo>/reports/<dossier-slug>-<infil-id>.md` and attach to dossier in DB
- `patch` — diff file. Exfil action: attach to dossier, no remote action
- `mixed` — both code (pr) and report. Exfil action: both

Package payload (jsonb) fields: type, summary, pr_title, pr_body, branch_name, report_md, diff_text, files_changed, commits_count.

## Endpoints

- `POST /api/infils/{id}/exfil-ready` — called by the supervisor after verifier-gate passes. Body `{ package_type, branch, suggested_pr_title?, suggested_pr_body?, files_changed?, commits_count? }`. Transitions LIVE → EXFIL_RDY. (Endpoint stub lives in proxy-v2-05a; this slice fills in the state-change logic + package_payload persistence.)
- `GET /api/infils/{id}/package` — returns the package payload for preview
- `POST /api/infils/{id}/exfil` — body `{ approved: true }` — daemon performs type-specific exfil action, transitions to EXFIL_D

## Files in scope

- `daemon/src/exfil/mod.rs` (new — package builder + publish actions)
- `daemon/src/exfil/pr.rs` (push + gh pr create + queue auto-merge)
- `daemon/src/exfil/report.rs` (write markdown + DB attach)
- `daemon/src/exfil/patch.rs` (attach to dossier)
- `daemon/src/api/infils/exfil.rs` (exfil endpoint + package preview endpoint)
- `daemon/src/api/infils/exfil_ready.rs` (fill in state-change logic on the stub from proxy-v2-05a)
- `daemon/src/state_machine.rs` (LIVE→EXFIL_RDY, EXFIL_RDY→EXFIL_D)

## Files out of scope

- Dead drops (covered by package + drops semantics but separate slice if drops surface needs work — folded into MV3.10 drops verb)
- CLI exfil verb (proxy-v2-10)

## Stop condition

- [ ] Successful loop completion transitions LIVE→EXFIL_RDY
- [ ] Package builder produces a typed payload based on dossier + infil state
- [ ] `GET /api/infils/{id}/package` returns the payload
- [ ] `POST /api/infils/{id}/exfil` for type=pr executes `gh pr create` with payload values
- [ ] type=report writes markdown to repo's reports dir, attaches path to dossier
- [ ] type=patch attaches diff to dossier
- [ ] Infil transitions to EXFIL_D; dossier.completed_at set
- [ ] Integration test for each package type

## Feedback loops

- `cargo test exfil`
- End-to-end: infil Quill on a small fix → completes → EXFIL_RDY → curl preview → curl exfil → verify PR opened on GitHub

## Quality bar

production
