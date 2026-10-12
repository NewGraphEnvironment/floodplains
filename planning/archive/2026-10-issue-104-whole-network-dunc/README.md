## Outcome

Whole-network mode is in steps 1–3 as `species: all`: a reserved token in the species slot that
reads the whole stream network at order ≥ 2 with no access join, attributes the floodplain by
`blue_line_key`, and writes link's per-segment habitat as a separate `habitat_link` table, joined
by position at query time and never cut into the geometry. It was proven end to end on DUNC (#120),
a new group with no published item to supersede.

What was learned:
- **The access join is a scope, not just a filter.** DUNC is in `fresh.streams` and link's habitat
  tables but absent from `streams_access`.
- **Attribution no longer gates the floor.** flooded 0.6.5 (flooded#71, #72) removed the cost.
- **The position join carries to a second group and species.**
- **A whole-network floodplain crosses its group boundary more** (#53). This broke a check whose
  tolerance was measured on species areas, and the check was left failing rather than loosened.
- **The publish layer refuses `all_ff04` by key regex.** Publishing, join geometry and region
  support are #123.

## Measurement

- **Step 1** (DUNC): 6.8 s, 0.47 GB. 13,023 segments / 3,493 km (bcfp 3,493 km, 0.0%), 2,236 blue
  lines; `habitat_link` 53,654 rows (bt, wct).
- **Step 2:** 8.9 min, 13.3 GB for three scenarios plus blue-line attribution, of which attribution
  was ~3.3 min. MORR's order ≥ 2 attribution took 33 min on flooded 0.6.0 on a same-size grid, and
  BULK's 170 min. `all_ff02/04/06` = 178.8 / 185.0 / 187.0 km².
- **Step 3:** 9.7 min, 19.3 GB. 1,282 patches, 119.5 ha gross tree loss (harvest 32.6%).
- **The join:** all 203,285 cells attributed, keys 100% matched. bt spawning floodplain is 5,101 ha
  by position (nearest), against 16,907 ha by blue line.
- **Composition check:** +4.67% change over clipped patches, because 205.4 ha (1.1%) of floodplain
  lies outside the group polygon. Recorded, not loosened.
- **Species mode untouched:** the read's SQL is pinned by sha256, and `provenance-check.R` passes
  live on neexdzii and bulk.
- **Review:** the plan review returned 23 findings (`review-1.md`). Code-check took 3 rounds: two
  fragile findings, then a Clean round with a 15-item enumeration (`review-round*.md`).
- Durable verdict: `research/whole_fwa_floodplain.md`, "Pipeline pilot: DUNC".

## Evidence

`scripts/floodplain_lcc/logs/20261012_*dunc*.md`

Closed by: PR (this branch, `104-serve-whole-floodplains-keyed-by-blue-li`)
