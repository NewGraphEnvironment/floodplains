## Findings

- **[moderate]** CLAUDE.md:103-104 — "any other area gains `in_wetland` on its next step 3 or `fire_tag.R` run". This is false for `mcgr` and `pine` through the `fire_tag.R` route. Their `transition_*_2017_2023` layers carry **no** tag columns at all: `PRAGMA table_info` shows no `in_fire`, `in_harvest` or carries (probed read-only across all 23 areas; the other 21 have both). `fire_tag.R:286,313` compares every cause column. `tr[["in_fire"]]` is NULL, so `fp_same_values(NULL, <vec>)` fails its length test and every cause column counts as "moved". The layer is REFUSED and the script `stop()`s. Those two areas gain `in_wetland` from `fire_tag.R` only with `FORCE=1`. The same holds for any area whose fire or cutblock table has changed since it was tagged. That is the designed refusal, but the sentence presents the re-tag as automatic. Suggested wording: "on its next step 3, or a `fire_tag.R` run that does not move a cause (`mcgr`/`pine` were never tagged, so need `FORCE=1`)".

- **[minor]** README.Rmd:171-172 (same text at README.md:52-53 and index.html:1544) — "Each change patch is intersected with the overlay layers named in `config/disturbance.yml` … Fire and harvest are what that file lists today." After this branch, `config/disturbance.yml` also lists `wetland` (under `context:`), so the sentence is now inaccurate. The new sentence added two lines below softens it but does not fix it. Suggest "Fire and harvest are the causes that file lists today". Two siblings outside the diff are stale the same way. The subtitle baked into `fig/attribution.png` (built by `scripts/readme_functions.R:369`) says "fire and harvest are what config/disturbance.yml lists today". The roxygen at `scripts/readme_functions.R:300` says "the two overlays `config/disturbance.yml` happens to list". The PNG only changes on an `update_figs` rebuild, so at least reword the builder string so the next rebuild is right.

- **[minor]** CLAUDE.md:89-90 — "(renamed from `disturbance_context`: `$` partial-matches, so with no sources `cfg$disturbance` returned the wetlands and step 3 logged them as causes)". This is written as an event that happened. It was a hypothetical found by a review probe (review-round2.md) on a key that existed only mid-branch. At HEAD, `disturbance_context` appears in `run_area.R` only inside a comment, and step 3 never ran that way. `run_area.R:158-160` phrases it correctly ("would return … would tag and log"). `disturbance-check.R:185-186` repeats the past-tense version. Suggest "would have returned … step 3 would have logged".

- **[minor]** planning/active/task_plan.md:46 — the ticked Phase 2 item still says "`cfg$disturbance_context` from `context`". The code sets `cfg$context_overlays` (`run_area.R:164`). This is a planning file that will be archived, but it is the one place that states the key name wrongly.

Verified true, no action needed:
- `fire_tag.R` writes the main layer, keeps the published geometry, refuses on a moved cause, and `FORCE=1` overrides.
- `promote_to_multi = FALSE` is in both readers.
- The 3,947 / 5,024 / 5,692 figures and the byte-copy restore match findings.md:117-137.
- necr and bulk are declared `GEOMETRY` with `in_wetland` present (1,820 and 1,231 TRUE).
- `fwa_wetlands_poly` has `area_ha` (probed in fwapg).
- The validator rules match the prose: `year_col`/`window`, the key whitelist, case-folded core clash, and case-folded duplicate names and carries.
- The report refuses undated entries and missing `in_` columns.
- Carried attributes join back by row.
- `disturbance-check.R` has the snapshot mode and the `PRAGMA table_info`/`gpkg_geometry_columns` schema read.
- `changes_only = TRUE` is passed at 03:204.
- `run_region.R` skips on `lulc_summary.rds`.
- `fp_readme_sources()` reads `sources:` only.
- `fig/attribution.png` exists.
- README.md and index.html each changed in exactly the one hunk that mirrors README.Rmd, and `readme_content-check.py` passes (anchors and catalogue facts).
- The new prose restates no catalogue numbers.
- #93's body and the stac_floodplains_bc#6 comment exist, as the ticked Phase 5 item says.
- No other prose outside planning/archive and logs still says `fire_tag.R` writes a `_disturbance` layer. CLAUDE.md:137 and gpkg_prune-legacy.R describe it as history.
- The docs-staleness checklist items (renamed scripts, new workflows) are not triggered: no script was renamed.
