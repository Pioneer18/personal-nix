---
title: Azure DevOps PAT setup for git + REST API access
tags: [azure-devops, ado, auth, pat, keychain, tier-3]
---

# Azure DevOps PAT setup for git + REST API access

## Problem

RelyMD source lives in Azure DevOps (`myidealdoctortelehealth.visualstudio.com/MYidealDOCTOR/_git/...`). There's no Azure DevOps MCP server installed and `az` CLI is not on this machine, so reading PRs / commits / etc. requires direct REST API calls authenticated with a Personal Access Token. The same PAT also drives `git push` / `git pull` via the osxkeychain credential helper.

PATs expire (default 30 days, max 1 year). When they expire, both git operations and API calls return 401, and the failure surfaces as `Access Denied: The Personal Access Token used has expired.` from the REST endpoint.

## Generate a new PAT

1. https://myidealdoctortelehealth.visualstudio.com/_usersSettings/tokens → **+ New Token**
2. **Name:** machine-scoped + dated (e.g. `claude-code-mbp2-2026-05`) so revocation is easy.
3. **Organization:** `myidealdoctortelehealth`
4. **Expiration:** 90 days or 1 year (30 days = monthly rotation pain).
5. **Scopes — Custom defined:**
   - **Code → Read & write** (covers repo read, PR read/comment, *and* git push). Do NOT use just "Read" — it blocks push.
   - **Work Items → Read** (optional; lets an agent resolve linked work items from PR descriptions).
   - Everything else off.
6. Click **Create**, copy the token (only shown once).

## Install into osxkeychain (so both git and curl can use it)

Copy PAT to clipboard, then in a shell:

```bash
PAT=$(pbpaste | tr -d '\n\r')

# Remove any existing (likely expired) entry — no need to know the old password.
printf "protocol=https\nhost=myidealdoctortelehealth.visualstudio.com\nusername=jonathan.sells\n\n" \
  | git credential reject

# Store the new one — git's osxkeychain helper writes it into Keychain.
printf "protocol=https\nhost=myidealdoctortelehealth.visualstudio.com\nusername=jonathan.sells\npassword=%s\n\n" "$PAT" \
  | git credential approve

unset PAT
pbcopy < /dev/null   # clear clipboard
```

This stores under Keychain service `myidealdoctortelehealth.visualstudio.com`, account `jonathan.sells`. Git's osxkeychain helper reads it on every push/pull.

## Verify

Git side — any `git pull` / `git push` against an ADO remote should succeed silently.

REST API side:

```bash
# Pull the PAT back out of keychain (git credential fill does this cleanly).
PAT=$(printf "protocol=https\nhost=myidealdoctortelehealth.visualstudio.com\n\n" \
        | git credential fill 2>/dev/null \
        | awk -F= '/^password=/{print $2}')

curl -s -u ":$PAT" \
  "https://myidealdoctortelehealth.visualstudio.com/MYidealDOCTOR/_apis/git/repositories/Group%20Management%20Portal/pullrequests?api-version=7.1&\$top=3&searchCriteria.status=active" \
  | python3 -m json.tool | head -30
unset PAT
```

HTTP 200 with a JSON body listing PRs = working. HTTP 203 with HTML "Access Denied" body = expired/wrong scopes (203 is ADO's misleading code for auth failures).

## REST API cheatsheet

Base URL pattern:

```
https://myidealdoctortelehealth.visualstudio.com/MYidealDOCTOR/_apis/<resource>?api-version=7.1
```

Auth header: Basic with empty user + PAT as password → `curl -u ":$PAT"` or `Authorization: Basic $(printf ":%s" "$PAT" | base64)`.

Useful endpoints (URL-encode repo name → `Group%20Management%20Portal`):

- List active PRs: `/_apis/git/repositories/<repo>/pullrequests?searchCriteria.status=active`
- Single PR: `/_apis/git/repositories/<repo>/pullrequests/<id>`
- PR threads (comments): `/_apis/git/repositories/<repo>/pullrequests/<id>/threads`
- PR commits: `/_apis/git/repositories/<repo>/pullrequests/<id>/commits`
- PR iterations / file changes: `/_apis/git/repositories/<repo>/pullrequests/<id>/iterations`
- Repo contents at ref: `/_apis/git/repositories/<repo>/items?path=<path>&versionDescriptor.version=<branch>`
- All repos in project: `/_apis/git/repositories`

Status filter values: `active`, `abandoned`, `completed`, `all`.

## Rotation

PAT expiration is silent — no email warning by default. Calendar a reminder ~7 days before expiry, or just re-run this recipe when something 401s. The old entry doesn't need manual deletion in keychain; `git credential reject` + re-approve overwrites cleanly.

## Revoke

If a token leaks or the machine is lost:

1. https://myidealdoctortelehealth.visualstudio.com/_usersSettings/tokens → revoke by name.
2. Local cleanup (optional): `security delete-internet-password -s myidealdoctortelehealth.visualstudio.com`

## Related

- [[mac-pre-proxy-prep]] — broader machine setup
- [[mcp-packaging-convention]] — long-term plan would be an ADO MCP server replacing the curl recipe
