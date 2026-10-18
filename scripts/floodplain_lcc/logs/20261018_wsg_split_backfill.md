# The group-line split backfill: `in_wsg` + `in_open_water` on every published area (#53, #138)

**Date:** 2026-10-18 (UTC) · **Issues:** #53, #138, #60 · **Produced by:** `scripts/floodplain_lcc/gpkg_backfill-split.R`
(per-area logs in `20261018_wsg_split_backfill/`), tables re-derived from `data/<area>/` and the
pre-split byte backups in `data/backup/20261018_wsg_split/<area>/` (gitignored).

## What ran

- **Dry sweep** (`DRY=1`), all 24 areas, 20:24–20:47 UTC: every area rc=0, so every check passed
  before any area was written. Logs: `*_dry.log`.
- **Write sweep**, all 24 areas, 20:47–21:59 UTC: every area rc=0 and printed `Done:` once. Logs:
  `*_write.log`, `WRITE_RESULTS`. Each area was backed up first, and each backup's md5 was checked
  against its source. DUNC had been written once at 20:18 under the design from before the plan
  review. It was restored from its byte backup (md5 matched) before the sweep.
- **Idempotency:** a second write run on DUNC left `floodplain.gpkg`, `floodplain_landcover.gpkg`
  and `provenance.json` byte-identical (md5).
- **Checks**, all four regions (`region_checks-run.sh <region>` with `FP_SPLIT_BACKUP`) plus neexdzii,
  22:05–22:35 UTC.

## Reproduction: the inside rows are the published rows

In all 23 whole-WSG groups, the re-vectorised patches inside the group are the published, clipped
patches **byte for byte**: WKB, `patch_id`, `name_basin` and order. The backfill refuses otherwise.
neexdzii is a subset area, so it is checked by key and area instead.

Cause, context and lookback columns did not move anywhere. The cause gate never needed `FORCE`.
Inside change and inside tree loss equal the published totals in every whole-WSG group (max
difference 0.000000 ha). On neexdzii, the patches that have a sub-basin give tree loss
**773.4 ha**, the parity figure, and the floodplain is **142.0 km²**. The ground outside every
sub-basin (1.1 ha of tree loss, 3.4 ha of change) lies outside BULK.

| group | scenario | floodplain ha | outside ha | outside % | patch rows (was) | change in ha (was) | change outside ha | tree loss in ha (was) | open water in ha (% of in) |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| BOWR | all_ff04 | 38,999.0 | 1,033.3 | 2.65 | 2376 (2346) | 1,412.7 (1,412.7) | 43.9 | 586.5 (586.5) | 4,674.1 (12.3) |
| BULK | all_ff04 | 65,999.2 | 1,318.2 | 2.00 | 9286 (9210) | 5,584.9 (5,584.9) | 82.1 | 2,793.4 (2,793.4) | 5,662.5 (8.8) |
| DUNC | all_ff04 | 18,521.4 | 204.5 | 1.10 | 1446 (1299) | 715.0 (715.0) | 33.6 | 116.9 (116.9) | 10,418.7 (56.9) |
| FRAN | all_ff04 | 109,630.9 | 1,224.1 | 1.12 | 10115 (9888) | 12,002.5 (12,002.5) | 272.9 | 10,139.8 (10,139.8) | 51,948.7 (47.9) |
| KISP | all_ff04 | 32,440.4 | 326.3 | 1.01 | 5239 (5170) | 2,099.4 (2,099.4) | 26.6 | 350.5 (350.5) | 4,769.3 (14.9) |
| KOTL | all_ff04 | 75,414.2 | 923.8 | 1.22 | 5938 (5657) | 3,248.6 (3,248.6) | 142.3 | 643.1 (643.1) | 45,838.3 (61.6) |
| LARL | all_ff04 | 37,550.9 | 344.4 | 0.92 | 2968 (2936) | 1,886.8 (1,886.8) | 21.0 | 379.4 (379.4) | 21,429.1 (57.6) |
| LCHL | all_ff04 | 42,681.2 | 1,389.7 | 3.26 | 9551 (9396) | 4,802.0 (4,802.0) | 200.4 | 1,526.4 (1,526.4) | 5,431.7 (13.2) |
| LNTH | all_ff04 | 38,856.1 | 908.9 | 2.34 | 4830 (4745) | 2,504.8 (2,504.8) | 44.8 | 746.5 (746.5) | 7,940.4 (20.9) |
| LSAL | all_ff04 | 29,088.4 | 615.6 | 2.12 | 4623 (4562) | 2,535.3 (2,535.3) | 94.1 | 1,003.9 (1,003.9) | 5,461.0 (19.2) |
| MCGR | all_ff04 | 35,533.1 | 1,072.4 | 3.02 | 4157 (4063) | 2,426.5 (2,426.5) | 79.8 | 776.7 (776.7) | 1,619.4 (4.7) |
| MORK | all_ff04 | 66,704.0 | 1,152.2 | 1.73 | 6796 (6502) | 3,371.6 (3,371.6) | 94.7 | 1,063.0 (1,063.0) | 2,277.2 (3.5) |
| MORR | all_ff04 | 47,931.9 | 595.1 | 1.24 | 3519 (3351) | 1,747.2 (1,747.2) | 76.9 | 659.5 (659.5) | 17,794.9 (37.6) |
| NECR | all_ff04 | 75,959.1 | 1,015.2 | 1.34 | 11469 (11323) | 10,003.3 (10,003.3) | 190.1 | 4,463.8 (4,463.8) | 10,945.3 (14.6) |
| PARS | all_ff04 | 55,944.2 | 633.2 | 1.13 | 9309 (9189) | 6,070.8 (6,070.8) | 219.3 | 1,753.0 (1,753.0) | 3,324.2 (6.0) |
| PCEA | all_ff04 | 84,334.4 | 35,196.9 | 41.73 | 2425 (1565) | 754.4 (754.4) | 1,700.3 | 227.7 (227.7) | 35,937.7 (73.2) |
| PINE | all_ff04 | 48,887.3 | 986.9 | 2.02 | 9710 (9604) | 4,107.5 (4,107.5) | 105.0 | 1,033.0 (1,033.0) | 1,193.0 (2.5) |
| SLOC | all_ff04 | 15,449.5 | 128.2 | 0.83 | 1196 (1179) | 398.8 (398.8) | 5.4 | 119.7 (119.7) | 8,587.6 (56.1) |
| TABR | all_ff04 | 26,719.1 | 846.5 | 3.17 | 2780 (2646) | 1,799.9 (1,799.9) | 54.6 | 634.6 (634.6) | 1,198.9 (4.6) |
| THOM | all_ff04 | 25,704.2 | 561.2 | 2.18 | 2735 (2564) | 2,709.0 (2,709.0) | 126.9 | 1,169.1 (1,169.1) | 6,755.8 (26.9) |
| UFRA | all_ff04 | 30,173.2 | 373.7 | 1.24 | 10932 (10799) | 3,037.2 (3,037.2) | 34.5 | 827.2 (827.2) | 2,993.6 (10.0) |
| UNTH | all_ff04 | 23,493.2 | 190.6 | 0.81 | 4552 (4544) | 1,441.1 (1,441.1) | 23.0 | 672.9 (672.9) | 1,726.2 (7.4) |
| WILL | all_ff04 | 35,124.5 | 874.9 | 2.49 | 2502 (2337) | 1,631.6 (1,631.6) | 127.5 | 679.3 (679.3) | 3,915.6 (11.4) |
| NEEXDZII | co_ff04 | 14,204.0 | 212.7 | 1.50 | 2028 (2018) | 1,278.7 (1,278.7) | 3.4 | 773.4 (773.4) | 2,460.8 (17.6) |

max |change in - was| = 0.000000 ha; max |tree loss in - was| = 0.000000 ha (neexdzii excluded: its in_wsg pieces include ground outside every sub-basin)
outside %: median 1.61, range 0.81-41.73

- **Columns.** "outside" is `!in_wsg` on the primary scenario's floodplain layer (vector).
  "Patch rows" counts pieces now and patches before the split; `transition_patches` in provenance is
  the new count. "Change in" and "tree loss in" are taken over `in_wsg` patches; "(was)" is the
  published, clipped layer. "Open water in" is `in_floodplain & in_wsg & in_open_water` cells.
- **PCEA**, as #138 found: 41.7% of its floodplain and 1,700.3 ha of its change lie outside the
  group, in Williston's PARA and FINA arms. Inside the group, 73.2% of its floodplain is open water.
  Every other group has 0.81–3.26% outside, which is #53's edge effect.

## Checks

| region | provenance | composition | bridge | disturbance (whole file) | disturbance (`all_ff04`) | wsg_split |
|---|---|---|---|---|---|---|
| skeena | 3/3 PASS | 3/3 PASS | 3/3 PASS | FAIL (legacy species layers) | 3/3 PASS | 3/3 PASS |
| fraser | 13/13 PASS | 12/13 (NECR, below) | 13/13 PASS | FAIL (legacy) | 13/13 PASS | 13/13 PASS |
| peace | 3/3 PASS | 3/3 PASS | 2/3 (PCEA, below) | FAIL (legacy) | 3/3 PASS | 3/3 PASS |
| columbia | 4/4 PASS | 4/4 PASS | 2/4 (LARL, SLOC, below) | 3/4 FAIL (legacy; DUNC has none) | 4/4 PASS | 4/4 PASS |

neexdzii passes all five checks.

**composition-check's bound now passes in all 23 groups.**
- #125 measured it failing in every one: +1.1% to +7.8%, and PCEA +225%.
- Under #53 it compares `in_wsg` change cells with `in_wsg` patches, to 0.5 ha (DUNC: −0.03 ha). The
  whole footprint is compared exactly (1e-6), now that nothing is clipped.

Every remaining FAIL was known before this work:
- NECR `composition-check` (5): the accuracy module's wetland count is on `ch_ff04`, its design's
  scenario, not `all_ff04` (#140). 12,809.0 vs 6,436.6 ha.
- `bridge-check` union proxy: PCEA 0.848, LARL 0.889, SLOC 0.893 (#139; the true union is higher).
- Whole-file `disturbance-check`: the retired species layers predate the context overlays. They
  also lack `in_wsg`, because the backfill touches only the area's own species (#131 prunes them).

## Region totals (README)

`fig/region_totals.csv`, built by `fp_fig_region_totals()`, sums the primary scenario over `in_wsg`.
Under `in_wsg` groups are disjoint, so the sum is the floodplain inside the region's group polygons.
"Sum of whole delineations" is the overlapping sum.

| region | groups | in its groups km² | of which open water km² | sum of whole km² |
|---|---:|---:|---:|---:|
| columbia | 4 | 1453.4 | 862.7 | 1469.4 |
| fraser | 13 | 5674.1 | 1068.9 | 5786.7 |
| peace | 3 | 1523.5 | 404.6 | 1891.7 |
| skeena | 3 | 1441.3 | 282.3 | 1463.7 |

## The forward path reproduces the backfill (DUNC, 22:35–22:39 UTC)

`run_area.R dunc 3` was run after the backfill (log: `20261018_wsg_split_backfill/dunc_forward_step3.log`).
The STAC fetch was a cache hit for all three years: step 3's AOI is now `fl_valley_poly()` of the
floodplain raster, which is WKB-identical to the layer from before the split, so drift's AOI key did
not move.

Against a snapshot of the backfilled outputs, everything is identical:
- the classified and transition content digests;
- `transition_patches` (1,446);
- `inputs_hash` and `outputs_hash`;
- the composition table digest;
- every `floodplain_landcover.gpkg` layer, in rows, attributes and WKB.

DUNC therefore carries a forward step-3 record rather than a `wsg_split` repair. All five checks pass
on it.
