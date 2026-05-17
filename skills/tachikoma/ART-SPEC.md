# Tachikoma Art Spec

Defines the art slots used throughout the tachikoma skill. Each slot has a fixed emotional register, size envelope, rendering context, and face assignment. Art is delivered as pre-made `.txt` files using Unicode shade-block characters (`▒▓░`) — no conversion needed, embed directly.

## Art files

Located at `~/projects/personal-nix/assets/bmo-faces/set/` during development; copied into the skill at implementation time.

| File | Dimensions | Used in |
|---|---|---|
| `big-bmo.txt` | 67L × 120W | PHASE 1 GRILL (fixed) |
| `smile-small.txt` | 52L × 120W | STARTUP pool, COMPLETE (fixed) |
| `content-small.txt` | 48L × 120W | PHASE 6 REVIEW (fixed) |
| `neutral-small.txt` | 48L × 120W | STOPPED (fixed) |
| `out-of-wack-small.txt` | 48L × 120W | PHASE R RECOVERY (fixed) |
| `angry-small.txt` | 48L × 120W | STARTUP pool, ERROR pool, CAP HIT pool |
| `disbelief-small.txt` | 48L × 120W | STARTUP pool, ERROR pool, CAP HIT pool |
| `frustrated-small.txt` | 48L × 120W | STARTUP pool, ERROR pool, CAP HIT pool |

`angry-ascii.txt`, `angry.txt`, and all original large `.txt` files are retired in favour of the `-small` variants and `big-bmo.txt`.

## Rendering contexts

| Context | Where | Technique | Color |
|---|---|---|---|
| **bash-ansi** | `tachikoma.sh` | `printf` / `cat` | Monochrome — files use `▒▓░`, no ANSI color codes needed |
| **claude-text** | `SKILL.md` outputs | Unicode block chars in a code block | No ANSI — Claude's conversation output; monospace font renders correctly |

All bash-ansi art is gated behind:
```bash
[ -t 1 ] || SKIP_ART=1
[ -z "$NO_COLOR" ] || SKIP_ART=1
[ "$(tput cols 2>/dev/null || echo 80)" -ge 120 ] || SKIP_ART=1
```

The 120-col threshold matches the actual art width. Users on narrower terminals get the plain-text banner fallback — do not crop or truncate the art.

## Rotation

Three slots randomize their face on each run using `$RANDOM`:

- **STARTUP pool:** all 7 faces (angry, content, disbelief, frustrated, neutral, out-of-wack, smile)
- **ERROR pool:** angry, disbelief, frustrated
- **CAP HIT pool:** angry, disbelief, frustrated

Implementation: assign each pool member an index, select via `$(( RANDOM % N ))`.

---

## Art slots

### STARTUP — static (bash-ansi)

**Face:** random from all 7 faces, selected fresh each run.

**Emotional register:** Any — the randomness is the personality. A Tachikoma booting up with an angry face is funny. The boot copy carries the emotional arc.

**Size envelope:** 48–52L × 120W (varies slightly by face).

**Surrounding copy (printed after art):**
```
Initializing shell...
Mounting systems...
Tachikoma online. Ghost: active.
<work-request-title> — N iterations authorized.
```

---

### COMPLETE — static (bash-ansi)

**Face:** smile (fixed).

**Emotional register:** Satisfied, mission accomplished. Quiet confidence.

**Surrounding copy:**
```
<work-request-title> — stand-alone complete. Ghost at rest.
Run /tachikoma done to review and merge.
```

---

### ERROR — static (bash-ansi)

**Face:** random from angry, disbelief, frustrated.

**Emotional register:** Something went wrong. The specific face varies — angry, disbelieving, or frustrated — all are appropriate for a failed run.

**Surrounding copy:**
```
<work-request-title> — error at iter N. Ghost lost.
Manual recovery required. Check .tachikoma/run.log for details.
```

---

### CAP HIT — static (bash-ansi)

**Face:** random from angry, disbelief, frustrated.

**Emotional register:** Hit the iteration limit. Spent but not broken — the ghost is preserved. Same face pool as ERROR since running out of runway is also a frustrating outcome.

**Surrounding copy:**
```
<work-request-title> — N of N iterations logged. Ghost preserved.
Run /tachikoma resume to continue, or /tachikoma done to review.
```

---

### STOPPED — static (bash-ansi)

**Face:** neutral (fixed).

**Emotional register:** Standby. Deliberately paused — alert but still, ready to resume.

**Surrounding copy:**
```
<work-request-title> — halted at iter N. Ghost preserved.
Run /tachikoma resume to continue, or /tachikoma done to review.
```

---

### PHASE 1 GRILL — static (claude-text)

**Face:** big-bmo (fixed). Full-body character — this is the landing page of the skill.

**Rendering context:** claude-text (Unicode block chars, no ANSI color).

**Size envelope:** 106L × 180W.

**Surrounding copy (printed after art):**
```
I'll ask ~7 questions to scope this run. Takes ~2 minutes.
Type 'cancel' at any point to abort — nothing is created until you approve.
```

---

### PHASE 6 REVIEW — static (claude-text)

**Face:** content (fixed).

**Emotional register:** Measured pride. Presenting finished work before the user has approved — not celebrating yet.

**Rendering context:** claude-text (Unicode block chars, no ANSI color).

**Surrounding copy (printed after art):**
```
Loop complete. Here's what changed:
[diff stat follows]
```

---

### PHASE R RECOVERY — static (claude-text)

**Face:** out-of-wack (fixed).

**Emotional register:** Something interrupted it and it's waiting for direction. Not failed — just needs to be told what to do.

**Rendering context:** claude-text (Unicode block chars, no ANSI color).

**Surrounding copy (printed after art):**
```
Loop interrupted. Here's what happened:
[last progress note + log tail follows]
Resume / Review / Restart?
```

---

## Fallback behavior

When `SKIP_ART=1` (not a TTY, `$NO_COLOR` set, or terminal < 200 cols), the bash script prints the plain-text banner only:

```
═══════════════════════════════════════════════════════════════
  🚀 starting — repo: <name> · branch: <branch>
  cap: N iter(s) · pid: <pid>
═══════════════════════════════════════════════════════════════
```

claude-text slots (Phase 1, 6, R) have no fallback — they always print the Unicode art as a code block.

---

## Plugging in new art

To add or replace a face:

1. Place the `.txt` file alongside the others (Unicode `▒▓░` style, no ANSI codes).
2. Note its dimensions.
3. Add it to the file table above and assign it to a slot or rotation pool.
4. Update the rotation arrays in `tachikoma.sh.tmpl` if it joins a pool.
5. Update the relevant code block in `SKILL.md` if it's a claude-text slot.

The copy, fallback logic, and gating checks do not change.
