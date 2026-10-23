# Findings — Composite windows name their scenario; NECR's accuracy sample moves to all_ff04 (#148)

## Issue context

**If we fix it:** the composite windows the review chips are built from carry the floodplain they were measured on, and a stage refuses windows from another one. NECR's accuracy sample is redrawn on the floodplain that is actually published, `all_ff04`, under that guard.
**If we never do:** after a `FORCE=1` redraw onto a new scenario (legal since #140), `chip_build-composite.R` builds the new sample's chips from windows measured on the old floodplain, with no message. And NECR's accuracy work keeps measuring land cover on `ch_ff04`, a floodplain the catalogue retired on 2026-10-15.

Found by #140's `/code-check branch` round 4, which walked every write in `scripts/landcover_accuracy/`. It is the one output whose scenario is still implicit.

## Why NECR is redrawn here (decided 2026-10-23)

NECR's design (`reference/necr/design.json`) is on `ch_ff04`; stac_floodplains_bc v2.0.0 retired the species items on 2026-10-15, so the published NECR floodplain is `all_ff04` (75,909 ha footprint against `ch_ff04`'s 41,838 ha). Nobody has labelled in either QGIS project, so the redraw costs regeneration only. The one thing lost is the model labeller's labels for the first draw (hash committed in 4072a24): nobody has seen them and labeller B has none, so no result informs the redraw. They are discarded unread and the model labeller re-runs on the new draw. The redraw is exactly the case the window guard exists for, so the guard lands first.

## Where it breaks

- `window_count-clear.R run` counts clear days over the `floodplain.gpkg` layer `cfg$primary_scenario` and writes `windows_clear_obs.csv` with no scenario.
- `derive` reads it back unchecked. Where 2017 needs widening it mixes those cached shares with direct counts over the current scenario's floodplain, then writes the committed `windows.csv`.
- `chip_build-composite.R`, `review_build-qgis.R` and `review_render-sheets.R` read `windows.csv` with no scenario check.

## Work

- `run` stamps `scenario` in `windows_clear_obs.csv`; `derive` refuses a missing or different one.
- `derive` writes `scenario` into `windows.csv`; its readers refuse a mismatch with `fp_acc_area()`'s scenario (`fp_acc_windows_read()`, the shape of `fp_acc_omission_read()`, #140). A file with no column is refused, not passed.
- Offline arms in `accuracy-check.R`, each with a must-fail form.
- Redraw NECR: `FORCE=1 sample_draw-pilot.R necr all_ff04` (seed 930093, 30 per stratum, whole footprint), after removing the first draw's `review_key.csv` and `labels_model.sha256` and moving the old review projects and `model/` aside unread.
- Regenerate on the new draw: windows (`validate`/`run`/`derive`, logs grepped per drift#87), the wetland and omission references (criterion 4), `imagery.csv`, `wayback.csv`, the dated, Wayback and S2 chips, both review projects (B: 75 points), and the model labeller's sheets and labels (hash only committed).
- Rewrite the research file's "Reference sample (NECR pilot)".

Relates #140, #93, #145, #131.

## Errors Encountered

| Error | Resolution |
|-------|------------|
