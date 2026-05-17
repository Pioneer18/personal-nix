---
status: grabbed
target_repo: ~/Projects/tachikoma-starter
github_issue: ""
failure_count: 0
last_updated: 2026-05-12
tachikoma_branch: tachikoma/proxy-bundled-signed-notification-app-sl
tachikoma_worktree: /Users/pioneer/Projects/tachikoma-starter-tachikoma-proxy-bundled-signed-notification-app-sl
---

# PROXY bundled signed notification app (slice proxy-15-extended, M5)

Build the `notify-app/` Swift project — a minimal signed macOS app required for action-button notifications in modern macOS. The daemon invokes it to post notifications with Approve/Dismiss callbacks; without a signed bundle, macOS silently drops action buttons.

## Apple Developer account

Account: mindful.developer.js@icloud.com
Team ID: look up via `xcrun altool --list-providers -u mindful.developer.js@icloud.com` or Xcode → Preferences → Accounts.

## Goal

`proxy-daemon` can post macOS notifications with action buttons (Approve / Dismiss / Snooze) that call back into the daemon API when tapped. The notification app is a signed, minimal Swift CLI that posts one notification per invocation and exits.

## Architecture

Per ARCHITECTURE.md § 18 + Appendix B decision: separate Swift project at `notify-app/` with its own bundle ID and `.entitlements`. The daemon invokes it via `Command::new("notify-app")` (on PATH after install) or absolute path from `proxy.toml`.

## Files in scope

- `notify-app/` — new Swift package (NOT part of Cargo workspace)
  - `Sources/NotifyApp/main.swift` — parse argv: `--title`, `--body`, `--action-url` (deep-link back to daemon), `--identifier`
  - `notify-app/Package.swift`
  - `notify-app/NotifyApp.entitlements` — `com.apple.security.app-sandbox` false (CLI tool)
  - `notify-app/Info.plist` — bundle ID `com.proxy.notify`, version 1.0
- `notify-app/build.sh` — `swift build -c release`, codesign with Developer ID
- `daemon/src/manager/actions.rs` — add `NotifyAction` variant that shells out to notify-app binary
- `proxy.toml.example` — add `[notify] app_path = "/usr/local/bin/proxy-notify"` field

## Files out of scope

- UNUserNotificationCenter delegate (CLI tool posts + exits; callbacks are URL scheme deep-links)
- Notarization (local dev signing sufficient for v1.0)
- Web push (already shipped in proxy-15-web-push-salvage)

## Stop condition

- [ ] `swift build -c release` in `notify-app/` succeeds
- [ ] `codesign --verify --verbose notify-app/.build/release/proxy-notify` passes
- [ ] Running `proxy-notify --title "Test" --body "Hello" --action-url "proxy://approve/123"` posts a macOS notification visible in Notification Center
- [ ] Notification has an action button; tapping it opens the action URL
- [ ] `daemon/src/manager/actions.rs` has `NotifyAction` variant invoking the binary
- [ ] `cargo build --release` still clean after daemon changes

## Feedback loops

- `swift build -c release`
- `codesign --verify`
- Manual: run binary directly, observe notification in macOS

## Quality bar

production

## Context refs

- `docs/ARCHITECTURE.md` § 15 (notify-app component) + Appendix B (signing decision)
- `daemon/src/manager/actions.rs` — existing action dispatch pattern
- Apple Developer account: mindful.developer.js@icloud.com
