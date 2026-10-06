# Code-check round 1 — #111 (blind review), 2026-10-06

Reviewer: subagent, read-only. `accuracy-check.R` run in a temp copy: ALL PASS. Live projects were
inspected: A and B carry no `point_id` in the .qgs, labels.gpkg holds only the blind schema, all
480 cell squares contain their point, feature order = review_id order, and Change patches and
Wetland are unchecked and appear in no theme but "9 After labelling". The chip VRT sources are
hash-named.

## Findings

- **[leak] fp_accuracy.R `fp_acc_review_key` (append path, `new$review_id <- n0 + perm`) + research/landcover_accuracy.md:211-213.**
  Points added when the sample grows always take ids `n0+1..n`. The research file says the full
  sample "should raise the stable strata first", so the new batch is mostly or entirely stable
  strata. Every id above 480 then tells the labeller that the map's answer is "no change". If only
  `stable Trees` grows, it says Trees -> Trees, which is exactly the anchoring #111 exists to
  remove. Shuffling inside the batch does not help, because the batch's stratum mix comes from the
  allocation, which is public. Changing the ids does not help either: the appended rows are also
  the only unlabelled ones once labelling has started. There is no fix inside the key. Two options:
  (a) draw the full sample before labelling starts, or (b) record in the research file that labels
  in a growth batch were made knowing the batch's stratum mix, and treat them that way.
  `accuracy-check.R` "new points take the next ids" pins the current behaviour.

- **[fragile] research/landcover_accuracy.md: the agreement rules that review-111.md G7 calls "pre-registered in research" are not in the file.**
  `grep -i 'agreement|kappa|second labeller|both labelled|reported apart' research/` finds nothing
  (line 66 is unrelated). The `## Labelling key` section is the pre-registered text, and it says
  nothing about how agreement is scored. The code also differs from G7: `fp_acc_agreement` drops
  every point that either labeller marked `cannot_label` and does not report that count at all, so
  "cannot_label reported apart" is not implemented. If the rules are written after B labels exist,
  they are no longer pre-registered, and that is the discipline #93 rests on.

- **[fragile] accuracy_estimate.R:80-84 / fp_accuracy.R `fp_acc_agreement` / sample_draw-pilot.R:112-120: labels_b.csv is never checked against the design.**
  The agreement step merges A and B by `point_id` alone. `labels_b.csv` carries stratum, cell and
  map_class, but nothing compares them with sample.gpkg. The redraw guard in `sample_draw-pilot.R`
  looks only at `labels.csv`, so it allows a redraw over B's labels. After such a redraw,
  `labels_b.csv` describes other cells under the same ids, and the agreement table is computed from
  the wrong cells with no error. This is the "a point_id is not an identity" rule that every other
  stage enforces. Fix: run `fp_acc_design_check(b, smp, "labels_b.csv")` before the merge, and add
  `labels_b.csv` (and `review_key.csv`) to the redraw guard.

- **[fragile] labels_export.R:43 `fp_acc_working_copy_role`: a working copy that predates a sample growth can no longer be exported.**
  The role is "a" only when the copy holds every point in the current key. Once
  `review_build-qgis.R` has grown `review_key.csv`, a pilot-era copy of 480 points is refused as
  "neither", even though its labels are valid. The Mergin copy is that case: per G9, floodplains'
  gpkg is never copied over it, so it does not gain the new points at build time. The fix is to
  accept a copy whose ids are exactly `1..n0` of the key, i.e. a prefix of it, as A's. Fail-safe,
  but it blocks the planned pilot -> full workflow.
