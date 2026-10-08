---
title: OCR a tall screenshot (Teams transcript scroll capture)
link: assets/ocr-tall-screenshot.swift
---

A tall CleanShot scroll capture (e.g. 2570×25000 px) is shrunk until it can't be read when Claude views it. OCR it in slices with macOS Vision instead (no install needed):

```sh
swift ~/projects/personal-nix/wiki/recipes/assets/ocr-tall-screenshot.swift "<image.png>" > out.txt
```

The script crops 2000 px slices (100 px overlap) and prints the text top to bottom. Slices repeat a few lines at the seams; remove the duplicates when you read it. First used 2026-10-07 for a 1h20 Teams transcript.
