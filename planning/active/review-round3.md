# Code-check round 3: model labeller (#145), branch diff 033981a...21a6d3e

## Checklist read

- `code-check-python.md` (7 KB): read in full. No Python in the diff.
- `code-check.md`: prose of all 14 H3s under `## Mechanisms` (tables and evidence blocks skipped).
- `code-check-r.md` sections for the tools and shapes in the diff: Read-back shape; `on.exit()` at top
  level; `nzchar(NA)`; `strsplit()` trailing field; CSV whitespace / `strip.white`; `match()` and NA;
  `as.integer("NaN")`; `tempfile()` lifetime; `system2()` exit status; `readBin()` u32.
- `code-check-spatial.md`: `sf::gdal_utils()` does not raise; `terra::rast()` on a SpatRaster;
  gdalwarp writes into an existing destination; Wayback in QGIS / capture date; VRT and mask bands;
  `plotRGB()` 500k-cell cap.
- `code-check-shell.md`: `git check-ignore -v` (tracked vs not-ignored, `ls-files --error-unmatch`).

## Mechanism

**Identity by name, freeze by a re-runnable writer.** Every step identifies the artefact it consumes by
a path or a name that is the same in every run, and every "frozen" reference is written by a step that
can be run again. So a guard ends up comparing two records that one run, or a re-run, makes agree.
The pipeline assumes it runs once, in order: render, label, extract, import, commit hash, B labels,
publish, estimate. Whatever sits at the path when a step runs is taken to be the output of the
step before it.

The R1 and R2 findings were all this:
- a stale `sheet_map.csv` beside new sheets: sheet names depend only on the counter, so they are equal
  across renders;
- a partial `labels_b.csv` accepted because it was present;
- a Read counted as read because the call existed;
- the hash and B checked on disk rather than committed;
- B not frozen.

The same assumption still holds in four places (F1 to F4 below). The freeze R2 added is written by a
command that re-runs cleanly (F1). The consumer of the model hash never reads it (F2). Nothing ties a
transcript or raw batch to the render whose map translates it (F3). "Committed" stands in for
"committed before B" (F4).

## Enumeration (place, sound/unsound, file:line)

Each entry is a check that accepts presence, a name or a shape as proof of a property, or a pair of
records from one run compared with each other.

| # | place | verdict | where |
|---|---|---|---|
| 1 | Gate trigger: any reviewer starting `model:` | **unsound**: it trusts what labels.csv says about itself, and labels.csv is never compared with `labels_model.sha256` (F2) | accuracy_estimate.R:72 |
| 2 | B complete: `setequal(point_id, second subset)` | sound. `labels_export.R` writes only rows with a label_status, and `fp_acc_labels_frame` validates it, so "every subset point present" means "every subset point labelled or cannot_label" | fp_accuracy.R:821-829; accuracy_estimate.R:75; labels_import-model.R:155 |
| 3 | B frozen: `labels_b.csv` vs `labels_b.sha256` | **unsound**: the reference is rewritten by every re-run of publish (F1) | labels_import-model.R:172; accuracy_estimate.R:77-80 |
| 4 | publish: `labels_b.csv` and `labels_model.sha256` tracked and clean | sound for "committed now". **Unsound** as a stand-in for "the model hash was committed before B existed" (F4) | labels_import-model.R:160-164 |
| 5 | publish: `labels_model.csv`, and an existing labels.csv, equal the committed hash; copy checked | sound at publish time | labels_import-model.R:165-170 |
| 6 | Estimate reads labels.csv with no hash check | **unsound** (F2) | accuracy_estimate.R:59-61 |
| 7 | extract: first user turn equals `batch_prompt(b)` exactly | sound for the prompt text. **Unsound** as a binding to the render: the prompt holds only the batch path and counter sheet names, which are the same in every render (F3) | labels_import-model.R:77; batch_prompt at :47-63 |
| 8 | extract: each wanted sheet Read with a non-error result (`fp_acc_unread`) | sound for "a file of that name in that directory was read". **Unsound** for "the sheet the current map assigns was read" (F3) | fp_accuracy.R:1013-1019; labels_import-model.R:111 |
| 9 | extract: key.md Read without error | **unsound** for "the agent read the pre-registered key": its content is never compared (F5) | fp_accuracy.R:1018; labels_import-model.R:111 |
| 10 | Read matched to its result by `tool_use_id` (`%in%`) | sound in practice. `%in%` matches NA to NA, so a call with no id and a result with no `tool_use_id` would pair; the transcripts always carry ids | labels_import-model.R:97 |
| 11 | Transcript audit: only Reads of own-batch sheet names and key.md | sound (normalised paths; any other tool or path is a violation) | fp_accuracy.R:1001-1006 |
| 12 | Model id taken from the transcript; one per batch; one across batches | sound | labels_import-model.R:81-84, :131-132 |
| 13 | import: raw `batch_NN.csv` against its `batch_NN.audit.json` | **unsound (low)**: they are written together and never compared (no row count or hash check), and a re-extract overwrites an accepted batch silently (F6) | labels_import-model.R:124-125, :129-134 |
| 14 | import: sheet → review_id and cell via the current `sheet_map.csv`, then `fp_acc_unblind` checks cell against the key | **circular** about which image the model saw: review_id and cell come from the same map row, so the cell check passes for any self-consistent map, including a newer render's (F3) | labels_import-model.R:136, :140; fp_accuracy.R:719-731 |
| 15 | import: role "a" (every keyed point) | sound | labels_import-model.R:138 |
| 16 | import: refuses when the hash exists, unless `FORCE=1` | sound as a local guard. The FORCE hatch is not seen downstream (F4) | labels_import-model.R:142-144 |
| 17 | Render refuses when `raw/` is non-empty | **unsound** as "the map is frozen once any label exists": labels exist in transcripts before any extract (F3) | review_render-sheets.R:41-43 |
| 18 | Render: cells.gpkg against the key (review_id set, cell) | sound (independent producers) | review_render-sheets.R:48-51 |
| 19 | Render: map, key and record removed before the first sheet (R1 fix) | sound: an aborted render leaves no map | review_render-sheets.R:127-128 |
| 20 | `fp_acc_sheet_dir_check`: names match the counter, no other files, no PNG text chunks | sound | fp_accuracy.R:965-981 |
| 21 | `fp_acc_sheet_title_ok`: anchored allow-list | sound | fp_accuracy.R:941-945 |
| 22 | `fp_acc_model_wc`: each sheet once, no unknown sheet, whole-number codes | sound | fp_accuracy.R:1023-1047 |
| 23 | `fp_acc_labels_frame` on model rows: status, IO codes, blanks, confidence, imagery | sound | fp_accuracy.R:396-425 |
| 24 | `fp_acc_second_stable`, idempotent by count | sound. `fp_acc_second_subset` short-circuits on any existing `second`, so it does not reset the growth | fp_accuracy.R:740-783 |
| 25 | B's design check against sample.gpkg | sound | accuracy_estimate.R:65-69 |
| 26 | Gate abstention: A's status matched to B's labelled points | sound on a whole labels.csv. A point missing from A counts as not abstaining, which matters only through F2 | fp_accuracy.R:833-834 |
| 27 | Reply: last text or hand-back containing a ```csv fence, then its last fence | acceptable. If the hand-back holds no fence, an earlier draft is used, but row coverage is still enforced | labels_import-model.R:100-109 |
| 28 | accuracy-check arms that grep source text ("gates BEFORE", "synthetic bypass", "blank reviewer", "publish refuses incomplete B", "re-render removes the map", "committed and clean", "freezes B", "gate refuses an edited B", "B checked before the gate") | proxies. Each passes on any line, comment or string holding the text. The "gate refuses an edited labels_b.csv" arm stays green although F1 defeats the freeze | accuracy-check.R:189-215, :243-249 |

## Findings

### F1 (High): re-running publish re-freezes an edited labels_b.csv, which defeats R2's freeze

labels_import-model.R:172 writes `labels_b.sha256` from the current `labels_b.csv` every time publish
reaches the end. Publish reaches the end again after these steps:
1. B is published.
2. The person sees the model's labels in `reference/<area>/labels.csv` and edits `labels_b.csv` toward
   them.
3. The edit is committed.
4. Publish runs again.

On the second run every check passes:
- B is complete;
- B and the model hash are tracked and clean;
- `labels_model.csv` equals the hash;
- labels.csv exists and equals the hash (line 168).

So line 172 records the edited B, and accuracy_estimate.R:77-80 accepts it. Fitting B to A is what the
freeze exists to stop, and it raises κ and change agreement. The grep arm at accuracy-check.R:248-249
cannot see this.

Fix: refuse in publish when `labels_b.sha256` exists and differs from `sha256(fb)`, or write it only
when labels.csv did not exist before this run.

Stronger: have the estimate compare `labels_b.csv` with the blob committed in the commit that first
added `labels.csv`, rather than with a file publish rewrites.

### F2 (Medium): the estimate never checks labels.csv against `labels_model.sha256`, and decides whether to gate from the file's own reviewer column

accuracy_estimate.R:59-61 reads labels.csv, and :72 gates only when a reviewer starts with `model:`.
The committed hash is checked once, at publish (labels_import-model.R:165-169), and never by the
consumer the gate protects.

**Edited or deleted model rows pass the gate.**
- Agreement counts only points both labellers labelled.
- A model row that is missing counts as not abstaining (fp_accuracy.R:834).
- So deleting the model's disagreeing rows raises κ and change agreement and lowers abstention.
- A rewritten `reviewer` column skips the gate entirely.

The research text says labels.csv "is checked against the hash". The check is published and never
re-read at the point of use.

Fix:
- When `reference/<area>/labels_model.sha256` exists, require `sha256(labels.csv)` to equal it before
  anything else.
- Trigger the gate on that file's presence, with the reviewer prefix only as a cross-check.
- Refuse when the hash file exists and labels.csv carries no `model:` reviewer.

### F3 (Medium): nothing ties a transcript or raw batch to the render whose `sheet_map.csv` translates it

The prompt holds only `…/model/batch_NN` and the counter names `sheet_001…`, and both are the same in
every render (fp_accuracy.R:926, :931-938; labels_import-model.R:47-63). Every check that follows
compares records from the same render, or names that are the same across renders:
- `extract` checks the prompt by equality (:77) and the reads by basename (fp_acc_unread);
- `import` maps through whatever `sheet_map.csv` is on disk (:136);
- `fp_acc_unblind`'s cell check passes for any self-consistent map (enumeration 14).

The render guard checks only `raw/` (review_render-sheets.R:41). These sequences therefore attach every
label to a different point with no error:
- agents run, the sheets are re-rendered (a fix to the renderer, a new seed), then the transcripts are
  extracted;
- `raw/` is moved aside as the guard's own message says, the sheets are re-rendered, and `raw/` is
  moved back before import.

The research subsection says the map "is frozen once any label exists". The code freezes it only once a
batch has been extracted.

NECR looks unaffected: the log records one render (seed 1792760671) before the first spawn. That cannot
be confirmed from the repo, because `render.json` is in the gitignored model directory, which I did not
read.

Fix: put a render identifier (the seed, or a sha of `sheet_map.csv`) into the prompt, for example in the
batch directory name or as a line of text. The existing exact-prompt check then binds each transcript
to its render. Record the identifier in each audit, and have `import` refuse an audit whose identifier
differs from the current `render.json`. Also refuse to render when `model/transcripts/` is non-empty.

### F4 (Low): publish checks "committed", not "committed before B existed"

`import` replaces the model's labels under `FORCE=1` (labels_import-model.R:142). Publish then accepts
any committed hash (:160-164), including one committed after `labels_b.csv`. The pre-registration rests
on the hash predating B: "until then, only their SHA-256 is committed".

Fix: in publish, require the last commit touching `labels_model.sha256` to be an ancestor of the first
commit adding `labels_b.csv`:

```
git merge-base --is-ancestor $(git log -1 --format=%H -- <sha>) $(git log --diff-filter=A --format=%H -- <labels_b> | tail -1)
```

### F5 (Low): the key the agents read is never compared with the pre-registered key

`extract` checks that `key.md` was Read without error (fp_accuracy.R:1018). It does not check that its
contents are `fp_acc_labelling_key()` as committed. The prompt gets an exact-equality check; the other
input to every label does not.

This is latent for NECR. The `## Labelling key` section is byte-identical (sha 98bed080…, 72 lines) at
every commit from 8b6b648 to HEAD, so any render on this branch wrote the same key.

Fix: compare `key.md` (or the text of its Read result in the transcript) with `fp_acc_labelling_key()`
at extract, and record its sha in the audit.

### F6 (Low): a raw batch is not tied to its audit, and an accepted batch is overwritten silently

`extract` writes `raw/batch_NN.csv` and `.audit.json` without refusing when they already exist
(labels_import-model.R:124-125). A second transcript for an accepted batch replaces the first and
leaves no trace. The research text allows re-labelling a batch only after a refusal.

`import` reads both files but never compares them: it does not check `n_rows`, and no csv hash is
recorded. So a hand-edited raw csv flows into `labels_model.csv` and its hash.

Fix: refuse when `raw/batch_NN.csv` exists (FORCE to override, recorded in the audit), record
`sha256(batch_NN.csv)` in the audit, and have `import` verify it.
