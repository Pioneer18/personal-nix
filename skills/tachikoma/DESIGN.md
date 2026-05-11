# Tachikoma Art — Design Document

Companion to [ART-SPEC.md](ART-SPEC.md). That file defines the slot assignments and constraints. This file captures the rationale, the lore copy system, the technical decisions, and the implementation checklist.

---

## What we're building

Terminal art and lore-consistent copy across the tachikoma skill — startup screen, exit states, and key interactive phases. Modeled after Claude Code's welcome screen aesthetic but themed around the Ghost in the Shell Tachikoma characters, rendered as BMO faces.

---

## Where art appears

| Location | Slot name | Rendered by | Face |
|---|---|---|---|
| Phase 1 grill opening | PHASE 1 GRILL | Claude text output | big-bmo (fixed) |
| Phase 5 shell launch | STARTUP | `tachikoma.sh` bash | random — all 7 |
| Loop complete | COMPLETE | `tachikoma.sh` bash | smile (fixed) |
| Loop error | ERROR | `tachikoma.sh` bash | random — angry / disbelief / frustrated |
| Cap hit | CAP HIT | `tachikoma.sh` bash | random — angry / disbelief / frustrated |
| Loop stopped | STOPPED | `tachikoma.sh` bash | neutral (fixed) |
| Phase 6 review | PHASE 6 REVIEW | Claude text output | content (fixed) |
| Phase R recovery | PHASE R RECOVERY | Claude text output | out-of-wack (fixed) |

---

## Art technique

**Pre-made Unicode shade-block art** (`▒▓░`) delivered as `.txt` files. No conversion step — embed directly via `cat` (bash-ansi slots) or paste into code blocks (claude-text slots).

**Why shade-block over half-block (`▀▄█`):** the BMO faces were drawn in this style; it's the asset we have. Shade-block gives a softer, more painterly look vs the sharper pixel-art of half-block.

**No ANSI color:** the files are monochrome. This means dark/light terminal compatibility is trivially satisfied — no fg/bg pairing needed.

**Startup:** single static frame, face selected randomly at runtime via `$(( RANDOM % 7 ))`. No frame animation — the boot copy carries the emotional arc.

**Phase 1, 6, R art** uses the same Unicode block chars — rendered in Claude's conversation output as a fenced code block.

**Art suppression** (bash slots):
```bash
[ -t 1 ] || SKIP_ART=1               # not a TTY — pipe, nohup, log redirect
[ -z "$NO_COLOR" ] || SKIP_ART=1     # $NO_COLOR convention
[ "$(tput cols 2>/dev/null || echo 80)" -ge 120 ] || SKIP_ART=1  # art is 120 cols wide
```
Do not crop or truncate art. Users on narrow terminals get the plain-text banner.

---

## Rotation design

Three slots pick a face randomly on each run:

| Slot | Pool | Rationale |
|---|---|---|
| STARTUP | all 7 | Personality — any face on boot is valid, surprise is the point |
| ERROR | angry, disbelief, frustrated | All three fit "something went wrong" |
| CAP HIT | angry, disbelief, frustrated | Same — running out of runway is also a frustrating outcome |

Implementation: bash `case $(( RANDOM % N ))` switch, one branch per face. No state persisted between runs.

---

## Lore copy system

Three layers, each doing distinct work:

| Layer | Role | Examples |
|---|---|---|
| **Tachikoma** | The subject — the tool itself | `Tachikoma online.`, `error at iter N` |
| **Ghost / Shell** | Internal state — consciousness and body | `Ghost: active`, `Ghost lost`, `Ghost preserved` |
| **Work request title** | Real-world grounding — what the run is actually doing | `<title> — N iterations authorized` |

### Agreed copy per state

**Startup:**
```
Initializing shell...
Mounting systems...
Tachikoma online. Ghost: active.
<title> — N iterations authorized.
```

**Complete:**
```
<title> — stand-alone complete. Ghost at rest.
Run /tachikoma done to review and merge.
```

**Error:**
```
<title> — error at iter N. Ghost lost.
Manual recovery required. Check .tachikoma/run.log for details.
```

**Cap hit:**
```
<title> — N of N iterations logged. Ghost preserved.
Run /tachikoma resume to continue, or /tachikoma done to review.
```

**Stopped:**
```
<title> — halted at iter N. Ghost preserved.
Run /tachikoma resume to continue, or /tachikoma done to review.
```

**Phase 1 grill:**
```
I'll ask ~7 questions to scope this run. Takes ~2 minutes.
Type 'cancel' at any point to abort — nothing is created until you approve.
```

**Phase 6 review:**
```
Loop complete. Here's what changed:
[diff stat follows]
```

**Phase R recovery:**
```
Loop interrupted. Here's what happened:
[last progress note + log tail follows]
Resume / Review / Restart?
```

---

## Art assets

Art is provided as pre-made `.txt` files. All 8 files are in hand. No conversion needed.

Current status: **all assets in hand — implementation unblocked.**

---

## Implementation checklist

### States
- [ ] **[blocking]** STARTUP art in `tachikoma.sh.tmpl` — random face from all 7, static
- [ ] **[blocking]** COMPLETE art in `tachikoma.sh.tmpl` — smile, static
- [ ] **[blocking]** ERROR art in `tachikoma.sh.tmpl` — random from angry/disbelief/frustrated
- [ ] **[blocking]** CAP HIT art in `tachikoma.sh.tmpl` — random from angry/disbelief/frustrated
- [ ] **[blocking]** STOPPED art in `tachikoma.sh.tmpl` — neutral, static
- [ ] **[blocking]** PHASE 1 GRILL art in `SKILL.md` — big-bmo in fenced code block
- [ ] **[blocking]** PHASE 6 REVIEW art in `SKILL.md` — content in fenced code block
- [ ] **[blocking]** PHASE R RECOVERY art in `SKILL.md` — out-of-wack in fenced code block
- [ ] **[should-fix]** Update all exit-state copy to agreed lore pattern

### Rotation
- [ ] **[blocking]** STARTUP rotation — `case $(( RANDOM % 7 ))` selecting from all 7 face files
- [ ] **[blocking]** ERROR rotation — `case $(( RANDOM % 3 ))` selecting from angry/disbelief/frustrated
- [ ] **[blocking]** CAP HIT rotation — same as ERROR

### Edge cases
- [ ] **[blocking]** Guard all bash art behind TTY + `$NO_COLOR` + width checks (threshold: 200 cols)
- [ ] **[should-fix]** Check `$TERM` / `$COLORTERM` — fall back to plain text if no Unicode support

### Interaction feedback
- [ ] **[should-fix]** Include work request title in startup and all exit banners

### Visual consistency
- [ ] **[blocking]** Phase 1/6/R art: embed in fenced code blocks in `SKILL.md`
- [ ] **[should-fix]** Verify all `.txt` files render correctly in target monospace fonts
