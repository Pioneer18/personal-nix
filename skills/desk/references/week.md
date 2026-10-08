# Weekly review (`/desk week`)

Goal: 10 minutes that leave the board true. Run the steps in order. Batch the questions and accept terse answers.

1. **Recap:** `desk digest`. Show counts: done, dropped, captured this week (`desk list --status all --since <Mon>`).
2. **Untriaged to zero:** run the `/desk triage` walk.
3. **Stale:** `desk stale`. For each item, ask the question it prints (still P1? / demote to P3? / drop?).
4. **Waiting gone cold:** waiting items past their nudge. For each: chase (`desk chased`), close, or re-date.
5. **External links:** for open tasks with `jira`/`pr`, check live status. Offer to close tasks whose ticket is Done or PR merged.
6. **P3 sweep:** `desk list --priority P3`. Ask whether anything should come back to P2 or be dropped.
7. **Delegates not handed off** for more than 5 days: ask whether to hand off now or reconsider.
8. **Hygiene:** `desk lint`. Fix problems.
9. **Report:** if it is Friday and `reports/<week>.md` is missing, offer `/desk report`.
10. `desk push`.
