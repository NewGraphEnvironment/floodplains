# Model labels, NECR, on the `all_ff04` draw — 2026-10-24 (#148)

The blind model labeller ran on all 480 points of the NECR sample redrawn on `all_ff04` (#148). It used the
protocol pre-registered in `research/landcover_accuracy.md`, "Model labeller", unchanged, with the dated
amendment there recording the redraw. The first draw's labels (`logs/20261023_model_labels_necr.md`) were
discarded unread, and this run's hash replaces theirs.

**This log holds no label and no class count.** The labels stay in gitignored
`data/necr/accuracy/model/labels_model.csv` until the person's `labels_b.csv` is committed, so that labeller
B is blind to them. Their SHA-256 is committed now in `reference/necr/labels_model.sha256`
(`084dafcd3563…`). Nothing here says how accurate they are. Agreement is measured once B's labels exist.

## Run

- **Sheets:** `review_render-sheets.R necr 40` rendered 480 sheets in 12 batches in 5.9 min, at
  2026-10-24T08:30:49Z, with render seed `1792830297`. Each sheet shows four Sentinel-2 same-season
  composites (2017 August–September; 2018, 2020 and 2023 August), the Wayback capture nearest 2017 and the
  one nearest 2023 (unclipped), and the 2012 air photo. The orthophoto is left out.
- **Labeller:** `claude-opus-5-5`, read from every transcript. The agents were Plan type. A Plan canary,
  run first and given no task, found no `CLAUDE.md` text and no design term in its context. "Floodplain"
  appeared only in the working-directory path.
- **Prompt:** the text `labels_import-model.R prompt` builds from `model_labeller-prompt.md`.
  `extract` checks that each agent's first message equals it exactly.
- **Batches:** 12 batches, run 3 at a time. The first was spawned at 2026-10-24T08:31:28Z and the last
  extracted at 08:48:20Z. Each took 175 to 262 s, with 109 to 118k tokens and 42 tool calls (41 Reads and
  the hand-back).

## Transcript audit

Every batch read its key and its own 40 sheets, and nothing else.

| batch | rows | reads | violations | missing | extra | transcript sha256 |
|---:|---:|---:|---:|---:|---:|---|
| 1 | 40 | 41 | 0 | 0 | 0 | 288660b19bdf |
| 2 | 40 | 41 | 0 | 0 | 0 | 99201ac82061 |
| 3 | 40 | 41 | 0 | 0 | 0 | 1d07e2c05783 |
| 4 | 40 | 41 | 0 | 0 | 0 | 52325677a1de |
| 5 | 40 | 41 | 0 | 0 | 0 | c3c4c32e21aa |
| 6 | 40 | 41 | 0 | 0 | 0 | 9fefe97ca719 |
| 7 | 40 | 41 | 0 | 0 | 0 | 49687630e28a |
| 8 | 40 | 41 | 0 | 0 | 0 | a165b2afcea1 |
| 9 | 40 | 41 | 0 | 0 | 0 | 7e5bce0596ab |
| 10 | 40 | 41 | 0 | 0 | 0 | b02cdc99ddff |
| 11 | 40 | 41 | 0 | 0 | 0 | 454332608723 |
| 12 | 40 | 41 | 0 | 0 | 0 | 19139f5a5198 |

No batch was refused or labelled twice. Batch 6 added notes after its `csv` block, which the prompt asks
it not to do. `extract` reads the block alone, so the notes are in the transcript and not in the labels.
The transcripts are kept in gitignored `data/necr/accuracy/model/transcripts/`. Each agent's reply also reaches the session that runs the batches, as its hand-back message. That
session labels nothing and reviews nothing blind, and it copies the transcripts and runs `extract` by script.

## Counts that reveal no class

- **Status:** 476 labelled and 4 `cannot_label` (0.8% of the sample). The abstention ceiling is measured
  against B's points only.
- **Confidence:** 270 low, 172 medium and 38 high.
- **Deciding imagery:** 243 `several`, 225 `esri_dated` and 12 `s2_composite`.

## What the agents raised about the form

- One batch (6) named the key's note that yards and groves count as Built area, and said a reading by
  land cover alone would put a residential grove in Trees. The key is pre-registered, so it stands.
- Batch 6 also listed the sheets whose label rests on the Sentinel-2 composites alone, because no sharp
  panel is near that endpoint.

Neither changed anything mid-labelling. Both are recorded in the PWF findings.

## Next

The person labels the 75-point audit in `necr_lulc_review_b`, after the review projects are synced to
Mergin (the server still serves the first draw), and exports it with `REVIEWER=b labels_export.R necr`.
Then `labels_import-model.R freeze necr`, then `publish` (checked against the hash), then
`accuracy_estimate.R necr`, which applies the gate.
