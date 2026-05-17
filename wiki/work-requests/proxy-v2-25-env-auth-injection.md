---
status: open
parent: proxy-v2-5ech-epic
target_repo: ~/Projects/tachikoma-starter
last_updated: 2026-05-17
depends_on: [proxy-v2-23-provider-trait, proxy-v2-24-loop-image-bilingual]
quality_bar: production
---

# PROXY v2 — per-provider env + auth injection (MV8.25)

Wire the daemon's container-spawn path to the `Provider` trait. When launching an infil, read `infil.provider`, ask the corresponding `Provider` impl for its env + mount-spec, and assemble the `docker run` invocation accordingly. Keys come from the existing AES-256-GCM secret store (slice 07 — PATs); add an `OPENAI_API_KEY` slot.

## Goal

`POST /api/work-requests/:id/dispatch` (or the v2-renamed dossier dispatch endpoint) with `infil.provider='codex'` launches a container with `OPENAI_API_KEY` injected and `~/.codex/` mounted read-only — and **never** `ANTHROPIC_API_KEY` or `~/.claude/`. The wrong env is structurally impossible to leak, not just unlikely. End-to-end test verifies both happy paths and the leak-resistance.

## Files in scope

- `daemon/src/secrets/mod.rs` or equivalent — add `get_openai_api_key()` slot alongside the existing PAT functions
- `daemon/src/api/work_request_dispatch.rs` (or v2 dossier-dispatch handler) — read `infil.provider`, resolve `Provider`, assemble env + mounts before `docker run`
- `daemon/src/run_backend/local_docker.rs` — accept `EnvVec` + `MountSpec[]` from the caller; do not hardcode env names
- `daemon/src/secrets/keychain.rs` (or wherever PAT keychain access lives) — extend to handle the OpenAI key
- Tests: `daemon/tests/integration_provider_env.rs` (new)

## Files out of scope

- The encrypted-key write side (handler stores keys via existing Settings UI — that page just gains an OpenAI key field; UI work is a separate small slice or rolls into MV8.28)
- Admission integration (MV8.26)
- Image internals (MV8.24)

## Leak-resistance guarantees

The spawn path constructs env + mounts in a single function that takes `Provider` as input and returns a `ContainerSpawnSpec`. There is exactly one place where env names appear, and that place reads from `Provider::env_for()`. No alternate path constructs env directly. Unit tests assert: a `Provider::Codex` spawn-spec contains no string `"ANTHROPIC_API_KEY"` anywhere in its env or args; and vice versa.

## Stop condition

- [ ] Spawn path reads `infil.provider`, calls `providers::resolve(infil.provider).env_for(&secrets)`, passes result to `LocalDockerBackend::start`
- [ ] Secret store has an OpenAI key slot accessible via `secrets.openai_api_key()` → `Option<Plaintext>`
- [ ] `LocalDockerBackend::start` accepts env + mounts as parameters; no hardcoded `ANTHROPIC_API_KEY` left in the spawn code path
- [ ] Unit test: spawning with `Provider::Codex` includes `OPENAI_API_KEY` env entry, includes a mount to `/home/proxy/.codex/`, excludes any `ANTHROPIC_*` env or `.claude` mount
- [ ] Unit test: spawning with `Provider::Claude` is the mirror image
- [ ] Integration test (with mocked Docker socket): full dispatch flow for both providers leaves the right container spec in the launch transcript
- [ ] `cargo build --workspace`, `cargo clippy --workspace --all-targets -- -D warnings`, `cargo test --workspace` all pass
- [ ] Manual e2e: handler stores both keys, dispatches a small dossier with `--provider codex`, container starts, `codex` runs, exfil succeeds

## Feedback loops

- `cargo test -p proxy-daemon provider_env`
- `cargo test -p proxy-daemon dispatch`
- `cargo clippy --workspace --all-targets -- -D warnings`

## Quality bar

production
