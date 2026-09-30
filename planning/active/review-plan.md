# Plan review (Plan agent, 2026-09-29) and disposition

The reviewer read the plan, #93, drift 0.19.0 and rfp 0.86.0 source, and NECR's data. Its measurements:

- `transition.tif` and `classified_*.tif` share one grid: `compareGeom` TRUE, 8945×6288.
- `transition == c17*1000 + c23` wherever transition is non-NA: 0 mismatches.
- Floodplain footprint 4,183,814 cells. Transition non-NA 4,078,867. IO change cells 577,945, of
  which 472,998 are kept and **104,947 sieved to NA (1,049 ha, 18% of IO change)**.
- `in_wetland` is TRUE on 1,820 of 5,692 patches. **1,228.7 of 1,569.8 ha of Trees→Rangeland** sits
  in `in_wetland` patches.
- Cutblocks by `data_source`: RESULTS 100,096; "Satellite Imagery - Change Detection" 21,702 (18%);
  VRI 38. 25,342 have `percent_clearcut < 90`, and 10,308 have a null `harvest_end_date`.
- NECR fire years on the patches: 2017 (40), 2018 (87), 2023 (62).

| id | finding | disposition |
|---|---|---|
| B1 | Phase 2 blocked on `count`; the script can't detect it | **Already fixed** before the review landed: drift#92 filed, integer guard in f2e3dd2, and the guard fired live |
| B2 | Masking to `transition.tif` drops 1,049 ha of sieved IO change from the population | **Accept.** Mask to the footprint (`classified_2017` non-NA). Map claim for sieved cells = "no change" (`c17*1000+c17`); a 15th stratum, "sieved change (<1 ha)" |
| B3 | Patch-level `in_wetland` at precedence 3 guts Trees→Rangeland | **Accept.** Wetland stratum = FV endpoint OR cell inside FWA wetland (cell level, rasterised `fwa_wetlands_poly`); one definition for change and stable strata. Criterion 3 uses the Trees→Rangeland **map-class** UA, which is independent of stratum precedence |
| G1 | Transition-class strata from raster codes; only causes from polygons; take cause order from `sources:` | **Accept**, with an assertion that rasterised patch cells ⊆ transition change cells |
| G2 | `map =` named list gives no `map_class` | **Accept** (verified `dft_accuracy_sample.R:346-351`): `map = c(list(class = reported), setNames(cls, years))` |
| G3 | Criteria lack operational definitions | **Accept**: Phase 1b pins them in the research note before any Phase 4/5 result |
| G4 | Omission definition | **Accept, mostly**: RESULTS/VRI only (drop satellite change detection, which is optical and not independent of IO); `percent_clearcut >= 90`; start ≥ 2018 and end ≤ 2022; fire 2018–2022; D = the dissolved union ∩ footprint ∩ c17 Trees; numerators IO-unsieved (criterion 4) and published-sieved; pooled and area-weighted |
| G5 | The design record vs the working copy | **Accept**: `reference/necr/sample.gpkg` is the record; reviewers edit a copy in the project dir; `labels.csv` export joins by `point_id` |
| G6 | 3,780 chips can't be layers; `cache_dir` in the project | **Accept**: `cache_dir` in the project, a manifest, one VRT per window-year |
| G7 | rfp/tidyhydat not in `packages.R`; drift floor | **Accept** |
| O1 | Run 3/4/5 while #92 is open | Already the case |
| O2 | Definitions before Phase 4 | Accept (Phase 1b) |
| O3 | Sample after the project layout is fixed | The sample is the design record in `reference/`, independent of the project dir, so no reorder is needed |
| O4 | PWF boxes unchecked | Stale: they were flipped in 9b05604 |
| A1 | Full-AOI read time at res 100 | Carried to drift#92 / Phase 2 when unblocked |
| A2 | Assert the res-20 vs res-100 tolerance | Accept when Phase 2 unblocks |
| A3 | Same-day double counting across MGRS tile overlap | Add to drift#92 |
| A4 | Snow in `mask_values` | Note in the research note |
| A5 | Assert the classified/transition consistency | Accept (a strata-builder assertion) |
| S1 | Chip budget ~52 h | Accept: chips per window wait on Phase 2 windows anyway; land the script and time 5 points |
| S2 | Pilot allocation; stable strata starve at 30 | **User chose 14 × 30 at the gate.** Draw 30 per stratum (15 strata). Raising `n` with the same seed extends the pilot, and the caution goes in the research note and the final report |
| AC1/AC2 | State which acceptance items this PR meets; branch checks | Accept |
