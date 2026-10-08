# Code-check round 2 (#115): review of the diff and the round-1 fixes

Read in full: the checklist (code-check R / shell / spatial / conventions), the diff, and every
changed file. `accuracy-check.R` was run in a copy of the repo with `data/` excluded, and every arm
passed, the new #115 arms included.

## Round-1 fixes, checked

All six round-1 fixes hold. The probes behind that:

1. **Cache name carries the bbox.** OK. The key is the md5 of the 5-decimal bbox strings. A digest
   change after a version bump would only cost a refetch.
2. **`grep` on the relative path.** OK. It catches `wayback_<yr>/*.tif` and any `.aux.xml`
   sidecar beside a VRT. A probe confirmed that `GDAL_PAM_ENABLED=NO` set after `library(terra)`
   still suppresses sidecars from writeRaster, extract and buildvrt.
3. **`own_key` from the clip's coordinates.** OK. The named vector loses its names through the
   `w[i, ]` row subset and the write.csv/read.csv round trip, so `identical(prev$own_key,
   r$own_key)` is TRUE on a kept chip (probed). An old manifest with no `own_key` column gives NULL,
   which forces a rebuild. That is the intended outcome.
4. **`stop` on a NULL `built`.** OK. When it fires, the old manifest survives but both VRTs are
   already unlinked, so `wb_ok()` returns NULL.
5. **Placement 8.** OK. Applied with `rfp_qgs_style_set` to a copy of the NECR `.qgs`, the result
   was `labelsEnabled="1"`, `<labeling type="simple">` and placement 8.
6. **"Esri <year>:" prefix.** OK. Evaluated in the QGIS 4.2.1 python:
   - With both capture columns it returns `'Esri 2017: 2017-06-11, 0.31 m\nEsri 2023: 2021-06-22,
     0.5 m'`. Map keys come back sorted, so 2017 comes first.
   - With no capture columns it returns `None`, so no label is drawn.

## Findings

- **[fragile]** `scripts/landcover_accuracy/wayback_build-chips.R:184` vs `:195-220`. The
  manifest is written before the build's own guards run.
  - `built.csv` is written at line 184, and the VRTs already exist by then. The guards come after
    it: non-image files (195), a point_id in a file name (198), and the per-point mosaic pixel
    check (220).
  - So when the pixel check refuses ("N point(s) do not read their own chip from the mosaic"),
    everything it refused stays in place as current. `built.csv` matches `wayback.csv`, and the
    VRTs are present.
  - The next `review_build-qgis.R` run therefore passes `wb_ok()`. It adds the "<year> Esri capture"
    layers and themes and writes the capture labels into `cells.gpkg`. The reviewer is served the
    mosaic the build refused, where a point shows a neighbour's capture under a label naming its
    own.
  - The refusal is therefore only a non-zero exit, and nothing downstream sees it. The research
    file says the opposite: "refuses unless it is that point's own chip".
  - Fix: run the guards before `write.csv(built, man_csv)`. Alternatively, on any guard failure,
    unlink `built.csv` (or the VRTs) so that `wb_ok()` returns NULL.

- **[fragile]** `scripts/landcover_accuracy/review_build-qgis.R:243-262` (`wb_ok()`). It never
  checks that the built chips were cut for the current sample.
  - What it does check: `built.csv` against the review key (point_id per review_id), and its
    `release_id` against `wayback.csv`.
  - What it does not check: whether the chips were clipped to the current Voronoi cells. That is a
    function of the whole point set (`own_key`).
  - The scenario is a sample that grows (pilot to full, ids kept), followed by a re-run of
    `wayback_index-capture.R`. The re-run is required, because otherwise `fp_acc_wayback_read`
    refuses. If `review_build-qgis.R` then runs before `wayback_build-chips.R` has finished (or
    after it was killed or failed before line 184), `wb_ok()` passes. The new points have no
    `built.csv` row, and the old points' releases still match.
  - Result: the old chips are clipped to the old, larger Voronoi cells, and those cells cover the
    new points' locations. A new point then draws a neighbour's capture under it while its cell
    label reads "Esri 2017: none". That is the cross-chip read the Voronoi clip and the pixel check
    exist to prevent, and nothing in the review build catches it.
  - The dated orthophoto path has the equivalent guard (line 359: `imagery.csv`'s point set must
    equal the sample's). The wayback path has none, and because `built.csv` does not record failed
    chips, `wb_ok()` cannot tell "failed" from "not built for this sample".
  - Fix: record the build's sample (the point set, or a digest of `own_key`) and its failures in the
    manifest. Then refuse in `wb_ok()` unless the point set equals `smp_design$point_id`. Recomputing
    the Voronoi `own_key` in `wb_ok()` and comparing it would also work.

Nothing else found against the checklist. The items checked:
- `$` partial matching on JSON/data frames;
- `match()` NA;
- `paste` zero-length;
- `nzchar(NA)`;
- `tryCatch(warning=)`;
- `gdal_utils` raising: warp and buildvrt raise on failure;
- `mask()` touches, consistent `touches = FALSE`;
- bbox reprojection: the polygon is transformed before the bbox is taken;
- `make_valid` on multi-ring polygons: 0 of 319 multi-ring polygons in NECR's 21,422 cached
  features have an outer ring past the shell, and a probe showed a disjoint ring survives as a part;
- pagination: the metadata layers support it, and the largest cached query is 311 features against
  a `maxRecordCount` of 1000;
- blindness: no point_id or design column in chip names, VRT sources, `cells.gpkg` or labels;
- `labels_form` / `FP_ACC_IMAGERY` agreement.
