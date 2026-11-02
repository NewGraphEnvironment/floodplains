# Code check, round 4 (#136)

## Checklist read

- index_code-check.md (the scratchpad index), headings and first lines in full. No full section of
  code-check.md was cited, so none was opened beyond the index.
- `git show c8a0c94`; `git diff 766d015...HEAD` (excluding index.html and the PNG); every file in
  planning/active/; floodplains#136 body; site issues newgraphenvironment.github.io#66 and #65
  (bodies and comments); the site's `content/project/open_source_software/index.md` and the blob
  of `floodplains_attribution.png` there.

## Verified

- The site's `floodplains_attribution.png` has git blob sha `2999188c…` (348,072 bytes), equal to
  `git hash-object` of `766d015:fig/attribution.png`. It is embedded at `index.md:109`. The owed
  item's path, its "byte-identical to main's old figure" and its pointer to #66 (open, titled
  "Swap the Open Source page's attribution figure once floodplains#136 ships") are all accurate.
- The new PNG is 339,169 bytes, 1500 px, within #65's stated site limits (≤ 1600 px, < 750 KB).
- The progress.md and task_plan.md claims match the branch.

## Findings

- **[severity: fragile]** planning/active/task_plan.md:48-53 — The owed item says the site swap
  "waits on this merge", which presents #136 as everything #66 is waiting for. It is not. #66's
  body names two defects in the figure: "whose subtitle names a config file **and whose legend says
  'not yet attributed'**". Its parent, site #65 (closed), lists both as the problem ("Subtitle names
  a config file; 'not yet attributed' breaks the copy rules") and gives the remedy as "Re-export,
  after floodplains#136". So the site expects #136's re-export to fix both. This branch fixes only
  the subtitle. `UNATTRIBUTED <- "not yet attributed"` (`scripts/readme_functions.R:60`) is
  unchanged, and the new PNG still carries it in the legend and the bar. #136's own body never
  mentions the legend, so nothing in floodplains owns the second half. When #66 is worked after
  merge, the copied figure will still break the site's copy rules, and #66 will either be closed
  with its stated problem half-fixed or stall with no issue to wait on. Either widen #136's scope
  (a label change also touches the README alt text and prose that quote "not yet attributed"), or
  file a floodplains issue for the legend wording. Then make the owed item and a comment on #66 say
  which half this merge delivers.
  - **Rule:** none
