# Review round 2 — staged diff for #106 (channel-migration probe)

Scope: the three round-1 fixes, reviewed against `research/channel_migration.md` rule v2 and its
new "Applying the rule" notes, plus a second pass over the parts of the three scripts that the
fixes touch.

## Fix 1: `fp_ch_sustained()` first-year Snow/Ice/Clouds (fp_channel.R:189-192)

- `f <- terra::classify(stack[[1]], rcl)` now sends a first-year 9 or 10 to NA, so
  `away_ever`/`returned`/`onset_ok` (all `f * 0`) are NA there and the cell's result is NA. It is
  excluded from the patch mean (`na.rm`) and from `aw()` (which tests `!is.na`, and NaN is NA). This
  matches the rule ("Snow/Ice (9), Clouds (10) and NA years count as missing").
- Inside the footprint with a valid first year, `away` and `back` are always 0 or 1 (an NA later
  year goes through `ifel(is.na(c_k), 0, ...)`), so `|` and `&` never meet an NA.
- `fp_acc_grid()` orders `cls` by `seq(change_interval)`, so the stack is ascending and the
  `years[k] <= onset_max` snapshot of `away_ever` is the right onset test.
- **Must-fail arm checked.** On a copy (`$TMPDIR/r2copy`), the check runs green. Reverting line 190
  to `f <- stack[[1]]` turns exactly one assertion red: "a Snow/Ice or Clouds 2017 class is missing
  too".

## Fix 2: lakes by grid footprint (channel_probe-migration.R:110-117)

Probed on the real NECR (EPSG:32610) and BULK (EPSG:32609) `classified_2017.tif`:

- `sf::st_bbox(<SpatRaster>)` carries the raster's CRS, so `st_transform(..., 3005)` has a source
  CRS. The direction (grid CRS to 3005, the table's CRS) is correct.
- `Find_SRID` confirms fwa_lakes_poly and fwa_rivers_poly are 3005.
- I compared the bbox of the transformed 5-vertex rectangle with a bbox taken after densifying the
  rectangle to 50 m before the transform. The difference is 0.000 m on every edge in both areas,
  because the UTM-to-Albers rotation puts the extremes at the corners. The envelope covers the
  whole buffered grid, so it covers every patch plus 50 m.
- `sqlInterpolate()` writes the coordinates as full-precision `::float8` literals, e.g.
  `ST_MakeEnvelope(1234567.891234::float8, ...)`. No rounding, no injection surface.
- `geom && envelope` returns every lake whose bbox overlaps, whole, so `near_dist()` sees each
  candidate lake's full geometry. It returns a superset, which is correct for a distance test.
- Rivers still go through `q_wsg()` (WSG-limited), as the rule says.

## Fix 3: BULK D minimum (fp_channel.R:278,289; research note)

`D_dir = d_ok` applies `n_opp >= 10` together with `R < 0.5`. The "Applying the rule" note states
this reading and the code matches it. The note is in Results, not in the v2 text, and no threshold
moved.

## In-flight run

The `probe_frozen.R` run in the scratchpad matches the staged script except for its `source()` of
`fp_channel_frozen.R`, and that copy is byte-identical to the staged `fp_channel.R`. So the NECR/BULK
run now going is running the fixed code. The untracked
`logs/20261002_channel-migration_necr.{csv,md}` (08:39) predates both fixes. The run will overwrite
them under the same date stem.

## Findings

Clean.
