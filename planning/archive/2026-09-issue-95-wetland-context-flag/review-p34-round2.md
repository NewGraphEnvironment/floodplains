# Code-check P3-4, round 2: fire_tag.R round trip and disturbance-check.R comparison

## Mechanism

A reader or writer **default** transforms data on its way through, and the check reads both sides
through the **same default**, so the transform is applied to the reference as well and cancels out.
In round 1 the default was `st_read(promote_to_multi = TRUE)`. The comparator is exposed the same
way. `fp_same_values()` compares through `as.character()`, which has two defaults: it keeps only 15
significant digits, and it ignores storage type. The snapshot also records only what `sf` returns,
so anything `sf` drops on read (fid, declared field types, CRS, column order) cannot be compared by
the check at all.

To break that symmetry, this review compared the layers with a **different reader**. It attached
SQLite directly, read-only, and compared scratch copies of the live NECR and BULK gpkgs against the
pre-re-tag `backup_*` copies, joined on `fid`. The result is below.

## Enumeration

fire_tag.R round trip (read, tag, re-attach geometry, write):

- **`st_read` promote_to_multi.** Handled (round 1). The `gpkg_geometry_columns.geometry_type_name`
  is `GEOMETRY` in both backup and live, on both areas.
- **`st_read` check_ring_dir.** Handled. The default is FALSE, so rings are not reoriented. The GPKG
  geometry blobs, header and envelope included, are byte-identical by fid: 0 of 5,692 NECR and
  0 of 7,161 BULK differ.
- **`st_make_valid` in the tagger.** Handled. The published geometry is put back by position
  (`stopifnot(nrow)`), and the blob comparison above covers it.
- **fid.** Handled on the data, not compared by the check. `st_read` drops fid and `st_write`
  renumbers from 1. Joined on fid, the backup and live layers agree on key, geometry, core and cause
  columns: 0 differences, fid 1..5692 and 1..7161.
- **Declared field types.** Handled on the data, not compared by the check. The DDL of the existing
  columns is identical: `patch_id MEDIUMINT`, `fire_year REAL`, `fire_number TEXT`, `in_* BOOLEAN`
  and so on. The only change is the two appended context columns, `in_wetland BOOLEAN` and
  `waterbody_poly_id MEDIUMINT`.
- **SQLite storage class per cell** (`typeof`). Handled: 0 rows differ on any existing column.
- **Integer64 read as double** (`int64_as_string = FALSE`). Cannot arise today. No transition layer
  in any of the 21 areas has an Integer64 field; I scanned every `data/*/floodplain_landcover.gpkg`.
  Carried columns are re-fetched rather than passed through, so only core columns take the read
  path, and those are MEDIUMINT, REAL or TEXT.
- **Datetime and timezone.** None. No date or datetime field exists in any transition layer.
- **String encoding.** Handled. The TEXT columns compare equal with `IS NOT` at the SQLite level.
- **Column order.** Handled. The DDL order is identical apart from the appended context columns, and
  the item keys come last, as step 3 writes them. The check asserts only the last 3 names.
- **CRS and srs_id.** Handled on the data, not compared by the check. WKB carries no CRS. `srs_id` is
  32610 or 32609 in both files, `gpkg_spatial_ref_sys` holds 4 rows in both, and neither file has a
  row the other lacks.
- **Geometry column name, FID name, spatial index.** Handled. The column is `geom` and the FID is
  `fid` in both. The rtree has 5,692 rows in both and 0 bounds differ. The feature-count triggers
  are present in both.
- **`gpkg_contents`.** Handled. `last_change` is pinned (#45), extents are identical, and
  `description` and `identifier` are unchanged.
- **Layer order in `gpkg_contents`.** Can differ, and does. `delete_layer = TRUE` re-creates the
  table at the end, so the transition layer now sorts after `patch_watercourse_*` on both areas. I
  found no positional layer reads in `floodplains/scripts` or `stac_floodplains_bc/scripts`, so this
  is harmless.
- **File bytes.** Can differ. A re-tag that changes nothing still rewrites the layer, and #45 already
  bounds in-place rewrites as not byte-identical. This is a known limitation, not introduced here.
- **`layer_styles` and `gpkg_metadata`.** Neither table exists in data/, so there is nothing to
  orphan.

disturbance-check.R comparison (snapshot vs after):

- **Geometry.** Handled: WKB unpromoted plus the declared type (round 1 fix).
- **Row key.** Handled: ordered by (name_basin, patch_id).
- **Attribute values.** Can hide a change (Finding 1). The values go through `as.character()`, which
  keeps 15 significant digits.
- **Attribute types.** Not compared (Finding 2). `fp_same_values(2021, 2021L)` is TRUE.
- **Column set.** Not compared for cause columns (Finding 3). `keep <- intersect(...)` drops any
  snapshot column that is absent after the re-tag.
- **fid, CRS, layer order.** Not compared. All of them are clean on the live data by the SQLite
  comparison above.

## Findings

- **[low]** fp_disturbance.R:197-200, `fp_same_values`, as used by disturbance-check.R. It compares
  numbers through `as.character()`, which rounds to 15 significant digits. So
  `fp_same_values(0.1 + 0.2, 0.3)` is TRUE. As a probe on the NECR backup, I recomputed `area_ha`
  from `st_make_valid()` geometry: 1,601 rows changed, and the helper hid 2 of them (max relative
  difference 8.4e-12). A real regression would still be flagged by its other rows, so the practical
  risk is small. It is the same mechanism as round 1, though: the comparator's default loses exactly
  what it is meant to detect. The helper exists to tolerate storage-type differences. A tighter form
  keeps that and loses nothing:
  `if (is.numeric(x) && is.numeric(y)) identical(as.double(x[!is.na(x)]), as.double(y[!is.na(y)]))`.
  (Inside a previous fix? Yes: `fp_same_values` was added in this phase to replace `identical()`.)

- **[low]** disturbance-check.R, live section. Declared field types are compared neither against the
  snapshot nor against a canonical type. `fp_same_values` is type-blind by design, so these pass both
  fire_tag's refuse-guard and the check:
  - a cause carry that flips from REAL to MEDIUMINT on re-tag, for example because a bc2pg reload
    changed the Postgres column type. That is the "one column, two types across areas" class that
    #95 fixed for Boolean.
  - a Boolean carry that is not repaired.

  The "typed, not Boolean" assertion covers context carries only. `tabr`, `ufra`, `unth` and `will`
  (`fire_year` and `fire_number`) and `thom` (`harvest_start_year_calendar`) are published BOOLEAN
  today. After a re-tag of those areas the check would not show whether the repair happened. A
  reader-independent fix is cheap: add the layer's DDL (`sqlite_master.sql`) and `srs_id` to the
  snapshot, then assert that every pre-existing column keeps its declared type, except
  BOOLEAN→typed on an all-NA column. That one field also covers column order, CRS and the
  geometry declaration without going through `sf`. (Inside a previous fix? No. The gap is in the
  new snapshot format.)

- **[low]** disturbance-check.R, `keep <- setdiff(intersect(names(s0$attrs), names(tr)), ctx_cols)`.
  A column present in the snapshot and missing after the re-tag leaves `keep` without complaint.
  Probe: snapshot columns `{patch_id, fire_number}` and after-column `{patch_id}` give
  `keep = patch_id`, and the check passes. Core and context columns are covered by other assertions.
  Cause columns (`in_fire`, `fire_year`, `fire_number`, `in_harvest`, `harvest_*`) are not. fire_tag
  has no current path that drops one, so this is a guard gap rather than a live defect. The fix is
  `ok("no snapshot column is missing", !length(setdiff(names(s0$attrs), names(tr))))`.
  (Inside a previous fix? Partly. The `intersect` was carried over from the pre-#95 check into the
  rewritten live section.)

No finding on fire_tag.R itself. At the SQLite level, every column that existed before the re-tag is
unchanged in value and storage class, and every geometry blob is unchanged by fid, on both re-tagged
areas. The only differences are the two appended context columns and the layer's position in
`gpkg_contents`.
