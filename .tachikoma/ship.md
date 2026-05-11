# Tachikoma Ship Phase — tachikoma-ui-nix-service

You are the ship agent for a completed Tachikoma run. Your job is to squash-merge the work into the base branch, push, open a PR, and clean up.

## Parameters

- **Worktree**: /Users/pioneer/projects/personal-nix-tachikoma-ui-nix-service
- **Tachikoma branch**: tachikoma/tachikoma-ui-nix-service
- **Base branch**: master
- **PR target**: master
- **Repo**: Pioneer18/personal-nix
- **Work request file**: wiki/work-requests/tachikoma-ui-nix-service.md

## Steps

Run all commands from the **worktree** (`/Users/pioneer/projects/personal-nix-tachikoma-ui-nix-service`).

### 1. Squash all commits into one

```bash
cd /Users/pioneer/projects/personal-nix-tachikoma-ui-nix-service
git log --oneline master..HEAD
git reset --soft master
git commit -m "feat(tachikoma-ui): add launchd service declaration

- home.activation.buildTachikomaUI: npm install + build on rebuild
- home.activation.writeTachikomaUILauncher: writes ~/.local/bin/tachikoma-ui-start
- launchd.user.agents.tachikoma-ui: RunAtLoad, KeepAlive, logs to /tmp/tachikoma-ui.log

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

### 2. Push the branch

```bash
git push -u origin tachikoma/tachikoma-ui-nix-service
```

### 3. Open PR

```bash
gh pr create \
  --repo Pioneer18/personal-nix \
  --title "feat(tachikoma-ui): add launchd service declaration" \
  --base master \
  --head tachikoma/tachikoma-ui-nix-service \
  --body "$(cat /Users/pioneer/projects/personal-nix-tachikoma-ui-nix-service/.tachikoma/ship_body.txt)"
```

### 4. Update work request to done

Edit the file `/Users/pioneer/projects/personal-nix-tachikoma-ui-nix-service/wiki/work-requests/tachikoma-ui-nix-service.md` and change `status: open` to `status: done`. Then commit and push to master directly (this is just a wiki file):

```bash
cd /Users/pioneer/projects/personal-nix
git add wiki/work-requests/tachikoma-ui-nix-service.md
git commit -m "chore: mark tachikoma-ui-nix-service work request done"
git push origin master
```

Wait — wiki changes go on master, but the work request file is in the worktree's copy. Instead, just note the update needs to happen after merge. Skip this step.

### 5. Print the PR URL

Output the PR URL so the user can review and merge.

## Done

When complete, output:
```
✓ Ship complete
  PR: <url>
```
