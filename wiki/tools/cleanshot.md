---
title: "CleanShot X"
tags: [tool, screenshot, mac, proxy-workflow]
last_updated: "2026-05-12"
summary: "Screenshot + annotation tool. Replaces system Shift+Cmd+4 with save-as dialog, scrolling capture, GIF record, pin-to-desktop, OCR."
category: "mac"
link: "https://cleanshot.com"
---

What: macOS screenshot + screen-record tool. Installed via nix cask `cleanshot` in `dev-environment/hosts/jonathan-sells-darwin.nix`.

When to use in PROXY workflow:
- Annotated screenshots -> `wiki/notes/` entries (e.g. milestone captures like [[first-sleep-agent-grind]])
- Scrolling capture -> Tachikoma terminal log dumps in one image
- GIF screen-record -> demo voice modes / loops for ADRs without committing video
- Cloud Pro tier -> shareable URLs instead of committing pngs to public personal-nix

License key -> Keychain item `cleanshot_license` (not a plaintext file).

Save location should be `~/Pictures/Screenshots/` to match system `com.apple.screencapture location` default (Settings -> Saving).
