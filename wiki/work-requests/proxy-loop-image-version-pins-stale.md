---
status: open
target_repo: ~/Projects/tachikoma-starter
last_updated: 2026-05-20
quality_bar: production
---

# PROXY — `daemon/loop-image/versions.lock` pins are stale, image build fails

`daemon/loop-image/versions.lock` pins:

```
claude=1.0.0
codex=0.1.0
```

Both are gone from npm (claude-code latest is 2.1.145, codex latest is 0.133.0-alpha). `daemon/scripts/build-loop-image.sh` fails at the Dockerfile's `npm install -g` step with `npm error notarget`. **No `proxy-loop:v2` image can be built today**, so `proxy infil` creates an `infils` row, hits Docker spawn 404 (`pull access denied for proxy-loop`), and the row transitions to BURNED. Observed 2026-05-20 launching a Phantom against `tachikoma-skill-ship-md-template-missing` — infil `afb5d5f7-a80e-4806-9b45-4517280d8a5e` burned.

## Goal

`daemon/scripts/build-loop-image.sh` runs clean against current npm registry; `docker images proxy-loop:v2` shows a tagged image; `proxy infil phantom --dossier <slug>` spawns successfully and the section grid shows the live infil.

## Files in scope

- `daemon/loop-image/versions.lock` — bump `claude` to a current published version and `codex` to a current stable
- `daemon/loop-image/README.md` — if it documents version expectations
- `daemon/loop-image/Dockerfile` — only if a version-bump exposes API/CLI shape changes

## Files out of scope

- The MCP `tachikoma_dispatch` cutover to v2 (separate slice)
- `proxy brief` CLI implementation (still stubbed — separate slice)

## Stop condition

- [ ] `versions.lock` pins resolve to published npm packages — `npm view @anthropic-ai/claude-code@<pin>` and `npm view @openai/codex@<pin>` both return success
- [ ] `daemon/scripts/build-loop-image.sh` exits 0
- [ ] `docker images proxy-loop:v2` shows the built image
- [ ] Manual e2e: insert a dossier → `proxy infil phantom --dossier <slug>` → infil row stays in `LIVE` state, Docker container running, refresh `http://localhost:3737/` and Phantom card shows LIVE=1
- [ ] README updated with the new pin rationale (date + reason for picking these specific versions)

## Feedback loops

- `daemon/scripts/build-loop-image.sh`
- `docker run --rm proxy-loop:v2 claude --version && docker run --rm proxy-loop:v2 codex --version`
- Manual e2e per Stop condition above

## Quality bar

production
