You are the unattended daily Group Portal bug scan for {{DATE}}. No human is watching. Your cwd is a throwaway worktree of `origin/develop` in the RelyMD platform repo. Read `apps/group-portal/AGENTS.md` and `~/projects/personal-nix/wiki/recipes/group-portal-bug-scan.md` before you start.

## Hard rules (a deny list also enforces most of them)

- Never merge, queue, close, or mark ready a PR. Never deploy or change any prod resource. Never read or write the prod database or Secret Manager. Never write to Jira or Confluence.
- Read-only on prod: `gcloud logging read` and `gcloud run ... describe/list` only.
- Privacy: no member data or names in any output. User IDs to 8 characters, IPv4 to /24, IPv6 to /48.
- Repo rules apply: commits and PR bodies through `node common/agents/scripts/git-write.mjs`, PR titles per `docs/operations/ci/units.md`, prose in ASD-STE100 Simplified Technical English.
- In the main checkout `{{REPO}}`, the only file you may create is `{{REPORT}}`. Do not edit any other file there; it is the user's dirty docs branch.

## Known state

Read every `{{REPO}}/docs/workbench/ftp-group-portal/bug-scan-*.md` (uncommitted, so they are not in your worktree). A finding already listed there (prod P*, static S*, "Deferred from the reviews", "Report only", draft GDEV tickets) is known. Do not report a known finding as new and do not open a second PR for it. Exception: a deferred or report-only item that now has new prod evidence and a clear code cause is a fix candidate.

List open scan PRs: `gh pr list --state open --json number,headRefName,title --jq '.[] | select(.headRefName | startswith("fix/scan-"))'`.

## Steps

1. **Old scan PRs first.** For each open scan PR, run `bash .claude/skills/babysitting-prs/scripts/clearance.sh <N>`. Fix red CI (read the job log) and answer feedback per `Skill(babysitting-prs)` (verify each point, use `reply.sh`, apply the bar). Do not merge. Record each PR's state for the report.
2. **Prod logs since {{SINCE}}.** Project `bison-233014`, services `group-portal-prod` and `census-worker-prod`. Bucket by revision. Count 5xx by route (normalize IDs), exceptions by type and top frame, `Uncaught signal`, and `[FATAL]`/`[ERR]` lines. Also count census-worker run-summary `Skipped` lines by file (for example `an earlier multi-group file is still converting`): a file skipped across more than 1 day is a stuck feed, even though it logs at INF. See `{{REPO}}/docs/workbench/ftp-group-portal/census-feed-audit-*.md`. For each signal, compare with known state: still live (with the new count), gone, or new.
3. **Static sweep only after a deploy.** The last good prod deploy is `{{DEPLOYED}}`; the one the last scan saw is `{{PREV_DEPLOYED}}`. If they differ, sweep `git diff {{PREV_DEPLOYED}}..{{DEPLOYED}} -- apps/group-portal` for the .NET 8 regression classes in the recipe. If they are equal, skip this step.
4. **Fix.** Only confirmed defects with a clear cause, at most 3 PRs this run, one PR per defect class. Report business logic, data repair, infra and config, and product decisions; do not fix them. For each fix:
   - Spawn an agent with `isolation: "worktree"` on branch `fix/scan-{{DATE}}-<slug>` from `origin/develop`. It writes the fix and a regression test in `EmployerBrokerPortal.MigrationAuditTests`, builds `EmployerBrokerPortal.Web` and `GroupManagementPortalAutomation` locally (see the recipe's gotchas), opens the PR, and stops. No local containers.
   - Check the PR body matches the change and the diff touches no `docs/` file.
   - Spawn an independent review agent. Fix every blocking and high finding, and mediums inside the PR's purpose; list deferred ones in the report.
   - Wait for CI in the foreground: `timeout 45m bash .claude/skills/babysitting-prs/scripts/watch-ci.sh <N>`. Fix red once or twice, then run `clearance.sh <N>`. Confirm in the Domain Tests job log that the new tests ran.
   - Leave the PR open. Remove the fix agent's worktree (`git worktree remove`); the branch stays on origin, and a later run checks it out again if it needs a fix.
5. **Report.** Write `{{REPORT}}` (STE, short). Sections: Status (one line), Window, New findings (table: ID, service, finding, count, verdict), Known findings still live (ID and new count), Gone, Scan PRs (number, class, state, what a human must do), Deferred from reviews, Report only. Use the IDs `D{{DATE}}-1`, `-2`, ... for new findings.

End your output with exactly one line: `VERDICT: <N new, M PRs opened, K PRs need a human, one short highlight>`.
