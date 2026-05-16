#!/usr/bin/env bash
# eval.sh — frozen private eval set for the Tachikoma loop.
#
# Implements ADR 008 Principle 7 (frozen private eval set). Pinned cases let
# the handler A/B-test prompt-template and harness changes against the
# handler's own historical work — uncontaminated, comparable, repeatable.
#
# Subcommands:
#   eval.sh add <issue-ref> [<acceptance-script>]
#     Pin a past issue + the resulting PR's diff fingerprint as a case.
#     issue-ref: org/repo#N. acceptance-script: optional path to a script
#     that exits zero if the new run's output is acceptable (defaults to
#     "diff size within 50% of original").
#
#   eval.sh list
#     Show pinned cases.
#
#   eval.sh run [<case-slug>] [--model <name>]
#     Re-run Tachikoma against one or all pinned cases on a fresh worktree
#     branch `eval/<case-slug>-<timestamp>`. Records pass/iters/tokens.
#
#   eval.sh report [<since-date>]
#     Diff results across runs (regression detection).
#
# Storage:
#   ~/projects/personal-nix/wiki/tachikoma-eval/
#     cases/<slug>.yaml          — pinned case metadata
#     runs/<slug>-<ts>/          — per-run output (log, stats, diff)
#     ledger.tsv                 — append-only run ledger for regression queries
#
# Exit codes:
#   0 — success.
#   1 — invocation error.
#   2 — case not found.
#   3 — run failed (Tachikoma errored or verifier-gate rejected at cap).

set -e
set -o pipefail

EVAL_ROOT="${TACHIKOMA_EVAL_ROOT:-$HOME/projects/personal-nix/wiki/tachikoma-eval}"
CASES_DIR="$EVAL_ROOT/cases"
RUNS_DIR="$EVAL_ROOT/runs"
LEDGER="$EVAL_ROOT/ledger.tsv"

ensure_dirs() {
  mkdir -p "$CASES_DIR" "$RUNS_DIR"
  if [ ! -f "$LEDGER" ]; then
    printf 'timestamp\tcase_slug\tmodel\titers\toutcome\ttokens_in\ttokens_out\tnotes\n' > "$LEDGER"
  fi
}

cmd_add() {
  if [ -z "${1:-}" ]; then
    cat <<'EOF' >&2
eval add: usage
  eval.sh add <org/repo#N> [<acceptance-script>]
      Pin from a GitHub issue or PR ref. N is tried as an issue first,
      then as a PR.
  eval.sh add --local <brief.md> [<acceptance-script>]
      Pin a local-mode Tachikoma case from a markdown brief file. First
      H1 (or first line if no H1) becomes the title; rest is the body.
  eval.sh add --from-worktree <wt-path> [<acceptance-script>]
      Pin from a live (or surviving) Tachikoma worktree. Reads
      plans/prd.json + .tachikoma/prompt.md to recover goal + scope.
EOF
    exit 1
  fi

  case "$1" in
    --local)         shift; cmd_add_local "$@" ;;
    --from-worktree) shift; cmd_add_worktree "$@" ;;
    --*)             echo "eval add: unknown flag '$1'" >&2; exit 1 ;;
    *)               cmd_add_ref "$@" ;;
  esac
}

# Original GitHub-ref intake (org/repo#N — issue or PR).
cmd_add_ref() {
  local ref="$1"
  local accept_script="${2:-}"
  ensure_dirs

  # Parse org/repo#N
  local repo_part="${ref%#*}"
  local num_part="${ref##*#}"
  if [ "$repo_part" = "$ref" ] || [ -z "$num_part" ]; then
    echo "eval add: '$ref' is not org/repo#N" >&2
    exit 1
  fi

  # Resolve N as either an issue or a PR. Both sources give us title + body;
  # we capture the relevant metadata regardless. Source type recorded.
  local source_type title body pr_num pr_diff_lines pr_files
  pr_num=""
  pr_diff_lines="0"
  pr_files="0"

  title="$(gh issue view "$num_part" --repo "$repo_part" --json title --jq .title 2>/dev/null || echo "")"
  if [ -n "$title" ]; then
    source_type="issue"
    body="$(gh issue view "$num_part" --repo "$repo_part" --json body --jq .body 2>/dev/null || echo "")"
    # Try to find the merged PR that closed this issue.
    pr_num="$(gh pr list --repo "$repo_part" --state merged --search "linked:$num_part" \
      --json number --jq '.[0].number' 2>/dev/null || echo "")"
  else
    # Fall through to PR lookup.
    title="$(gh pr view "$num_part" --repo "$repo_part" --json title --jq .title 2>/dev/null || echo "")"
    if [ -z "$title" ]; then
      echo "eval add: could not fetch issue OR PR $ref (gh auth? does the ref exist?)" >&2
      exit 1
    fi
    source_type="pr"
    body="$(gh pr view "$num_part" --repo "$repo_part" --json body --jq .body 2>/dev/null || echo "")"
    pr_num="$num_part"
  fi

  if [ -n "$pr_num" ]; then
    pr_diff_lines="$(gh pr diff "$pr_num" --repo "$repo_part" 2>/dev/null | wc -l | tr -d ' ')"
    pr_files="$(gh pr view "$pr_num" --repo "$repo_part" --json files --jq '.files | length' 2>/dev/null || echo "0")"
  fi

  # Slug
  local slug
  slug="$(echo "$title" \
    | tr '[:upper:]' '[:lower:]' \
    | sed 's/[^a-z0-9]/-/g; s/-\+/-/g; s/^-//; s/-$//' \
    | cut -c1-40)"
  slug="${source_type}-${num_part}-${slug}"

  local case_file="$CASES_DIR/$slug.yaml"
  if [ -e "$case_file" ]; then
    echo "eval add: case already pinned at $case_file" >&2
    exit 1
  fi

  # Save body to a sibling file so we can preserve newlines / markdown.
  local body_file="$CASES_DIR/$slug.body.md"
  printf '%s\n' "$body" > "$body_file"

  cat > "$case_file" <<EOF
slug: $slug
ref: $ref
source_type: $source_type
title: $title
body_file: $body_file
original_pr: ${pr_num:-null}
original_diff_lines: $pr_diff_lines
original_files_changed: $pr_files
acceptance_script: ${accept_script:-null}
pinned_at: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF

  echo "Pinned case: $slug"
  echo "  file:           $case_file"
  echo "  source:         $source_type ($ref)"
  echo "  title:          $title"
  echo "  original PR:    ${pr_num:-none}"
  echo "  original diff:  $pr_diff_lines lines, $pr_files files"
  if [ -n "$accept_script" ]; then
    echo "  accept script:  $accept_script"
  else
    echo "  accept rule:    default — diff size within 50% of original"
  fi
}

# Pin a local-mode Tachikoma case from a markdown brief file.
# Title = first H1 in the file (or first non-empty line if no H1).
# Body  = the rest of the file verbatim.
cmd_add_local() {
  local brief_path="$1"
  local accept_script="${2:-}"
  if [ -z "$brief_path" ] || [ ! -f "$brief_path" ]; then
    echo "eval add --local: brief file required and must exist" >&2
    exit 1
  fi
  ensure_dirs

  # Title: first H1, else first non-empty line, else "(untitled)".
  local title
  title="$(awk '
    /^# +/ { sub(/^# +/, ""); print; exit }
    /^[^[:space:]]/ && !found { print; found=1; exit }
  ' "$brief_path")"
  [ -z "$title" ] && title="(untitled local brief)"

  local slug
  slug="$(echo "$title" \
    | tr '[:upper:]' '[:lower:]' \
    | sed 's/[^a-z0-9]/-/g; s/-\+/-/g; s/^-//; s/-$//' \
    | cut -c1-40)"
  slug="local-${slug}"

  local case_file="$CASES_DIR/$slug.yaml"
  if [ -e "$case_file" ]; then
    echo "eval add --local: case already pinned at $case_file" >&2
    exit 1
  fi

  local body_file="$CASES_DIR/$slug.body.md"
  cp "$brief_path" "$body_file"

  # Brief-mode diff stats are unknown until the run completes — leave at 0.
  cat > "$case_file" <<EOF
slug: $slug
ref: local:$(basename "$brief_path")
source_type: local-brief
title: $title
body_file: $body_file
original_brief: $brief_path
original_pr: null
original_diff_lines: 0
original_files_changed: 0
acceptance_script: ${accept_script:-null}
pinned_at: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF

  echo "Pinned case: $slug"
  echo "  file:           $case_file"
  echo "  source:         local-brief"
  echo "  brief:          $brief_path  (copied → $body_file)"
  echo "  title:          $title"
  if [ -n "$accept_script" ]; then
    echo "  accept script:  $accept_script"
  else
    echo "  accept rule:    handler-judged (no GH ref to anchor)"
  fi
}

# Pin a local-mode Tachikoma case from a live (or surviving) worktree.
# Reads plans/prd.json for goal/scope/stop-condition; falls back to the
# rendered .tachikoma/prompt.md if the PRD isn't present (e.g. --issue mode).
# Best-effort: also captures the resulting PR if the branch was merged.
cmd_add_worktree() {
  local wt="$1"
  local accept_script="${2:-}"
  if [ -z "$wt" ] || [ ! -d "$wt" ]; then
    echo "eval add --from-worktree: worktree path required and must be a directory" >&2
    exit 1
  fi
  ensure_dirs

  local prd_file="$wt/plans/prd.json"
  local prompt_file="$wt/.tachikoma/prompt.md"

  if [ ! -f "$prd_file" ] && [ ! -f "$prompt_file" ]; then
    echo "eval add --from-worktree: neither $prd_file nor $prompt_file found — not a Tachikoma worktree?" >&2
    exit 1
  fi

  local title goal stop_condition quality_bar files_in files_out
  if [ -f "$prd_file" ]; then
    # PRD is the authoritative source for local-mode runs.
    if ! command -v python3 >/dev/null 2>&1; then
      echo "eval add --from-worktree: python3 required to parse $prd_file" >&2
      exit 1
    fi
    title="$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d.get("goal","")[:120])' "$prd_file")"
    goal="$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d.get("goal",""))' "$prd_file")"
    stop_condition="$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d.get("stop_condition",""))' "$prd_file")"
    quality_bar="$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d.get("quality_bar",""))' "$prd_file")"
    files_in="$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(", ".join(d.get("files_in_scope",[])))' "$prd_file")"
    files_out="$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(", ".join(d.get("files_out_of_scope",[])))' "$prd_file")"
  else
    # --issue / --remote mode worktree — no PRD; pull from rendered prompt.md.
    title="$(grep -A1 '^## Goal' "$prompt_file" | tail -1 | cut -c1-120)"
    goal="$(awk '/^## Goal/{flag=1; next} /^## /{flag=0} flag' "$prompt_file" | head -20)"
    stop_condition="$(awk '/^## Stop condition/{flag=1; next} /^## /{flag=0} flag' "$prompt_file" | head -10)"
    quality_bar="(see prompt.md)"
    files_in="$(awk '/^## Files in scope/{flag=1; next} /^## /{flag=0} flag' "$prompt_file" | head -10 | tr '\n' ' ')"
    files_out="$(awk '/^## Files out of scope/{flag=1; next} /^## /{flag=0} flag' "$prompt_file" | head -10 | tr '\n' ' ')"
  fi
  [ -z "$title" ] && title="(worktree case from $(basename "$wt"))"

  local slug
  slug="$(basename "$wt" | sed 's/.*-tachikoma-//' | cut -c1-40)"
  slug="local-wt-${slug}"

  local case_file="$CASES_DIR/$slug.yaml"
  if [ -e "$case_file" ]; then
    echo "eval add --from-worktree: case already pinned at $case_file" >&2
    exit 1
  fi

  # Compose the body file from the resolved brief.
  local body_file="$CASES_DIR/$slug.body.md"
  {
    echo "# $title"
    echo ""
    echo "## Goal"
    echo ""
    echo "$goal"
    echo ""
    echo "## Stop condition"
    echo ""
    echo "$stop_condition"
    echo ""
    echo "## Files in scope"
    echo ""
    echo "$files_in"
    echo ""
    echo "## Files out of scope"
    echo ""
    echo "$files_out"
  } > "$body_file"

  # Best-effort PR detection: if the worktree's branch was merged, find the PR.
  local pr_num="" pr_diff_lines="0" pr_files="0" branch
  branch="$(git -C "$wt" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")"
  if [ -n "$branch" ] && command -v gh >/dev/null 2>&1; then
    pr_num="$(gh pr list --head "$branch" --state merged --json number --jq '.[0].number' 2>/dev/null || echo "")"
    if [ -n "$pr_num" ]; then
      pr_diff_lines="$(gh pr diff "$pr_num" 2>/dev/null | wc -l | tr -d ' ')"
      pr_files="$(gh pr view "$pr_num" --json files --jq '.files | length' 2>/dev/null || echo "0")"
    fi
  fi

  cat > "$case_file" <<EOF
slug: $slug
ref: local-wt:$(basename "$wt")
source_type: local-worktree
title: $title
body_file: $body_file
original_worktree: $wt
original_branch: ${branch:-unknown}
quality_bar: ${quality_bar:-unknown}
original_pr: ${pr_num:-null}
original_diff_lines: $pr_diff_lines
original_files_changed: $pr_files
acceptance_script: ${accept_script:-null}
pinned_at: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF

  echo "Pinned case: $slug"
  echo "  file:           $case_file"
  echo "  source:         local-worktree"
  echo "  worktree:       $wt"
  echo "  branch:         ${branch:-unknown}"
  echo "  title:          $title"
  echo "  body:           $body_file (rendered from PRD + prompt.md)"
  echo "  original PR:    ${pr_num:-none}"
  echo "  original diff:  $pr_diff_lines lines, $pr_files files"
  if [ -n "$accept_script" ]; then
    echo "  accept script:  $accept_script"
  else
    echo "  accept rule:    handler-judged (local mode)"
  fi
}

cmd_list() {
  ensure_dirs
  if ! ls "$CASES_DIR"/*.yaml >/dev/null 2>&1; then
    echo "No pinned cases. Use \`eval.sh add <org/repo#N>\` to pin one." >&2
    exit 0
  fi
  printf '%-50s %-30s %-15s %-10s\n' "SLUG" "REF" "TYPE" "DIFF-LINES"
  printf '%-50s %-30s %-15s %-10s\n' "----" "---" "----" "----------"
  for f in "$CASES_DIR"/*.yaml; do
    local slug ref source_type diff
    slug="$(grep '^slug:' "$f" | awk '{print $2}')"
    ref="$(grep '^ref:' "$f" | awk '{print $2}')"
    source_type="$(grep '^source_type:' "$f" | awk '{print $2}')"
    diff="$(grep '^original_diff_lines:' "$f" | awk '{print $2}')"
    printf '%-50s %-30s %-15s %-10s\n' "$slug" "$ref" "$source_type" "$diff"
  done
}

cmd_run() {
  local case_slug="${1:-}"
  shift || true
  local model_override=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --model) model_override="$2"; shift 2 ;;
      *) echo "eval run: unknown arg $1" >&2; exit 1 ;;
    esac
  done

  ensure_dirs
  local cases=()
  if [ -n "$case_slug" ]; then
    local f="$CASES_DIR/$case_slug.yaml"
    if [ ! -f "$f" ]; then
      echo "eval run: case not found: $case_slug" >&2
      exit 2
    fi
    cases+=("$f")
  else
    if ! ls "$CASES_DIR"/*.yaml >/dev/null 2>&1; then
      echo "eval run: no cases pinned" >&2
      exit 1
    fi
    while IFS= read -r line; do cases+=("$line"); done < <(ls "$CASES_DIR"/*.yaml)
  fi

  for f in "${cases[@]}"; do
    local slug ref source_type title body_file
    slug="$(grep '^slug:' "$f" | awk '{print $2}')"
    ref="$(grep '^ref:' "$f" | awk '{print $2}')"
    source_type="$(grep '^source_type:' "$f" | awk '{print $2}')"
    title="$(grep '^title:' "$f" | cut -d: -f2- | sed 's/^ //')"
    body_file="$(grep '^body_file:' "$f" | awk '{print $2}')"
    local ts; ts="$(date -u +%Y%m%dT%H%M%SZ)"
    local run_dir="$RUNS_DIR/$slug-$ts"
    mkdir -p "$run_dir"

    echo ""
    echo "── eval run: $slug ($ref) ──"

    # We don't auto-launch /tachikoma from here — eval requires the handler
    # to drive launch (worktree mgmt + grill bypass require the skill). This
    # subcommand instead records the *intent* and prints the launch command.
    # For issue-sourced cases: launch via --issue. For PR-sourced cases:
    # there's no live issue to re-launch from, so print a local-mode launch
    # cmd seeded with the captured title + body file.
    local launch_cmd
    local model_env=""
    if [ -n "$model_override" ]; then
      model_env="TACHIKOMA_MODEL=$model_override "
    fi
    case "$source_type" in
      issue)
        # ref looks like org/repo#N — pass to --issue verbatim.
        launch_cmd="${model_env}/tachikoma --issue $ref"
        ;;
      pr)
        # PR-sourced cases have no live issue; print local-mode hint.
        launch_cmd="${model_env}/tachikoma  # local mode; seed goal from: $body_file (title: $title)"
        ;;
      local-brief|local-worktree)
        # Local-mode cases — bare /tachikoma, handler pastes the brief at grill.
        launch_cmd="${model_env}/tachikoma  # local mode; paste brief from: $body_file"
        ;;
      *)
        launch_cmd="${model_env}/tachikoma  # unknown source_type=$source_type; brief: $body_file"
        ;;
    esac
    echo "$launch_cmd" > "$run_dir/launch.cmd"
    echo "PENDING: $launch_cmd" > "$run_dir/status"
    echo "  run dir:        $run_dir"
    echo "  source type:    $source_type"
    echo "  title:          $title"
    echo "  brief file:     $body_file"
    echo "  launch:         $launch_cmd"
    echo "  After the run completes, call:"
    echo "    eval.sh record $run_dir <iters> <outcome> [<tokens_in> <tokens_out>]"
  done
}

cmd_record() {
  local run_dir="${1:-}"
  local iters="${2:-?}"
  local outcome="${3:-?}"
  local tokens_in="${4:-?}"
  local tokens_out="${5:-?}"
  if [ -z "$run_dir" ] || [ ! -d "$run_dir" ]; then
    echo "eval record: usage: eval.sh record <run_dir> <iters> <outcome> [<tokens_in> <tokens_out>]" >&2
    exit 1
  fi
  ensure_dirs
  local slug; slug="$(basename "$run_dir" | sed 's/-[0-9TZ]\{16\}$//')"
  local ts; ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  local model="${TACHIKOMA_MODEL:-sonnet}"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$ts" "$slug" "$model" "$iters" "$outcome" "$tokens_in" "$tokens_out" "" \
    >> "$LEDGER"
  echo "RECORDED: $slug iters=$iters outcome=$outcome model=$model" > "$run_dir/status"
  echo "Recorded: $slug outcome=$outcome iters=$iters"
}

cmd_report() {
  local since="${1:-}"
  ensure_dirs
  if [ ! -s "$LEDGER" ]; then
    echo "No runs recorded yet." >&2
    exit 0
  fi
  echo "Run ledger ($LEDGER):"
  if [ -n "$since" ]; then
    awk -F'\t' -v since="$since" 'NR==1 || $1>=since' "$LEDGER" | column -t -s '	'
  else
    column -t -s '	' "$LEDGER"
  fi
  echo ""
  echo "Pass rate per case (across all runs):"
  awk -F'\t' 'NR>1 {
    case_tot[$2]++
    if ($5=="pass") case_pass[$2]++
  } END {
    for (c in case_tot) {
      p = (c in case_pass) ? case_pass[c] : 0
      printf "  %-50s %d/%d\n", c, p, case_tot[c]
    }
  }' "$LEDGER"
}

case "${1:-}" in
  add)    shift; cmd_add "$@" ;;
  list)   shift; cmd_list "$@" ;;
  run)    shift; cmd_run "$@" ;;
  record) shift; cmd_record "$@" ;;
  report) shift; cmd_report "$@" ;;
  ""|--help|-h)
    cat <<'EOF'
eval.sh — frozen private eval set for the Tachikoma loop

Subcommands:
  add <org/repo#N> [<accept-script>]              Pin from a GitHub issue/PR ref
  add --local <brief.md> [<accept-script>]        Pin a local-mode case from a brief file
  add --from-worktree <wt-path> [<accept-script>] Pin from a live Tachikoma worktree
  list                                             Show pinned cases
  run [<case-slug>] [--model <name>]               Print launch cmd(s) for a re-run
  record <run-dir> <iters> <outcome>               Record the result of a re-run
  report [<since-date>]                            Show ledger + per-case pass rate

Storage: ~/projects/personal-nix/wiki/tachikoma-eval/
See PROXY ADR 008 § P7 for rationale.
EOF
    ;;
  *)
    echo "eval.sh: unknown subcommand '$1'" >&2
    exit 1
    ;;
esac
