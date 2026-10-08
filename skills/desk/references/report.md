# Friday leadership report

Audience: leadership, spoken aloud on Friday in about **2 minutes (≈250 words)**. Topics: what happened this week, what's on deck next.

1. `desk digest` (default: Monday of this week → today). For `month`: `--since` the 1st. For a project: filter the output to that project.
2. Check the live status of the Jira keys/PRs in the digest when it changes the story (merged, shipped, blocked).
3. Read last week's `reports/<prev-week>.md` if it exists. Call out items promised last week that landed or slipped.
4. Write:

```
## Week of <Mon m/d>, Jonathan

**Done**
- <outcome in plain language, by project; lead with impact, not ticket names> (max ~6)

**On deck next week**
- <top P0/P1 + due soon> (max ~5)

**Risks / need from leadership**   ← omit if nothing
- <blocked P0, waiting item gone cold with who, a decision needed>
```

Style: plain words for non-engineers, no ticket speak, no internal IDs unless asked, one line per bullet, and every sentence readable aloud.

5. Show the draft. After the user approves or edits it, save it to `reports/<YYYY-Www>.md` (ISO week, `date +%G-W%V`) and run `desk commit "desk: report <week>"`. NOW.md stops showing the Friday nudge once the file exists.
