# Code-check round 3 — branch 136-fig-attribution-png-the-subtitle-is-writ vs main

## Checklist read

- code-check-python.md: in full (7,237 bytes).
- code-check.md: every index line, and the prose of all 14 H3s under `## Mechanisms`
  (table rows and evidence blocks skipped); also the full section "A link to a repo-hosted
  artifact must be *tracked*, not merely present". Not read in full: the other 28 headings under
  "Rules that stand alone", "Security" and "Spreadsheets and PDFs" (index lines only; none names a
  tool or shape this diff uses).
- code-check-r.md, code-check-shell.md, code-check-spatial.md: index read in full. No full
  section read: the diff's R change only deletes two `labs(subtitle =)` arguments and comments, and
  the artefacts are a PNG and a self-contained HTML; no indexed tool or shape in these files
  applies (all headings unread beyond the index).

## What was checked (read-only)

- `index.html`'s embedded PNGs decoded: the second one is byte-identical to `fig/attribution.png`
  at HEAD (sha256 `039c6674…`, 339,169 bytes); the first is byte-identical to `fig/floodplain.png`
  (unchanged, `730068c1…`). On main the same holds for the old PNG (`9602df4c…`). With the base64
  payloads masked, HEAD's and main's `index.html` are equal, so the HTML differs only in the image.
- `README.md` is unchanged on the branch; it references `fig/attribution.png` by path, so GitHub
  and Pages serve the new file.
- New PNG read back: no subtitles, both titles present, legend and bar labels intact; the bar reads
  fire 66 ha 4% / harvest 474 ha 30% / not yet attributed 1025 ha 66% (sum 1,565 ha, matching
  BULK's recorded 1,565.1 ha), identical to main's PNG. The bar panel lays out cleanly with the
  subtitle row gone. 1500x1500 RGBA, same as before.
- Nothing in the repo depends on the removed text: no check, script or doc greps "subtitle",
  "attributed to today", "takes any layer" or "lists today" for this figure;
  `disturbance-check.R`'s use of `fp_readme_sources()` is about the cause list, not the subtitle;
  `fp_fig_theme()`'s `plot.subtitle` is still used by `fp_fig_floodplain()`; `src` is still used
  for `lv` and the missing-column stop.
- PWF claims checked against the tree: 7023066 (#95, 2026-09-28) is the last commit before this
  branch to touch the PNG and 17df5e0 did not; README.md unchanged; `data/bulk/` is empty (gpkgs
  removed); no render byproducts on disk; the `/code-check` box is correctly still unticked.
  `origin/main` (ls-remote) is still 766d015, the merge base.

## Findings

- **[severity: fragile]** planning/active/task_plan.md:60-61 — The plan records the company site as
  a conditional ("If the company site holds its own copy of the PNG rather than linking Pages, it
  needs a refresh there after merge"). It does: `newgraphenvironment.github.io/content/project/
  open_source_software/floodplains_attribution.png` is a committed byte copy of main's old figure
  (sha256 `9602df4c…`, 348,072 bytes, from b1e4860, 2026-10-14), embedded at `index.md:109`. #136's
  stated symptom is that figure on the site's Open Source page, so merging this branch (and closing
  #136 on it) leaves the subtitled image live on the site, with a closed issue reading as fixed.
  The code is right; the follow-up needs to be a stated, owned step (a site issue or a task in
  #136's close-out), not a hypothetical.
  - **Rule:** code-check.md "Written data outlives the fix"

No other issues found.
