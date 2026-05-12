---
status: done
target_repo: ~/Projects/tachikoma-starter
github_issue: ""
failure_count: 0
last_updated: 2026-05-11
---

# PROXY — Encrypted PAT Management

Store multiple GitHub PATs encrypted at rest in the DB. Map PATs to repos via per-repo config. Inject the correct `GH_TOKEN` env var when spawning a loop. The plaintext PAT is never stored.

## Goal

User can add named PATs in the UI. Each PAT is AES-256-GCM encrypted before storage. Repos are mapped to PATs in per-repo config. The loop runner automatically decrypts and injects the right `GH_TOKEN` for each repo.

## Files in scope

- `apps/web/src/app/settings/pats/**`
- `apps/web/src/app/api/pats/**`
- `apps/web/src/lib/crypto.ts` (AES-256-GCM encrypt/decrypt)
- `apps/web/src/lib/runner/**` (inject GH_TOKEN)
- DB migration for `pats` table

## Files out of scope

- Jira credentials (separate concern)
- OAuth tokens (Slice 13)

## Stop condition

- [ ] `pats` table: id, name (unique), encrypted_value, iv, auth_tag, created_at (plaintext PAT never in DB)
- [ ] Encryption uses AES-256-GCM with key from `PROXY_ENCRYPTION_KEY` env var
- [ ] `POST /api/pats` accepts `{ name, value }`, encrypts before storing, returns `{ id, name }` only
- [ ] `GET /api/pats` returns `[{ id, name, created_at }]` — no encrypted values exposed
- [ ] `DELETE /api/pats/[id]` removes PAT and nulls any repo_configs referencing it
- [ ] Settings > PATs page: list PATs (name only), add new (name + value), delete
- [ ] Loop runner: reads `pat_id` from repo config → decrypts PAT → sets `GH_TOKEN` in subprocess env
- [ ] `PROXY_ENCRYPTION_KEY` documented in `.env.example` with generation instructions (`openssl rand -base64 32`)
- [ ] `npx tsc --noEmit` passes

## Feedback loops

- `npx tsc --noEmit`
- Manual test: add a PAT, verify only name returned by GET, verify GH_TOKEN injected correctly in a test loop run

## Quality bar

production
