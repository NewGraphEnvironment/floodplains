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
