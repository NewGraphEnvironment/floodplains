# Task: Composite windows name their scenario; NECR's accuracy sample moves to all_ff04 (#148)

**If we fix it:** the composite windows the review chips are built from carry the floodplain they were measured on, and a stage refuses windows from another one. NECR's accuracy sample is redrawn on the floodplain that is actually published, `all_ff04`, under that guard.
**If we never do:** after a `FORCE=1` redraw onto a new scenario (legal since #140), `chip_build-composite.R` builds the new sample's chips from windows measured on the old floodplain, with no message. And NECR's accuracy work keeps measuring land cover on `ch_ff04`, a floodplain the catalogue retired on 2026-10-15.
Found by #140's `/code-check branch` round 4, which walked every write in `scripts/landcover_accuracy/`. It is the one output whose scenario is still implicit.

## Context

The catalogue retired the species floodplains on 2026-10-15, so NECR's published floodplain is now
`all_ff04`. Its accuracy sample, though, is still drawn on `ch_ff04` (`reference/necr/design.json`).
The user chose (2026-10-23) to redraw the sample on `all_ff04`, because nobody has labelled in either
QGIS project, so every review artefact can be overwritten. #148 (the windows record no scenario) is
the guard a redraw onto a new floodplain needs, so it goes first and the redraw runs under it.

Measured in exploration (2026-10-23):
- **`all_ff04`'s footprint:** 75,909 ha (change 9,665 ha, sieved 1,758 ha, stable 64,485 ha), against
  `ch_ff04`'s 41,838 ha. 1,015 ha (1.3%) lies outside the group polygon (`in_wsg = FALSE`).
- **Tags:** the `all_ff04` patches carry every column the draw reads (`in_fire`, `in_harvest`,
  `in_wetland`, `in_fire_prior`, plus `in_wsg` and `in_open_water`).
- **The pre-registration names no scenario:** there is no `ch_ff04` anywhere in
  `research/landcover_accuracy.md`. "Reference sample (NECR pilot)" is descriptive and gets rewritten.
- **The one thing a redraw loses:** the model labeller's labels for the current sample. They were made
  2026-10-23, and only their hash is committed (`labels_model.sha256`, 4072a24). Nobody has seen them,
  and labeller B has no labels, so no result informs the redraw. `freeze` only checks that the model
  hash's last commit precedes `labels_b.csv`'s, so a new hash is legal.
- **The redraw has to clear two committed files.** `review_key.csv` is append-only, and
  `fp_acc_review_key(have = old)` refuses a moved point. `labels_model.sha256` makes `import` refuse
  without `FORCE=1`. Both describe the old draw.
- **rfp refuses a project directory that already exists,** so the four old review directories are
  moved aside, not overwritten. Chips are cached by their AOI (`dft_stac_composite` on the point's
  box), so moved points re-fetch: a cold build.
- **Windows readers:** `chip_build-composite.R:34` (with a `WINDOWS=` override), `review_build-qgis.R:79`
  and `review_render-sheets.R:56`. The writers are `window_count-clear.R` `run`
  (`windows_clear_obs.csv`) and `derive` (`windows.csv`).
- **Prerequisites:** `FP_ORTHO_STAC` is set in R's environment, and fwapg is up (`fresh-db`,
  `pg_isready -h localhost`).
- **Costs from the earlier NECR logs:**
  - window `run`: 27 min, and `ch_ff04`'s floodplain was half this size;
  - S2 chips cold: 31.5 s a chip, so about 480 x 4 = 17 h;
  - Wayback: index 32 min, chips 21 min;
  - sheets: 9.5 min;
  - model labelling: 12 Plan-agent batches, about 17 min.

## Decided at the gate

- **Redraw NECR on `all_ff04`** (user, 2026-10-23, option 1). The QGIS projects can be overwritten.
- **Population:** the whole `all_ff04` classified footprint, including the 1.3% outside the group
  polygon, because that is what the item ships. No code change.
- **Seed and allocation stay:** 930093, 30 points per stratum. The 75-point second-labeller subset
  is regenerated from the seed by the existing code.
- **The old model labels are discarded unread.** The model labeller re-runs on the new draw in this PR:
  12 Plan agents, which is past the five-agent bound, stated here so approving the plan approves the spend.
- **No Mergin sync.** The projects are rebuilt locally; syncing is the user's call later.
- **Base:** stacked on #140's branch, because it builds on `fp_acc_area()`'s design resolution and
  on `FORCE=1` redraw. The PR names #149 as its base until #149 merges.

## Phase 0: Scope the issue
- [x] Edit #148's body and title: add the NECR redraw on `all_ff04` with its reason, and drop "Re-measure NECR on ch_ff04"

## Phase 1: Windows name their scenario (#148)
- [x] `window_count-clear.R run`: write a `scenario` column in `windows_clear_obs.csv` (`cfg$primary_scenario`)
- [x] `derive`: refuse a `windows_clear_obs.csv` with a missing or different scenario; write `scenario` into `windows.csv`
- [x] `fp_acc_windows_read(path, scenario)` in `fp_accuracy.R`, the shape of `fp_acc_omission_read()`: refuse a missing column or a different scenario, and keep the existing column, duplicate and character-`months` checks
- [x] Use it in `chip_build-composite.R` (the `WINDOWS=` override is checked too), `review_build-qgis.R` and `review_render-sheets.R`
- [x] Sheet titles accept any measured window (`fp_acc_sheet_title_ok()` named only Aug and Aug-Sep; plan review Blocker 1), with an arm
- [x] `accuracy-check.R` arms: no column refused, another scenario refused, right scenario passes, `derive`'s input guard; each shown red against a copy with the guard removed

## Phase 2: Redraw NECR on all_ff04
- [x] Hold the commit of the new `sample.gpkg`/`strata.csv`/`design.json` until `windows.csv`, `imagery.csv` and `wayback.csv` are regenerated (accuracy-check's live wayback arm; review item 11)
- [x] Move aside, without reading: the three `data/necr/accuracy/review/necr_lulc_review*` directories and `data/necr/accuracy/model/`, into `data/necr/accuracy/_aside_<UTC date>/`
- [x] `git rm` `reference/necr/review_key.csv` and `reference/necr/labels_model.sha256` (they describe the old draw)
- [x] `FORCE=1 Rscript sample_draw-pilot.R necr all_ff04`, logged; run it again and `cmp` `sample.gpkg`, `strata.csv` and `design.json` (byte-identical redraw)
- [x] Check: strata partition the footprint; `design.json` `transition_layer = transition_all_ff04_2017_2023`; `fp_acc_area("necr")` resolves `all_ff04` with no NOTE

## Phase 3: Regenerate the reference inputs on the new draw
- [x] `window_count-clear.R necr validate`, then `run`, then `derive`, each `> log 2>&1`, with `grep -c repoprted` = 0 on every cache-filling log; `windows.csv` carries `all_ff04`. **If `derive` refuses (no window clear everywhere outside 2017), stop and ask: the pre-registered rule is not tuned** (review item 2)
- [x] Before the omission run: record in findings.md that the all_ff04 value of criterion 4 is the one that counts, decided for catalogue reasons, with the ch_ff04 value (0.2549) kept visible (review item 7)
- [x] `reference_composition-wetland.R necr` and `reference_omission-disturbance.R necr` (both stamped `all_ff04`); `composition-check.R necr` (5) PASS; report criterion 4's new value
- [x] `imagery_index-dated.R necr` produces `imagery.csv`; `wayback_index-capture.R necr` produces `wayback.csv`
- [x] Air-photo thumbnails: reuse the aside project's `dated/airphoto_*` if they are keyed by frame, not point (review item 9)
- [ ] `review_build-qgis.R necr` (A) creates the project and `review_key.csv`; then `imagery_build-dated.R`, `wayback_build-chips.R` and `caffeinate -s chip_build-composite.R necr` (about 17 h, backgrounded, gated on its own log and manifest, not its exit)
- [ ] Rebuild A, then `REVIEWER=b` B (75 points), so both carry the chips and the dated themes; 0 labels in each

## Phase 4: Model labeller on the new draw
- [ ] `review_render-sheets.R necr 40`; batches through `labels_import-model.R prompt → extract` with blind Plan agents (canary first, 3 at a time); `import` writes the new `labels_model.sha256`. This session never reads `model/`.

## Phase 5: Records
- [ ] `research/landcover_accuracy.md`: rewrite "Reference sample (NECR pilot)" (drawn on `all_ff04`, the new strata table, the reason, and that the first draw's model labels were discarded unread); update the chip and Wayback counts, the windows, criterion 4 and the Verified line
- [ ] Logs under `scripts/landcover_accuracy/logs/2026*_<stage>_necr.md` for each stage
- [x] CLAUDE.md #93 bullet: windows name their scenario; NECR's sample is on `all_ff04` since #148
- [x] Research, Model labeller subsection: a dated amendment note recording the redraw, the discarded first-draw hash (4072a24) and why, written before the new hash is committed (review item 3)
- [ ] Research, other ch_ff04 numbers: the wetland composition table, the dated-imagery table, the windows sentence, the Wayback shares, the Status line, the "NECR run" line. Pre-registered rationale (sieve 18%, prior fire 27%, 48/39/86%) stays as dated rationale (review items 4, 6)
- [x] CLAUDE.md, the other stale lines: "all_ff04 under a ch_ff04 sample", "windows do not yet (#148)", "sieve removes 18%", the expected-failure note on NECR (5), and review_key "append-only" (a forced redraw starts a new key) (review item 5)
- [x] Curated windows copy under `scripts/landcover_accuracy/logs/`
- [x] Edit #131's body: the must-fail arm protects whatever scenario `fp_acc_design_scenario()` names (now `all_ff04`); `ch_ff04` is no longer protected by the design

## Validation

- [ ] Tests pass
- [ ] `/code-check` clean (once over the branch with `/code-check branch`)
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

Verification:
- `accuracy-check.R` ALL PASS, with the new arms; the mutations turn them red, run in a copy.
- The redraw is byte-identical twice; `fp_acc_grid()` passes the `all_ff04` grid and refuses `ch_ff04`'s.
- `windows.csv`, `wetland_composition.csv` and `omission_disturbance.csv` all carry `all_ff04`; `composition-check.R necr` (5) PASS.
- Chips: manifest complete, 0 missing, no `repoprted` in the logs. Wayback: every point reads its own chip.
- Both projects rebuilt with 0 labels; B holds 75 points; `review_key.csv` consistent with `sample.gpkg`.
- `labels_model.sha256` committed, with no file from `model/` in git.
- `SYNTHETIC=1 accuracy_estimate.R necr` exits 0; `composition-check.R necr` prints an `ok` line for (5), not INFO.
- `chips_manifest.csv`'s point set equals `sample.gpkg`'s, 4 windows each; B's count equals 3 per stratum + 9 per stable stratum from the new `strata.csv`.

