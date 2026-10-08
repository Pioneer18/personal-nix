# Meeting flow

Inputs: pasted text, a file path (.docx, .vtt, .pdf, .txt, .md, .csv), or an image (whiteboard / notebook photo). Sources: Teams transcripts (usually .docx, sometimes .vtt), Zoom transcripts, Copilot summaries, typed notes, photos.

## 1. Extract text

| Input | How |
|---|---|
| .docx | `textutil -convert txt -stdout <file>` |
| .vtt | Read it, drop cue numbers/timestamps, merge consecutive lines from the same speaker (`<v Name>` tags or `Name:` prefixes) |
| .pdf / .txt / .md / .csv | Read tool |
| image | Read tool (vision), then transcribe. Mark illegible parts `[illegible]`. Describe diagrams in text as well |
| Copilot summary | Treat as notes. It is already a summary, so extract, do not re-summarize its wording away |

## 2. Redact (hard rule)

Replace patient identifiers with `[redacted]`: names, DOB, MRN, SSN, addresses, phones, emails, and any detail that identifies a specific patient. Colleagues, vendors, and clients (companies) are fine. Then pipe the text through `desk phi-scan -`. On exit 5, check each hit, redact true positives, and continue if the rest are false positives (for example "DOB field validation bug").

## 3. Resolve people and projects

Map speakers/attendees with `desk match "<name>"`. For unknowns, ask one batched question: "New people: 'Mike R' (new?), 'Sam' (= Samantha X?)". Only create entities after a yes.

## 4. Draft (always shown before writing)

```
M 2026-09-29 "Payroll sync w/ Finance" · Sarah, Tom · pace · teams-transcript
Summary: <≤5 lines>
Decisions:
  1. …
Tasks:
  1. [mine]     Send revised export spec · due Fri · suggests P1 (exec ask)
  2. [waiting]  Tom: confirm GL codes · nudge +3bd
  3. [delegate] Ticket for rounding bug · suggests P2
  4. [ask]      Star: budget for contractor
Key info: …
Open questions: …
→ enter = write all · x 2,4 = strike · edit 3 "<change>" · cancel
```

Rules for extraction:
- A task needs an owner and a concrete action. "Someone should look at that" is not a task. List it under Open questions.
- Owner is Jonathan → `mine`. Jonathan must hand it to someone → `delegate`. Someone else committed to deliver to Jonathan → `waiting`. Jonathan wants to raise it with someone later → `ask`. Work between other people that Jonathan does not track → leave it out (mention it in Summary if it matters).
- Apply the same P0 suggestion rules as capture.

## 5. Write

```
desk new-meeting "<title>" --date YYYY-MM-DD --people a,b --projects x --source teams-transcript --no-commit
desk add "<task>" --kind … --source M-<id> --no-commit      # per accepted task
```
Then edit the meeting file: fill Summary, Decisions, Tasks (`- T-0144 [mine] …` per created task), Key info, Open questions, and the redacted transcript inside the `<details>` block under Raw.

- Append each decision to `projects/<x>.md` under `## Decisions` as `- YYYY-MM-DD <decision> ([M-…](../meetings/…))`.
- Copy durable Key info into the project/person/ref file it belongs to.
- For a 1:1, append a dated 2-3 line entry under the person's `## 1:1 log`.
- Photos: save to `meetings/YYYY/MM/attachments/<meeting-slug>-N.<ext>` only if the photo shows no patient data, and link it from the meeting file.
- Finish with `desk commit "desk: meeting M-…"` and print the receipts.
