# Plan review for #103 (Plan agent, 2026-10-02): findings and disposition

The `Plan` agent is read-only, so it returned this review as a reply; it is saved here verbatim in
substance. Disposition: **done** means already handled, **folded** means taken into the plan,
**declined** means not taken, with the reason.

## Blockers
1. **Stratum 19's source contradicts its guard.** The prior-fire polygons are cell-level and cover
   stable and sieved cells, so a cause-style stray guard would refuse every real draw.
   - **folded**: cell-level, like wetland. Stratum 19 = `chg & !is.na(prior)`, with no stray guard.
   - The accuracy-check arm instead asserts that a prior cell that is stable or sieved never lands
     in 19.
2. **The report would count a lookback passed as a source.** **done**: `fp_disturbance_report()`
   refuses any entry carrying `lookback`. The arm is in Phase 2.
3. **A source could carry `lookback:`.** **done**: the validator refuses it. The arm is in Phase 2.
4. **The live check's `tag_cols` excludes lookback columns, so the core-column check fails after
   the re-tag.** **folded**: the live section includes `lookback:` and gains mirrored arms (typed,
   and set exactly where `in_fire_prior` is TRUE).
5. **`run_area.R` was missing from the plumbing.** **done** (`cfg$lookback_overlays`).

## Gaps
- **Carry-as-map.** Only `.dst_query` needs the source names. **done**: there is a
  `.dst_carry_shape` validator. **folded**: arms for a malformed map, and for a plain list emitting
  no `AS`.
- **Window double-shift.** **folded**: callers pass `cfg$change_interval` and `.dst_window` derives
  the lookback window. An arm checks that `.dst_query` gives 2002–2016 from 2017–2023, and the
  Phase 4 caller passes the change interval.
- **`design.json` lookback has no reader.** **folded**: `accuracy_estimate.R` refuses when the
  design's lookback differs from the config's.
- **`prior = NULL` goes last, and 19 appears only when it is given.** **folded**.
- **Missing arms.** **folded**:
  - prior beats wetland change;
  - stratum 19's label must not start with `"change: "`.
- **`FP_ACC_IMAGERY` and the qml have no consistency check.** **folded**: a new parse-and-setequal
  arm, with a must-fail.
- **No base theme exists.** **folded**: write "Review" with `rfp_qgs_theme_set` first. Theme
  creation is idempotent through `rfp_qgs_theme_names()`.
- **Private endpoint leak into committed logs.** **folded**:
  - a tracked-files grep for the host in validation;
  - the imagery scripts never print hrefs.
- **Load recovery after a partial append.** **folded**: the script header documents the `DELETE`
  recovery.

## Ordering
- **Moving the project aside loses the chip cache.** **folded**: move `chips/cache` into the new
  project before re-chipping.
- **Phase 6 needs a final `review_build-qgis.R` run.** **folded**. The order is: rebuild, then
  chips, then dated imagery, then rebuild again with themes.
- **Edit the qml before the first rebuild.** **folded**.
- **`FP_ORTHO_STAC`.** **declined as stated**: the variable is NOT set yet; the findings only name
  it. It moves to the start of Phase 5.
- **Phase 5 after the Phase 4 redraw.** Kept.

## Assumptions
- **drift drops a 0-cell stratum.** **folded**: `sample_draw` reports when 19 is configured but
  empty.
- **Unaffected strata keep their points.** **folded**: after the redraw, assert that strata 1, 2,
  20, 30, 31 and 32 are unchanged. drift is 0.20.0 now, where the design was drawn under 0.19.0.
- **Thumbnail resolution vs 10 m S2.** **folded**: measure it in Phase 6, and accept "no air-photo
  theme" as an outcome.
- **QGIS reaching the COGs.** **folded**: verify by opening a VRT through GDAL, the same library
  QGIS uses.
- **`in_fire` is a strict prefix of `in_fire_prior`** (`$` on a data.frame partial-matches where
  `in_fire` is absent, as in mcgr and pine). **declined**:
  - `in_fire_prior` was the name in the approved plan and the issue;
  - grep finds no `$in_fire` reader, and the code reads tag columns with `[[`;
  - noted in the PR as a known hazard.

## Scope
- **Stratum 19 is fire-specific while the lookback list is generic.** **folded**: the strata use
  only the lookback entry named `fire_prior`. The script refuses any other lookback entry rather
  than silently ignoring it, until a mapping exists.
- **One `imagery` value cannot name an epoch.** Accepted. `imagery.csv` gives the epoch per point,
  and `note` carries it if needed.

## Acceptance
- **Strata identity and ha moved.** **folded**.
- **The NECR pilot table in `research/landcover_accuracy.md` goes stale.** **folded**: Phase 7
  updates it.
- **Phase 3 live-check result, and no refusal on necr.** **folded**.
- **Validation additions.** **folded**:
  - the host grep;
  - `accuracy_estimate.R SYNTHETIC=1` on the redrawn design.
