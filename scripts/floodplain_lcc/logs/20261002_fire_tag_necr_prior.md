# Re-tag NECR with the fire_prior lookback (#103, phase 3)

**Run:** 2026-10-02 · `Rscript scripts/floodplain_lcc/fire_tag.R necr`, then `disturbance-check.R necr <snapshot taken before the prior-fire load>` · no FORCE

The cause columns, the core columns and the geometry (WKB, unpromoted) are unchanged against the snapshot. The re-tag added only `in_fire_prior`, `fire_prior_year` and `fire_prior_number`.

```

area=necr  layer=transition_ch_ff04_2017_2023  window=2017-2023  sources=fire,harvest  context=wetland  lookback=fire_prior
  wrote layer: transition_ch_ff04_2017_2023 (5692 patches)

=== NECR Trees->non-Trees LOSS vs disturbance ===
 total loss      : 1943.2 ha
 in_fire        : 565.6 ha (29%)
 in_harvest     : 588.9 ha (30%)
 residual (noise): 886.3 ha (46%)
   of which in_fire_prior: 242.8 ha (27% of residual; prior, not counted)
 context in_wetland   : 1820 patches, 2482.8 ha

live: area=necr  gpkg=/Users/airvine/Projects/repo/floodplains/data/necr/floodplain_landcover.gpkg  layers=transition_ch_ff04_2017_2023
  PASS  at least one transition layer
  PASS  no legacy `_disturbance` / `_fire` sibling (#55)
  -- transition_ch_ff04_2017_2023
  PASS  every context and lookback column is present
  PASS  in_wetland tagged something (an empty fetch would leave it all FALSE)  (1820 patches)
  PASS  `waterbody_poly_id` is set exactly where in_wetland is TRUE
  PASS  `waterbody_poly_id` is typed, not Boolean  (integer)
  INFO  in_fire_prior: 314 patches (zero is legitimate for a lookback)
  PASS  `fire_prior_year` is set exactly where in_fire_prior is TRUE
  PASS  `fire_prior_year` is typed, not Boolean  (numeric)
  PASS  `fire_prior_number` is set exactly where in_fire_prior is TRUE
  PASS  `fire_prior_number` is typed, not Boolean  (character)
  PASS  the protected core columns are exactly the layer's non-tag columns  (area_ha,from_class,name_basin,patch_id,scenario,species,to_class,transition,wsg)
  PASS  item keys stay the last columns, as step 3 writes them
  PASS  patch set identical to the snapshot, by (name_basin, patch_id)  (5692 vs 5692 patches)
  PASS  no snapshot column was dropped by the re-tag
  PASS  every cause, carried and core column holds the same values as the snapshot
  PASS  declared geometry type and srs_id unchanged  (GEOMETRY/32610 vs GEOMETRY/32610)
  PASS  declared field types unchanged (BOOLEAN -> typed allowed for carries)
  PASS  geometry is byte-identical to the snapshot (WKB, unpromoted)  (0 rows differ)

ALL PASS
```
