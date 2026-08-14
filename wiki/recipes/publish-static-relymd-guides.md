# Publish HTML guides to static.relymd.app

Publish self-contained HTML files (e.g. release user guides from
`docs/operations/release/notes/guides/`) to RelyMD's public static host.
No pipeline writes this bucket; publishing is manual.

- Host: `https://static.relymd.app` → GCS bucket `gs://bison-public-static2`
  (backend bucket `static-content-backend-bucket`, project `bison-233014`).
- Content is public internet. Only publish content safe for that
  (test-env screenshots, no PHI).

## Procedure

1. `gcloud auth login` as jonathan.sells@relymd.com (project `bison-233014`).
2. Upload with explicit content type and a short cache TTL:

   ```sh
   gsutil -h "Content-Type:text/html; charset=utf-8" \
          -h "Cache-Control:public, max-age=300" \
          cp <file>.html gs://bison-public-static2/guides/<file>.html
   ```

3. Verify: `curl -sI https://static.relymd.app/guides/<file>.html` → 200 with
   `content-type: text/html`.

Re-running the same `cp` republishes; the 300s cache TTL keeps updates fast.

Published 2026-08-13: `guides/patient-guide.html`, `guides/insight-admin-guide.html`
(sources on `develop` at `docs/operations/release/notes/guides/bison/`).
Retire this manual step when the Insight in-app Guides tab ships.
