# Code-check review, round 1 (#93, scripts/landcover_accuracy + packages.R)

## Findings

- **[severity: bug]** scripts/landcover_accuracy/fp_accuracy.R:129-131 (`fp_acc_strata`): stable Flooded Vegetation outside an FWA polygon lands in "stable other", which contradicts the pinned definition. research/landcover_accuracy.md, "Strata", says: *"Wetland is decided per cell (a Flooded Vegetation endpoint, or a cell inside `fwa_wetlands_poly`), and the same way for change and stable land."* The change branch does this (line 141: `(f == 4) | (t == 4) | inw`). The stable branch tests `inw` only.
  - **Measured on NECR** (live fetch of the wetland context entry, same `fp_acc_fetch` and `fp_acc_rasterize` path): 4,984 stable 4->4 cells, of which only 588 are in an FWA wetland. So **4,396 cells (88% of stable FV, about 44 ha)** are in stratum 32 "stable other", which has 1,769,802 cells and 30 points.
  - Expected FV points drawn from that stratum at n = 30: about 0.07. This is the class criterion 1 (FV producer's accuracy) is about. It is the case drift's own `dft_accuracy_estimate` docs warn of: "a rare class hiding in a large stratum makes the interval too narrow".
  - The estimate is not biased, but the design deviates from a pre-registered definition, and it degrades exactly the criterion that needs FV.
  - **It must be settled before labelling.** Changing a stratum's cell set re-maps its ranks to different cells, so pilot labels joined by `point_id` would not carry over. The committed reference/necr/sample.gpkg, strata.csv and design.json would need a redraw.
  - Either add `| (f == 4L)` to the stable-wetland rule and relabel stratum 30, or amend the research note before any label exists.
  - accuracy-check.R has no stable 4->4 case, which is why this passes.

- **[severity: bug]** scripts/landcover_accuracy/window_count-clear.R:106-109: in `run` mode, a composite that errored (`clear_count` returns NULL from the tryCatch) is written as `median = 0, p10 = 0, max = 0, share_ge1 = 0, share_ge3 = 0`. Those are valid-looking measurements of "no clear observations".
  - A transient STAC or Planetary Computer failure for one month would therefore read as a cloudy month in `windows_clear_obs.csv`, and it would steer the window choice this script exists to measure.
  - Write NA for the stats (and ideally a `failed` flag). Only `n_cells = 0` hints at the failure, and nothing downstream is told to read it.
  - The script is blocked on drift#92 today, but this path is what runs once drift can count.

- **[severity: fragile]** scripts/landcover_accuracy/fp_accuracy.R:52-55 (`fp_acc_grid` sync guard): `!is.na(tr) & (tr != expect)` is NA wherever `expect` is NA, and `na.rm = TRUE` then drops it. So a transition cell outside the classified footprint is never counted as a disagreement.
  - That is the out-of-sync case the comment names: a partial re-run of step 3, or a floodplain change between runs, which moves the mask.
  - The mirror direction is worse. Where the transition is NA and the classified endpoints differ, the cell is silently counted as **"sieved change"** in `fp_acc_strata`, and as a published miss in `fp_acc_omission`.
  - Measured 0 such cells on NECR today (transition non-NA outside the footprint: 0; stable cells with transition NA: 0), so no current number is wrong.
  - The guard fails toward pass for the footprint half of "out of sync". Testing `!is.na(tr) & (is.na(expect) | tr != expect)` closes the checkable half.

## Checked and clean

- accuracy-check.R was run and reports ALL PASS.
- The footprint is identical across all 7 classified years on NECR (4,183,814 cells), so `from` and `to` non-NA equals the note's "`classified_2017` non-NA".
- `reported` map_class for sieved points is `from*1000+from`, verified in sample.gpkg (for example 2 -> 11 sieved gives 2002).
- No NA `map_class` in any stratum.
- drift 0.19.0's per-stratum stream and `useHash = FALSE` do make the pilot-to-full extension a prefix.
- The omission filters match the pre-registered definition, and the union is rasterised once, so overlaps count once.
- `fp_acc_fetch` is equivalent to the inline code it replaced.
- packages.R installs `pkgs_accuracy` without attaching it.
- drought_rank-gauges.R: every gauge has all 7 window years in the log.
- The harvest stratum has 17 of 30 points outside any harvest polygon at cell level. That follows from the patch-level any-touch flags, which the note chooses deliberately ("They use the published patch flags"). It is not a defect.

/Users/airvine/Projects/repo/floodplains/planning/active/review-round1.md
