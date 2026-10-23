# Model labeller: the batch prompt (#145)

Pre-registered 2026-10-23, before the first batch was labelled. Every batch is sent this text, with
`{batch_dir}`, `{key_path}`, `{n}` and `{sheets}` filled in by `labels_import-model.R prompt <area> <batch>`.
Nothing else is sent. Never edit this file to fit agreement already measured. See
`research/landcover_accuracy.md`, "Model labeller".

---

You are labelling land cover for an accuracy assessment. Work only from the files named here.

1. Read the labelling key at `{key_path}` in full before you look at any image. It defines the
   classes, the decision rules and the confidence ceilings, and it governs every label.
2. Then read each of the {n} images in `{batch_dir}`, one at a time, with the Read tool. They are:
   {sheets}.
   Each image is a contact sheet for one 10 m cell, outlined in red. The top row is Sentinel-2 summer
   composites at 10 m, 310 m across, with a dashed square marking the bottom row's window. The bottom
   row holds sharper imagery, 120 m across: Esri Wayback captures titled with their capture date, and
   air photos titled with their year. A panel reading "no coverage" or "no capture" has no image.
3. For each sheet, label the outlined cell twice and independently: its class in 2017
   (`ref_from`) and in 2023 (`ref_to`). Do not infer one year from the other.

Rules:
- Use only the Read tool, and read only `{key_path}` and the images in `{batch_dir}`. Do not list,
  search or open anything else, and do not run commands.
- Classes are IO class codes: 1 Water, 2 Trees, 4 Flooded vegetation, 5 Crops, 7 Built area,
  8 Bare ground, 9 Snow/Ice, 11 Rangeland.
- `label_status` is `labelled` or `cannot_label`. Use `cannot_label` only as the key's rule 7
  allows, and then leave both classes blank and say why in `note`.
- `confidence` is `high`, `medium` or `low`, and is capped by the key's rule 5 using the dates in the
  panel titles.
- `imagery` is what decided the label: `s2_composite`, `esri_dated` (a Wayback panel), `airphoto`,
  or `several`.
- `note`: a few words, no commas.

Reply with one fenced block and nothing after it:

```csv
sheet,ref_from,ref_to,label_status,confidence,imagery,note
sheet_NNN.png,<code>,<code>,<status>,<confidence>,<imagery>,<note>
```

(The second line shows the shape only. It is not an example label.)

Give exactly one row for each of the {n} sheets in `{batch_dir}`, using its file name.
