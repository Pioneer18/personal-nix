---
title: "Smoke-test healthbite staging deploys (2026-05-12)"
tags: [healthbite, deploy, smoke-test, staging, supabase, pending-followup]
last_updated: "2026-05-12"
target_repo: ~/Projects/healthbite
status: grabbed
---

# Smoke-test healthbite staging deploys (2026-05-12)

Run these checks before deploying the same migrations + edge functions to prod (`mfjfcfuwjbhqgqmtmhwe`).

## What was deployed to staging (nuihvxluxdpdjgkvtdih)

Migrations (applied via dashboard SQL editor — bypassed broken supabase tracking):

- `20260508000001` — `fitness_tests.secondary_value` / `secondary_unit` nullable cols (PR #131)
- `20260508000002` — `process_document_outcomes` telemetry table (PR #133)
- `20260508000003` — `meal_analysis_cache` table (PR #142)

Edge functions deployed:

- `process-document` (PR #133 — detection + telemetry)
- `analyze-meal-ai` (PR #142 — cache + server-side persist)
- `analyze-meal-from-image` (PR #142 — auto-submit + persist)
- `persist-meal-analysis` (PR #142 — NEW function for manual-confirm path)

## Why smoke-test before prod

The migrations were applied via raw SQL because supabase tracking is corrupted (17 ghost migrations from Paul's local checkout exist on staging tracking, and our 41 local migrations show as untracked). Tracking can't be trusted, so we need direct end-to-end validation that the schema + functions work together. If something is off (e.g. a column got missed because of merge weirdness in #142), better to catch it on staging with the test user than in prod.

The mobile app is on the dev branch; can run via `npm run staging` to point at the staging Supabase project.

## Test scenarios

### 1. Meal logging cache + server orchestration (PRs #134/#136/#142)

- Log a novel meal (e.g. "two scrambled eggs and toast") via the text logger.
  - Expect: submit-time toast "✓ Logged. We're analyzing the nutrition — feel free to keep going."
  - Expect: meal appears in feed within ~15-30s with full nutrition (no longer stuck at processing).
- Log the same meal description again.
  - Expect: appears in feed in <2s (cache hit).
  - Verify in DB: `SELECT meal_description, hit_count FROM meal_analysis_cache WHERE meal_description ILIKE '%scrambled eggs%';` — `hit_count` should be ≥ 2.
- Log a meal, then immediately force-close the app.
  - Expect: on next open, meal shows full nutrition (writes happened server-side, not client).
- Photo flow: take a clear photo of identifiable food (e.g. an apple).
  - Expect: high-confidence path → no manual-confirmation UI → auto-submitted to feed.
- Photo flow: take a blurry/ambiguous photo.
  - Expect: low-confidence path → manual confirmation UI → user confirms → server-side persist via `persist-meal-analysis` function.

### 2. Bloodwork detection + telemetry (PRs #132/#133)

- Upload a bloodwork PDF via the dedicated Bloodwork screen.
  - Expect: biomarkers extracted, friendly success message with count.
- Upload a non-lab PDF via the Documents screen.
  - Expect: prompt "Is this a lab report?" appears. Choose "No" → routed through generic doc heuristic.
- Upload a lab PDF via the Documents screen, choose "Yes, lab report".
  - Expect: parser runs even if keyword detection would have failed (`expected_document_type=blood_work` bypass).
- Verify telemetry row exists:

  ```sql
  SELECT user_id, expected_document_type, detected_blood_work, biomarker_count, final_status, created_at
  FROM process_document_outcomes
  ORDER BY created_at DESC
  LIMIT 5;
  ```

- Diagnostic query — should return zero rows in healthy state. Any rows here = a real failure to investigate.

  ```sql
  SELECT file_type, extraction_method, expected_document_type, COUNT(*) AS failed_attempts
  FROM process_document_outcomes
  WHERE created_at > now() - interval '1 day'
    AND detected_blood_work = true
    AND COALESCE(biomarker_count, 0) = 0
  GROUP BY 1, 2, 3
  ORDER BY failed_attempts DESC;
  ```

### 3. Farmer carry (PR #131)

- Open the Fitness Test logger, pick Farmer Carry.
  - Expect: new two-input form (weight per hand + minutes/seconds), not the old single-input.
- Enter values (e.g. 50 lbs at 60 seconds for a 200-lb person → BW·s = 15).
  - Expect: percentile renders. Should match `calcPercentile` output for that BW·s score.
- Verify DB:

  ```sql
  SELECT raw_value, secondary_value, secondary_unit, percentile
  FROM fitness_tests
  WHERE test_key = 'farmer_carry'
  ORDER BY created_at DESC
  LIMIT 5;
  ```

  `secondary_value` / `secondary_unit` should be populated for new entries; legacy rows should still have NULL there but a stored `percentile`.
- `TestSummaryGrid` + `TestHistoryList` should render new rows as "X lbs · Ym Zs" format.

## Deliverable

Either a "all clean, ready for prod" message (and proceed with prod deploys in next session), or a list of any failures with reproduction steps so we fix before prod.

## Out of scope

- Auth overhaul (#145) smoke test — separate followup; needs Apple Dev Portal + Supabase Dashboard ops set up first (SIWA capability per bundle ID, Apple provider in Supabase, EAS dev build with new native modules).
- RHR baseline (#149) smoke test — works automatically on next mobile build for users with 14+ days of RHR data; no edge-function dependency to validate.
- Tracking reconciliation — separate effort with Paul to recover the 17 ghost migrations.

## Related session

`~/projects/personal-nix/wiki/auto-merged-pr-report.md` — entry dated `2026-05-12T04:48:23Z` covers the PR walkthrough that produced these merges.
