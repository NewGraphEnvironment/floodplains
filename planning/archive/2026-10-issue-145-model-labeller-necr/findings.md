# Findings — #145 model labeller on NECR

## Issue context

**If we do it:** BULK's published change (`bulk_all_ff04`) gets an error-adjusted area with a confidence interval, and every sampled change carries a year and a verdict from dated imagery. drift's article showed how to look at one 3 × 3 km box; this does it for the whole group, by sample.
**If we never do:** the one box we looked at stays our only evidence. In it, 4 of the 5 change areas that sharp imagery brackets were class errors, not change. That is n = 5, which is too few to be a rate and too many to ignore.

## Where this comes from

drift's article [floodplain-change-dating](https://github.com/NewGraphEnvironment/drift/blob/main/vignettes/articles/floodplain-change-dating.Rmd) (drift#108) reads `bulk_all_ff04` from the catalogue. It works in four steps:

1. It dates each clean switch with `dft_rast_break_class()` / `dft_rast_break_category()`.
2. It groups same-year switches of 1 ha or more into 10 change areas.
3. It looks at each area in Sentinel-2 summer composites (`dft_stac_composite()`, every year) and in Esri Wayback (`dft_wayback_*`). It also gives each one a Google Maps link, which is an undated look.
4. Wayback brackets 5 of the areas (2016-09-11 → 2020-09-18). Only C changed. A, B, D and E are class errors: meadow relabelled Crops ↔ Rangeland, and trees that did not change. The 5 areas dated after 2020 have Sentinel-2 only. Four look like forest opening up and one is unclear.

## Why a sample, not a census

BULK's `all_ff04` transition layer has **9,210 pieces (5,585 ha) inside the group, 1,152 of them ≥ 1 ha (4,651 ha)**. Read 2026-10-22 from `data/bulk/floodplain_landcover.gpkg`. Looking at every area the way the article does would cost more than 100 times its effort, and it would still give no area estimate.

A stratified sample's size is set by the number of strata and the precision we want, not by the area. So a watershed group costs about what a reach costs. #93 already has the design (Olofsson 2014, `dft_accuracy_*`), the blind review and the Wayback capture index for NECR, at 16 strata × 30 points.

## Proposal: BULK as #93's second reference area, with the article's dating added

1. **Measure imagery coverage first.** This is metadata only, with no chips.
   - Run `dft_wayback_captures()` over BULK's floodplain to find which captures exist at zoom 17–19, and how near each is to 2017 and to 2023. The box's newest sharp capture is 2020. NECR has 2023-08 captures, so coverage varies across a group, and this step measures that.
   - Check the dated orthophoto coverage (#103).
   - The result decides which strata can be bracketed by sharp imagery and which rest on Sentinel-2 alone.
2. **Design** `reference/bulk/` on `transition_all_ff04_2017_2023`, with the same strata rules as NECR (causes, wetland, lookback, sieved). It must not inherit #140: the design names its own scenario.
3. **Date each sampled point.** BULK is `lulc_annual: true`, so break class and category come from the classified rasters already on disk, with no refetch. Each point also gets the Sentinel-2 brightening year, the article's year-on-year rise against the box. These become **context** for the labeller, never the map claim being tested.
4. **Chips:** Sentinel-2 composites for every year, and Wayback before and after where step 1 found captures, built with drift's tools (#134).
5. **Label with a model, and check it against a person.** The steps run in this order:
   - **Pre-register first.** Before any label exists, add an agreement threshold to `research/landcover_accuracy.md` beside the existing criteria. For example, Cohen's κ ≥ 0.7 on `ref_from` / `ref_to`, and ≥ 0.8 agreement on change / no change.
   - **The model labels every point.** Each point's chips (Sentinel-2 every year, Wayback before and after) and the pre-registered labelling key go to a blind agent. Blind means Plan or Explore type (CLAUDE.md §2): it sees `review_id` and imagery only, never the map class, the stratum or the patch. Its labels go to `labels_model.csv`, with confidence ceilings as the key sets them.
   - **A person labels a random subset blind**, about 60 to 100 points spread across strata. These go to `labels.csv`.
   - **Agreement decides which labels feed `accuracy_estimate.R`.**
     - Above the threshold, the model's labels are used, and the person's labels on the subset are kept as the audit.
     - Below it, the disagreements show where the model fails. Those strata go back to a person, and the model is used only where it held.
   - **Google imagery stays out of the model's input.** Its terms bar that use, and the imagery is undated.
6. **Estimate and report** with #93's `labels_export.R` and `accuracy_estimate.R`.

## Decided (2026-10-22)

- **Unit: points.** They reuse all of #93 and give unbiased area estimates. Change areas would match the article, but area-based accuracy needs its own estimator, and drift does not have one.
- **NECR first.** Run the model-labeller check (step 5) on NECR first. Its 480 points and chips are already built, so the only new work there is a person labelling the audit subset. BULK follows with the protocol already validated, and its sample size is set from what NECR shows.

## Not in scope

- **neexdzii.** It is a subset of BULK on the retired coho layer. The BULK sample covers its ground.
- A classifier of our own. That depends on #93's pre-registered criteria.
- The floodplain boundary itself. That is #141.

Relates #93, #103, #111, #134, #140, #141, drift#108.



## Model labeller: what the agents flagged about the form (2026-10-23)

Raised unprompted by batch agents, and true of the human's form too (`labels_form.qml`), so it is not a model-only defect:
- **One `label_status` per point for two years.** A cell readable in 2023 but not in 2017 must either be labelled at low confidence or lose both years to `cannot_label` (batch 4 chose the former on two sheets).
- **One `confidence` and one `imagery` per point for two labels.** Agents took the lower ceiling and the source that decided the harder label.
- Agents classed gravel roads and tracks as Bare ground, not Built area (IO's Built examples are paved), and trees inside a homestead yard as Built (IO's note).
Candidates for a follow-up on the form; changing it now would change the pre-registered schema mid-labelling.

## Errors Encountered

| Error | Resolution |
|-------|------------|
| `[clamp] cannot clamp a raster with no values` in the renderer | `terra::rast(x)` on a SpatRaster is an empty template (code-check-spatial); use `x[[1:3]] * 1` |
| `[crop] extents do not overlap` | the air photo VRT does not cover every point; test `terra::relate(..., "intersects")` first |
| S2 panels near-black and smoothed | fixed square-root stretch on 0–0.25; `plotRGB(smooth = FALSE)` |
| Byte binding of transcript image to sheet failed on 26 of 40 sheets | the Read tool passes a small PNG through but re-encodes a large one (>~500 KB here) to JPEG; compare decoded pixels instead (own 0.0031–0.0040 mean abs diff, other sheets ≥ 0.038; tol 0.01) |
