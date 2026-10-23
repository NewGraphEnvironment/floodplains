# Task: Check BULK's change against dated imagery: a stratified sample, dated with Sentinel-2 and Esri Wayback, labelled by a model and audited by a person (#145)

**If we do it:** BULK's published change (`bulk_all_ff04`) gets an error-adjusted area with a confidence interval, and every sampled change carries a year and a verdict from dated imagery. drift's article showed how to look at one 3 × 3 km box; this does it for the whole group, by sample.
**If we never do:** the one box we looked at stays our only evidence. In it, 4 of the 5 change areas that sharp imagery brackets were class errors, not change. That is n = 5, which is too few to be a rate and too many to ignore.

Approved plan (gate 2026-10-23 UTC; the user's answers were given 2026-10-22 Vancouver time):

Branch `145-check-bulk-s-change-against-dated-imager`. This PR is **Part of #145**, not Closes. BULK's design and labelling wait until NECR shows whether the model labeller holds.

## Context

#93 built NECR's blind reference sample and review project: 480 points in 16 strata, with Sentinel-2 chips for 2017, 2018, 2020 and 2023, Wayback chips for 2017 and 2023, and the 2012 air photo and 2021 orthophoto. Nobody has labelled any of it. Both working copies hold 0 labels (480 and 48 rows), and there is no `reference/necr/labels*.csv`. #145 replaces "a person labels all 480" with three steps:
- a blind model agent labels every point;
- you label the 48-point second-labeller subset;
- a pre-registered agreement threshold decides whether the model's labels feed the estimate.

Because no label exists yet, the protocol can still change without invalidating anything. It has to be committed before the first label.

## Decided at the gate

- **The audit subset is the existing 48** (`second` column, 3 per stratum, #111). Your answer, 2026-10-23.
- **The threshold** is Cohen's κ ≥ 0.7 on `ref_from` and on `ref_to`, **and** at least 85% agreement on change versus no change (`ref_from != ref_to`). These are point estimates over the points both of us labelled. Your answer, 2026-10-23.
- **Roles reuse the machinery that exists.** The model is labeller A (`labels.csv`, all 480) and you are labeller B (`labels_b.csv`, `_b` project). `fp_acc_working_copy_role()`, `fp_acc_unblind()`, `fp_acc_labels_frame()` and `fp_acc_agreement()` are reused as they are.
- **The #113 decisions are folded in here** with its recommendations, and approving this plan approves them. #113 is then closed by this PR.
  - **Rule 5 widens to ±2 years.** #113's premise is stale since the Wayback chips (#115). Measured from `wayback.csv`, Wayback falls within ±1 year of 2017 for 243 of 480 points and of 2023 for 263, and within ±2 years for 349 and 365.
  - **Growth blinding: accept it and report it.** The model never sees a `review_id` (below), so the batch hint reaches only a human labeller.
- **Fail path is not built now.** If agreement falls short, `accuracy_estimate.R` refuses, and handing strata back to a person becomes its own issue with the disagreement table attached.

## Phase 1 — Pre-register the protocol (committed alone, before any label)
- [x] `research/landcover_accuracy.md` gets a new subsection, "Model labeller (pre-registered 2026-10-23, before any label)", under Review setup. It sets out:
  - the roles and the threshold above, and what happens when the threshold fails;
  - the change-agreement definition;
  - what the model sees (the contact sheets, below) and never sees;
  - that `reviewer` records the model id.
- [x] Amend the "Second labeller" bullet: agreement now **gates** the estimate when A is a model. It still never enters the estimate's numbers.
- [x] Rule 5: ±1 → ±2 years (#113 decision 1). Review setup: the growth policy (#113 decision 2).
- [x] Commit only this file. The timestamp is the pre-registration.

## Corrections after the plan review (2026-10-23; `review-plan.md`)

Gate answers to the review's three forks (user, 2026-10-23): leave the orthophoto out of what the model sees; grow the audit by 9 points in each stable stratum (48 → 75, 36 stable); abstention ceiling ≤ 10%.

- [x] Phase 1b — amend the pre-registration before any label: the audit growth, model labels kept out of the repo (SHA-256 only) until `labels_b.csv` lands, unclipped Wayback, no orthophoto, the batch prompt committed (`model_labeller-prompt.md`), the transcript-audit rule, the inputs differ by design, the abstention ceiling, intervals printed. The per-stratum fallback rule is deferred to a follow-up issue (3 points per change stratum cannot carry it).
- [x] `fp_acc_second_stable()` + seed purpose `second_labeller_stable`, wired into `review_build-qgis.R`; B's working copy (0 labels) is rebuilt so the new points sit in `review_id` order.
- [ ] Push the branch before the first agent spawn, so the pre-registration has a public timestamp.
- **Phase 5 moved out of this PR** to Owed: drift 0.20.0 is installed and does not export `dft_wayback_captures` (checked), and BULK work waits on NECR anyway.
- Phase 3 details: `sheet_map.csv` records `cell` at render; the importer requires role "a" via `fp_acc_working_copy_role()`; the reviewer id comes from the transcript's `model` field; the canary passes on design terms only (the working directory names the repo); a coverage check asserts every sheet labelled exactly once.
- Phase 4 details: the gate runs **before** `fp_acc_estimate()`, `SYNTHETIC=1` bypasses it, it triggers on any `model:` reviewer, and `accuracy-check.R`'s `identical(ag$n, c(3L, 3L))` arm is updated for the new `change` row.

## Phase 2 — Contact sheets the model can read
- [ ] `scripts/landcover_accuracy/review_render-sheets.R <area>`. For each point it writes one PNG of panels around the 10 m cell (about 150 m window, cell outlined):
  - Sentinel-2 same-season composites for 2017, 2018, 2020 and 2023 (`chips_manifest.csv`);
  - Wayback for 2017 and 2023 (`dated/wayback_<yr>/<review_id>.tif`), each headed with its **capture** date and resolution from `wayback.csv`;
  - the air photo and orthophoto where `imagery.csv` covers the point.

  Every panel title is source and date only.
- [ ] **Blind by construction.** Sheets are written as `sheet_<k>.png` under a fresh random order. A gitignored `sheet_map.csv` maps them back to `review_id`. No stratum, map class, patch, wetland or `review_id` appears on a sheet. A guard checks the PNG text metadata and file names against `fp_acc_blind_leaks()`.
- [ ] Output goes to `data/necr/accuracy/model/` (gitignored). The sheets are never committed: they contain the private orthophoto.
- [ ] I look at about 5 sheets myself for legibility at the size an agent reads them. That is a render check, not labelling.

## Phase 3 — Label with blind agents
- [ ] Canary: one Plan and one Explore agent, with no tools, asked whether their context mentions `stratum`, `in_harvest` or `floodplains`. Use whichever type is clean.
- [ ] Batches of 40 sheets, so **12 agent spawns, 3 at a time**. That is above the usual 5-per-task bound, and I'm stating it here so the budget is approved at this gate.
- [ ] Each agent gets the `labelling_key.md` path, its sheet directory, and the output contract: one CSV row per sheet with `sheet, ref_from, ref_to, label_status, confidence, imagery, note`, using the IO codes and vocab in `FP_ACC_IO_CODES`, `FP_ACC_STATUS`, `FP_ACC_CONFIDENCE` and `FP_ACC_IMAGERY`. It is never told what any point is.
- [ ] Each reply's CSV is extracted from the agent's transcript **by script**, never retyped. Each transcript's tool calls are audited for any read outside its batch directory and the key; a hit throws out that batch's labels.
- [ ] `scripts/landcover_accuracy/labels_import-model.R <area>`:
  - maps `sheet` to `review_id`, then unblinds through `fp_acc_unblind()`;
  - builds rows with `fp_acc_labels_frame()`, which validates the vocab;
  - sets `reviewer = "model:claude-opus-5-5"` and `labelled_on`;
  - writes `reference/necr/labels.csv`, with the same refuse-to-overwrite rule as `labels_export.R`.
- [ ] Commit `labels.csv` and the extraction/audit log under `scripts/landcover_accuracy/logs/20261023_model_labels_necr.md`, which records the counts per status and per confidence. It shows no accuracy, because nothing exists to compare against yet.

## Phase 4 — The gate in the estimate
- [ ] `fp_acc_agreement()` gains a `change` row (agreement on `ref_from != ref_to`).
- [ ] `accuracy_estimate.R`: when `labels.csv`'s `reviewer` starts with `model:`, it requires `labels_b.csv`. It then computes agreement and **refuses** to estimate unless the pre-registered threshold holds, printing the per-stratum disagreement table. The threshold constants live in `fp_accuracy.R`, with a comment naming the research section.
- [ ] `accuracy-check.R` adds offline arms, each with a must-fail case:
  - the importer refuses an unknown sheet, a missing sheet, an out-of-vocab code and a duplicate;
  - the sheet renderer's blind guard fires when a leak column is planted;
  - the gate refuses when B is absent, when κ is below 0.7 and when change agreement is below 0.85, and passes at the threshold.

  Restore each defect and watch the arm go red.

## Phase 5 — BULK imagery coverage (MOVED to Owed: needs drift ≥ 0.24 for `dft_wayback_captures`)

Not run in this PR; see Owed at the end.

## Owed at the end (reported, done after merge)
- [ ] You label the 48 points in `necr_lulc_review_b`, then run `labels_export.R necr` with `REVIEWER=b`.
- [ ] `accuracy_estimate.R necr` gives agreement, then either the estimate or the refusal. The verdict is recorded in the research file, #93 and #145.
- [ ] BULK design, chips and labelling (#145 steps 2–6), sized from NECR's result.
- [ ] BULK Wayback coverage (old Phase 5), after drift is upgraded past 0.20.0.
- [ ] After `labels_b.csv` lands: write `labels.csv` from the hashed model file, check the hash, commit, run the estimate.

## Validation
- [ ] `accuracy-check.R` passes, and every new arm has been seen red.
- [ ] `SYNTHETIC=1 accuracy_estimate.R necr` still runs.
- [ ] `/code-check branch`, at least 3 rounds.
- [ ] PWF checkboxes match the landed work, then `/planning-archive` and `/gh-pr-push`.

Verification of the model labels themselves is the owed agreement step. Nothing in this PR claims they are accurate.

