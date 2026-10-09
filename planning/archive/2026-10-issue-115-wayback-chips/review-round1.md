# Code-check round 1: #115 Wayback chips

Reviewed: the staged diff (cc_diff.patch), with every changed file read in full. Probes ran in the
scratchpad only, and no repo file was edited.

## Findings

- **[severity: bug]** scripts/landcover_accuracy/wayback_index-capture.R:105-106 (cache) and :44 (`bb`).
  The metadata cache is keyed by release and layer only (`<release_id>_L<L>.rds`). The query it
  caches is clipped to the sample's bbox (`geometry=<bb>`, :74). When the sample grows (pilot to
  full, which is documented) or is redrawn, the header says to re-run this script, and
  that re-run reuses every cached response. Any point outside the old bbox then gets no hits from
  any release. It is written to `wayback.csv` as "no capture" (empty release), and
  `fp_acc_wayback_read` accepts it, because the row exists. A cached `NULL` (no features in the old
  bbox) is just as stale. This is the drift#25 class: a cache key without the AOI. Only `FORCE=1`
  escapes it, and nothing tells you that you need it. `data/necr/accuracy/wayback/meta/` is already
  populated. Fix: put the bbox (or a hash of it) in the cache file name, or store `bb` with the
  response and refetch on mismatch.

- **[severity: fragile]** scripts/landcover_accuracy/wayback_build-chips.R:188-193 and :216. Line 188
  is `list.files(dir_dated, pattern = "^wayback", recursive = TRUE)`. `pattern` matches the BASENAME
  even with `recursive = TRUE`. Measured: given `wayback_2017/0001.tif`,
  `wayback_2017/0001.tif.aux.xml` and `wayback_2017.vrt`, it returns only `wayback_2017.vrt`. So
  `wb_files` never contains a chip. Three things follow:
  - The non-image guard ("rtj's compose refuses them") never inspects the chip directories, which is
    exactly where a `.aux.xml` would appear: QGIS opening a single chip with PAM enabled, or any
    run without `GDAL_PAM_ENABLED=NO`.
  - The point_id-in-filename guard sees only the two VRT names.
  - The final "%d files, %.0f MB" line reports the VRTs only.

  Fix: list without a pattern and filter the relative path with `grepl("^wayback_", ...)`.

- **[severity: fragile]** scripts/landcover_accuracy/wayback_build-chips.R:80 (`own_key`) and :132
  (`same`). Whether a kept chip still has the right clip is decided by the BBOX of its clipped
  polygon, rounded to 0.1 m. A Voronoi edge that cuts only a corner of the ±150 m square leaves
  the bbox unchanged. Worked example: old point at (0,0), new point at (100,140). The bisector
  enters the top edge at x=-62 and the right edge at y=-1.4, so the remaining polygon still touches
  all four bbox edges. When the sample grows, the old chip is kept with its stale, larger clip and
  overlaps the new neighbour's chip, which breaks the "each pixel belongs to its nearest point"
  rule.
  - If the new point lies inside the old square and the old chip is listed later in the VRT, the
    read-back check catches it and stops. That is safe, but only `FORCE=1` recovers.
  - If the new point lies outside the old square, nothing catches it. The overlap shows the old
    point's capture inside the new point's cell.

  This is a proxy standing in for the property. Fix: key on the clip geometry itself (a digest of
  `st_as_binary(own[i])`, or of the sorted neighbour set), not its bbox.

- **[severity: fragile]** scripts/landcover_accuracy/wayback_build-chips.R:177 and :198-212. If no
  chip is built at either endpoint, `do.call(rbind, list())` is `NULL`:
  - `write.csv(NULL, ...)` writes a manifest with no rows.
  - In the read-back loop, `b <- built[built$endpoint == e, ]` is `NULL`, and `if (!nrow(b))` aborts
    with "invalid argument type" (measured).

  This happens when every point has no capture or every fetch fails, for example when the network
  is down with `FORCE=1`. The script then dies with an unrelated error rather than reporting
  "no chips". Guard with `if (is.null(built))`.

- **[severity: fragile]** scripts/landcover_accuracy/cells_outline.qml:24 (`placement="6"`). In
  `Qgis::LabelPlacement` order (verified against QGIS 4.2's `_core.pyi`), 6 is
  `OrderedPositionsAroundPoint` (cartographic, for point layers) and 8 is `OutsidePolygons`.
  - On this polygon layer, labels land outside the cell only because the default
    `polygonPlacementFlags` allow outside placement when the cell is smaller on screen than the
    label.
  - Once the reviewer zooms in so that the 10 m cell is larger than the label, the placement
    switch receives 6. As far as I can tell, pal does not handle 6 for polygons. The label then
    either disappears or falls back to an inside placement over the very square being judged,
    depending on the QGIS version. I am not certain which.

  The comment promises "Labelled OUTSIDE the cell". Fix: use `placement="8"`.

- **[severity: fragile, low]** scripts/landcover_accuracy/cells_outline.qml header and
  review_build-qgis.R:396 (`base` includes `LYR_CELLS`). The capture label is a property of the
  cells layer, and that layer is in every theme. So "2017: 2017-06-11, 0.31 m / 2023: …" also
  draws beside the cell in the Sentinel-2, orthophoto and air photo themes and in "0 Start". The
  qml comment says this happens only "in each '<year> Esri capture' theme". Under labelling-key
  rule 5 (confidence ceiling set by imagery date), a capture date printed beside a 2021
  orthophoto can be read as describing that orthophoto. Making it theme-specific would need a
  separate labelled layer that only the Esri capture themes include.

## Checked and fine

These were reviewed or probed and are not issues:

- **Blind review:** chip and VRT names use review_id only; the manifest, WMS XML and tiles are
  outside the project; cells.gpkg is leak-checked on read-back.
- **review_build-qgis.R:** `cbind.sf` keeps the CRS and the geometry. `wb_ok` cross-checks against
  both the review key and `wayback.csv`.
- **Prune:** affects only `^wayback_` paths, and B's own files survive.
- **wayback_build-chips.R:**
  - `own_key` names are dropped on assignment to a data.frame column, so `identical()` with the
    manifest holds (probed).
  - `gdal_utils` raises on a GDAL error.
  - `-tap` keeps NECR's single-zoom chips on one grid.
  - `touches = FALSE` is used in both `rasterize` and `mask`.
- **wayback_index-capture.R:**
  - The multi-outer-ring Esri polygon read as one polygon with "holes" is repaired correctly by
    `st_make_valid` (even-odd; probed).
  - `%||%` is defined in fp_accuracy.R.
- **rfp:** `rfp_qgs_style_set`'s field check finds no column reference in the label expression
  (probed with `.qgs_expr_fields`).
- **Form and imagery list:** `esri_dated` in the form equals `FP_ACC_IMAGERY` (set check), and is
  consistent with labelling-key rule 5.

/Users/airvine/Projects/repo/floodplains/planning/active/review-round1.md
