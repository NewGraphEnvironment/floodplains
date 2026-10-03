# Plan review — #108 (Plan agent, 2026-10-02), with dispositions

Reviewer read the plan + codebase read-only (gdalinfo with PAM off, ogrinfo -ro, SELECT-only psql).
Condensed; each line ends with what was done.

## Blockers
- **B1** A top-level `composition` section in provenance.json makes stac_floodplains_bc's reader stop
  (`known` top-level keys, stac `scripts/fp_provenance.R:172-178`). -> Already avoided: recorded as a
  `composition` SIBLING inside `landcover[<scenario>]` (`fp_prov_set_sibling`), where the reader reads
  explicit paths. Found independently before the review landed.
- **B2** `fp_prov_set` / provenance-check only know three sections. -> Moot for sections (sibling).
  provenance-check still needs `composition` in `KEYS_BODY` (landcover only) + declared keys + 7c
  reconciliation. Done in provenance-check.R.

## Gaps
- **G1** Footprint is the touches=TRUE mask, ~5.5-6.3% above the vector floodplain, so the ALR
  cell-vs-vector check needs a cell-centre `in_floodplain` population. -> Measured independently on NECR
  (ALR 17,809 cells-ha vs 16,895 vector; restricted to centre-in-floodplain 16,885.5, 0.05%). Added an
  always-present `in_floodplain` bit.
- **G2** Footprint wording ("same rule as accuracy" -- accuracy uses BOTH endpoints) and Clouds (10)
  missing from hard-coded class tables. -> Wording fixed; class names from the raster's cats unioned
  with `drift::dft_class_table("io-lulc")`.
- **G3** `fp_table_content_sha256` refuses text/logical. -> Already: digest over integer codes.
- **G4** Stale-composition detector: composition digests must equal landcover's; entry <=> table.
  -> In composition-check live and provenance-check.
- **G5** Promised any-touch cross-check. -> In composition-check live (weak form: change cells inside
  => some patch tagged).
- **G6** Change reconciliation should be one-sided (cells >= patches; sub-basin clipping). -> Done.
- **G7** `.dst_fetch` pads 1000 CRS units; step 3's floodplain is 4326. -> composition_build reads the
  floodplain itself and transforms to the raster CRS before fetching.
- **G8** `gpkg_backfill-wsg.R` scenario_of() anchored regex would key `composition_*` (and latent
  `patch_watercourse_*`) as species "composition". -> Unanchored.
- **G9** `fire_tag.R` prints any-touch ha per context. -> Relabelled "ha touching (any-touch, not an
  area share)".
- **G10** Zero-transition path. -> Already: NULL trans => every change is sieved; call outside the gate.
- **G11** Wetland table has no COMMENT. -> Per-overlay digest over fetched carry keys in `inputs`.
- **G12** README.Rmd / scripts README inventory / CLAUDE.md forward-only notes. -> Phase 5.

## Ordering
- **O1** stac change before writing provenance -> moot (sibling).
- **O2** `fire_tag.R bulk` also rolls out #103's lookback columns to BULK; snapshot before fire_tag.
  -> Stated in the log; snapshot taken.
- **O3** Call composition after the landcover fp_prov_set. -> Done that way.
- **O4** fire_tag before composition-check live. -> Phase 4 order.

## Assumptions
- **A1** The publisher copies `floodplain_landcover.gpkg` WHOLE (`01_stage.R:296-298`), so
  `composition_*` will be published on the next stac rebuild -- my "ignored until opted in" was wrong.
  Written as a plain attributes table (bridge precedent). -> findings.md corrected; stac issue says so.
- **A3** fire_tag will not refuse (cause_cols are sources only). **A4** ALR facts confirmed.
- **A5** Memory: NECR measured 42 s / 9.9 GB RSS with lapp + freq. BULK measured in Phase 4.

## Acceptance
- **AC1** ALR in+out = floodplain is tautological -> the meaningful check is G1's.
- **AC3** NECR wetland reference `data/necr/accuracy/wetland_composition.csv` (6,436.64 ha) must equal
  the composition's footprint in_wetland exactly. -> Live check, when the file exists.
- **AC4** `fp_composition_summary()` so #92 and the log share one definition. -> Added.
- **AC5** provenance-check composition arms must go red. -> Must-fail arms added.
