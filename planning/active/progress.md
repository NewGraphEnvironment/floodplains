# Progress — Agricultural Land Reserve: floodplain share, change share, and change inside the ALR per area (#108)

## Session 2026-10-02

- Plan-mode exploration — phases approved by user (long crossed composition table; shared fn + backfill CLI; freeze ALR snapshot)
- Created branch `108-agricultural-land-reserve-floodplain-sha` off main
- Scaffolded PWF baseline from issue #108 with approved phases
- Next: start Phase 1
- Phase 1: `scripts/fwapg/alr_load.sh` written and run. 3,226 rows == WFS count, STATUS all 'ALR',
  sum(st_area) 4,612,396 ha. Comment `snapshot=2026-10-02T20:49:31Z; rows=3226; record=92e17599-…`.
  Re-run refuses (exit 1). bc2pg does not load FEATURE_AREA_SQM / FEATURE_LENGTH_M (columns:
  alr_poly_id numeric, status, feature_code, objectid, geom MultiPolygon 3005).
- Phase 2: `alr` context entry in config/disturbance.yml (carry alr_poly_id). disturbance-check.R
  offline: accepted arm, must-fail alias-onto-area_ha arm (mutation: disabling .dst_core_clash turns
  it FAIL), tag fixture, residual-unchanged, report refuses alr as a cause. Live: an empty in_alr is
  INFO (headwater groups may hold no ALR); composition-check.R decides fact vs failed fetch.
- Phase 3: fp_composition.R (lapp encoder + freq; fp_composition_build; fp_composition_summary),
  composition_build.R, composition-check.R, step 3 wiring, fp_prov_set_sibling, provenance-check 3c +
  7c, fp_rast_cells shared with the accuracy module. Plan review folded in (planning/active/review-108.md):
  composition provenance is a `composition` SIBLING in landcover[<scen>] because stac's reader refuses
  unknown top-level keys; `in_floodplain` added after measuring the footprint ring.
- /code-check: 4 rounds (review-round1..4.md). Rounds 2 and 3 each found defects inside the previous
  round's fixes; round 4 was a mechanical enumeration of every value the composition consumes and every
  write that precedes a guard, and its one remaining row (step 3 dying in composition, read by 7c as
  pre-#108) is now a 7c FAIL keyed on the absent per-scenario summary marker, proven both ways on a mork
  copy. Mechanism: inputs read NOW from mutable stores, made GUARDED (refused pre-write) not merely TIED.
- Phase 4: NECR + BULK snapshot -> fire_tag (in_alr; BULK also gained #103's in_fire_prior) ->
  composition_build -> composition/disturbance/provenance checks, all exit 0, causes + WKB unchanged.
  Log: scripts/floodplain_lcc/logs/20261002_composition_build-rollout_necr-bulk.md (+ dir).
