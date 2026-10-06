# Code-check round 2 — #111 (blind review), 2026-10-06

Reviewer: subagent, read-only. Reviewed the round-1 fixes (commit 675c8e3) against the full files.
`accuracy-check.R` run in a temp copy: ALL PASS. Probed in the temp copy (`probe.R`, not committed):

- The redraw guard loop (`sample_draw-pilot.R`), run verbatim against the committed key and sample:
  it passes on the unchanged draw. It refuses a moved cell under a `labels_b.csv` point, and it
  refuses a moved cell under a keyed point that is not in B's subset once `labels_b.csv` is absent,
  which is the `review_key.csv` arm. Fix 2 works as intended.
- `fp_acc_agreement` on a hand-built A/B pair: the counts `both_cannot` / `a_only_cannot` /
  `b_only_cannot` are correct, and `n` counts only the points both labelled. Fix 1 works as intended.
- B's live project (`necr_lulc_review_b`) holds 48 rows, ids 21..470, and the blind schema only. Its
  dated VRT sources are named by air-photo frame. No csv, json, md or qgs file in it names
  `point_id` or `stratum`, apart from an rfp template csv. B's 3-per-stratum subset has the same
  stratum mix as A's 30-per-stratum pilot, so B's prior is not shifted relative to A's.

## Findings

- **[fragile] scripts/landcover_accuracy/fp_accuracy.R `fp_acc_working_copy_role` (the new prefix rule) + accuracy-check.R:258.**
  Fix 3 is meant to accept "a copy made before the sample grew". What it actually accepts is any
  copy whose ids are `1..n` with `n < nrow(key)`, and that test cannot tell a pre-growth copy from
  a **truncated** one. Probed on the committed, ungrown key (480 rows):
  `fp_acc_working_copy_role(1:470, key)` returns `"a"`. Before the fix, that call was refused.
  - **How it happens.** Feature order is review_id order (by design). So losing the tail of the
    table loses the highest ids, which is exactly a prefix. A QGIS delete over the last rows does
    that, and so does a Mergin sync conflict that drops trailing features.
  - **What it costs.** The export now goes ahead. Any labels in the lost rows that were never
    exported are gone without a trace. The closing message ("N labelled ... of 480 sample points")
    makes the shortfall look like "not labelled yet" rather than "lost". `labels_export.R`'s
    refuse-to-drop check only protects labels that were already exported. Before the fix, the
    refusal itself was the signal that the copy was damaged.
  - **The test was moved, not kept.** The original must-fail arm was
    `fp_acc_working_copy_role(ks0$review_id[1:10], ks0)`, and ids 1..10 are a prefix. The fix
    rewrote that arm to use scattered even ids, so it no longer exercises the case it used to.
  - **A stale comment.** The `labels_export.R` header still says "anything else is refused".
  - **Possible fix.** Bound the rule to sizes the key has actually had. Recording a `batch` (or
    `n_at_append`) column at append time works, because the key is append-only and the value then
    never changes. Accept a copy only if its ids are exactly batches 1..j. Then restore the `1:10`
    arm as a must-fail, next to the new "1..n0 of a grown key" pass arm.

No other defect found in the fixes. Item 4 (the growth-batch hint) is documented as a known limit,
as accepted, and its text in `research/landcover_accuracy.md` and `CLAUDE.md` matches the code. The
agreement rules sit under `## Review setup`, outside `## Labelling key`, so they are not copied into
the labeller's `labelling_key.md`, which is correct.
