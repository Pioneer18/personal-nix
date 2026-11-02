---
title: Group Portal login crashes (SIGSEGV 503) for a user without MFA
tags: [relymd, group-portal, identity, mfa, runbook]
link: https://github.com/relymd/platform/pull/3454
---

# Non-MFA login crash

**Symptom.** `POST /login` with a correct password returns 503. The Cloud Run log shows `Uncaught signal: 11` / `Container terminated on signal 11` (on rev 00015 it was a handled `NullReferenceException` at `SessionController.Login` line 126). Only users with `AspNetUsers.TwoFactorEnabled = 0` (2,282 of 2,798 active on 10-27). Each crash also drops other in-flight requests on that instance.

**Cause.** `SessionController.Login` normalized the SMS number (`phoneNumber.StartsWith("+1")`) before the `RequiresTwoFactorRegistration` branch. The first submit of a non-MFA user posts no number, so the value was null. Legacy MVC5 had the same code. Why a null reference ends the process with SIGSEGV on the `aspnet:8.0` image is not proven.

**Not every SIGSEGV is this bug.** After #3454 shipped (rev 00024), the process still dies with signal 11 about once a day while idle: no request in flight, no exception logged, ~10 s after a normal `GET /login`. Seen on 00018, 00023, 00024. If the 10 s before `Uncaught signal: 11` hold no `POST /login`, it is that separate crash (P9 in `bug-scan-2026-10-27.md`), cause unknown; next step is a crash dump (`DOTNET_DbgEnableMiniDump=1`).

**Fix (#3454, merged 2026-10-27).** Registration check first, then `MfaPhoneNumber.Resolve` (Domain), which returns null for an empty number and shows "Please enter a valid mobile phone number.".

**Related.** #3437 (`PasswordSignInAsync` returns `RequiresTwoFactor` after the Twilio code). Workbench: `docs/workbench/ftp-group-portal/bug-scan-2026-10-27.md`.
