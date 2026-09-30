## Outcome

This branch delivered phases 1–6 of #93: measuring IO LULC's accuracy inside the NECR floodplain.
#93 stays open for the human labelling, the estimates and the verdict.

- **Criteria.** The classify-ourselves criteria and their operational definitions were committed
  before any result.
- **Drought years** are measured from unregulated gauges. 2023 is the low-flow year, and it is IO's
  change endpoint.
- **Free reference.** The fire/harvest omission is computed, and so is IO's labelling of FWA
  wetlands. Criterion 4 does not hold.
- **Sample.** A 450-point stratified pilot is drawn with drift 0.19.0, and it redraws
  byte-identical.
- **Review project.** An rfp QGIS project with a constrained IO-code label form is built, and so
  is the label → estimate → criteria pipeline, exercised on synthetic labels.
- **Composite windows** are held on drift#92: `aggregation = "count"` silently returns
  reflectance.

What was learned:
- **The plan review changed the design before any result.** Masking the population to
  `transition.tif` would have dropped the 18% of IO change that the 1 ha sieve removes. The
  any-touch `in_wetland` flag would have moved 78% of Trees→Rangeland into the wetland stratum.
- **/code-check needed four rounds.** Round 2 found a defect inside round 1's fix. Round 3 named the
  mechanism, "an absent, failed or only-nominally-same value folded into a definite one", and
  enumerated 53 sites. Its best catch: a `point_id` survives a redraw while its point moves, so
  labels matched by id alone would silently be scored against other cells. Round 4 re-walked 75
  sites with 0 defects.
- **A measurement outside scope became #100.** Only 48.9% of NECR's harvest-attributed tree loss
  lies inside a cutblock.

The durable verdicts live in `research/landcover_accuracy.md`.

## Measurement

- **Drought** (Aug–Sep mean flow percentile, 4 free-flowing gauges):
  - 2023 is in the lowest quintile at 3 of 4, median rank 0.14. Lake-buffered gauges: 0.03 and
    0.01.
  - The regulated 08JC001 ranks 2023 at 0.45. It would have hidden the drought, and that is why it
    is excluded.
- **Harvest omission** over 92.1 ha of qualifying clearcut:
  - IO 0.255, so criterion 4 does not hold.
  - The published map 0.411. The sieve adds 16 points.
  - Fire (635 ha): IO 0.314.
- **FWA wetlands** (6,436.6 ha):
  - IO calls them 0.3–0.9% Flooded Vegetation, 51–58% Trees and 34–41% Rangeland.
  - Trees swings 7.6 points between years inside wetlands, against 3.5 points floodplain-wide.
- **Harvest attribution** (→ #100): 287.8 of 588.9 ha of harvest-attributed tree loss is inside a
  cutblock (48.9%). For fire it is 94.2%.
- **Strata:**
  - 15 strata partition the 4,183,814 footprint cells.
  - The change strata sum to the 472,998 published change cells; the sieved stratum holds 104,947.
  - The cell-level wetland fix moved 4,396 stable Flooded Vegetation cells.
- **Chips:**
  - 44 s each (30 in 22.1 min). A full pilot at 4 windows is ~22 h.
  - 5 of 15 test points had no usable July–August 2017 scene under 20% cloud.
- **Wrong turns kept:**
  - The issue's `aggregation = "count"` recipe was assumed to work. It returns reflectance
    (drift#92).
  - Sourcing `run_area.R` for its config reader would have dispatched the pipeline.
  - A headless QGIS load of the project failed on the bundled Python's numpy. The form was
    verified from the `.qgs` XML instead.

## Evidence

`scripts/landcover_accuracy/logs/20260929_*` · review rounds `planning/archive/2026-09-issue-93-lulc-accuracy-pilot/review-*.md`

Closed by: PR (Part of #93) — see branch `93-measure-io-lulc-accuracy`
