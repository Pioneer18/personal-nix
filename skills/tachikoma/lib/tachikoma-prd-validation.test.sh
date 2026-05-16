#!/usr/bin/env bash
# Tests for prd-validate.py and prd-load.sh.
# Mirrors queue-grab.test.sh style.

set -e
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALIDATE="$SCRIPT_DIR/prd-validate.py"
LOAD="$SCRIPT_DIR/prd-load.sh"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

PASS=0
FAIL=0

# valid_prd writes a minimal valid PRD to $1.
valid_prd() {
  cat >"$1" <<'EOF'
{
  "schema_version": 1,
  "target_repo": "MioMarker/healthbite",
  "goal": "Fix the vital age calc",
  "quality_bar": "production",
  "stop_condition": "All tests green and biomarker tests cover the regression",
  "files_in_scope": ["src/biomarkers/**"],
  "files_out_of_scope": ["docs/**"]
}
EOF
}

run_case() {
  local name="$1"
  local expected_rc="$2"
  local prd_file="$3"
  local expect_stderr_contains="${4:-}"

  local actual_rc actual_stderr
  set +e
  actual_stderr="$("$VALIDATE" "$prd_file" 2>&1 >/dev/null)"
  actual_rc=$?
  set -e

  local ok=1
  if [ "$actual_rc" -ne "$expected_rc" ]; then ok=0; fi
  if [ -n "$expect_stderr_contains" ] && [[ "$actual_stderr" != *"$expect_stderr_contains"* ]]; then ok=0; fi

  if [ $ok -eq 1 ]; then
    PASS=$((PASS + 1))
    echo "  ok — $name"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL — $name"
    echo "       expected rc=$expected_rc stderr~$(printf %q "$expect_stderr_contains")"
    echo "       got      rc=$actual_rc stderr=$(printf %q "$actual_stderr")"
  fi
}

# Happy path
valid_prd "$TMPDIR/valid.json"
run_case "minimal valid PRD passes" 0 "$TMPDIR/valid.json"

# Missing required fields — one case per required field
for field in schema_version target_repo goal quality_bar stop_condition files_in_scope files_out_of_scope; do
  valid_prd "$TMPDIR/missing-$field.json"
  python3 -c "
import json, sys
with open('$TMPDIR/missing-$field.json') as f: d = json.load(f)
d.pop('$field', None)
with open('$TMPDIR/missing-$field.json', 'w') as f: json.dump(d, f)
"
  run_case "missing required field: $field" 1 "$TMPDIR/missing-$field.json" "missing required field '$field'"
done

# Malformed: schema_version != 1
valid_prd "$TMPDIR/bad-version.json"
python3 -c "
import json
with open('$TMPDIR/bad-version.json') as f: d = json.load(f)
d['schema_version'] = 2
with open('$TMPDIR/bad-version.json', 'w') as f: json.dump(d, f)
"
run_case "schema_version != 1 rejected" 1 "$TMPDIR/bad-version.json" "must equal 1"

# Malformed: bad target_repo pattern
valid_prd "$TMPDIR/bad-target.json"
python3 -c "
import json
with open('$TMPDIR/bad-target.json') as f: d = json.load(f)
d['target_repo'] = 'not-a-valid-form'
with open('$TMPDIR/bad-target.json', 'w') as f: json.dump(d, f)
"
run_case "bad target_repo pattern rejected" 1 "$TMPDIR/bad-target.json" "does not match pattern"

# Malformed: quality_bar not in enum
valid_prd "$TMPDIR/bad-quality.json"
python3 -c "
import json
with open('$TMPDIR/bad-quality.json') as f: d = json.load(f)
d['quality_bar'] = 'experimental'
with open('$TMPDIR/bad-quality.json', 'w') as f: json.dump(d, f)
"
run_case "quality_bar not in enum rejected" 1 "$TMPDIR/bad-quality.json" "must be one of"

# Unknown top-level key (strict validation)
valid_prd "$TMPDIR/bad-extra.json"
python3 -c "
import json
with open('$TMPDIR/bad-extra.json') as f: d = json.load(f)
d['unknown_field'] = 'should-be-rejected'
with open('$TMPDIR/bad-extra.json', 'w') as f: json.dump(d, f)
"
run_case "unknown top-level key rejected (strict)" 1 "$TMPDIR/bad-extra.json" "unknown field 'unknown_field'"

# Business rule: objective_id without operation_slug
valid_prd "$TMPDIR/bad-objective.json"
python3 -c "
import json
with open('$TMPDIR/bad-objective.json') as f: d = json.load(f)
d['objective_id'] = 'obj-1'
with open('$TMPDIR/bad-objective.json', 'w') as f: json.dump(d, f)
"
run_case "objective_id without operation_slug rejected" 1 "$TMPDIR/bad-objective.json" "'objective_id' requires 'operation_slug'"

# iteration_cap out of range
valid_prd "$TMPDIR/bad-cap.json"
python3 -c "
import json
with open('$TMPDIR/bad-cap.json') as f: d = json.load(f)
d['iteration_cap'] = 100
with open('$TMPDIR/bad-cap.json', 'w') as f: json.dump(d, f)
"
run_case "iteration_cap > 50 rejected" 1 "$TMPDIR/bad-cap.json" "greater than maximum"

# items category not in enum
valid_prd "$TMPDIR/bad-item-category.json"
python3 -c "
import json
with open('$TMPDIR/bad-item-category.json') as f: d = json.load(f)
d['items'] = [{'id': 'T-001', 'category': 'urgent', 'description': 'do thing'}]
with open('$TMPDIR/bad-item-category.json', 'w') as f: json.dump(d, f)
"
run_case "items[].category not in enum rejected" 1 "$TMPDIR/bad-item-category.json" "must be one of"

# Valid file with all optional fields populated
cat >"$TMPDIR/full.json" <<'EOF'
{
  "schema_version": 1,
  "target_repo": "Pioneer18/personal-nix",
  "goal": "Add fast dispatch mode",
  "quality_bar": "production",
  "stop_condition": "REST endpoint returns 200 for a valid PRD",
  "files_in_scope": ["skills/tachikoma/**"],
  "files_out_of_scope": ["wiki/**"],
  "items": [
    {"id": "T-001", "category": "functional", "description": "schema", "steps": ["write schema"], "blocked_by": []},
    {"id": "T-002", "category": "test", "description": "tests", "steps": ["happy path"], "blocked_by": ["T-001"]}
  ],
  "pr_target_branch": "master",
  "github_issue": "Pioneer18/personal-nix#42",
  "epic_slug": "tachikoma-launch-latency",
  "operation_slug": "proxy-build",
  "objective_id": "obj-3",
  "iteration_cap": 20,
  "iteration_mode": "afk",
  "feedback_loops": {
    "typecheck": "bin/relymd typecheck",
    "test": "bin/relymd test",
    "lint": "bin/relymd lint"
  },
  "model": "sonnet",
  "planner_model": "haiku-4.5",
  "idempotency_key": "550e8400-e29b-41d4-a716-446655440000"
}
EOF
run_case "full PRD with all optional fields passes" 0 "$TMPDIR/full.json"

# Invalid: bad JSON
echo "{ not valid json" >"$TMPDIR/bad-json.json"
run_case "invalid JSON returns exit 2" 2 "$TMPDIR/bad-json.json" "invalid JSON"

# Invalid: missing file
run_case "missing file returns exit 2" 2 "$TMPDIR/nonexistent.json" "cannot read"

# prd-load.sh integration: valid → echoes PRD
valid_prd "$TMPDIR/load-valid.json"
set +e
LOAD_OUT="$("$LOAD" "$TMPDIR/load-valid.json" 2>/dev/null)"
LOAD_RC=$?
set -e
if [ "$LOAD_RC" -eq 0 ] && [[ "$LOAD_OUT" == *"schema_version"* ]]; then
  PASS=$((PASS + 1))
  echo "  ok — prd-load.sh echoes valid PRD"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL — prd-load.sh on valid PRD: rc=$LOAD_RC out=$LOAD_OUT"
fi

# prd-load.sh: invalid → exit 1
echo '{"schema_version": 99}' >"$TMPDIR/load-bad.json"
set +e
"$LOAD" "$TMPDIR/load-bad.json" >/dev/null 2>&1
LOAD_RC=$?
set -e
if [ "$LOAD_RC" -eq 1 ]; then
  PASS=$((PASS + 1))
  echo "  ok — prd-load.sh exits 1 on invalid PRD"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL — prd-load.sh on invalid PRD: rc=$LOAD_RC"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ]
