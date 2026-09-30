# Code-check round 3 (#93)

Reviewer: subagent, 2026-09-29. Scope: the branch diff plus the staged diff (`diff3.patch`), with the new
files read in full: `accuracy_estimate.R`, `labels_export.R`, `review_build-qgis.R`,
`chip_build-composite.R`, `chip_rgb.qml`, `reference/necr/labels_form.qml`, and the phase 6-7 helpers
in `fp_accuracy.R`. They were checked against drift 0.19.0's `dft_accuracy_estimate`, `_labels`,
`_size` and `_sample`, the `dft_stac_composite` return and cache (installed 0.19.0; the checkout at
0.19.1 differs from v0.19.0 only in `dft_rast_classify`), and rfp 0.86.0's `rfp_project_create`,
`rfp_qgs_vector_add` and `rfp_qgs_raster_add`.

Runs: `accuracy-check.R` passes everything (ALL PASS). `SYNTHETIC=1 accuracy_estimate.R necr` runs
to a verdict. The probes ran in `/private/tmp/claude-501/r3`. Nothing in the repo or under
`data/necr` was edited or run against, apart from a read-only `ls` of the review directory.

## Mechanism

Rounds 1 and 2, and two of this round's findings, share one assumption. **A value that is absent,
failed, not evaluable, or only nominally the same can be folded into the nearest determinate value
without changing the answer.** Each instance looked like this:

- An FV cell outside FWA was treated as "not wetland", so it landed in stable other (R1).
- A failed month became 0 clear observations (R1).
- An NA endpoint dropped out of a disagreement count (R1).
- An empty month and a failed month became the same NA (R2).

This round adds two:

- An unevaluable endpoint becomes "the other endpoint's value", which decides criterion 1.
- A `point_id` present in both files is taken to mean "the same point".

The fix is the same shape each time. Give absence its own state and carry that state through to the
output (a status, `NA` to "undetermined", or a refusal). Never let it resolve to a neighbouring
value.

## Enumeration (table)

Every point in the diff where an absent, empty, NA, failed, unlabelled or unevaluable input becomes a
number, a class or a decision. "OK" means the outcome is correct, or fails loud.

| # | file:line | input that can be absent/NA/empty | becomes | verdict |
|---|---|---|---|---|
| 1 | fp_accuracy.R:17-18 | `primary_scenario`, `change_interval` absent from area.yml | run_area.R's defaults | OK (same defaults) |
| 2 | fp_accuracy.R:28 | raster with no EPSG | stop | OK |
| 3 | fp_accuracy.R:48 | endpoint year missing from the series | stop | OK |
| 4 | fp_accuracy.R:55 | NA endpoint under a published transition cell | counted as a disagreement | OK (R1 fix) |
| 5 | fp_accuracy.R:55 / :154 | transition NA on a **stable** footprint cell (from == to) | not checked by the sync guard; `reported` = NA, so the point gets map_class NA | OK-loud: drift refuses an NA map_class at estimate time. NECR's 450 points have none |
| 6 | fp_accuracy.R:63 | zero polygons | all-NA raster (no cause or wetland) | OK |
| 7 | fp_accuracy.R:76-80 | NA in from/to/trans/inpoly | excluded by explicit `!is.na` before `na.rm` | OK |
| 8 | fp_accuracy.R:82-83 | denominator 0 | omission NA | OK |
| 9 | fp_accuracy.R:118-120 | trans NA with from != to | sieved stratum; stable does not depend on trans | OK |
| 10 | fp_accuracy.R:131-147 | NA conditions outside the footprint | `foot &` makes them FALSE, so the stratum is NA | OK (accuracy-check `outside`) |
| 11 | fp_accuracy.R:165 | patch `in_<cause>` NA | `%in% c(TRUE,1L)` makes it "not a cause" | OK: the tagger writes FALSE by default (fp_disturbance.R:164) |
| 12 | fp_accuracy.R:175 | fetch returns 0 rows | 0-row sf, so an empty raster (#6) | OK |
| 13 | fp_accuracy.R:190-205 | duplicate or unknown ids; bad or blank status; labelled row missing a class; cannot_label row with a class | stop | OK |
| 14 | fp_accuracy.R:204-205 | confidence/imagery NA | allowed | OK (optional fields) |
| 15 | fp_accuracy.R:211, 213 | cannot_label ref_class; NA labelled_on | NA, written `""` | OK |
| 16 | fp_accuracy.R:206 + labels_export.R:32 | working copy's design columns (`cell`, geometry, `map_class`, `stratum`) that disagree with sample.gpkg | **ignored, and the design is taken from sample.gpkg by point_id** | **BUG, Finding 1** |
| 17 | fp_accuracy.R:242-243 | label point not in the sample | stop | OK |
| 18 | fp_accuracy.R:246-252 | stratum with < 2 labelled points | stop | OK |
| 19 | fp_accuracy.R:246-253 | drawn points with **no row** in labels.csv (not yet labelled) | dropped. Visible only as drawn − labelled − cannot_label in the table; criteria.csv does not record completeness | OK: the draw order is random within a stratum, so it is still a valid subsample. Note only |
| 20 | fp_accuracy.R:261 | measure/class absent from drift's table | NA | OK |
| 21 | fp_accuracy.R:267 | `in_<cause>_poly` column absent (a cause added to the yml after the draw) | `as.logical(NULL)`, length 0, then a data.frame row-mismatch error | OK-loud |
| 22 | fp_accuracy.R:266 + accuracy_estimate.R:37 | a cause **removed or renamed** in disturbance.yml after the draw | drops out of `cause_st` and `in_poly`, which silently redefines criterion 2 on both sides | **fragile, Finding 3** |
| 23 | fp_accuracy.R:276-279 | "target" in neither map nor reference | area 0, se 0 | OK: area 0 implies every ȳ_h is 0, so se is 0 |
| 24 | fp_accuracy.R:293 | unattributed area 0 | hw NA, so criterion 2 is undetermined | OK |
| 25 | fp_accuracy.R:289-290, 300 | FV producer's accuracy NA at one endpoint (no reference FV that year) | **`min(..., na.rm = TRUE)` returns the other endpoint's value, so the result is a determinate hold/not-hold** | **BUG, Finding 2** |
| 26 | fp_accuracy.R:302 | both endpoints NA (min is Inf) | NA | OK |
| 27 | fp_accuracy.R:303-307 | criterion NA | counted in `n_na`, verdict "undetermined" when it could tip the result | OK |
| 28 | fp_accuracy.R:312-313 | stratum SD NA | set to 0 | OK-unreachable: #18 guarantees n ≥ 2, and drift gives a census an SD of 0 |
| 29 | fp_accuracy.R:316-321 | every SD 0 | a note instead of a size | OK |
| 30 | fp_accuracy.R:221-236 | synthetic RNG state | restored | OK |
| 31 | accuracy_estimate.R:43 | labels.csv absent | stop | OK |
| 32 | accuracy_estimate.R:48-50 | omission CSV absent; value blank | NA, criterion 4 undetermined | OK |
| 33 | accuracy_estimate.R:49 | harvest "all" row absent | `numeric(0)`, a data.frame row-mismatch error | OK-loud |
| 34 | accuracy_estimate.R:44 + fp_accuracy.R:242 | labels.csv stratum/map_class disagree with sample.gpkg | only point_id + ref are kept, so the redraw is not seen | **BUG, Finding 1** |
| 35 | labels_export.R:31 | row with ref classes but blank label_status | not exported (still unlabelled) | OK: no number moves; the point stays in "drawn" |
| 36 | labels_export.R:35-51 | old labels.csv empty; no overlap | `mapply` over zero-length gives `!list()`, which is `logical(0)`; nothing is refused | OK (probed) |
| 37 | labels_export.R:40-45 | a point dropped or relabelled vs committed | stop unless FORCE | OK |
| 38 | review_build-qgis.R:36 | project **directory** exists without the `.qgs` (chip_build-composite.R ran first) | `rfp_project_create()` stops with "Project directory already exists" | **BUG, Finding 4** (live on disk now) |
| 39 | review_build-qgis.R:67-73 | labels.gpkg missing fields; working-copy id not in the sample | stop | OK |
| 40 | review_build-qgis.R:74-78 | sample redrawn with the same ids at different cells | "unchanged" / append | **BUG, Finding 1** |
| 41 | review_build-qgis.R:100-107 | no chips | a message, no layers | OK |
| 42 | chip_build-composite.R:63-68 | composite fails **or** window empty (drift warns, then aborts) | NULL, so `file` is NA ("missing") | OK: no number is derived, the n_miss count is reported, and a re-run retries (cache hits are free). The empty and failed cases are conflated but harmless here |
| 43 | chip_build-composite.R:83-84 | a window-year with zero chips | no VRT (a stale VRT from an earlier run is kept, and its files still exist) | OK |
| 44 | chip_build-composite.R:52-54 | windows.csv whose `months` are all single numbers (read.csv makes the column integer) | `strsplit()` on an integer errors | OK-loud (low) |
| 45 | chip_build-composite.R:29 | `n_points` not numeric | NA, so all points are used | OK |
| 46 | window_count-clear.R:47-58 | NA cells inside the AOI | 0 | OK (R2 fix; drift returns NA for no clear observations) |
| 47 | window_count-clear.R:70-85 | skip warning, then abort | "empty"; any other error is "failed" (NA) | OK (R2 fix; accepted text match) |
| 48 | window_count-clear.R:91-95 | all-NA "ok" raster | non-integer guard vacuous; stats 0 | OK-unreachable: drift raises `drift_empty_cube` first, which becomes "empty" |
| 49 | window_count-clear.R:123-131 | empty vs failed | 0 vs NA rows; failed ones warn | OK |
| 50 | reference_omission-disturbance.R:57-63 | NA year value | kept in the pooled row, and `sort()` drops it from the per-year rows | OK: the SQL window excludes NA years |
| 51 | reference_omission-disturbance.R:69-73 | no qualifying harvest | "NOT EVALUABLE" | OK |
| 52 | reference_composition-wetland.R:44-46 | a class code not in the table | class NA | OK (no such code in NECR) |
| 53 | sample_draw-pilot.R:69-72 | strata that fail to partition the footprint | stop | OK |

## Findings

- **[severity: bug]** `review_build-qgis.R:62-79`, `labels_export.R:29-32` with `fp_accuracy.R:206`,
  and `accuracy_estimate.R:44` with `fp_accuracy.R:242`: **a redraw keeps every `point_id` and moves
  the points. None of the three stages that carry labels can see it, so labels are silently scored
  against other cells.**
  - drift numbers points `<stratum>_<k>`, where k is the rank in draw order
    (`dft_accuracy_sample.R:186`). The ranks come from `sample.int(n_cells[h], n)`. So any change to
    a stratum's cell set changes `n_cells[h]` and relocates **every** point of that stratum under the
    same ids. drift's own comment at `:313` warns that "pilot labels joined by point_id would land on
    other cells".
  - `sample_draw-pilot.R` is the documented way to go from pilot to full ("keep SEED and raise N").
    It unconditionally `unlink`s and rewrites `sample.gpkg` from the live inputs:
    - `transition.tif` and the patch cause flags;
    - FWA wetlands fetched from the database;
    - `disturbance.yml`.

    #100 will change the harvest cause flags, and that alone moves all harvest (and neighbouring)
    stratum points.
  - None of the three stages checks anything but the id:
    - `review_build-qgis.R` checks only that the working-copy ids are a subset of the sample (`gone`),
      then reports "unchanged".
    - `fp_acc_labels_frame()` takes `stratum`/`map_class` from sample.gpkg by id and deliberately
      discards the working copy's copy. accuracy-check.R even asserts "map_class comes from the
      design, never the working copy".
    - `fp_acc_estimate()` merges only `point_id`/`ref_*`/`label_status` from labels.csv and ignores
      the `stratum`/`map_class` recorded there.
  - Result: a reviewer's label for a cell is scored against a different cell's map class and
    stratum. The error-adjusted areas and all four criteria move, with no error.
  - The evidence to detect it is already stored: `labels.gpkg` carries `cell`, geometry, `stratum`
    and `map_class`; `labels.csv` carries `stratum` and `map_class`. So compare those and **refuse**
    on any mismatch, in labels_export and in accuracy_estimate, rather than taking the design side.
    Optionally, have sample_draw-pilot.R refuse to overwrite when labels.csv exists and an existing
    id's `cell` changed.

- **[severity: bug]** `fp_accuracy.R:289-290,300`: **criterion 1 collapses a non-evaluable
  endpoint into the other endpoint's value.**
  - drift returns producer's accuracy `NA` for a class with no reference label. That happens here
    when the reviewer labels no Flooded Vegetation at one date, which is plausible given IO's 0.3-0.9%
    FV share inside FWA wetlands.
  - `min(pa17, pa23, na.rm = TRUE)` then reports the other endpoint alone. With pa17 = NA and
    pa23 = 0.8, the result is "does not hold", although the pre-registered rule ("< 0.5 at
    **either** endpoint") cannot be evaluated at 2017.
  - That determinate FALSE feeds `n_hold`/`n_na`. It can turn "undetermined (a criterion could not
    be evaluated)" into "IO meets the pre-registered bar", which is the verdict the criteria exist to
    decide.
  - This is the same mechanism as R1/R2 (`na.rm` folding NA into a number). The criterion should be
    NA whenever either endpoint is NA and neither is < 0.5. That is: TRUE if any non-NA value is
    < 0.5, otherwise NA if any is NA, otherwise FALSE.

- **[severity: fragile]** `accuracy_estimate.R:36-37` with `fp_accuracy.R:266-267`: **causes are
  read from the current `config/disturbance.yml`, not from the design record.** `design.json`
  carries `"causes": ["fire","harvest"]`.
  - A cause **removed or renamed** in the yml after the draw leaves its points in `cause_st`'s
    complement on the map side. On the reference side it drops that cause's `in_<cause>_poly` from
    `in_poly`, so criterion 2 is silently computed under a different definition than the sample was
    drawn for.
  - An **added** cause fails loud (#21).
  - Read `causes` from `design.json` (or refuse when the yml disagrees with it).

- **[severity: bug]** `review_build-qgis.R:36-45`: **the project-exists test keys on the `.qgs`, but
  `rfp_project_create()` refuses an existing directory** (`rfp_project_create.R`, "Project directory
  already exists").
  - `chip_build-composite.R:47-50` `dir.create`s `<dir_proj>/chips/cache` inside the project
    directory. So whenever chips are built first, the project cannot be created.
  - This is the state on disk now: `data/necr/accuracy/review/necr_lulc_review/` holds only
    `chips/`, from the timing run, and no `.qgs`. The next `review_build-qgis.R necr` will stop.
  - It fails loud and loses nothing, but it blocks the phase 6 build. Three ways out:
    - build the project first (and have chip_build refuse without the `.qgs`);
    - create into a temp name and move;
    - put the chip cache outside the project until the project exists (rfp only needs the VRT's
      sources inside the project at `rfp_qgs_raster_add` time).
  - Probed: `terra::vrt()` writes `relativeToVRT="1"` sources, so the relocatable-project claim does
    hold.

No other findings. The drift contract is honoured:

- The `strata` columns and the grid-consistency of area/n_cells hold.
- Nonresponse is removed before drift sees it.
- `use` is "accuracy".
- Classes are numeric, so `acc()`'s numeric comparison is valid.
- `dft_accuracy_size` gets positive weights summing to 1, and SDs aligned by position (unnamed).

The rfp calls match the 0.86.0 signatures:

- the service keys exist;
- the three FWA context layers resolve in `bcrestoration_mobile`;
- a relative gpkg path is resolved against the project directory.

The chip layer bands 1/2/3 are red/green/blue: drift names and writes them in the `bands` order
into a COG, not a NetCDF, so terra's alphabetical-variable trap does not apply.

/Users/airvine/Projects/repo/floodplains/planning/active/review-round3.md
