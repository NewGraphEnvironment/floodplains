## Outcome

Each NECR accuracy review point now has local, sharp Esri imagery from the **capture** nearest each endpoint (2017, 2023). `wayback_index-capture.R` reads every Wayback release's capture metadata, because a release date is not a capture date, and writes `reference/necr/wayback.csv`. `wayback_build-chips.R` fetches the chips with GDAL, which follows the relative redirect QGIS cannot (qgis/QGIS#54161), into `dated/wayback_<year>/<review_id>.tif`. Each chip is clipped to its point's Voronoi cell. `review_build-qgis.R` adds `<year> Esri capture (nearest per point)` layers and themes, and labels each cell with the capture date. Labels decided on the chips record a new `esri_dated` value, apart from the undated `esri` basemap that labelling-key rule 5 caps at low; that was the user's decision at the plan-review fork. Things learned:
- a GDAL VRT ignores source **mask** bands when compositing but honours source **nodata**, so overlapping per-point chips need nodata clipping;
- base R `file.info()` has no inode column, so `fp_acc_link_tree`'s "already linked" test (and its check arm) were `identical(NULL, NULL)`, and reviewer B never picked up a rewritten file;
- a flatness guard for placeholder tiles refuses open lake.

The durable verdict is `research/landcover_accuracy.md`, section "Esri Wayback captures nearest each endpoint (#115)".

## Measurement

- Index: 197 releases x metadata layers 4-6, 32.2 min cold, 1.3 min warm. The two runs wrote a byte-identical `wayback.csv`. 90,538 (point, release) captures, 52 distinct capture dates.
- Capture distance from the endpoint, NECR 480 points:
  - 2017: 6 same year, 237 +/-1 year, 106 +/-2 years, 131 further;
  - 2023: 148 / 115 / 102 / 115.
  - So 243 points (51%) gained sharp imagery within +/-1 year of 2017, where the nearest before was the 2012 4.4 m air photo. 115 points resolve to the same capture at both endpoints.
- Point 1 (`17_00009`): 2017 is capture 2017-06-11, 0.31 m, as the issue predicted from a per-point identify. It is served by release 16245, the later of two releases serving that capture.
- Build: 960 chips, 711 MB, 21.2 min cold. The first run failed 4 chips: one transient warp error, and three "flat" refusals that were open lake. With the flat guard removed, a re-run took 0.3 min.
- Every point reads its own chip from the mosaic, checked for all 960.
- Wrong turns, kept:
  - JPEG + mask chips composited wrongly, and their mask went to a `.msk` sidecar;
  - the flat guard came from a review assumption about placeholder tiles;
  - the plan-gate recommendation to reuse `esri` contradicted rule 5, which the plan review caught.
- Review: Plan review plus 3 code-check rounds (4 agents). Round 3 ended the loop with an enumeration of every reused artifact. Its four non-holding entries were fixed, and the inode fix carries a must-fail arm.

## Evidence

- `scripts/landcover_accuracy/logs/20261008_wayback_necr.md`
- `review-plan.md`, `review-round*.md` in this directory

Closed by: PR for #115 (branch `115-wayback-chips-sharp-imagery-at-the-captu`)
