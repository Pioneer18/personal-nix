# Runbook: sccache does not work inside nix builds (macOS/nix-darwin)

**Discovered**: 2026-05-17 during `proxy-rust-services.nix` bring-up.  
**TL;DR**: Do not set `RUSTC_WRAPPER=sccache` inside crane/nix derivations on this machine. Both modes fail.

---

## Failure mode 1 — sccache daemon mode (default)

**Symptom**: build fails immediately with:
```
sccache: encountered fatal error
sccache: error: failed to spawn Command { std: cd "/nix/var/nix/builds/nix-build-<drv>-NNN/source" && env -i ... rustc ... }
```

**Root cause**: The sccache **server** runs as `pioneer` on `localhost:4226`. Nix build directories are `drwx------` owned by `_nixbldN`. Pioneer cannot `cd` into them to spawn the compiler, so the server returns a fatal error to the client (running as `_nixbldN`).

**Why not just stop the server?**: Without a running server, sccache tries to start a local daemon. The local daemon needs HOME to be writable. Nix builds set `HOME=/homeless-shelter` (read-only). Daemon startup fails.

---

## Failure mode 2 — SCCACHE_NO_DAEMON=1

**Symptom**: build hangs indefinitely; no error output; must be killed by timeout.

**Root cause**: With `SCCACHE_NO_DAEMON=1`, cc-rs invokes sccache as the C compiler wrapper. In this mode sccache spawns immediately and exits (becoming a zombie/defunct process almost instantly). Cargo, meanwhile, is waiting for the sccache output pipe that will never receive data. The build process hangs forever — no error, no timeout from nix, just a stuck `cargo check` process.

**Attempted SCCACHE_DIR workarounds**:
- `~/Library/Caches/sccache` — not writable by `_nixbldN` (Permission denied)
- `/private/tmp/nix-sccache` (mode 1777) — doesn't help in no-daemon mode; sccache exits before writing anything

---

## Why sccache doesn't help inside nix anyway

Nix's `cargoArtifacts` (crane's `buildDepsOnly`) is content-addressed: if `Cargo.lock` and all inputs are identical, nix reuses the store output in O(0). This is strictly better than sccache for the dep-build case. For the per-binary build (source changed), the rebuild only compiles the changed crate, not all deps — again matching what sccache would give you.

**Conclusion**: `RUSTC_WRAPPER=sccache` adds zero value inside nix derivations and breaks both ways. Keep it for interactive cargo builds outside nix (e.g., in your shell profile or direnv).

---

## Correct configuration (as of 2026-05-17)

In `modules/proxy-rust-services.nix`:
- No `RUSTC_WRAPPER` on any crane derivation
- No `SCCACHE_DIR`, no `SCCACHE_NO_DAEMON`
- For fast incremental host builds: `export RUSTC_WRAPPER=sccache` in shell / direnv outside nix

---

## Related

- `modules/proxy-rust-services.nix` — the sccache comment at the `buildInputs` section has the definitive explanation
- PR #22 — brought up these failure modes during initial crane integration
