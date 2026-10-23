# Model labels, NECR — 2026-10-23 (#145)

**Superseded (#148, 2026-10-23):** these labels were made on the first, `ch_ff04` draw. The sample was redrawn on `all_ff04` before labeller B made any label and before any agreement was computed; these labels were discarded unread, and their hash (commit 4072a24) was replaced. The run below is kept as the record of the method.

The blind model labeller on all 480 NECR sample points, run under the protocol pre-registered in
`research/landcover_accuracy.md`, "Model labeller" (commits `8b6b648`, `a4f663a`, pushed before the first
batch).

**This log holds no label and no class count.** The labels stay in gitignored
`data/necr/accuracy/model/labels_model.csv` until the person's `labels_b.csv` is committed, so that labeller
B is blind to them. Their SHA-256 is committed now: `reference/necr/labels_model.sha256`
(`85c28025e9cb…`). Nothing here says how accurate they are. Agreement is measured once B's labels exist.

## Run

- **Sheets:** `review_render-sheets.R necr 40` produced 480 sheets in 12 batches in 9.5 min, with render seed
  `1792760671`. `fp_acc_sheet_dir_check()` passed. Each sheet shows four Sentinel-2 same-season composites
  (2017, 2018, 2020, 2023), the Wayback capture nearest 2017 and the one nearest 2023 (unclipped), and the
  2012 air photo. The orthophoto is left out.
- **Labeller:** `claude-opus-5-5`, read from every transcript. The agents were Plan type. A canary of
  Plan and Explore found no design term and no `CLAUDE.md` contents in either context.
- **Prompt:** the text `labels_import-model.R prompt` builds from `model_labeller-prompt.md`.
  `extract` checks that each agent's first message equals it exactly.
- **Batches:** 12 batches, run 3 at a time. The first was spawned at 2026-10-23T13:14:56Z and the last extracted at 13:31:15Z, both read from `date -u` and the audit records. Each took 168 s to
  286 s, with 109 to 118k tokens and 42 tool calls (41 Reads and the hand-back).

## Transcript audit

Every batch read its key and its own 40 sheets, and nothing else.

| batch | rows | reads | violations | missing | extra | transcript sha256 |
|---:|---:|---:|---:|---:|---:|---|
| 1 | 40 | 41 | 0 | 0 | 0 | 3fd5a8da4e08 |
| 2 | 40 | 41 | 0 | 0 | 0 | e43eb3438b93 |
| 3 | 40 | 41 | 0 | 0 | 0 | 3af72cacebc5 |
| 4 | 40 | 41 | 0 | 0 | 0 | 017f162f70fc |
| 5 | 40 | 41 | 0 | 0 | 0 | 360f1160f990 |
| 6 | 40 | 41 | 0 | 0 | 0 | deb7a490444c |
| 7 | 40 | 41 | 0 | 0 | 0 | 43edcfbd1b12 |
| 8 | 40 | 41 | 0 | 0 | 0 | 5e8039153137 |
| 9 | 40 | 41 | 0 | 0 | 0 | e645f1a79f02 |
| 10 | 40 | 41 | 0 | 0 | 0 | c7846e7dbe19 |
| 11 | 40 | 41 | 0 | 0 | 0 | 7318bebb7789 |
| 12 | 40 | 41 | 0 | 0 | 0 | 5018ef82c0a0 |

No batch was refused or labelled twice. The transcripts are kept in gitignored
`data/necr/accuracy/model/transcripts/`.

## Counts that reveal no class

- **Status:** 471 labelled and 9 `cannot_label` (1.9% of the sample). The abstention ceiling is measured
  against B's points only.
- **Confidence:** 243 low, 195 medium, 41 high, and 1 blank (a `cannot_label` row).
- **Deciding imagery:** 236 `several`, 226 `esri_dated`, 17 `s2_composite`, and 1 blank.

## What the agents raised about the form

Agents raised these without being asked. The person's form has the same shape:

- `label_status`, `confidence` and `imagery` each hold one value per point, but every point has two labels
  (2017 and 2023).
- A cell that can be read in one year and not the other must either be labelled at `low` or lose both
  years.

These are recorded in the PWF findings as a follow-up for the form. They are not changed mid-labelling.

## Next

The person labels the 75-point audit in `necr_lulc_review_b` and exports it with `REVIEWER=b labels_export.R necr`.
Then `labels_import-model.R publish necr` (checked against the hash), then `accuracy_estimate.R necr`, which
applies the gate.
