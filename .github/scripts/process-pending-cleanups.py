"""
Hourly scheduled cleanup for cross-repo tachikoma PRs.
Reads wiki/pending-pr-cleanups.yml, checks each PR's state via GitHub API,
and for merged PRs: deletes the work-request file and closes the linked issue.

Called by the tachikoma-cleanup workflow on schedule and workflow_dispatch events.
Requires GH_TOKEN with access to target repos (set GH_PAT secret for cross-org repos).
"""

import json
import os
import subprocess
import sys

import yaml


def run(cmd, **kwargs):
    return subprocess.run(cmd, text=True, **kwargs)


PENDING = "wiki/pending-pr-cleanups.yml"

if not os.path.exists(PENDING):
    print("No pending-pr-cleanups.yml — nothing to do.")
    sys.exit(0)

with open(PENDING) as f:
    data = yaml.safe_load(f) or {}

entries = data.get("entries") or []
if not entries:
    print("No pending entries.")
    sys.exit(0)

remaining = []

for entry in entries:
    pr_url = entry["pr_url"]
    slug = entry["slug"]
    issue = entry.get("issue", "")

    result = run(
        ["gh", "pr", "view", pr_url, "--json", "state,merged,number"],
        capture_output=True,
    )
    if result.returncode != 0:
        print(f"Cannot check {pr_url}: {result.stderr.strip()} — keeping in pending.")
        remaining.append(entry)
        continue

    pr = json.loads(result.stdout)

    if pr["merged"]:
        print(f"PR {pr_url} merged — cleaning up slug={slug} issue={issue!r}")

        wr = f"wiki/work-requests/{slug}.md"
        if os.path.exists(wr):
            os.remove(wr)
            run(["git", "add", wr])
            print(f"  Staged deletion of {wr}")
        else:
            print(f"  {wr} not found — already cleaned up.")

        if issue:
            issue_repo, issue_num = issue.split("#", 1)
            state_result = run(
                ["gh", "issue", "view", issue_num, "--repo", issue_repo, "--json", "state"],
                capture_output=True,
            )
            if state_result.returncode == 0:
                state = json.loads(state_result.stdout).get("state", "")
                if state == "OPEN":
                    run(
                        [
                            "gh", "issue", "close", issue_num, "--repo", issue_repo,
                            "--comment",
                            f"Closed automatically via tachikoma: {pr_url} merged.",
                        ]
                    )
                    print(f"  Closed issue {issue}")
                else:
                    print(f"  Issue {issue} already {state} — skipping.")
            else:
                print(f"  Could not fetch issue {issue} — skipping.")

    elif pr["state"] == "CLOSED":
        print(f"PR {pr_url} closed without merging — removing from pending, work-request stays.")
    else:
        print(f"PR {pr_url} still open — keeping in pending.")
        remaining.append(entry)

data["entries"] = remaining
with open(PENDING, "w") as f:
    yaml.dump(data, f, default_flow_style=False, sort_keys=False)
run(["git", "add", PENDING])

result = run(["git", "diff", "--cached", "--quiet"])
if result.returncode != 0:
    run(["git", "config", "user.name", "tachikoma-cleanup[bot]"])
    run(["git", "config", "user.email", "tachikoma-cleanup[bot]@users.noreply.github.com"])
    run(["git", "commit", "-m", "chore: tachikoma cleanup — process pending PR closures"])
    run(["git", "push"])
    print("Changes committed and pushed.")
else:
    print("No changes to commit.")
