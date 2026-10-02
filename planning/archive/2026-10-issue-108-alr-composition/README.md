## Outcome

Loaded the Agricultural Land Reserve into fwapg as a frozen, dated snapshot (`scripts/fwapg/alr_load.sh`,
3,226 polygons, all `STATUS = 'ALR'`). Tagged change patches with `in_alr` + `alr_poly_id` as a `context:`
overlay. Added a cell-level composition table, `composition_<scenario>_<from>_<to>`, that answers
the issue's three questions, plus the matching wetland ones, by summation:

- how much of the floodplain is ALR;
- how much changed;
- how much changed inside the ALR.

Step 3 builds the table, `composition_build.R` backfills it, and its provenance is a `composition`
sibling inside `landcover[<scenario>]`. It is rolled out to NECR and BULK (backfill) and to neexdzii
(full step 3, parity reproduced).

**What was learned:**

1. **A share must come from cells, never from an any-touch flag.** Summing `in_alr` patches
   overstates change in the ALR by about 5%.
2. **The classified footprint is not the floodplain.** It is the `touches = TRUE` mask ring, 5.5–6.3%
   larger, so a cell-centre `in_floodplain` became the denominator.
3. **A provenance section can't just be added at the top level.** The plan proposed a top-level
   section; the publisher refuses unknown top-level keys, which would have stopped NECR and BULK
   publishing, so the record became a sibling instead.
4. **A backfill must refuse inputs no record vouches for.** Its inputs, read from mutable stores at
   build time, have to be refused before the write. Comparing them against the record afterwards is
   too late.

That last lesson took four review rounds. Rounds 2 and 3 each found the defect again inside the
previous round's fix, and round 4 was a mechanical enumeration that ended the loop.

## Measurement

| | NECR `ch_ff04` | BULK `co_ff04` | neexdzii `co_ff04` |
|---|---|---|---|
| floodplain (in_floodplain) | 39,627.4 ha | 38,641.3 ha | 14,282.8 ha |
| ALR share of floodplain | 42.6% | 41.3% | 31.2% |
| change | 4,730.0 ha | 3,639.7 ha | 1,289.0 ha |
| change inside ALR | 52.0% | 63.4% | 54.4% |
| change cells vs patches | +0.37% | +0.34% | +0.29% (13 sub-basins) |
| ALR cells vs vector ∩ | 0.05% | 0.03% | 0.01% |

**The footprint diagnosis.** Before `in_floodplain`, NECR's ALR was 17,809 ha of cells against
16,895 ha of vector. I first read that 5.4% gap as a tolerance problem. It is the mask ring. NECR's
footprint wetland count equals the accuracy module's `wetland_composition.csv` exactly (6,436.64 ha).

**Parity.** neexdzii step 3 reproduced 770.0 ha of tree loss over 2,032 patches, with the transition
`outputs_hash` byte-identical.

**Cost.** One `lapp` + `freq` pass: about 45 s / 12–13 GB on NECR (56 Mcells) and 130 s / 13 GB on
BULK (169 Mcells).

**Review rounds.** One Plan review plus four `/code-check` rounds (`review-*.md` here).

## Evidence

- `scripts/floodplain_lcc/logs/20261002_composition_build-rollout_necr-bulk*`
- `scripts/fwapg/logs/20261002_*_bc2pg_load_alr.log`

Handoff: NewGraphEnvironment/stac_floodplains_bc#70.

Closed by: PR for branch `108-agricultural-land-reserve-floodplain-sha`
