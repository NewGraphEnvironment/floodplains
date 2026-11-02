## Checklist read

Read `index_code-check.md`, `index_code-check-r.md`, `-shell`, `-spatial`, `-python` indexes, and the
`## Mechanisms` H3 prose of `code-check.md` (tables skipped). Cited below: code-check.md "A fixture that
cannot reach the failure mode" (a text scan used to enumerate under-counts a continuation line),
"Verification that reads its own output" (name what reads each field you write) and "Documentation
Staleness".

**Mechanism behind rounds 3 and 4.** The figure and its label words are read by consumers outside this
repo, and those consumers had expectations the issue body did not state. Round 3 found a byte copy on the
company site. Round 4 found that site's copy rules (no "not yet" wording). This is code-check.md
"Verification that reads its own output": for every field you write that your own code never reads back,
name what does read it. So the label string has a reader set wider than `readme_functions.R`, and this
round enumerates that set.

## Findings

- **[severity: fragile]** CLAUDE.md:115-116 — The text is "fire **4.2%** / harvest **30.3%** / not yet⏎
  attributed **65.5%** by area. … It is now computed at figure-build time into `fig/attribution.png`".
  This names the figure's grey category by the old label. Since 81e3174 the figure, its legend and its
  bar all say "no mapped cause", so a reader of this sentence looks for a label that no longer exists.
  The phrase is wrapped across two lines, which is why the Phase 4 sweep missed it: a single-line
  `grep "not yet attributed"` does not match it. (`grep -n "not yet *$" CLAUDE.md` finds it.) The fix is
  to say "no mapped cause" here, or "the residual". The numbers themselves still match the bar (4 / 30 / 66).
  - **Rule:** code-check.md "Documentation Staleness"; code-check.md "A fixture that cannot reach the failure mode" (a text scan used to enumerate misses a continuation line, so the "two comment mentions" count was a sample)
- **[severity: fragile]** scripts/floodplain_lcc/disturbance-check.R:6 and scripts/floodplain_lcc/fp_disturbance.R:30 — Both comments tie themselves to "the README attribution figure" in the lines around them. Both name its share in quotes as the old label: `would shrink "not yet attributed"`. These are two more readers of the label string, beyond the "two comment mentions" in `readme_functions.R` that Phase 4 updated. They now quote a category the figure does not have. The same one-word change fixes both: "no mapped cause".
  - **Rule:** code-check.md "Documentation Staleness"

## Checked, no finding

The relabel itself:
- `CAUSE_STYLE$source` is built from `UNATTRIBUTED`, so `fp_cause_style()` matches it and returns grey `#6f757d`. It does not fall back to "other" (green).
- The rebuilt PNG shows grey dots, a grey legend key and a grey bar segment.
- `cause == UNATTRIBUTED` at readme_functions.R:344 still orders the grey dots underneath.
- No code compares against the old literal. `git grep` finds the string only in the comments above, in CLAUDE.md, and in planning.
- The bar text "no mapped cause / 1025 ha  66%" is shorter than the old label and fits clearly inside its 66% segment span.

Readers in this repo:
- README.Rmd:166 builds the alt text from `fp_cause_colour(UNATTRIBUTED)`.
- README.md:49 and the index.html alt text both read "grey where there is no mapped cause".
- index.html's embedded base64 decodes byte-identical to `fig/attribution.png` (sha 0abb1869…, 339,590 bytes).
- `scripts/floodplain_lcc/README.md:94` names the figure but not the label.
- `readme_content-check.py` and `readme_determinism-check.sh` do not reference the figure's text.
- README prose "the unattributed share" (README.Rmd:183) describes the report's residual, not the legend, and still reads correctly.

Readers on the site (newgraphenvironment.github.io, fetched; checkout on `how-it-works-pills-2026-11` = PR #68):
- The caption at `content/project/open_source_software/index.md:109` is "Floodplain tree loss 2017–2023 in the Bulkley watershed group, by attributed cause." It matches the new figure's title and its bar title.
- Site #66 asks for two things: the subtitle (dropped) and "not yet attributed" (relabelled). It has no comments. The new PNG contains no "not yet" or "yet" text.
- The site's image limits are 1400–1600 px and under about 750 KB, PNG allowed for maps with text. The new PNG is 1500 x 1500 px and 339,590 bytes.
- PR #68 leaves the swap as an open test-plan box. That is the owed item already in task_plan.md.

Readers elsewhere in the org (`gh search code` plus a grep of local checkouts):
- `logic/talks/2026-terrace-cop/fig/README.md:10` references `floodplains/fig/attribution.png` "at source" for slide 5. `deck_assets.json` has no attribution entry, and no deck text quotes the label or the subtitle. `ledger.md:75` cites "about a third", which is still true (4 + 30 = 34%). Not affected.
- `stac_floodplains_bc/README.{Rmd,md}` use "unattributed" and the dead 5 / 36 / 62 split. That is pre-existing and is #77's open item. It does not reference the figure or the label, so it is out of scope here.
