---
name: orient-to-branch
description: Orient to the current git branch before working on it — surveys commit history, the associated PR, linked GitHub issue, linked PROXY work request, Jira ticket (if branch encodes one), and the repo's AGENTS/CLAUDE/ADR docs. Use when starting work on an unfamiliar branch, resuming after a break, or when the user says "orient to this branch", "catch me up", "what's going on with this branch", or invokes `/orient-to-branch`.
---

# Orient to Branch

Goal: in one pass, build a complete picture of *what the branch is for*, *what's been done*, *what's left*, and *what code you'll touch* — before writing a single line.

## Workflow

Run the read-only steps in parallel. Skip steps cleanly when the artifact doesn't exist (no PR, no issue, no work request, no docs).

### 1. Branch context
- `git branch --show-current` — record the branch name.
- `git status` — note any uncommitted changes (they're part of the picture).
- Parse the branch name for identifiers:
  - **Jira key**: uppercase letters + `-` + digits, e.g. `PLRM-1222`, `ABC-123`.
  - **GitHub issue**: trailing `#123` or `-123` after the type prefix.
  - **PROXY slug**: kebab-case slug after the type prefix (`feat/some-slug` → `some-slug`).

### 2. Commit history
- Detect the base branch: try in order `dev`, `develop`, `main`, `master`. Pick the first that exists on the remote (`git rev-parse --verify origin/<name>`).
- `git log <base>..HEAD --oneline` — full commit list on this branch.
- `git diff <base>...HEAD --stat` — what files changed and by how much.

### 3. PR (if exists)
- `gh pr view --json title,body,state,labels,reviews,comments,headRefName,baseRefName,statusCheckRollup`
- Read the description; then the **most recent** review comments (not stale ones).
- Note unaddressed review feedback and failing checks.

### 4. Linked GitHub issue
- Extract from PR body (`Closes #123`, `Fixes #123`, `org/repo#123`) or from the branch name.
- `gh issue view <num> --json title,body,labels,comments,state`.

### 5. Jira ticket (if branch encodes one)
- If an Atlassian MCP tool is available (`mcp__plugin_atlassian_atlassian__*`), fetch the ticket by key.
- Otherwise, note the Jira key for the user to consult — don't fabricate ticket content.

### 6. PROXY work request (if PROXY is running)
- Probe `curl -fsS http://localhost:3000/api/work-requests?limit=100`. If it fails (connection refused), skip cleanly — don't try to start PROXY.
- Match against the result:
  - `slug` equal to or substring of the branch-derived slug, **or**
  - `githubIssue` matching the PR's repo + issue number.
- If matched, read `description`, `targetRepo`, `status`, and `config.failure_count`.

### 7. Codebase rules and docs
- Read repo-root `CLAUDE.md`, `AGENTS.md`, and `README.md` if present.
- Read `docs/ARCHITECTURE.md`, `docs/CONTEXT.md`, and the `docs/adr/` index if present.
- For each package directory touched by the diff, read its local `CLAUDE.md` / `AGENTS.md` if present (monorepo packages often have their own).

### 8. Code under the diff
- Read the modified files end-to-end (not excerpts).
- Follow one level of imports/callers around the changes — enough to understand surrounding context, not the whole module graph.

## Output

End with a 4-line synthesis the user can grok at a glance:

```
Purpose:  <one sentence — what this branch ships>
Status:   <commits ahead · PR state · review state · uncommitted changes>
Blockers: <unaddressed review notes · failing checks · open questions — or "none">
Next:     <the single most-likely next action>
```

Then offer to dive in: "Ready to work on this — want me to <next action>, or something else?"

If an artifact doesn't exist, say `"none"` for that line — don't speculate.

## Anti-patterns

- Don't summarize file contents you didn't read.
- Don't skip the PROXY probe because "it's probably not running" — `curl` is cheap and fails fast.
- Don't read every file in the repo — only files in the diff and one level of context around them.
- Don't propose changes during orientation. Orientation is read-only; the next message is where work starts.
- Don't fabricate Jira/issue content when the tool to fetch it isn't available — flag the gap instead.
