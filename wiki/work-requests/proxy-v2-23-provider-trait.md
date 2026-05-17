---
status: open
parent: proxy-v2-5ech-epic
target_repo: ~/Projects/tachikoma-starter
last_updated: 2026-05-17
depends_on: [proxy-v2-22-provider-schema, proxy-v2-05-runner-branching]
quality_bar: production
---

# PROXY v2 — Provider trait + Claude/Codex impls (MV8.23)

Introduce `daemon/src/providers/` with the `Provider` trait sibling to `RunBackend`. Two implementations land: `ClaudeProvider` and `CodexProvider`. A registry resolves `infils.provider` → `&dyn Provider` at infil-start time. No container changes here — those land in MV8.24.

## Goal

The runner-branching code path (proxy-v2-05) can call `let provider = providers::resolve(infil.provider);` and receive an `Invocation` (binary + base args), an env vector, and a mount-spec list. Provider impls do not perform any I/O themselves — they describe what the container-spawn path should do. `cargo build` passes; unit tests cover the registry and both impls.

## Files in scope

- `daemon/src/providers/mod.rs` (new — trait + registry + `Invocation` / `MountSpec` types)
- `daemon/src/providers/claude.rs` (new — `ClaudeProvider` impl)
- `daemon/src/providers/codex.rs` (new — `CodexProvider` impl)
- `daemon/src/providers/tests.rs` (new — unit tests)
- `daemon/src/lib.rs` or `daemon/src/main.rs` (add `mod providers;`)

## Files out of scope

- Loop container image / Dockerfile (MV8.24)
- Env-key decryption + actual container spawn integration (MV8.25)
- Admission gating (MV8.26)
- Codex addendum text (MV8.29) — this slice's `callsign_addendum()` returns placeholder strings; MV8.29 fills them in

## Trait sketch

```rust
pub trait Provider: Send + Sync {
    fn name(&self) -> &'static str;
    fn invocation(&self) -> Invocation;
    fn env_for(&self, secrets: &SecretStore) -> Result<Vec<(String, String)>>;
    fn auth_files(&self) -> Vec<MountSpec>;
    fn callsign_addendum(&self, callsign: &str) -> String;
}

pub struct Invocation { pub binary: String, pub base_args: Vec<String> }
pub struct MountSpec { pub host: PathBuf, pub container: PathBuf, pub read_only: bool }
```

The registry exposes `pub fn resolve(provider: Provider) -> &'static dyn Provider` (or a `Box<dyn Provider>` if lifetime constraints push that way). Static dispatch on the enum keeps the hot path branch-predictable.

## Stop condition

- [ ] `Provider` trait defined with the 5 methods above
- [ ] `ClaudeProvider` impl: invocation `["claude", "-p"]`; env returns `ANTHROPIC_API_KEY` + `CLAUDE_CONFIG_DIR`; mounts `~/.claude/` read-only
- [ ] `CodexProvider` impl: invocation `["codex", "--prompt-file"]`; env returns `OPENAI_API_KEY` + `CODEX_CONFIG_DIR`; mounts `~/.codex/` read-only
- [ ] Registry: `providers::resolve(Provider::Claude)` returns the Claude impl; `Provider::Codex` returns the Codex impl
- [ ] Unit tests cover: registry maps both providers; both impls return non-empty invocation; both return distinct env-var names; mount specs use the right home-dir subpaths
- [ ] `callsign_addendum()` returns a non-empty string per (callsign, provider) pair — fills in MV8.29 but interface honored now
- [ ] `cargo build --workspace` passes
- [ ] `cargo clippy --workspace --all-targets -- -D warnings` passes

## Feedback loops

- `cargo test -p proxy-daemon providers::tests`
- `cargo clippy --workspace --all-targets -- -D warnings`

## Quality bar

production
