# Code-check round 6 (terminating): model labeller (#145), HEAD 1f49f85

## Checklist read

- `code-check.md`, Mechanisms prose (evidence tables skipped):
  - A guard that fails toward pass ("what the guard reads", "where the guard sits", "which direction it fails");
  - A fixture that cannot reach the failure mode;
  - A proxy is not the property;
  - Verification that reads its own output;
  - A guard's scope, escape hatches, and remedies;
  - Written data outlives the fix.
- `code-check-r.md`: `system2(stdout = TRUE)` warns rather than raising (`fp_acc_git` output mode); `$`
  partial matching; `identical()` on reader results.
- `code-check-shell.md`: `git diff a..b` two-dot vs three-dot; `pwd` keeps typed case; a fetch can fail and
  still deliver. The git guards here are `git log` and `merge-base`, not `diff` ranges, so the two-dot rule
  does not apply. I tested path case by probe.
- `code-check-python.md`: not applicable.
- Round 5's 53 places (`review-round5.md`), walked against HEAD, plus every place c80d167 added.

Method:
- I read every file in full at HEAD: `fp_accuracy.R` (model-labeller section, 926-1159),
  `labels_import-model.R`, `accuracy_estimate.R`, `review_render-sheets.R`, the model arms of
  `accuracy-check.R` (500-619), `labels_export.R`, and research "Model labeller" (331-365).
- I read `git show c80d167` in full. `review_render-sheets.R` is unchanged since round 5.
- Probes 1-3 ran in a detached worktree (`git worktree add --detach` into the scratchpad, now removed). They
  sourced `fp_accuracy.R` and drove the guards in throwaway `git init` repositories under the scratchpad. Each
  probe called the guards in the order and with the arguments the scripts use.
- Nothing under `data/necr/accuracy/model/` was read. Nothing was written under `data/` or `reference/`.
- `git log --all -- reference/necr/labels*.csv labels_b.sha256` holds only `labels_model.sha256` (4072a24).
  So NECR has no `labels.csv` in history that would block `freeze`.

## Enumeration (place | sound/unsound | file:line)

Line numbers are HEAD's. Round 5's 53 places:

| # | place | verdict | where |
|---|---|---|---|
| 1 | Gate trigger (a model hash on disk, or a `model:` reviewer) | sound for what it reads. Its estimate half is Finding 1 | accuracy_estimate.R:74-76; fp_accuracy.R:1105-1110 |
| 2 | B complete | sound | fp_accuracy.R:821-829; accuracy_estimate.R:79; labels_import-model.R:201-202 |
| 3 | B frozen | **sound** (round 5 F1 closed). A re-run, a clean, a second checkout, `git rm` with a re-freeze, and a branch cut from before the freeze all refuse. That is `--all` history in `git_never`, plus the count. See Finding 2 for over-refusal | fp_accuracy.R:1122-1132, :1134-1139 |
| 4 | publish/freeze: B and the model hash committed as they stand | sound | labels_import-model.R:205-206 |
| 5 | `labels_model.csv` equals the hash; the copy is checked | sound | labels_import-model.R:209-210, :221-223 |
| 6 | estimate: labels.csv against the hash | sound as a comparison, but the hash it compares with is read from disk and never held to history (Finding 1) | accuracy_estimate.R:75; fp_accuracy.R:1105-1110 |
| 7 | extract: first user turn is the prompt exactly | sound | labels_import-model.R:78-82 |
| 8 | extract: every wanted sheet read cleanly | sound | fp_accuracy.R:1013-1019; labels_import-model.R:123 |
| 9 | extract: the key, on disk and as text seen | sound | labels_import-model.R:126-133; fp_accuracy.R:1154-1159 |
| 10 | Read paired with its result by `tool_use_id` | sound in practice | labels_import-model.R:106-109 |
| 11 | Transcript audit | sound | fp_accuracy.R:1001-1006; labels_import-model.R:120 |
| 12 | One model per transcript and across batches | sound | labels_import-model.R:85-88, :173-174 |
| 13 | Raw csv against its audit | sound | labels_import-model.R:164-166; fp_accuracy.R:1142-1151 |
| 14 | import maps through the current sheet map | sound | labels_import-model.R:176-179 |
| 15 | import: role "a" | sound | labels_import-model.R:180-182 |
| 16 | import refuses an existing hash unless `FORCE=1` | sound at publish (the hash's last commit must precede B's first add, :207). Not re-checked at the estimate (Finding 1) | labels_import-model.R:185-187 |
| 17 | Render refuses while `raw/` or `transcripts/` hold anything | sound as a convenience | review_render-sheets.R:41-44 |
| 18 | Render: cells.gpkg against the key | sound | review_render-sheets.R:48-52 |
| 19 | Render: map, key and record removed before the first sheet | sound | review_render-sheets.R:128-129 |
| 20 | `fp_acc_sheet_dir_check` | sound | fp_accuracy.R:965-980 |
| 21 | `fp_acc_sheet_title_ok` | sound | fp_accuracy.R:941-945 |
| 22 | `fp_acc_model_wc` | sound | fp_accuracy.R:1023-1046 |
| 23 | `fp_acc_labels_frame` | sound | fp_accuracy.R:396-425 |
| 24 | `fp_acc_second_stable` | sound | fp_accuracy.R:761-779 |
| 25 | B design check | sound | accuracy_estimate.R:67-71 |
| 26 | Gate abstention | sound | fp_accuracy.R:831-840 |
| 27 | Reply: the last block with a csv fence | acceptable | labels_import-model.R:113-119; fp_accuracy.R:985-997 |
| 28 | accuracy-check arms | sound for the functions. The wiring arm now reads the parse tree (see Note A) | accuracy-check.R:542-617 |
| N1 | `fp_acc_freeze` | sound. Its caller now runs it only after `git_never` and an on-disk check | fp_accuracy.R:1050-1059; labels_import-model.R:213-216 |
| N2 | `fp_acc_image_matches` | sound | fp_accuracy.R:1068-1077 |
| N3 | `fp_acc_b64_sha256` | sound (used by an arm only) | fp_accuracy.R:1067 |
| N4 | extract: each sheet matches the image seen | sound | labels_import-model.R:134-143, :153-162 |
| N5 | extract refuses to overwrite an accepted batch | sound | labels_import-model.R:144-146 |
| N6 | Audit records the key, sheet and csv hashes | sound | labels_import-model.R:148-152, :165 |
| N7 | import re-verifies each batch | sound | labels_import-model.R:176 |
| N8 | publish/freeze: the hash's last commit is a strict ancestor of B's first add | sound at publish and freeze. **Not called by the estimate** (Finding 1) | fp_accuracy.R:1096-1101; labels_import-model.R:207-208 |
| N9 | publish writes the freeze after the copy | **gone**. Freeze and publish are now separate subcommands, and publish needs a committed freeze | labels_import-model.R:212-225 |
| N10 | estimate: labels.csv against the hash; the gate | sound for B. The model-hash half is Finding 1 | accuracy_estimate.R:74-94 |
| N11 | Render guard extended to `transcripts/` | sound as a convenience | review_render-sheets.R:41-44 |
| N12 | Arms for freeze and image matching | sound | accuracy-check.R:521-541 |
| M1 | `fp_acc_sha_file` | sound | fp_accuracy.R:1083 |
| M2 | `fp_acc_git` | sound. On git failure, output mode returns `character(0)` and status mode returns FALSE. See Note B for `git_never` | fp_accuracy.R:1086-1089 |
| M3 | `fp_acc_git_committed` | sound. I probed path case (`core.ignorecase`), a symlinked root, and `/tmp` against `/private/tmp`: each resolves to the same file | fp_accuracy.R:1092-1094 |
| M4 | `fp_acc_git_committed_before` | sound. After a `--no-ff` merge to main, a fast-forward, and main merged into the feature, the default history simplification still resolves c1 to the freeze commit and c2 to the publish commit (probe 1, cases 3 and 3b). After a squash it reads c1 == c2, which refuses (Finding 2) | fp_accuracy.R:1096-1101 |
| M5 | `fp_acc_labels_hashed` | sound for what it asserts. Finding 1 | fp_accuracy.R:1105-1110 |
| M6 | `fp_acc_b_frozen` | **sound against false agreement** (round 5 F1 closed). It over-refuses with a wrong message (Finding 2) | fp_accuracy.R:1122-1132 |
| M7 | `fp_acc_publish_first` | **removed**. `fp_acc_git_never` replaces it | — |
| M8 | `fp_acc_batch_verify` | sound | fp_accuracy.R:1142-1151 |
| M9 | `fp_acc_read_text` | sound | fp_accuracy.R:1154-1159 |
| M10 | extract `key_seen` | sound | labels_import-model.R:129-133 |
| M11 | unread/moved split | sound | labels_import-model.R:141-143 |
| M12 | Every guard called where needed | **unsound in one place**: the estimate does not re-check the model hash's history (Finding 1). Otherwise sound. No other script reads `labels_b.sha256`. `labels_export.R:49` writes `labels.csv` only for a role-"a" working copy. The estimate's `labels_hashed` refuses that, and so does `freeze` (on disk, or in history) | as listed |
| M13 | Throwaway-repo arms | sound | accuracy-check.R:566-604 |

Places c80d167 added:

| # | place | verdict | where |
|---|---|---|---|
| P1 | `fp_acc_git_commits` (`log --all`) | sound against false agreement: `--all` can only add commits. Over-counts (Finding 2): a stash index commit is counted, and so is a squash or rebase duplicate while the old ref lives. A `stash -u` of the untracked freeze counts 0, because the untracked parent is pruned by simplification (probe 1) | fp_accuracy.R:1112 |
| P2 | `b_frozen`: exactly one commit | sound against re-freeze. Over-refusal and a wrong message: Finding 2 | fp_accuracy.R:1125-1126 |
| P3 | `b_frozen`: freeze before labels.csv's first add | sound. A freeze and labels.csv in the same commit gives c1 == c2, which refuses | fp_accuracy.R:1129-1130 |
| P4 | `fp_acc_git_never` | sound in the scripts' call order. On its own it fails toward pass on a git error (Note B) | fp_accuracy.R:1134-1139 |
| P5 | `freeze` subcommand (never in history, not on disk, then write) | sound. A re-run before the commit refuses and names the remedy. A re-run after the commit refuses through history | labels_import-model.R:212-217 |
| P6 | `publish` subcommand (`b_frozen`, then `git_never(labels.csv)`, then the checked copy) | sound. A re-run after labels.csv is committed refuses. A re-run before that rewrites the same bytes | labels_import-model.R:218-225 |
| P7 | estimate: `b_frozen` with labels.csv | sound. If labels.csv is untracked it refuses with "was not committed before labels.csv was", which is misleading but fails closed | accuracy_estimate.R:81 |
| P8 | estimate: labels.csv committed as it stands | sound | accuracy_estimate.R:82-83 |
| P9 | Wiring arm reads the parse tree | sound for call presence. It does not pin arguments (Note A) | accuracy-check.R:605-617 |
| P10 | History arms (second freeze, `git rm` then re-freeze, committed twice, freeze after labels.csv) | sound and behavioural | accuracy-check.R:578-602 |
| P11 | Research text, two-step freeze and limits | accurate. It omits the merge constraint (Finding 2) | research/landcover_accuracy.md:351-365 |

## Findings

### Finding 1 (Low): the estimate holds B's freeze to history but not the model's hash. A model relabel made after B was seen passes the gate once it is committed

The pre-registered order is: the model's hash is committed before B's labels. `publish` and `freeze` enforce it
(`fp_acc_git_committed_before(sha_file, fb)`, labels_import-model.R:207). The estimate, which is the gate,
checks only that labels.csv equals `labels_model.sha256` **as it is on disk** (accuracy_estimate.R:75). It
checks that labels.csv is committed (:82), but not that:
- the hash is committed;
- the hash's last commit precedes B's first add;
- labels.csv was committed only once.

c80d167 moved B's freeze onto history at both ends. The model side kept the publish-time check only, and a
later commit can rewrite labels.csv and the hash together.

Reproduced (probe 3). In a throwaway repository: hash, then B, then freeze, then publish, all through the
guards. Then labels.csv and the hash were replaced together in one later commit, which is what an `import`
with `FORCE=1` plus a hand copy produces. The estimate's guard sequence then passed:
`fp_acc_labels_hashed` TRUE, `fp_acc_b_frozen(..., labels.csv)` passed, and labels.csv was committed. The
candidate fixes both fire on the same repository:
- `fp_acc_git_committed_before(hf, bf)` is FALSE;
- `length(fp_acc_git_commits(labels.csv))` is 2.

It is Low because it needs `FORCE=1` and a copy by hand: `publish` refuses, since labels.csv is already in
history. No ordinary re-run reaches it. It is still the mechanism: the gate compares two records that one
re-run (import) plus a write can make agree. It is also exactly the property the pre-registration exists for:
model labels not tuned after B.

Fix, in accuracy_estimate.R inside the gate branch:
- `fp_acc_git_committed(repo, fmsha)`;
- `fp_acc_git_committed_before(repo, fmsha, fb)`;
- refuse unless `length(fp_acc_git_commits(repo, labels.csv)) == 1`.

Add a must-fail arm for the probe-3 sequence, and add `fp_acc_git_committed_before` and `fp_acc_git_commits` to
the estimate's wiring list.

### Finding 2 (Low): the "committed exactly once" count refuses some ordinary workflows with a message that blames B, and a squash-merge refuses permanently

`fp_acc_git_commits` counts every commit on any ref (`--all`) whose diff touches the path (fp_accuracy.R:1112,
:1125-1126). Probes 1 and 2:

- **A stash of the staged freeze.** Run `freeze`, `git add` the freeze, `git stash`, `git stash apply`, then
  commit. The stash's index commit counts, so `publish` refuses: "has been committed 2 times: B was re-frozen,
  so the freeze proves nothing". After `git stash drop`, publish passes. B was never re-frozen, and the message
  does not name the stash.
- **A squash-merge of the branch that carries the freeze and publish commits.** While the feature branch, or
  `origin/<branch>`, still exists, n = 2 and the estimate refuses with the same message. Once the branch is
  deleted, the freeze and labels.csv first appear in one squash commit, so c1 == c2 and the estimate refuses
  "was not committed before labels.csv was". That refusal is permanent, with no way forward short of rewriting
  main. The repo merges with merge commits (`/gh-pr-merge`), and a `--no-ff` merge, a fast-forward, and main
  merged into the feature all pass (probe 1). So this matters only if the GitHub squash button is used, which
  research's "history rewritten on purpose" does not obviously cover.

Neither case makes a false pass: over-counting only refuses. The defect is a correct run refused with a
message that points at the wrong cause, and in the squash case with no remedy.

Fix:
- Count with `git log --exclude=refs/stash --all` in `fp_acc_git_commits` when it serves the count in
  `b_frozen`, so a stash cannot inflate it. `--exclude` must precede `--all`. Keep the stash included for
  `git_never`, where counting more only makes it stricter.
- Make the n != 1 message list the commits with their refs (`--format='%h %D %s'`), and say that a stash,
  rebase or squash duplicate also counts.
- Add one line to research "Model labeller" and to the publish message: merge the branch that holds the
  freeze and labels.csv with a merge commit, never squash. A squash puts both into one commit, and the
  estimate can never pass after it.

## Notes (not defects)

- **Note A: the wiring arm pins call names, not arguments.** If accuracy_estimate.R:81 drops its fourth
  argument (labels.csv), every arm stays green, and the estimate no longer checks the freeze's order against
  labels.csv. Only `freeze`'s `git_never(c(fz, f))` would then stand behind it, and it does. Likewise,
  deleting one of the two `fp_acc_git_never` calls in labels_import-model.R (:213 or :220) leaves the name in
  the parse tree. The downstream count and order checks backstop both. A parse-tree check on the arguments,
  or a behavioural run of the subcommands in the throwaway repository, would close it.
- **Note B: `fp_acc_git_never` reads a git failure as "never".** `fp_acc_git` returns `character(0)` on any
  error. Probe 2: in a directory that is not a repository, `git_never` passes. That is unreachable from the
  scripts, because both `freeze` and `publish` first need `fp_acc_git_committed` on the same repository and
  path prefix, which is FALSE when git fails. Checking `attr(out, "status")` in `fp_acc_git` and stopping on
  a non-zero status other than an empty log would make the function safe on its own.
- **Out of reach, already stated:** `git reset --hard` or `git branch -D` over unpushed freeze or publish
  commits drops them from `--all`, so a re-freeze passes. That is history rewritten on purpose. If wanted,
  `git log --all --reflog` in `git_never` alone would catch this until reflog expiry, without making the
  count stricter.

## Verdict

**Not clean: two Low findings, no Medium.**
- Round 5's Finding 1 is closed. No ordinary workflow I could construct makes the B freeze agree falsely:
  a re-run, clean, stash (untracked or staged), second checkout, `git rm` with a re-freeze, a branch from
  before the freeze, a merge commit, a fast-forward, a worktree or a subdirectory, or a path in another case
  or through a symlink.
- Finding 1 is the same asymmetry on the model side: the estimate re-checks B's freeze against history, but
  not the model hash's.
- Finding 2 is over-refusal with a misleading message; the squash case is permanent.
