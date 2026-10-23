## Outcome

#145 swaps "a person labels all 480 NECR reference points" for a check that a model can do it instead:

- a blind model agent labels every point;
- a person labels a 75-point audit;
- a pre-registered gate decides whether the model's labels may feed the estimate. The gate requires
  κ ≥ 0.7 on both endpoints, change agreement ≥ 0.85, and model abstention ≤ 10%.

**Pre-registration.** It was committed and pushed before any label existed, and it also settles #113:
rule 5 widens to ±2 years, and growth blinding is accepted and reported.

**The plan review changed three things,** each decided by the user:
- the orthophoto stays out of what is sent to the model;
- the audit grows by 9 points in each stable stratum (48 → 75, 36 stable);
- an abstention ceiling joins the gate.

**The labelling run.** All 480 sheets were rendered and labelled by 12 blind batches of Plan agents. Every
transcript passed the audit:
- each batch read only its own sheets and the key, and read all of them;
- each was sent the prompt exactly;
- each label is bound to the image the agent saw.

The labels stay gitignored behind a committed SHA-256 until the person's labels exist. **No accuracy is
claimed yet.**

**The code review.** `/code-check branch` ran six rounds. Rounds 2, 4 and 5 each found a defect inside the
previous round's fix, and all of them sat in one mechanism: the machinery that keeps the person blind to the
model's labels. Round 3 named it: steps identified their input by a name every run reuses, and "freezes" were
written by steps that can run again, so a re-run, a reused name or a missing file could make two records
agree. The end state anchors every freeze in git history, never in files on disk:
- `freeze` and `publish` are separate commands;
- each freeze must be committed exactly once, and before `labels.csv`;
- the work merges with a merge commit, never a squash.

Every guard is a function with a behavioural arm, and each was proved by mutation. The loop ended on round 6's
enumeration of 64 places.

## Measurement

- **The Read tool re-encodes large PNGs to JPEG.** 26 of 40 sheets at 1600 × 860 arrived as JPEG. A byte
  binding therefore refused them falsely, until it was replaced by a pixel comparison. A re-encoded sheet sits
  0.0031–0.0040 mean absolute RGB difference from its own PNG, against 0.038–0.139 from any other sheet. The
  tolerance of 0.01 separates them about tenfold. This is recorded in `research/landcover_accuracy.md`, "Model
  labeller".
- **The first render was unusable.** Forest came out near-black under a linear 0–0.25 stretch and blurred by
  terra's `plotRGB(smooth = TRUE)`. The sheets were fixed with a square-root stretch and unsmoothed pixels.
- **The run.** 480 sheets rendered in 9.5 min. The 12 batches each read 41 files with 0 violations. Result:
  471 labelled and 9 `cannot_label` (1.9%). Confidence was 243 low, 195 medium and 41 high.
- **Wayback.** The capture is within ±1 year of 2017 for 243 of 480 points, and within ±2 years for 349 of 480
  at 2017 and 365 at 2023. That measurement superseded #113's premise that every sharp source sits outside
  the window.
- **The audit subset was mostly change.** Before the growth, 39 of its 48 points sat in change strata, while
  the stable strata hold 86% of the area. That is why it grew.
- **The checks.** `accuracy-check.R` ends at 217 checks. Every new guard goes red when its defect is restored:
  9 + 9 + 4 + 3 mutations across the rounds.
- **Wrong turns, kept.**
  - A byte-equality binding: it was refuted by the JPEG re-encode, and the guard was wrong, not the data.
  - A freeze rewritten by a re-run of `publish` (round 3), then read as unset when its file was absent
    (round 4), then decided by files on disk (round 5).
  - A `git stash` index commit counted as a second freeze (round 6).

## Evidence

- `scripts/landcover_accuracy/logs/20261023_model_labels_necr.md`
- `planning/archive/2026-10-issue-145-model-labeller-necr/review-*.md`

## Owed

- You label the 75 audit points in `necr_lulc_review_b` (re-sync Mergin first if you label there), then run `REVIEWER=b labels_export.R necr` and commit `labels_b.csv`.
- `accuracy_estimate.R necr` gives agreement, then either the estimate or the refusal. The verdict is recorded in the research file, #93 and #145.
- BULK design, chips and labelling (#145 steps 2–6), sized from NECR's result.
- BULK Wayback coverage (old Phase 5), after drift is upgraded past 0.20.0.
- After `labels_b.csv` is committed: `labels_import-model.R freeze necr` → commit `labels_b.sha256` → `labels_import-model.R publish necr` → commit `labels.csv` → `accuracy_estimate.R necr`.

Closed by: PR (Part of #145; closes #113)
