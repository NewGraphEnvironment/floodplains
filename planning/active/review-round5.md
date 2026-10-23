# Code-check round 5 (terminating): model labeller (#145), HEAD 4294453

## Checklist read

- `code-check.md`, Mechanisms, rule prose only (evidence tables skipped): A guard that fails toward pass;
  A fixture that cannot reach the failure mode (including "ask the parse tree for a symbol rather than the
  file for text"); A proxy is not the property; Verification that reads its own output; A guard's scope,
  escape hatches, and remedies (including "a remedy in the error message is code the caller will run");
  Written data outlives the fix.
- `code-check-r.md`, for the tools the fixes use:
  - `system2(stdout = TRUE)` warns rather than raising;
  - `strsplit()` drops a trailing empty field;
  - `nzchar(NA)`;
  - `match()` treats NA as a value;
  - `identical()` on reader results.
- `code-check-python.md`: not applicable.
- Round 4's enumeration (`review-round4.md`), walked place by place against the current code, plus
  every place 781dc2a added.

Method:
- I read every file in full at HEAD: `fp_accuracy.R` (model-labeller section), `labels_import-model.R`,
  `accuracy_estimate.R`, `review_render-sheets.R`, the model arms of `accuracy-check.R` and `labels_export.R`.
- I read `git show 781dc2a` and the 97dfc8f..781dc2a diff of `accuracy_estimate.R`.
- **Probe 1** checked the Read tool's result format against fp_acc_read_text. It is a Python tally over
  60 recent transcripts from OTHER projects; no floodplains transcript was read. On Claude Code 2.1.309,
  every Read result is a plain string of `N<TAB>line` lines. All 93 such results end on a numbered line,
  with no appended reminder.
- **Probe 2** reproduced Finding 1. It sourced `fp_accuracy.R` from a detached worktree and ran the guards
  in a throwaway `git init` repository under tempdir. The worktree has since been removed.
- Nothing under `data/necr/accuracy/model/` was read, and nothing under `data/` or `reference/` was written.

## Enumeration (place | sound/unsound | file:line)

Round 4's 40 places, against the current code:

| # | place | verdict | where |
|---|---|---|---|
| 1 | Gate trigger (committed model hash, or a `model:` reviewer) | sound. `fp_acc_labels_hashed` returns FALSE only when the hash file is absent, and it is committed for NECR | accuracy_estimate.R:74-76; fp_accuracy.R:1105-1110 |
| 2 | B complete (`setequal` with the subset) | sound | fp_accuracy.R:821-829; accuracy_estimate.R:79; labels_import-model.R:194-195 |
| 3 | B frozen | **unsound** (Finding 1). The publish side reads "is this a first publish?" from the working tree only. The estimate side accepts a freeze that was rewritten and committed | fp_accuracy.R:1112-1125; labels_import-model.R:208, :214; accuracy_estimate.R:81 |
| 4 | publish: B and the model hash tracked and identical to HEAD | sound | labels_import-model.R:199-200; fp_accuracy.R:1092-1094 |
| 5 | publish: `labels_model.csv` and any existing labels.csv equal the hash; the copy is checked | sound | labels_import-model.R:205-211 |
| 6 | estimate: labels.csv against the hash | sound, and now behavioural | fp_accuracy.R:1105-1110; accuracy_estimate.R:75 |
| 7 | extract: the first user turn is the batch prompt exactly | sound (unchanged). No user turn errors, which fails closed | labels_import-model.R:74-78 |
| 8 | extract: every wanted sheet Read with a clean result | sound | fp_accuracy.R:1013-1019; labels_import-model.R:119 |
| 9 | extract: the key | **sound** (round 4 F4 closed). key.md on disk must equal the research key, and so must the TEXT of a clean Read of key.md in the transcript. A partial Read (offset/limit) or another version's line-number format reads FALSE and refuses, which fails closed | labels_import-model.R:122-129; fp_accuracy.R:1139-1144 |
| 10 | Read paired with its result by `tool_use_id` | sound in practice (unchanged NA-matches-NA note) | labels_import-model.R:102-105 |
| 11 | Transcript audit: own-batch sheets and key.md only | sound | fp_accuracy.R:1001-1006; labels_import-model.R:116 |
| 12 | Model id: one per transcript, one across batches | sound | labels_import-model.R:81-84, :169-170 |
| 13 | Raw csv against its audit | sound. A crash between the csv write and the audit write leaves a stale or missing audit, and import refuses | labels_import-model.R:160-162; fp_accuracy.R:1129-1130 |
| 14 | import maps through the current `sheet_map.csv` | sound. Each sheet's bytes are bound to the audit, and a re-render moves them | labels_import-model.R:172-175 |
| 15 | import: role "a" | sound | labels_import-model.R:176-178 |
| 16 | import refuses an existing hash unless `FORCE=1` | sound. A deleted-then-rewritten hash must be re-committed, and once B is committed that fails the ancestor check (place N8) | labels_import-model.R:181-185 |
| 17 | Render refuses while `raw/` or `transcripts/` hold anything | sound as a convenience | review_render-sheets.R:41-44 |
| 18 | Render: cells.gpkg against the key | sound | review_render-sheets.R:48-52 |
| 19 | Render: map, key and record removed before the first sheet | sound | review_render-sheets.R:128-129 |
| 20 | `fp_acc_sheet_dir_check` | sound | fp_accuracy.R:965-980 |
| 21 | `fp_acc_sheet_title_ok` | sound | fp_accuracy.R:941-945 |
| 22 | `fp_acc_model_wc` | sound | fp_accuracy.R:1023-1046 |
| 23 | `fp_acc_labels_frame` | sound | fp_accuracy.R:396-425 |
| 24 | `fp_acc_second_stable` | sound | fp_accuracy.R:761-779 |
| 25 | B design check | sound | accuracy_estimate.R:67-71 |
| 26 | Gate abstention | sound. A is whole, because it is hash-bound and role "a" | fp_accuracy.R:831-840 |
| 27 | Reply: the last block with a csv fence | acceptable (unchanged) | labels_import-model.R:109-115; fp_accuracy.R:985-997 |
| 28 | accuracy-check arms | **sound for the functions**: behavioural, and the mutation run went 9/9 red. One proxy remains in the wiring arm, see Note A | accuracy-check.R:542-591 |
| N1 | `fp_acc_freeze` (write when absent, pass on the same hash, refuse another; an empty file errors) | sound as a function. Its caller is Finding 1 | fp_accuracy.R:1050-1059 |
| N2 | `fp_acc_image_matches` | sound. Grey, 2-channel, resized or unknown media types give FALSE or an error | fp_accuracy.R:1068-1077 |
| N3 | `fp_acc_b64_sha256` | sound (used by the arm only) | fp_accuracy.R:1067 |
| N4 | extract: each wanted sheet matches the image seen | **sound** (round 4 F3 closed). `moved` excludes `unread` and sits inside the refusal branch, so the `rejected/` record keeps `unread_files`, `moved_sheets` and `key_text_seen` | labels_import-model.R:130-139, :149-158 |
| N5 | extract refuses to overwrite an accepted batch | sound | labels_import-model.R:140-142 |
| N6 | audit records `key_sha256`, `sheet_sha256` and `csv_sha256` | sound. `sheet_sha256` is meaningful only on acceptance, which requires every sheet to be seen | labels_import-model.R:144-148, :161 |
| N7 | import re-verifies csv, key and sheets per batch. A pre-fix audit (NULL field) fails closed | sound | labels_import-model.R:172; fp_accuracy.R:1127-1136 |
| N8 | publish: the hash's last commit is a strict ancestor of B's first add | sound, with a behavioural arm. Git failure gives empty output, which refuses. Squash merges and side-branch adds made before the hash commit both refuse, which fails closed | fp_accuracy.R:1096-1101; labels_import-model.R:203-204 |
| N9 | publish writes the freeze after the copy | **unsound** (Finding 1) | labels_import-model.R:208-214 |
| N10 | estimate: labels.csv against the hash; the gate | sound, apart from the B freeze (Finding 1) | accuracy_estimate.R:74-81 |
| N11 | Render guard extended to `transcripts/` | sound as a convenience | review_render-sheets.R:41-44 |
| N12 | Arms for freeze and image matching | sound (behavioural) | accuracy-check.R:521-541 |

Places 781dc2a added:

| # | place | verdict | where |
|---|---|---|---|
| M1 | `fp_acc_sha_file` | sound. An empty file errors, which fails closed | fp_accuracy.R:1083 |
| M2 | `fp_acc_git` (shQuote'd repo and path; `status = TRUE` returns the exit code; output mode returns `character(0)` on failure) | sound. A missing git gives 127 → FALSE | fp_accuracy.R:1086-1089 |
| M3 | `fp_acc_git_committed` (`ls-files --error-unmatch` and `diff --quiet HEAD`) | sound for what it asserts: staged-only, untracked and modified files all fail. It does not assert "never rewritten", which is Finding 1's estimate half | fp_accuracy.R:1092-1094 |
| M4 | `fp_acc_git_committed_before` | sound. A twice-added B takes the oldest add, which is stricter | fp_accuracy.R:1096-1101 |
| M5 | `fp_acc_labels_hashed` | sound | fp_accuracy.R:1105-1110 |
| M6 | `fp_acc_b_frozen` (the freeze must exist, be committed and match B) | **unsound**: a freeze rewritten by a second publish and then committed passes (Finding 1) | fp_accuracy.R:1112-1118 |
| M7 | `fp_acc_publish_first` | **unsound**: it reads labels.csv's presence on disk, an untracked file at that moment, so absence again reads as never-set (Finding 1) | fp_accuracy.R:1121-1125 |
| M8 | `fp_acc_batch_verify` | sound | fp_accuracy.R:1127-1136 |
| M9 | `fp_acc_read_text` | sound against the format measured on 2.1.309 (Probe 1). A leading-space format from older versions would refuse, not pass | fp_accuracy.R:1139-1144 |
| M10 | extract `key_seen` | sound | labels_import-model.R:125-129 |
| M11 | the `unread`/`moved` split | sound | labels_import-model.R:137-139 |
| M12 | Every new guard called on the paths that need it: the estimate calls `labels_hashed` and `b_frozen`; publish calls `committed`, `committed_before`, `publish_first` and `freeze`; import calls `batch_verify`; extract calls `read_text`. No other script reads `labels_b.csv` or a model `labels.csv` (`sample_draw-pilot.R:114` only refuses to redraw over them) | sound | as listed |
| M13 | Throwaway-repo arms. A commit that fails in the temp repo (a global hook or gpgsign) turns the positive arms red, which fails loud | sound | accuracy-check.R:570-586 |

## Findings

### Finding 1 (Medium): B's freeze can still be re-written by a re-run of publish. "Is this a first publish?" is read from an untracked file, and the estimate accepts a re-written freeze once it is committed

Round 4's F1 fix keys "not a first publish" on `labels.csv` existing on disk (fp_accuracy.R:1121-1125).
At the moment that matters, labels.csv is untracked, exactly as the freeze was:
- publish writes it together with the freeze;
- its message asks for both to be committed;
- nothing requires labels.csv to be committed before the estimate.

On a second checkout where neither was committed, or after a `git clean` / `git stash -u`, both files are
absent and publish treats the run as a first publish. The estimate side cannot catch this:
`fp_acc_b_frozen` requires the freeze committed and matching B, never that it is the freeze written
first. Its own remedy text ("missing or not committed") points the person at committing the re-written one.

Reproduced (Probe 2: a throwaway git repo, the guards called exactly as publish and the estimate call them):

```
--- variant A: both outputs left untracked (or another checkout), B edited after seeing labels.csv
publish PASSED (re-froze)
estimate's B-freeze guard PASSED on the edited B
freeze now holds edited B: TRUE  original B: FALSE
--- variant B: both committed, then git rm both and re-publish
publish PASSED (re-froze)
estimate's B-freeze guard PASSED
commits touching the freeze: 3
```

Variant A needs no history edit:
1. Publish on machine 1; the person reads labels.csv.
2. The person edits `labels_b.csv` toward it and commits.
3. Publish runs on a checkout without the two untracked files, with the gitignored model data synced.

Every publish guard passes:
- B is complete, tracked and clean;
- the hash's commit precedes B's first add;
- `labels_model.csv` matches the hash;
- labels.csv and the freeze are both absent.

The estimate then gates against the edited B.

Variant B leaves a trace in git (the freeze path has 3 commits), but nothing reads that trace.

Mechanism: the same as rounds 3 and 4. The discriminator for the B freeze is state that exists only on
disk (or a history git lets you append to), so a re-run plus an absence makes the two records agree.

Fix (any one closes variant B; (a) and (b) together close variant A up to an unpushed commit):
- (a) **Two-phase publish.** The first run writes `labels_b.sha256` and stops: "commit it, then run
  publish again". The second run requires the freeze committed and matching B, and only then writes
  labels.csv. labels.csv then never exists anywhere without a committed freeze before it.
- (b) **Decide "first publish" from history, not disk.** Refuse when
  `git log --all --format=%H -- reference/<area>/labels_b.sha256 reference/<area>/labels.csv` is
  non-empty and the freeze is absent.
- (c) **In `fp_acc_b_frozen`, require the freeze never rewritten.** Exactly one commit touches it
  (`git log --format=%H -- <freeze>` has length 1). Optionally, also require that commit to be an
  ancestor of (or equal to) the first commit adding labels.csv.

Add a must-fail arm for each, in the throwaway repo, using variants A and B above.

Residual, stated rather than fixed: a freeze committed on machine 1 and never pushed cannot be seen from
machine 2 by any of these. That is inherent to a local freeze; say so in the publish message.

## Note A (not a defect; test strength): the wiring arm is a text grep

accuracy-check.R:588-591 asserts that the scripts call the guards by `grepl("fp_acc_b_frozen(", ...)`
and its siblings. Deleting a call line turns it red. Commenting the call out, or moving it under a branch
that never runs, leaves it green: a comment satisfies a grep. Today no comment in either script contains
those call strings, so the arm holds as written. Parsing (`getParseData()`, token `SYMBOL_FUNCTION_CALL`)
would close it.

## Verdict

**Not clean: one Medium (Finding 1).** Round 4's other findings are closed:
- F2: behavioural arms; mutation 9/9 red;
- F3: the unread/moved split and the refusal record;
- F4: the key text from the transcript.

No defect was found in `fp_acc_git`, `fp_acc_git_committed`, `fp_acc_git_committed_before`,
`fp_acc_labels_hashed`, `fp_acc_batch_verify`, `fp_acc_read_text` or the extract changes. Finding 1 is
the round-3/round-4 mechanism once more, through the fix's own discriminator. With (a) and (c), the B
freeze no longer rests on a working-tree fact.
