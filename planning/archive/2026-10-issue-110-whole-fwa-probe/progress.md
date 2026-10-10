# Progress — Probe: cost and difference of a whole-FWA floodplain on MORR (#110)

## Session 2026-10-09

- `/planning-init 104` asked; #104 is gated on #110 (open, no work started), so the user chose to
  init #110 instead.
- Plan-mode exploration — phases approved by user; instruction: all phases to PR.
- Created branch `110-probe-cost-and-difference-of-a-whole-fwa` off main
- Scaffolded PWF baseline from issue #110 with approved phases
- Next: start Phase 1
- Phase 1: `fp_whole_fwa.R` + `floodplain_probe-check.R` (25 asserts). Arms are R predicates over ONE
  whole-group read rather than five SQL WHEREs, so nesting is checkable offline. Six planted defects
  (NA guard, arm-4 parent NA, grid check, species guard, seg-key format, arm check) each turn it red.
- Phase 2: runner `floodplain_probe-whole-fwa.R` (modes anchor / 1..5 / seg / report) and driver
  `floodplain_probe-run.sh` (per-mode process under `caffeinate -s /usr/bin/time -l`, gated on
  `PROBE_DONE <mode>` + an output newer than the mode's start stamp). `data/*` is gitignored
  (`.gitignore:3`), so `probe_whole_fwa/` never reaches git or the publish layer.
- First live run (04:57 UTC): anchor stopped at the DEM. Network digest MATCH; DEM digest DIFFERS from
  the 2026-09-03 record. Diagnosed: MRDEM source unchanged (Last-Modified 2026-06-24); terra
  1.9.34 → 1.9.50 now links GDAL 3.13.0 (sf still 3.8.5), and the warp's grid origin moved ~1.1 m W /
  0.6 m N. Anchor reworked to replay `fp_floodplain()` into `probe_whole_fwa/step2_replay/` on the
  same day's DEM; it passes (network MATCH, DEM MATCH vs replay, floodplain MATCH vs replay). Published
  `co_ff04` vs today: 35,769.1 → 35,618.0 ha (−0.42%).
- Filed flooded#67 (fl_dem_aoi lets GDAL choose the grid) and #117 (published floodplains not
  reproducible; fp_toolchain records sf's GDAL, not terra's).
- Plan review returned; dispositions in `review-plan.md`. Adopted: dem mode, cheap→expensive arm order,
  waterbody split, coho-reachable floodplain per arm, version stamps, habitat `IN (1,2)`,
  pre-registered rule (committed in `research/whole_fwa_floodplain.md` before any arm ran).
- 05:07 UTC: run `dem 5 3 4 2 1 seg` launched. dem OK (3.3 GiB peak).
- Arm 5 (05:08–05:38): delineation 79 s, 356.5 km² on the common grid, blk attribution 863 s for 340
  groups, 7.1 GiB peak. Its coho-reach pass ran with `complete = TRUE` by omission (bug); run
  stopped during arm 3, reach moved to its own guarded mode, relaunched `3 4 2 1 reach seg`.
- Run `3 4 2 1 reach seg` 05:39–08:53 UTC, all PROBE_DONE. Arm 5 re-run 09:07 for a clean RSS.
  Report first failed in the panels (`c(xmin = e[1])` → `xmin.xmin`, the `c(name = x)` trap); fixed,
  reran OK. Order-2 and bypass panels added. Results, rule table, recommendation written into
  `research/whole_fwa_floodplain.md`; log `scripts/floodplain_lcc/logs/20261009_floodplain_probe-whole-fwa_morr.{md,csv}`.
- Findings: delineation < 3 min at every floor, attribution 87–96% of cost; fallback (`complete = TRUE`)
  ≈ 13 min/scenario; floodplains not monotone in seeds (arm 1 loses 452 ha of arm 5's); order ≥ 2
  passes criteria 1–2, order ≥ 1 fails cost (90.7 min); supersession yes (16.6% at order ≥ 2).
- Code check: 4 rounds (plus the plan review = 5 reviewer agents). Rounds 2–4 each found a defect inside
  the previous round's fix, one mechanism throughout (ties that trust a name, presence, or two mutable
  stores agreeing now). Closed by enumeration of every report input (review-round4.md).
- Round 3 found the recommendation did not follow from the registered rule (criterion 3 names order-1
  panels); research and #104 now state both readings. #104 body + title revised; #110 outcome added.
