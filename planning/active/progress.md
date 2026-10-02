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
