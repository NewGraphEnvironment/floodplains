# Plan review — #145 (Plan agent, 2026-10-23)

Extracted from the agent's transcript by script.

## Review of the #145 plan (task_plan.md) against the code

Phase 1 is already committed (8b6b648), but its checkboxes are still unchecked (task_plan.md:30-37). The commit also includes planning/* files, although the plan says "Commit only this file" (:37).

### Blocker
1. **Phase 5 cannot run.** The installed drift is 0.20.0 and does not export `dft_wayback_captures` or `dft_wayback_pick` (checked with `getNamespaceExports`). They exist only in ../drift (0.24.3). The plan needs a drift upgrade step.
2. **Labeller B can see A's labels.** research/landcover_accuracy.md:337 says the person "is also blind to the model's labels". But Phase 3 commits `labels.csv` (task_plan.md:60) before B labels (:77). The repo is public, and `labels.csv` is keyed by point_id, which `review_key.csv` maps back to review_id. Fix: either B labels and exports first, or the model's labels stay outside the repo with only a SHA-256 hash committed until `labels_b.csv` lands.

### Ordering
- In accuracy_estimate.R the estimate runs and prints at :137-146 and is saved at :164, and agreement is computed only at :147-158. The gate has to run before `fp_acc_estimate()`, and `SYNTHETIC=1` has to bypass it.
- **Re-rendering breaks the mapping.** research:340 shuffles the sheet order "again for every render". A discarded batch (task_plan.md:54) must be relabelled from the frozen sheets. A re-render would silently remap every label. Freeze `sheet_map.csv` after the first render, and commit it after import, or the sheet-to-point mapping cannot be reproduced.
- **The pre-registration is not pushed.** The branch has no upstream, so the local commit date proves nothing. Push it, or post the SHA on #145, before the first spawn.

### Assumption
- **The blind guard checks the wrong thing.** `fp_acc_blind_leaks()` matches column *names* (fp_accuracy.R:639-640), not values. It cannot see a point_id, review_id or stratum label written into PNG text or a file name. Use `fp_acc_point_id_like()` (:257) plus value regexes. The must-fail arm "leak column planted" (task_plan.md:67) tests a column the renderer never writes.
- **`fp_acc_unblind()` refuses rows with no `cell`** (:725), and `fp_acc_design_check` requires `cell` (:377). `sheet_map.csv` must record `cell` when the sheets are rendered. If the importer takes `cell` from the key, the check compares the key with itself.
- **The importer should call `fp_acc_working_copy_role(sheet_map$review_id, key)` (:824)** and require role "a", so a partial import cannot become `labels.csv`.
- **Wayback inputs.**
  - Read capture dates from `data/necr/accuracy/wayback/built.csv` (all 960 rows "built"), not `wayback.csv`. That is the rule at fp_accuracy.R:264-267.
  - Chip files are named `%04d.tif` (:258).
  - The chips are clipped to Voronoi cells (wayback_build-chips.R:20-25, :129). The nodata wedges show neighbours within 300 m (176 of 480 points). That is a weak density cue, and change strata cluster. Re-warp the panels unclipped from the tile cache (`fp_acc_wayback_wms_xml`, cache).
- **`chips_manifest.csv` is keyed by point_id/window/year** (chip_build-composite.R:16, :75). The renderer has to join through the key and must never write point_id outside the gitignored map.
- **Orthophoto and air photo.**
  - The orthophoto VRT reads remote private tiles (review_build-qgis.R:393-394). Rendering needs `FP_ORTHO_STAC` and `fp_acc_quiet_urls`.
  - 25 points sit on a zero-filled collar (research ~:411).
  - `imagery.csv` lists film back to 1973. "Where imagery.csv covers" (research:344) should mean the themed VRTs in `dated/` (airphoto_2012, orthophoto_2021).
- **`fp_acc_agreement()` gains a row, which breaks an existing check.** accuracy-check.R:276 asserts `identical(ag$n, c(3L, 3L))` and will fail.
- **Model id.** Plan and Explore agents may not run on claude-opus-5-5. Take `reviewer` from the transcript's model field, not a hard-coded string (task_plan.md:58).
- **Gate trigger.** Use `any(startsWith(reviewer, "model:"))`. The fail path (research:361) mixes human and model rows.
- **Stale comment.** fp_accuracy.R:223-224 still says the key uses ±1 year.

### Gap
- **The agent prompt is not pre-registered.** Commit the exact batch prompt and output contract before the first spawn, or "you steered it" stays open to dispute.
- **No ceiling on the model's `cannot_label`.** Kappa is computed only over points both labelled (fp_accuracy.R:765-766). A model that abstains on hard cells inflates κ. Pre-register a maximum `a_only_cannot`.
- **Terms of use.** #145 keeps Google out "on terms". The same question applies to sending Esri Wayback and the private orthophoto to the model API, and the plan is silent.
- **The two labellers see different inputs.** B's project carries the undated Esri, Google and Bing layers, change patches and wetlands (research:366-367). The model sees sheets only, so a disagreement mixes labeller and input. State this, or have B work from the same sheets.

### Kappa over 48
- **The subset does not match the estimate's weight.** 13 of 16 strata are change strata (strata.csv), so 39 of the 48 audit points sit in change. The three stable strata carry 86% of the area weight but get 9 points. The audit says little about the model inventing change in stable land, which is where omission and area live.
- **The threshold is near a coin flip.** At about 45 points with po ≈ 0.8 and pe ≈ 0.35, SE(κ) ≈ 0.09, a 95% CI of about ±0.18. A labeller with true κ between 0.6 and 0.8 passes or fails about at random. Change ≥ 0.85 needs at least 41 of 45 points (SE ≈ 0.05).
- **Rare classes make κ unstable.** Snow/Ice, Built and Bare will have 0 to 2 cases.
- **Wording likely to be contested:**
  - "intervals… do not gate" (research:358);
  - the per-stratum fallback on 3 points (research:359-361), where one disagreement means 0.67;
  - an unweighted subset κ standing in for an area-weighted estimate;
  - one person treated as truth.

### Scope
- Phase 5 (BULK coverage) works against task_plan.md:8 ("BULK… waits") and adds the drift upgrade. Split it into its own PR.

### Acceptance
- **The canary will always fail on "floodplains".** The agent's environment block names the working directory /Users/airvine/Projects/repo/floodplains. Define pass on design terms only (stratum, map class, `in_*`).
- **No coverage check.** Nothing confirms that the 12 batches cover all 480 sheets exactly once with no duplicates.
- **The transcript audit has no stated rule.** Define what counts as a read outside the batch: CLAUDE.md, git status, and where `sheet_map.csv` lives.
- **Missing arms:**
  - `SYNTHETIC=1` bypasses the gate;
  - a gate on mixed reviewers;
  - the κ and change-agreement CIs are printed.

### Critical Files for Implementation
- /Users/airvine/Projects/repo/floodplains/scripts/landcover_accuracy/fp_accuracy.R
- /Users/airvine/Projects/repo/floodplains/scripts/landcover_accuracy/accuracy_estimate.R
- /Users/airvine/Projects/repo/floodplains/scripts/landcover_accuracy/accuracy-check.R
- /Users/airvine/Projects/repo/floodplains/scripts/landcover_accuracy/wayback_build-chips.R
- /Users/airvine/Projects/repo/floodplains/research/landcover_accuracy.md
