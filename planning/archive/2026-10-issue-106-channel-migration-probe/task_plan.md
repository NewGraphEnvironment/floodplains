# Task: Channel migration: tag long, thin, channel-adjacent water-change patches (erosion/deposition pairs) (#106)

IO LULC change inside the floodplain contains a recognisable migration signature that nothing tags:

- **Erosion:** Trees / Rangeland / Bare → Water, a strip along the outside of a bend.
- **Deposition and colonisation:** Water → Bare (a new bar), then Bare/Rangeland → Trees as the bar vegetates.
- **Migration is the pair:** an erosion strip and a deposition strip on opposite banks of the same reach. A lone Water patch is more often a water-level difference or a classification flip.

Today those patches land in whatever transition stratum their classes put them in. NECR's "any ↔ Water" accuracy stratum alone is 126 ha (`reference/necr/strata.csv`).

## Context

IO LULC change inside the floodplain contains a migration signature (erosion strip X→Water on
an outside bend, deposition Water→Bare/Rangeland on the opposite bank) that nothing tags. The
issue says measure first, then tag. **Decided at the gate:** this PR is **probe + verdict
only**. If the cluster separates, the tag (new columns on published transition layers, plus
`fire_tag.R`, `disturbance-check.R` and stac#6) gets its own issue designed from the measured
numbers. If it doesn't, the negative result closes #106.

Exploration findings that shape the work:

- **drift already ships `dft_transition_artifact()`** (drift 0.20.0 installed, 0.22.0 on main):
  `width_px` (2A/P), `boundary_frac` (share of cells next to the from-epoch interface, which
  is IO's own channel for X→Water), and **reciprocity**: an A→B patch with a B→A partner within
  5 px. It reads that pair as **misregistration**, which is the opposite reading of the same
  pattern. **Decided:** reuse its columns. Compute the channel-specific parts locally, and
  have the verdict say which signals tell migration apart from misregistration. Its reciprocity
  is exact-reverse only, so it cannot see Trees→Water paired with Water→Bare. That pairing is
  the migration case and the probe computes it.
- No elongation or MRR metric anywhere in drift. drift#77 covers patch shape as an article
  topic only.
- **The published transition is sieved at 1 ha** (`03_lulc_classify.R:65`, `patch_min_m2 <-
  10000`). A 20 m × 300 m bank strip is 0.6 ha, so most migration may never reach the layer.
  The probe also re-derives an **unsieved** transition from the on-disk endpoint
  `data/<area>/rasters/<scn>/classified_{2017,2023}.tif`
  (`dft_rast_transition(patch_area_min = 0)`). No fetch is needed.
- NECR and BULK are both `lulc_annual: true`, so all seven years are on disk. That gives a
  **persistence** signal: erosion stays Water through 2018–2023, while flicker does not.
- Channel geometry: `whse_basemapping.fwa_rivers_poly` holds 222 polys in NECR and 109 in BULK.
  The stream line is `streams_<sp>3` in `data/<area>/aquatic_network.gpkg`. `blue_line_key`
  pairing goes through the existing #54 bridge `patch_watercourse_<scn>_2017_2023`.
- The transition layer is a mix of POLYGON and MULTIPOLYGON, so read it with
  `promote_to_multi = FALSE` (CLAUDE.md).
- `reference/necr/strata.csv` stratum 16 "any ↔ Water" is 126.06 ha. No labels exist yet
  (`labels.csv` absent), so #93 cannot validate this yet.

## Phase 1: Pre-register the separation rule

- [x] Write `research/channel_migration.md` (provenance line, question, the candidate-cluster
      definition, and the **separation rule with thresholds**) and add it to the
      `research/README.md` index. Commit **before** any probe output exists, in the
      `landcover_accuracy.md` pattern. Draft rule, to be fixed in this commit:
  - candidate = Water-involving patch, `width_px ≥ 1.5` (not a drift sliver),
    MRR elongation ≥ 3, within 3 cells of IO endpoint Water **or** FWA channel (buffered
    for 1:20k offset), with long axis within 30° of the local stream bearing
  - role = erosion (X→Water) / deposition (Water→Bare|Rangeland|Trees)
  - **separates** if, in NECR unsieved: candidates hold ≥ 20% of Water-involving change
    area, **and** candidate persistence (to-class held in ≥ 4 of the 5 post-onset years)
    is ≥ 2× the non-candidate rate, **and** ≥ 25% of candidate area has an
    opposite-role partner on the same `blue_line_key` on the other side of the channel.
    BULK must reproduce the direction, not the magnitudes.

**Authority:** `research/channel_migration.md` (rule v2) supersedes the draft rule above. The
plan review (`review-plan.md`) found blockers in v1, and v2 answers them before any criterion is
applied.

- [x] Fold the plan review into rule v2 (pairing at the same station, sustained with onset ≤ 2021,
      per-role patches, direction test D, exact anchors) and commit it before the probe runs

## Phase 2: Probe script

- [x] `scripts/floodplain_lcc/channel_probe-migration.R <area>` (noun_verb-detail). It reads
      `area.yml` via `fp_read_config()`, keeps the run read-only (no gpkg writes), and
      writes `scripts/floodplain_lcc/logs/<yyyymmdd>_channel-migration_<area>.{csv,md}`.
  - two patch sets: the published sieved layer, and the unsieved set re-derived in memory from
    the endpoint tifs. Report the share of Water-involving change the sieve drops
  - `drift::dft_transition_artifact()` on each set (needs the unfiltered transition raster)
  - local metrics: MRR length/width (`sf::st_minimum_rotated_rectangle`), compactness
    4πA/P², distance to `fwa_rivers_poly` / stream line, axis-vs-bearing alignment,
    adjacency to IO Water at 2017 and 2023, persistence across the annual series, and
    opposite-bank erosion/deposition pairing via the bridge's `blue_line_key` and side of
    the stream line
  - read the DB with a parameterised query, use `promote_to_multi = FALSE`, and refuse to run
    when the expected year tifs are missing
- [x] `scripts/floodplain_lcc/channel_probe-check.R`: offline fixture assertions with
      must-fail arms. A synthetic straight channel with a known erosion/deposition pair
      must pair; a same-bank pair and a one-px reciprocal sliver must not. Check that the
      elongation and alignment arithmetic is correct on a rotated rectangle.

## Phase 3: Run and verdict

- [x] Run NECR, then BULK (`caffeinate -s`, log to file, gate on in-band errors and output
      mtime). Commit the logs.
- [x] Apply the pre-registered rule as written and fill in the results and decision in
      `research/channel_migration.md`. State the misregistration-vs-migration
      discriminators and the limits (only wide channels register as Water, the 6-year
      window, water level).
- [x] If it separates, file the tag issue (`in_channel_change` + `channel_role` as an
      additive context tag, never a cause; fire_tag/disturbance-check/stac#6 consequences;
      a drift issue for generic elongation or class-pair reciprocity if step 3 would need
      them) and link it. If it doesn't, record the negative result so it closes #106.
- [x] Update `CLAUDE.md` with a short pointer to the research file and the probe. Edit the
      #106 body so it reflects the verdict.

## Out of scope

Decadal migration from the #103 dated imagery (follow-up, nominated by the probe output),
any step-3 or published-layer change, and drift changes.

## Verification

- `Rscript scripts/floodplain_lcc/channel_probe-check.R`: all pass, and each guard is
  shown to fire with its defect restored
- the probe on NECR reproduces the 126 ha "any ↔ Water" order of magnitude on the
  cell-level unsieved set (a sanity anchor against `strata.csv`)
- the published gpkgs are unchanged: compare `md5` before and after the runs
- `/code-check` before each commit

## Validation

- [x] Tests pass
- [x] `/code-check` clean on each commit
- [x] PWF checkboxes match landed work
- [x] `/planning-archive` on completion
