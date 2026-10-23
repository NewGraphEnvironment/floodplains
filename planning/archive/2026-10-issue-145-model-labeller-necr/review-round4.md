# Code-check round 4 (terminating): model labeller (#145), HEAD 97dfc8f

## Checklist read

- `code-check.md`: the rule prose of the Mechanisms H3s, read for this round: A guard that fails toward
  pass; Verification that reads its own output; A guard's scope, escape hatches, and remedies; Restore
  the bug and prove the guard fires; Written data outlives the fix; One fact derived twice. Evidence
  tables skimmed only.
- `code-check-r.md`, for the tools the fixes use: `system2(stdout = TRUE)` warns rather than raising
  (status attribute); `identical()` on reader results versus file hashes; `nzchar(NA)`; `match()` and NA.
  (`file.copy()` returning FALSE is covered in code-check.md "Verification that reads its own output".)
- `code-check-python.md`: not applicable, because the diff holds no Python.
- Round 3's enumeration (`review-round3.md`), walked place by place against the current code.

Method: I read the current files in full and `git show 97dfc8f`. `accuracy-check.R` ran in a detached
worktree at HEAD and returned ALL PASS. A mutation run deleted three of the 97dfc8f guards; results
under Finding 2. Nothing under `data/necr/accuracy/model/` was read, and nothing under `data/` or
`reference/` was written. The worktree has been removed.

## Enumeration (place | sound/unsound | file:line)

Round 3's 28 places, against the current code:

| # | place | verdict | where |
|---|---|---|---|
| 1 | Gate trigger | **sound**. The presence of the committed hash file triggers the gate, and the reviewer prefix is only a second trigger | accuracy_estimate.R:74-79 |
| 2 | B complete (`setequal` with the subset) | sound (unchanged) | fp_accuracy.R:899-907; accuracy_estimate.R:82; labels_import-model.R:190 |
| 3 | B frozen: `labels_b.sha256` | **sound against a re-run of publish while the file exists. Unsound when the file is absent**: publish cannot tell "never frozen" from "freeze lost", and the file is never required to be committed (Finding 1) | fp_accuracy.R:1050-1059; labels_import-model.R:216; accuracy_estimate.R:84-87 |
| 4 | publish: B and the hash are tracked and clean | sound. The new ancestor check (N8) carries "committed before B" | labels_import-model.R:195-199 |
| 5 | publish: `labels_model.csv` and an existing labels.csv equal the hash; the copy is checked | sound | labels_import-model.R:208-213 |
| 6 | Estimate checks labels.csv against the hash | **sound**. The hash is read from disk. A `FORCE=1` re-import rewrites it, but labels.csv then differs and the estimate refuses | accuracy_estimate.R:75-78 |
| 7 | extract: first user turn equals `batch_prompt(b)` | sound for the prompt text. The prompt still names only reused paths, but the per-sheet image binding (N4) now ties the transcript to the render | labels_import-model.R:77 |
| 8 | extract: every wanted sheet Read with a clean result | sound, and backed by N4 | fp_accuracy.R:1013-1019; labels_import-model.R:116 |
| 9 | extract: key.md is the pre-registered key | **latent**. The check compares key.md on disk with the research key. Both are copies of one text, made by the render. The Read result in the transcript, which is what the agent saw, is not compared (Finding 4) | labels_import-model.R:119-120 |
| 10 | Read paired with its result by `tool_use_id` | sound in practice (unchanged). `match()`/`%in%` pair an NA id with an NA id, and `img_of` inherits this | labels_import-model.R:101-102 |
| 11 | Transcript audit: own-batch sheets and key.md only | sound | fp_accuracy.R:1001-1006 |
| 12 | Model id: one per transcript, one across batches | sound | labels_import-model.R:81-84, :157-158 |
| 13 | Raw csv against its audit | **sound**. `csv_sha256` is recorded right after the write and import re-verifies it. A crash between the csv write and the audit write leaves a mismatch, which refuses | labels_import-model.R:148-150, :162-163 |
| 14 | import maps through the current `sheet_map.csv` | **sound**. The map is not hashed. But each sheet's bytes are bound to the image the agent saw (extract) and to the audit (import), and a re-render with a new seed changes the bytes. A same-seed re-render gives the same map | labels_import-model.R:165-171 |
| 15 | import: role "a" | sound | labels_import-model.R:173 |
| 16 | import refuses an existing hash unless `FORCE=1` | sound. FORCE after B is caught by the ancestor check (N8) | labels_import-model.R:177-179 |
| 17 | Render refuses while `raw/` or `transcripts/` hold anything | sound as a convenience. The binding that matters is N4/N7, which holds even for transcripts kept outside `transcripts/` | review_render-sheets.R:41-44 |
| 18 | Render: cells.gpkg against the key | sound | review_render-sheets.R:48-52 |
| 19 | Render: map, key and record removed before the first sheet | sound | review_render-sheets.R:128-129 |
| 20 | `fp_acc_sheet_dir_check` | sound | fp_accuracy.R:965-981 |
| 21 | `fp_acc_sheet_title_ok` | sound | fp_accuracy.R:941-945 |
| 22 | `fp_acc_model_wc` | sound | fp_accuracy.R:1023-1047 |
| 23 | `fp_acc_labels_frame` | sound | fp_accuracy.R:396-425 |
| 24 | `fp_acc_second_stable` | sound | fp_accuracy.R:762-779 |
| 25 | B design check | sound | accuracy_estimate.R:67-71 |
| 26 | Gate abstention | **sound**. labels.csv is now bound to the hash, so A is whole | fp_accuracy.R:910-912 |
| 27 | Reply: last block with a csv fence | acceptable (unchanged) | labels_import-model.R:106-112 |
| 28 | accuracy-check grep arms | **proxies, now mutation-proven**. Three of 97dfc8f's guards can be deleted with ALL PASS (Finding 2) | accuracy-check.R:497-552 |

Places 97dfc8f added:

| # | place | verdict | where |
|---|---|---|---|
| N1 | `fp_acc_freeze`: write when absent, pass on the same hash, refuse another. An empty file errors (fail-closed) | sound as a function. Its caller's absent-file case is Finding 1 | fp_accuracy.R:1050-1059 |
| N2 | `fp_acc_image_matches`: identical bytes, or the same dimensions with mean abs RGB diff ≤ 0.01. An unknown media type, grey or resized image gives FALSE or an error | sound. A re-render needs every sheet in a batch to match; a single near-neighbour sheet is not enough | fp_accuracy.R:1067-1077 |
| N3 | `fp_acc_b64_sha256` | sound (used by the arm only) | fp_accuracy.R:1066 |
| N4 | extract: each wanted sheet matches an image the agent saw in its own clean Read | **sound** as a binding. **Regression in its placement**: it stops before the refusal branch (Finding 3) | labels_import-model.R:121-131 |
| N5 | extract refuses to overwrite an accepted batch | sound. FORCE is not recorded in the audit (note, not a defect: nothing is visible to bias a choice before B exists) | labels_import-model.R:132-134 |
| N6 | audit records `key_sha256`, `sheet_sha256` (the disk hashes N4 just matched) and `csv_sha256` | sound | labels_import-model.R:136-150 |
| N7 | import re-verifies csv, key and sheets per batch. A missing field (a pre-fix audit) fails closed | sound | labels_import-model.R:160-168 |
| N8 | publish: the hash's last commit is an ancestor of the first commit adding `labels_b.csv`, and they are not the same commit | sound. Git failure gives empty output, which refuses. A squash merge refuses, which fails closed. `tail` over `git log`'s date order assumes the oldest add prints last; that matters only for a twice-added `labels_b.csv` with clock skew, which is negligible | labels_import-model.R:200-207 |
| N9 | publish writes the freeze after the copy | see Finding 1 | labels_import-model.R:214-216 |
| N10 | estimate: labels.csv against the hash, and the gate triggered by the hash file | sound | accuracy_estimate.R:74-79 |
| N11 | Render guard extended to `transcripts/` | sound as a convenience (see 17) | review_render-sheets.R:41-44 |
| N12 | New arms: freeze (write, pass, refuse) and image matching (PNG, JPEG re-encode, a different image, a byte-only must-fail) | sound, because they are behavioural. The grep arms beside them are Finding 2 | accuracy-check.R:521-541 vs :542-552 |

## Findings

### Finding 1 (Medium): a missing `labels_b.sha256` reads as "never frozen", so re-running publish re-freezes an edited B. This is round 3's F1, through the absent file

`fp_acc_freeze` is write-once only while its file exists. Publish (labels_import-model.R:211-216) cannot
tell a first publish from a later one whose freeze file is gone. Nothing requires `labels_b.sha256` to
be committed:
- publish's message only says it was written;
- the estimate reads it from disk (accuracy_estimate.R:84-87);
- `reference/` has no ignore rule for it, so it sits untracked until someone commits it.

How a re-run produces a false agreement (traced by reading the code):
1. Publish on machine 1 writes labels.csv and `labels_b.sha256`. labels.csv is committed; the freeze
   is not.
2. The person sees labels.csv, edits `labels_b.csv` toward it, and commits the edit.
3. On a second checkout with the gitignored model data synced, or after the untracked freeze file is
   cleaned away, the estimate refuses because the freeze is missing. The obvious remedy is to run
   publish again.
4. Every publish check passes:
   - B is complete, tracked and clean;
   - the hash's commit is an ancestor of B's first add;
   - `labels_model.csv` and labels.csv both equal the hash.
5. `fp_acc_freeze` finds no file and writes the edited B's hash. The estimate then accepts the edited B.

**Fix:**
- The presence of labels.csv is the fact that tells the two cases apart. In publish, refuse when
  labels.csv already exists (or is tracked) and `labels_b.sha256` is absent.
- Require `labels_b.sha256` to be tracked and clean: in a second publish, and in the estimate's gate.
  Alternatively, have the estimate read the freeze from git (`git show <c>:reference/<area>/labels_b.sha256`
  at the commit that first added labels.csv) rather than from disk.

### Finding 2 (Low): the arms for three of 97dfc8f's guards stay green when the guards are deleted

The arms at accuracy-check.R:542-552 grep for a variable name or a message string. The mutation run
(detached worktree at HEAD, 2026-10-23 14:04Z) applied three changes together and got **ALL PASS**:
- deleted accuracy_estimate.R:75-78, the labels.csv-against-hash refusal (round 3's F2);
- deleted publish's `if (!before) stop(...)` (F4);
- turned import's csv-against-audit `stop` into `message` (F6).

Two arm names claim behaviour they do not test:
- "the estimate … checks labels.csv against it";
- "publish … requires the hash committed before B".

Round 3 place 28 named the class. The fixes added more members to it.

**Fix:** pull each predicate into a helper and give it a must-fail arm:
- labels.csv against the hash: a temp file pair;
- the ancestor check: a temp `git init` with the commits in each order;
- the audit check: an edited csv.

Alternatively, run the scripts against a temp `reference/`.

### Finding 3 (Low): the new image binding stops before extract's refusal branch, so an unread sheet is reported as a re-render and leaves no `rejected/` record

labels_import-model.R:129 stops before the refusal at :141. When a sheet was never read, or its Read
returned an error, `ids` is empty and `any(logical(0))` is FALSE. The sheet therefore lands in `moved`.

So since 97dfc8f:
- every batch refused for an unread or failed read stops with "… are not the images the agent saw … a
  re-render since the batch was labelled", which is the wrong cause;
- no `rejected/batch_NN_<ts>.json` is written. Before 97dfc8f the same transcript was refused with
  "N file(s) never read", and its record was kept.

It fails closed, but the diagnostic points the person at the render rather than the agent, and the
refusal record loses an entry.

**Fix:** compute `moved` only over sheets that are not in `unread`, and fold it into the refusal
condition, with its own count, rather than stopping early.

### Finding 4 (Low, latent): the key check compares two copies of one text, not what the agent read

The render writes key.md from `fp_acc_labelling_key()`, and extract compares key.md with
`fp_acc_labelling_key()` (labels_import-model.R:119). Both sides come from the research file as it
stands now. The transcript holds the key the agent actually saw (the text of its Read result for key.md),
and that text is never compared.

These steps would make the two sides agree falsely:
1. Agents label from the key as it was.
2. The `## Labelling key` section is edited.
3. The sheets are re-rendered with the same `RENDER_SEED`, with the transcripts kept outside
   `model/transcripts/`. The images still match, and key.md now holds the edited key.
4. Extract records the edited key as the one the batch was read under.

This needs an edit to pre-registered text, which git would show. The section is byte-identical on this
branch (round 3), so NECR is unaffected.

**Fix:** compare the Read result text for key.md in the transcript with `fp_acc_labelling_key()`.
Optionally, also pin the key's sha in `design.json` or in the pre-registration commit.

## Verdict

**Not clean: one Medium (Finding 1) and three Low.** Of round 3's six unsound places:
- F2, F3, F5 and F6 are closed: places 1, 6, 13, 14 and 26 are now sound, and 9 is latent only;
- F4 is closed by N8;
- F1 is closed only while the freeze file exists. Finding 1 is the same mechanism (a freeze written by a
  step that can run again), reached through the file's absence instead of its rewrite.

No defect was found in the new image comparison, the ancestor check or the per-batch audit hashes.
