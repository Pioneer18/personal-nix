---
status: open
parent: proxy-v2-5ech-epic
target_repo: ~/Projects/tachikoma-starter
last_updated: 2026-05-17
depends_on: [proxy-v2-23-provider-trait]
quality_bar: production
---

# PROXY v2 — bilingual loop container image (MV8.24)

Rebuild the loop container image with both `claude` and `codex` CLIs installed. Entrypoint dispatches on `$PROXY_PROVIDER`. Single image, tagged `proxy-loop:v2`. Image build is reproducible from the Dockerfile + a pinned tool-version lockfile.

## Goal

`docker run -e PROXY_PROVIDER=claude proxy-loop:v2 -p <prompt-file>` invokes `claude`. Same with `PROXY_PROVIDER=codex` invokes `codex`. Unknown provider exits 2 with a clear error. Image size is < 2 GB; build cache hit on layers that didn't change.

## Files in scope

- `daemon/loop-image/Dockerfile` (new or updated — both CLIs installed)
- `daemon/loop-image/entrypoint.sh` (new — bash dispatcher)
- `daemon/loop-image/versions.lock` (new — pinned `claude` + `codex` versions)
- `daemon/loop-image/README.md` (new — build + push instructions)
- `daemon/scripts/build-loop-image.sh` (new or updated — wraps `docker build` with the right tag)

## Files out of scope

- Spawn-path integration (MV8.25 — daemon writes the `-e` env)
- Auth-file mount strategy (MV8.25)
- Anything outside the image (provider trait stays in MV8.23)

## Entrypoint sketch

```bash
#!/usr/bin/env bash
set -euo pipefail
case "${PROXY_PROVIDER:-}" in
  claude) exec claude -p "${PROXY_PROMPT_FILE:?missing PROXY_PROMPT_FILE}" ;;
  codex)  exec codex --prompt-file "${PROXY_PROMPT_FILE:?missing PROXY_PROMPT_FILE}" ;;
  "")     echo "PROXY_PROVIDER unset" >&2; exit 2 ;;
  *)      echo "unknown PROXY_PROVIDER: ${PROXY_PROVIDER}" >&2; exit 2 ;;
esac
```

## Stop condition

- [ ] Image builds clean from `daemon/loop-image/` with `docker build -t proxy-loop:v2 .`
- [ ] Both `claude` and `codex` on `PATH` inside the container; `claude --version` and `codex --version` both succeed
- [ ] Entrypoint dispatches correctly for both values + errors on missing/unknown
- [ ] Image size < 2 GB (warn at 1.5 GB)
- [ ] `versions.lock` pins both CLI versions for reproducibility; build script reads it
- [ ] CI smoke test (or manual checklist in README): build → run `--version` for each provider → run with bad provider → expect exit 2

## Feedback loops

- `daemon/scripts/build-loop-image.sh`
- `docker run --rm proxy-loop:v2 sh -c 'claude --version && codex --version'`
- `docker run --rm -e PROXY_PROVIDER=bogus proxy-loop:v2; echo $?`  (should print `2`)

## Quality bar

production
