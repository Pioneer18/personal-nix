---
name: grill-me
description: Interview the user relentlessly about a plan or design until reaching shared understanding, resolving each branch of the decision tree. Use when user wants to stress-test a plan, get grilled on their design, or mentions "grill me".
---

Interview me relentlessly about every aspect of this plan until we reach a shared understanding. Walk down each branch of the design tree, resolving dependencies between decisions one-by-one. For each question, provide your recommended answer.

Ask the questions one at a time.

If a question can be answered by exploring the codebase, explore the codebase instead.

If the grilling target is a wiki seed (path matches `~/projects/personal-nix/wiki/seeds/<slug>.md`), the goal is to sharpen it into a PROXY v2 dossier-brief — surface the fields `/brief` will ask for: `target_repo`, `files_in_scope`, `files_out_of_scope`, `acceptance_criteria` (testable predicates, not "works"), `feedback_loops` (typecheck/test/lint commands), `linked_issues`, and the advisory `recommended_callsign` / `recommended_clearance` / `recommended_comms`. The downstream skill `/brief <slug>` will write the dossier file, invoke `proxy brief` to import it, and delete the source seed; you don't need to do that yourself, just produce a clear spec that skill can consume.
