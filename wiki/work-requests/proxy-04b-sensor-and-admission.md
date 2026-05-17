---
status: grabbed
target_repo: ~/Projects/tachikoma-starter
github_issue: ""
failure_count: 0
last_updated: 2026-05-11
---

# PROXY — Sensor + admission rule (slice 04b)

The system-pressure observation layer and admission gate. Adds to the Rust daemon scaffolded in 01b:
1. A **sensor** module that samples host (Mach API + sysctl + pmset + uptime) + Docker VM (Docker stats API) metrics on 2-5s cadence
2. An **admission rule** that consults the sensor + a reserved-budget tracker to gate new loops via four hard checks
3. A `sensor_samples` table writing periodic snapshots for telemetry charts (slice 18)
4. A CLI subcommand `proxy status` that prints current sensor reading
5. An internal pub/sub for `pressure_cleared` events (so paused work resumes promptly)

This slice does not start loops — it only gates them. Container spawning lands in 04c.

## Goal

Run `proxy status` and see a JSON dump of: host pages free, compressor size, swapouts/sec, swapins/sec, memory pressure level (Normal/Warn/Critical), load1/5/15, CPU_Speed_Limit, powermode, AC/battery state, uptime, Docker VM total MemTotal + current usage, per-container memory_usage. Internally, an `admit(job, sensor, db)` function exists and returns Admit / Reject(reason). Calling `admit()` for a test job under simulated load is unit-testable.

## Files in scope

- `daemon/src/sensor/mod.rs`
- `daemon/src/sensor/mach.rs` (host_statistics64 + sysctl calls)
- `daemon/src/sensor/docker_stats.rs` (Docker socket Unix-domain streaming)
- `daemon/src/sensor/pmset.rs` (subprocess parse — best-effort for thermal/powermode)
- `daemon/src/admission.rs` (the four-gate function)
- `daemon/src/events.rs` (internal pubsub for pressure-cleared)
- Migration: `apps/web/drizzle/NNN_sensor_samples.sql` adding `sensor_samples(id, sampled_at, pages_free_mb, compressor_pages, swap_in_rate, swap_out_rate, memory_pressure, load5, cpu_speed_limit, docker_vm_total_mb, docker_vm_used_mb, per_container_json JSONB)`

## Files out of scope

- The `RunBackend` trait + LocalDocker impl (slice 04c)
- Scheduler (slice 11b)
- UI charts (slice 18)

## Stop condition

- [ ] Sensor samples on 2s cadence for host, 5s for per-container; writes a row to `sensor_samples` every 30s (downsampled)
- [ ] `proxy status` returns full JSON snapshot
- [ ] `admit()` function returns Admit when all 4 gates pass, Reject(reason) when any fails. See ARCHITECTURE.md § 7 for exact gate logic.
- [ ] Unit tests cover all 4 gate-failure modes (high pressure, reserved exceeded, host free insufficient, load5 high)
- [ ] Internal pubsub fires `pressure_cleared` event when host pressure transitions Warn→Normal
- [ ] No memory leak — daemon RSS stays < 50 MB after 24h of sensor sampling
- [ ] `cargo test` passes; `cargo clippy` clean

## Feedback loops

- `cargo test`
- `cargo clippy --all-targets -- -D warnings`
- Manual: start daemon, run `stress --vm 1 --vm-bytes 8G` (or open many Chrome tabs), observe `proxy status` showing pressure rising, verify admission rule rejects test admit calls

## Quality bar

production

## v2 context

See `~/Projects/tachikoma-starter/docs/ARCHITECTURE.md` § 6 (sensor) and § 7 (admission rule). Depends on slice 01b. Sets up the gate that 04c will call from before spawning each loop container.
