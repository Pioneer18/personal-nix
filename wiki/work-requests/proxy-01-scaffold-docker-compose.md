---
status: done
target_repo: ~/Projects/tachikoma-starter
github_issue: ""
failure_count: 0
last_updated: 2026-05-11
shipped_pr: https://github.com/MioMarker/tachikoma-starter/pull/5
shipped_at: 2026-05-11
---

# PROXY — Project Scaffold + Docker Compose

Initialize the PROXY monorepo with Turborepo, Docker Compose orchestrating PostgreSQL + Redis + the Next.js app, and a working development environment. This is the foundation all other slices build on.

## Goal

`docker compose up` starts Postgres, Redis, and a Next.js dev server. `localhost:3000` returns a 200. TypeScript compiles without errors. The repo is a clean Turborepo monorepo with `apps/web` and room for `apps/tui` later.

## Files in scope

- `/` (new repo — all files)
- `docker-compose.yml`
- `turbo.json`
- `package.json`
- `apps/web/**`
- `.env.example`

## Files out of scope

N/A — this is a fresh repo with no existing code to protect.

## Stop condition

- [ ] `docker compose up` starts Postgres (port 5432), Redis (port 6379), and Next.js dev server (port 3000) without errors
- [ ] `curl localhost:3000` returns HTTP 200
- [ ] `npx tsc --noEmit` passes with 0 errors in `apps/web`
- [ ] `docker compose down` cleanly tears down all services
- [ ] `.env.example` documents all required env vars (DATABASE_URL, REDIS_URL, PROXY_ENCRYPTION_KEY)
- [ ] README documents `docker compose up` as the dev setup command
- [ ] Turborepo `turbo.json` defines `build`, `dev`, `typecheck` pipelines

## Feedback loops

- `docker compose up` (observe no errors)
- `curl localhost:3000` (expect 200)
- `cd apps/web && npx tsc --noEmit`

## Quality bar

production
