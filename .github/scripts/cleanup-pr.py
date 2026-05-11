"""
Handles cleanup when a PR in personal-nix is closed.
Reads tachikoma metadata from the PR body, deletes the work-request file,
and closes the linked GitHub issue (if any).

Called by the tachikoma-cleanup workflow on pull_request closed events.
"""

import json
import os
import re
import subprocess
import sys


def run(cmd, **kwargs):
    return subprocess.run(cmd, text=True, **kwargs)


def git_commit_and_push(message):
    run(["git", "config", "user.name", "tachikoma-cleanup[bot]"])
    run(["git", "config", "user.email", "tachikoma-cleanup[bot]@users.noreply.github.com"])
    run(["git", "commit", "-m", message], check=True)
    run(["git", "push"], check=True)


pr_number = os.environ["PR_NUMBER"]
merged = os.environ["PR_MERGED"] == "true"
repo = os.environ["REPO"]

if not merged:
    print("PR closed without merging — nothing to do.")
    sys.exit(0)

result = run(
    ["gh", "pr", "view", pr_number, "--repo", repo, "--json", "body,url"],
    capture_output=True,
    check=True,
)
pr_data = json.loads(result.stdout)
body = pr_data.get("body") or ""
pr_url = pr_data["url"]

slug_match = re.search(r"<!-- tachikoma-slug: (.+?) -->", body)
issue_match = re.search(r"<!-- tachikoma-issue: (.+?) -->", body)

if not slug_match:
    print("No tachikoma-slug marker in PR body — not a tachikoma PR.")
    sys.exit(0)

slug = slug_match.group(1).strip()
issue = issue_match.group(1).strip() if issue_match else ""
print(f"slug={slug} issue={issue!r}")

wr_file = f"wiki/work-requests/{slug}.md"
if os.path.exists(wr_file):
    os.remove(wr_file)
    run(["git", "add", wr_file])
    result = run(["git", "diff", "--cached", "--quiet"])
    if result.returncode != 0:
        git_commit_and_push(f"chore: close work-request {slug} (PR #{pr_number} merged)")
    print(f"Deleted {wr_file}")
else:
    print(f"{wr_file} not found — already cleaned up or never existed.")

if issue:
    issue_repo, issue_num = issue.split("#", 1)
    result = run(
        [
            "gh", "issue", "view", issue_num, "--repo", issue_repo, "--json", "state",
        ],
        capture_output=True,
    )
    if result.returncode == 0:
        state = json.loads(result.stdout).get("state", "")
        if state == "OPEN":
            run(
                [
                    "gh", "issue", "close", issue_num, "--repo", issue_repo,
                    "--comment", f"Closed automatically via tachikoma: {pr_url} merged.",
                ],
                check=True,
            )
            print(f"Closed issue {issue}")
        else:
            print(f"Issue {issue} already {state} — skipping.")
    else:
        print(f"Could not fetch issue {issue} — skipping.")
