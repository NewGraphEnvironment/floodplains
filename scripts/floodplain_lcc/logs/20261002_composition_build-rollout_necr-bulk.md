# 2026-10-02 — ALR + composition rollout, NECR and BULK (#108)

**Produced by:** `scripts/fwapg/alr_load.sh` (snapshot), `fire_tag.R`, `composition_build.R`,
then `composition-check.R`, `disturbance-check.R` (with a pre-tag snapshot) and `provenance-check.R`
per area. Raw output: `20261002_composition_build-rollout_necr-bulk/`.

**Inputs:** ALR snapshot `whse_legal_admin_boundaries.oats_alr_polys`, comment
`snapshot=2026-10-02T20:49:31Z; rows=3226; record=92e17599-ac8a-47c8-877c-107768cb373c`
(`scripts/fwapg/logs/20261002_204928_bc2pg_load_alr.log`). Rasters are step 3's existing outputs; no
STAC fetch. Machine m1, terra 1.9.34.

## Sequence, per area

1. `disturbance-check.R snapshot <area>` takes a snapshot.
2. `fire_tag.R <area>` adds `in_alr` + `alr_poly_id`. **On BULK it also adds #103's `in_fire_prior`
   lookback columns**, because this was BULK's first re-tag since the lookback landed. NECR had them
   already.
3. `composition_build.R <area>` writes `composition_<scen>_2017_2023` + the
   `landcover[<scen>].composition` provenance sibling.
4. The three checks run. **All exit 0 on both areas**, with every cause column and the geometry
   (WKB) byte-identical to the snapshot.

## Measurement

The numbers come from `fp_composition_summary()` over the table. They are recorded here as
evidence, and every other place re-derives them from the table (#77).

| | NECR `ch_ff04` | BULK `co_ff04` |
|---|---|---|
| floodplain (in_floodplain cells) | 39,627.4 ha | 38,641.3 ha |
| footprint (touches-mask ring incl.) | 41,838.1 ha | 41,089.7 ha |
| ALR in floodplain | 16,885.5 ha (42.6%) | 15,971.7 ha (41.3%) |
| FWA wetland in floodplain | 6,295.7 ha (15.9%) | 4,808.2 ha (12.4%) |
| change (survives the 1 ha sieve) | 4,730.0 ha | 3,639.7 ha |
| change inside ALR | 2,457.5 ha (52.0% of change) | 2,308.7 ha (63.4% of change) |
| change inside FWA wetland | 1,076.8 ha (22.8%) | 649.4 ha (17.8%) |
| sieved change | 1,049.5 ha | 985.3 ha |
| `in_alr` any-touch: patches / patch ha | 3,571 / 2,591.4 ha | 4,545 / 2,417.6 ha |

The last row is the overstatement the table exists to avoid. Summing flagged patches would report
5% more change "in the ALR" than lies there on NECR, and 5% more on BULK.

**Reconciliations (each against something the table was not derived from):**

| check | NECR | BULK |
|---|---|---|
| change cells vs transition patches `sum(area_ha)` | 4,730.0 vs 4,712.6 (+0.37%) | 3,639.7 vs 3,627.2 (+0.34%) |
| in_floodplain cells vs vector floodplain area | 39,627.4 vs 39,651.5 | 38,641.3 vs 38,653.1 |
| ALR cells vs vector floodplain ∩ ALR | 16,885.5 vs 16,894.7 (0.05%) | 15,971.7 vs 15,976.9 (0.03%) |
| wetland cells vs vector floodplain ∩ FWA wetland | 6,295.7 vs 6,300.5 | 4,808.2 vs 4,809.7 |
| footprint wetland vs `accuracy/wetland_composition.csv` | 6,436.64 vs 6,436.64 (exact) | no reference file |

- **Change vs patches.** The change side is ≥ the patch side on both areas. The patches are
  intersected with the sub-basin, so any cell the group boundary clips loses area on that side only.
  `composition-check.R` encodes this as a one-sided bound under 1%.
- **The footprint ring.** Before `in_floodplain` was added, ALR was 17,809 ha on the NECR footprint
  against 16,895 ha of vector. That is +5.4%: the `terra::mask(touches = TRUE)` ring around the
  floodplain, where ALR fields sit. This finding is why every share "of the floodplain" uses
  `in_floodplain` cells.

**Cost:** NECR 46 s at 12.3 GB peak RSS (56 Mcell grid). BULK 129 s at 12.8 GB (169 Mcell grid). The
cost is one `lapp` + `freq` pass.

## The step-3 path, on the parity fixture (neexdzii)

NECR and BULK used the backfill CLI. To exercise the composition inside step 3, I ran
`run_area.R neexdzii 3`. That path covers the stale-table delete, the marker unlink, the landcover
record, `fp_composition_build`, and the markers rewritten last. The STAC request hit the cache.

- **Parity holds.** Tree loss is 770.0 ha over 2,032 patches. The transition `outputs_hash` is
  byte-identical to the pre-run record. `inputs_hash` moved only because of the installed drift
  version stamp (0.13.0 → 0.20.0); every classified digest is unchanged.
- **Composition.** 336 rows. Floodplain 14,282.8 ha (vector 14,282.3); ALR 4,461.3 ha, 31.2% (vector
  4,461.8); change 1,289.0 ha, of it 701.0 ha (54.4%) inside the ALR.
- **Multi-sub-basin bound.** Change cells exceed patches by **+0.29%** across 13 sub-basins, inside
  the one-sided 1% bound.
- composition-check and provenance-check exit 0. Log: `run_area_step3_neexdzii.log` (paths
  redacted), plus `composition-check_neexdzii.log` and `provenance-check_neexdzii.log`.

## Evidence

`20261002_composition_build-rollout_necr-bulk/` holds the build, tag and check logs, two per area per
script.
