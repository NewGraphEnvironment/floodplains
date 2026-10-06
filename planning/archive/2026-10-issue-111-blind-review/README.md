## Outcome

The #93 NECR accuracy review is now built to be blind, randomised and cell-level, ready for rtj#367 to
put on Mergin.

- **Blind by construction.** The labels working copy carries an opaque, shuffled `review_id` and no
  design column. `point_id` encodes the stratum, so hiding fields could never have done this.
  `reference/<area>/review_key.csv` maps the id back, records each point's `batch` and the
  second-labeller subset, and is checked against the design at every step.
- **Pre-registered labelling key.** It is in `research/landcover_accuracy.md`, quotes IO's own class
  definitions from Esri's Living Atlas, and is copied into the project.
- **Each point's 10 m cell is drawn.**
- **IO's change patches and the FWA wetlands** are hidden in the tree and appear only in the
  `9 After labelling` theme.
- **Themes are named for the work,** in drop-down order.
- **A second labeller** works in a separate 48-point project, blind to the map and to labeller A, and
  agreement is pre-registered as information only.
- **The export decides A or B from what a working copy holds.**

**What was learned:**

1. **My recommendation on hay and pasture was wrong.** It claimed IO's legend; fetched, the legend
   names pastures under Rangeland. The user re-decided: follow IO exactly.
2. **rfp's template themes silently showed IO's answer.** A guard over the themes the build sets
   missed them; only reading back the written `.qgs` caught them.
3. **Review fixes reproduced their own defects twice:**
   - agreement rules recorded as pre-registered but never written;
   - a pre-growth export rule that also accepted a truncated copy.

   An enumeration of working-copy states ended the review loop.

## Measurement

| what | result |
|---|---|
| NECR key | 480 points; Spearman(review_id, stratum) = -0.013 |
| second-labeller subset | 48 points, 3 per stratum |
| key stability | reproducible from `design.json`; golden ids pinned |
| sample cells | 480 squares, each containing its point (`cell` is terra's number on the design grid, 5 of 5 by `cellFromXY`) |
| pre-fix project | the patch-visibility guard fires on 12 themes |
| synthetic export, A | 6 rows to `labels.csv`, point ids and design correct |
| synthetic export, B | 3 rows to `labels_b.csv` |
| synthetic export, partial copy | refused |
| `dated_imagery` | trimmed from every epoch since 1971 to the 2 with themes (airphoto 2012, orthophoto 2021) |

## Evidence

The plan review and the code-check rounds are `review-*.md` in this directory. There are no run logs:
the build and the export were verified live, and the verification is recorded in `progress.md`.

Open for the user before labelling:
- the visual check of the hand-written form styling in QGIS on m4;
- the +/-1-year confidence ceiling (review A2);
- whether to accept the growth-batch limit or label the full sample in one blind pass.

Closed by: PR for branch `111-necr-accuracy-review-blind-randomised-ce`
