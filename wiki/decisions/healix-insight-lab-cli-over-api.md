---
title: "healix-insight-lab uses `claude -p` (Max subscription) instead of the Anthropic API"
tags: [claude-code, anthropic-api, oauth, max-subscription, healix-insight-lab, billing, decision]
last_updated: "2026-05-16"
status: accepted
---

# healix-insight-lab uses `claude -p` (Max subscription) instead of the Anthropic API

**Status**: Accepted — 2026-05-16.

**Scope**: `~/Projects/healix-insight-lab`. Applies to the narrative-polish step in the insight pipeline.

## Context

The narrative generator (`src/lib/narrative.ts`) polishes the 5-slot trajectory finding template with Haiku 4.5. The original implementation imported `@anthropic-ai/sdk` and authenticated via `ANTHROPIC_API_KEY`.

The developer running this lab already pays for a Claude Max subscription, used daily via Claude Code. **Max-subscription quota is not an `ANTHROPIC_API_KEY`** — it's an OAuth credential the `claude` CLI stores in the OS keychain at login time. Requiring a separate API key here meant maintaining a second billing channel on top of the Max subscription that already covered Haiku.

The trigger was a 401 `invalid x-api-key` failure during a `npm run build-narrative-report` run on 2026-05-16. Symptom of the structural mismatch: Max OAuth ≠ API key.

## Decision

Swap the `@anthropic-ai/sdk` call in `src/lib/narrative.ts` for a subprocess invocation of `claude -p` (Claude Code CLI, print mode). This uses the Max subscription's OAuth credential from the keychain — same auth that powers `claude` in a terminal — instead of an API key.

Critical flag choices:

- **No `--bare`.** Bare mode disables OAuth keychain reads (`claude --help` says explicitly: *"OAuth and keychain are never read"*) and falls back to `ANTHROPIC_API_KEY`, defeating the entire point. Pay the overhead of loading hooks/MCP/CLAUDE.md per call; it's a few dozen calls per report.
- **`--output-format json` is required when using `--json-schema`.** Discovered during smoke testing: with a schema in force, the CLI puts the validated object on the envelope's `structured_output` field and leaves the default `result` text empty. Without `--output-format json`, stdout is just an empty newline.

The spawned env also has `ANTHROPIC_API_KEY` explicitly deleted, so even if a stale/invalid key is in the parent shell env, the child cannot silently prefer the broken API path.

## Why this matters across projects

Other personal repos that hit Anthropic for ad-hoc/dev use (one-shot LLM calls, narrative generation, summarization helpers) should follow the same pattern by default:

- **Default**: shell out to `claude -p` → Max subscription pays.
- **Reach for `@anthropic-ai/sdk`** only when there's a real reason (production server, CI, programmatic streaming, response.usage required, etc.).

This is the local-dev analogue of [`container-explicit-opt-in.md`](./container-explicit-opt-in.md): don't run a second billing channel by default when the one you already pay for can do the job.

## Consequences

**Positive**
- One auth concept per machine. No "wait, which key is in my shell rn" failure mode.
- Flat-rate billing under the Max subscription instead of per-token API charges.
- Removes the 401 class of failure for local pipeline runs.

**Negative**
- ~1–2 s subprocess startup per call vs ~200 ms direct SDK call. For 10–50 calls per report run, that's <1 min of wall time. Acceptable.
- Max subscriptions have fair-use rate limits — do not loop this across thousands of subjects. Single-subject lab use is fine.
- `response.usage` token counts are gone, so per-call dollar estimates are no longer surfaced. Max is flat-rate anyway, so this number was always going to be misleading under the new model.

## Triggers for revisiting

- Pipeline moves to a server-side / CI context where there is no Claude Code login (no OAuth available) — at that point reinstate the API-key path behind an env flag.
- An equivalent of Claude Code OAuth becomes available as a programmatic SDK auth method that doesn't require subprocess overhead — collapse the subprocess back to a library call.

## See also

- Project ADR: [`~/Projects/healix-insight-lab/docs/adr/0001-claude-cli-over-anthropic-api.md`](~/Projects/healix-insight-lab/docs/adr/0001-claude-cli-over-anthropic-api.md) — full ADR with code, including the `--bare` gotcha.
- Claude Code CLI auth model: `claude --help` § `--bare` flag (documents that bare mode disables OAuth/keychain).
- Related billing-channel hygiene principle: [[container-explicit-opt-in]] — don't run extra channels by default.
