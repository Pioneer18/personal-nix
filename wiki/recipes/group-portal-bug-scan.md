---
title: Group Portal bug scan and agent-fix loop
tags: [relymd, group-portal, recipe, agents]
link: https://github.com/relymd/platform/blob/develop/apps/group-portal/AGENTS.md
---

# Group Portal bug scan → fix loop (first run 2026-10-27, 6 PRs merged)

Expectations agreed with Jonathan (grill-me, 10-27):
1. **Scan** in parallel: (a) prod evidence: `gcloud logging read` on `group-portal-prod` + `census-worker-prod` (project `bison-233014`), bucketed by revision, plus read-only prod `SELECT` counts (native `/opt/homebrew/bin/sqlcmd -S 34.24.237.199,1433 -d EmployerBrokerPortal -U sqlserver`, password `group-portal-sql-root-password`, refuse write keywords); (b) static sweep of the .NET 8 regression classes (binding nulls, Identity, EF Core graph/tracking, TempData/JSON, MVC routing). Sentry MCP needs interactive OAuth.
2. **Fix** only confirmed defects with a clear cause; report business logic, data repair, product calls. ≤6 PRs, one per defect class, each with a `MigrationAuditTests` regression test.
3. Agents work in `isolation: worktree`, open the PR, and stop. The main session arms watchers, spawns an independent review per PR, fixes blocking/high/in-PR mediums, then queues (`gh pr merge N`). No local containers: CI `group-portal-domain-tests.yml` runs on each PR. Confirm in the job log that the new tests ran.
4. **No prod deploy** without a separate yes (`gh workflow run group-portal-prod.yml --ref develop`).
5. Results in `docs/workbench/ftp-group-portal/bug-scan-<date>.md`, uncommitted on Jonathan's docs branch; draft GDEV tickets, file after approval.

## Daily routine (since 2026-10-29)

- launchd agent `org.nix-community.home.group-portal-bug-scan` (module `modules/group-portal-bug-scan.nix`), 07:00 local; a slot missed while asleep runs once on wake. Local, not a cloud `/schedule` routine: it needs Jonathan's gcloud login for the prod logs.
- `scripts/group-portal-bug-scan.sh`: lockfile, gcloud + gh auth preflight (macOS notification on failure), throwaway worktree of `origin/develop` under `~/.local/state/group-portal-bug-scan/`, then `claude -p` (Opus 5.5, high, bypassPermissions, 4 h timeout, $40 budget) with `group-portal-bug-scan.prompt.md`.
- Guardrails: `group-portal-bug-scan.settings.json` deny list (merge, workflow run, sqlcmd, gcloud secrets/sql/run deploy, force push, Jira, DB MCP) plus the prompt. It opens at most 3 `fix/scan-<date>-<slug>` PRs; it never merges or deploys.
- Babysitting gap: the run exits, so its PRs are watched only by the next run (step 1 runs clearance on every open `fix/scan-*` PR) or by an interactive session. Merging stays a human act.
- Output: `docs/workbench/ftp-group-portal/bug-scan-<date>.md` (untracked, main checkout), log `~/Library/Logs/group-portal-bug-scan/<date>.log`, notification with the `VERDICT:` line. State: `last-success` (log window start), `last-deployed-sha` (static sweep runs only when it changes).
- Manual run: `launchctl kickstart -k gui/$(id -u)/org.nix-community.home.group-portal-bug-scan`; rerun on the same day with `FORCE=1 zsh scripts/group-portal-bug-scan.sh`.
- Auth: the script sources `~/.secrets` (`CLAUDE_CODE_OAUTH_TOKEN`; launchd does not run `~/.zshrc`). The gcloud user login expires about once a day (org reauth), so the 07:00 run skips with a notification (10-31 to 11-02 all skipped). After `gcloud auth login`, kickstart to catch up. Proposed fix: a read-only service account (logging + Cloud Run viewer) with its key in Keychain.
- Idle SIGSEGV (P9) is a known report-only finding: do not confuse it with the fixed login crash (runbook `group-portal-non-mfa-login-crash.md`).

Gotchas from run 1:
- No CI check compiles `EmployerBrokerPortal.Web` or `GroupManagementPortalAutomation`. The reviewer must build them locally (`mkdir -p Web/node_modules Web/public/js/dist` skips node-sass).
- An agent can paste the wrong PR body (#3458 got #3459's) or add a workbench doc that conflicts with Jonathan's local docs branch (#3461). Check every body and diff for `docs/`.
- A FluentValidation validator that opens its own `EmployerBrokerContext.Create(...)` cannot see rows in the test transaction.
- Returning a tracked EF entity from an API action can lazy-load `EmployerGroup.Users` (password hashes). Return projections.
- (2026-10-29) A red Domain Tests job can be the runner, not the tests: on `atlas-standard` (`CI_STANDARD_RUNNER`, set 10-29 23:17Z) `setup-dotnet` fails with `mkdir /usr/share/dotnet: Permission denied`. Read the failed step before fixing code; rerun once the runner is repaired. (2026-10-30) Correction: every self-hosted runner (also `vega`) fails without `DOTNET_INSTALL_DIR`; #3593 (`72871a8c1d`) sets it to `runner.temp`. A rerun reuses the old merge ref, so a PR opened before that fix needs `gh pr update-branch <N>`, not `gh run rerun`.
- (2026-10-30) The gcloud token can need reauthentication in the middle of a run (`Reauthentication failed. cannot prompt`). Pull every log set early, save it under `/tmp/gpscan-<date>/`, and work from the files.
- (2026-11-02) The full `group-portal-prod` log passes a 200,000 `--limit` in about one day (uptime checks alone send about 12,000 `GET /login` a day). Pull `logName=".../run.googleapis.com%2Frequests"` for request counts and a filtered read (`WRN]`, `ERR]`, `FTL]`, `Exception`, `Uncaught signal`, `severity>=WARNING`) for the signals; do not count from a capped full read.
