# Review round 3 — staged diff for #106 (channel-migration probe), fresh full pass

Scope: the staged `fp_channel.R`, `channel_probe-migration.R`, `channel_probe-check.R` and the
`research/channel_migration.md` diff, checked against rule v2 plus "Applying the rule". This pass
covered what rounds 1 and 2 did not: the md/CSV report, the gpkg writes, the misregistration
report, the empty and zero-pair paths, and whether each check assertion can fail. Every
experiment ran on copies in the scratchpad. Nothing in the repo was touched except this file.

## Verified correct (probed, not just read)

- **Zero-pair / no-candidate path.** `ci = integer(0)` leads to `fp_ch_pairs` returning the empty
  frame. `ci[pr$i]` stays `integer(0)`, and the `cbind(pr, crosses = logical(0), ...)` branch gives
  a typed 0-row frame with all 8 columns (probed). `fp_ch_pair_flags(pr, n)` comes back all FALSE,
  and `fp_ch_direction_r` on 0 rows is NA. The rule then gives C FALSE and D FALSE, never an error.
  The 08:39 NECR log shows this path ran on real data: 23 and 15 candidates, 0 pairs, table
  rendered.
- **Why NECR has 0 pairs** (read from a copy of `probe_*.gpkg`). That is the data, not a defect.
  21 of the 23 candidates are on the Nechako mainstem (blk 356362759), but no erosion/deposition
  pair there has overlapping station intervals. The closest opposite-role pair is 2659 (erosion,
  232,260 m, half-length 295) and 2679 (erosion). Every deposition is ≥ 17 km away in station.
- **gpkg pairs layer.** `pr$i`/`pr$j` are remapped through `ci[]` before `ero`/`dep` are taken, so
  `ero`/`dep` index rows of `p`. The output loop rebuilds `pt` from `st_point_on_surface()` of the
  same `p` geometry, in the same row order (`patch_id == row`). So the line endpoints are the right
  patches. The direction ero→dep in the layer is display only, and D uses dep→ero as the rule says.
- **Misregistration report.** `mask(tr, role raster)` keeps exactly the Water-involving cells.
  `mask()` keeps the factor levels, which `dft_transition_vectors()` requires, so it does not stop.
  drift 0.20.0's `changes_only` path is a no-op on these cells. Every patch's label is a level of
  `tr`, so `dft_transition_artifact(tv, tr)` passes its label and CRS checks. Sliver share and
  reciprocal share are area shares over transition-level Water-involving patches, which is what
  the rule's Population section and "three numbers" name.
- **Report labels against their computations.**
  - The "each condition alone" percentages are over erosion + deposition area.
  - The quantiles are unweighted over all role patches. The label claims no weighting.
  - The table columns map one-to-one onto `cand_ha`, `cand_share`, `sustained_cand/_wm`,
    `paired_opp/_same`, `dir_r`/`n_opp_pairs`, A–D, `separates` and `direction_holds`.
  - The integer `%d` fields stay integer through `cbind`/`rbind`.
  - The CSV writes NA as blank.
- **Rule mapping, re-checked.** Role class sets, IO adjacency per role (erosion uses 2017 Water,
  deposition uses 2023 Water, 7×7 window), the width/elong/align/channel_adjacent conjunction,
  station-interval overlap at half the MRR long side, the opposite/same kinds, A/B/C/D, and the
  verdict table all match. drift's sieve sets removed cells to NA, so a sieved Water-involving
  cell gets no role in the sieved set.
- **Mutation tests on the check script** (scratch copy). Removing the width filter from `wm`
  turns line 171 red. Removing the 1-cell simplify turns line 69 red. The station test (line 129),
  the margin in C (line 175), the onset and missing-year handling, and `crosses` in
  `fp_ch_pair_kind` each have an assertion that turns red.

## Findings

- **[low — assertion cannot fail]** `scripts/floodplain_lcc/channel_probe-check.R:130`. The check
  reads "a deposition 1.1 km away does not pair", but the station test alone already excludes
  patch 5: station 1400 against 100, half-lengths 100. So the 300 m edge-to-edge criterion
  (`FP_CH_PAIR_DIST`, `st_is_within_distance`) is never exercised.
  - **Measured:** with `dist = 1e9` in `fp_ch_pairs`, the whole check stays "all passed".
  - **Consequence:** a regression that drops or mis-sets the distance criterion ships green, and
    the rule's "within 300 m" would be unenforced.
  - **Fix:** the `pr300` frame (half-length 1e6) already isolates distance. Asserting
    `!"1 5" %in% paste(pr300$i, pr300$j)` makes the claim falsifiable.

- **[low — decorative must-fail arm]** `scripts/floodplain_lcc/channel_probe-check.R:172-173`.
  - **The defect:** the `r_all` fixture contains no `width_px < 1.5` patch, so the width filter on
    the width-matched set has nothing to act on. The arm reports `!B` whether or not the filter
    exists.
  - **Measured:** with `wm <- !cand` (no width filter), line 173 still passes. Line 171 (the 0.4
    lead) is the assertion that actually catches that mutation.
  - **Consequence:** nothing is unguarded today, but the label "must-fail arm" claims a guard this
    line does not provide.

No rule/code mismatches found in this pass.
