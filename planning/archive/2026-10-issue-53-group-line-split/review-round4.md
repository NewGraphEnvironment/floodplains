# Review round 4: branch 53-floodplains-cross-watershed-group-bounda (#53, #138)

**Scope.** HEAD a2b72b0. I read `gpkg_backfill-split.R` in full from disk, plus everything it calls that
writes: `fp_lulc_vectors.R` (`fp_write_transition`, `fp_write_bridge`), `fp_composition.R` (premise and
build), `fp_provenance.R` (read, write, set, set_sibling, outputs_premise, set_outputs), `fp_wsg.R`, and
`fp_rast_cells`. I also read round 3's findings and the round-3 commit's own diff
(`git show a2b72b0`; it changed only the backfill). From the checklist I read the rules that bear on
this round: the three GeoPackage rules, "A guard's scope, escape hatches, and remedies", "Written data
outlives the fix" and "A preview flag is only safe if it previews".

**What I ran.** Nothing was written to the repo or to `data/`, and `git status` was the same before and
after.
- **Kill test of `sf::st_write(append = TRUE, delete_layer = TRUE)`** in the scratchpad: a 400,000-row
  layer carrying `in_wsg` written over a 10-row layer without it, killed (SIGKILL) at 22 points between
  1.0 s and 5.1 s. At every point the layer was either the old one or **absent** once the journal was
  rolled back. It was never present carrying `in_wsg` with partial or zero rows. A `-journal` was left
  behind from 2.2 s on.
- **The real script on a copy.** I copied the repo's `scripts/`, `config/` and `DESCRIPTION` to a temp
  root, then copied in `data/sloc` and a copy of `data/backup/20261018_wsg_split/sloc`. `here::here()`
  resolved to the temp root. Three runs against that copy are described under findings 1 and 2.
- **Read-only checks of every existing backup** (`file:...?mode=ro&immutable=1`): `quick_check`, the
  header journal-mode bytes, and the number of layers carrying `in_wsg`. I also compared each backup's
  `provenance.json` against the live one with jq.

## Findings

- **[severity: fragile]** scripts/floodplain_lcc/gpkg_backfill-split.R:113-121, :130-132, :149: **a
  BACKUP dir that is new for an area already partly backfilled makes a "pre-split" backup of the
  partly split file.** The work list is then read from that backup, so a layer the earlier run lost is
  silently not on it.
  - **The defect.** The kept-or-copy loop copies whatever the live files hold when `<dir>/<area>/` has
    no backup yet. Nothing checks that the copy is pre-split. Line 139's "the backup is not the
    pre-split one" refusal cannot fire here: the layers that are split in the live file are skipped at
    :136 before it is reached, and a lost layer is absent from both files.
  - **Reproduced** on the sloc copy. `all_ff02` was deleted from the live `floodplain.gpkg`, which is
    the state a kill mid-`delete_layer` write leaves once rolled back. A run with
    `BACKUP=<new dir>` printed every other layer "already split", "composition current", "Done: sloc"
    and exit 0. `all_ff02` was still missing afterwards.
  - **The same run against the original backup** printed `all_ff02 MISSING from the live file --
    re-split from the backup` and re-created it. Its attributes and WKB came out identical to the
    published layer. So the round-3 design works only when BACKUP names the original backup.
  - **A lost transition layer** goes the same way under a new dir. `trans_expected` becomes FALSE, the
    log reads "absent", and `fp_prov_set_outputs` is skipped.
  - **Why the trigger is realistic.** The header (:35) names a dated directory
    (`data/backup/20261018_wsg_split`). A re-run on another day under that day's date is the natural
    invocation, and so is a re-run after the backup dir was cleaned up. All 24 areas are already
    split, so any future run is a re-run of exactly this kind.
  - **Fix.** Before the `file.rename(part, dest)`, open the `.part` and refuse if any layer matching
    the work-list patterns (or `tlyr`) carries `in_wsg`. Unlink the `.part` and tell the operator to
    point BACKUP at the original backup. The check has to come before the rename: a refused copy left
    under the real name would be "backup kept" on the next run.

- **[severity: fragile]** scripts/floodplain_lcc/gpkg_backfill-split.R:138 (and :154): **the round-3 fix
  also moved the INPUT of a present-but-unsplit layer from the live file to the backup.** That is
  correct only if nothing has written the layer since the backup was taken, and nothing checks it. The
  backup is kept indefinitely by design, so the window has no end.
  - **Reproduced** on the sloc copy. I rewrote the live `all_ff06` as an unsplit layer of 10,000.77 ha,
    the state a later step-2 run by a pre-#53 checkout leaves. A run with the original backup printed
    `all_ff06 split 1 -> 2 rows, 137.5 ha outside` and `Done: sloc`. Afterwards the live layer was the
    backup's **15,657.75 ha**. The newer delineation was replaced without any message saying the input
    came from the backup.
  - **The code before round 3** read `x` from the live file and would have split the 10,000.77 ha
    layer.
  - **Who writes an unsplit layer after the backup.** `main`'s step 2 and step 3: this branch is
    unmerged, and both checkouts share `data/`. Any older checkout does too.
  - **What protects the transition, and what does not.** The reproduction gate refuses when
    `transition.tif` moved. The scenario, `_by_` and classified layers have no gate, so a step-2-only
    re-run is the silent case.
  - **The re-split of a lost layer** (finding 1's correct path) has the same exposure. If a later
    step-2 write loses a layer (not a backfill write), the next backfill resurrects the backup's older
    delineation.
  - **Round 3 widened the window.** It moved the backup ahead of every refusal, so a refused write run
    now leaves a kept backup. The remedies those refusals print ("Re-run step 3") then land newer
    content after it.
  - **Fix.** Read a layer that is present but unsplit from the live file, as before. Use the backup
    only for the work list and for absent layers. Also refuse unless the backed-up `provenance.json`
    (copied today and never read) carries the same `floodplain` section and the same `landcover[scen]`
    `inputs_hash` and `transition_content_sha256` as the live one.
  - **The guard would refuse none of today's areas.** I measured all 24: every backup's `floodplain`
    section and landcover inputs equal the live file's.

- **[severity: fragile]** scripts/floodplain_lcc/gpkg_backfill-split.R:107-109 (and the header claim at
  :28-30): **the remedy printed after an interrupted run names no action, and the obvious wrong action
  corrupts the file.**
  - **What a re-run sees.** A run killed during any `st_write` leaves a hot `-journal`; the kill test
    shows one for most of the write window. The re-run then refuses, correctly, with "Recover or close
    it before backfilling".
  - **What the operator is likely to do.** Delete the `-journal`. That keeps the half-written pages,
    and the file is corrupt.
  - **The right step.** Open the file read-write once (`sqlite3 <f> 'pragma quick_check'`). SQLite rolls
    the transaction back, the lost layer is absent, and the next run re-splits it from the backup. That
    sequence works: it is the `all_ff02` run above.
  - **The header is wrong.** It promises that a run killed half way "is finished by running it again".
    In fact it needs this manual step first.
  - **Fix.** Put the step in the message, together with "never delete the -journal". Correct the header.

- **[severity: fragile, low]** scripts/floodplain_lcc/gpkg_backfill-split.R:110-111: **`DRY=1` reads
  the work list from the live file, while the write run reads it from the backup**, so after an
  interrupted run the preview omits a lost layer that the real run would re-split. When BACKUP is set
  and `<dir>/<area>/` holds a backup, the dry run can read its list from it, read-only, so the preview
  and the run agree.

## The mechanism, and whether round 3 closed it

Round 3's form of the mechanism is **closed for the backfill's own interruptions**. Every done-state
the re-run reads can now be produced only by that artefact's own completed write:
- **GDAL layer writes are one transaction.** I measured this, and it is why `in_wsg` present means the
  write finished.
- **`fp_prov_write` and the backup** both write a temp file and rename it.
- **The composition sibling** can only match a table that the same build wrote.

The work list also now comes from a file the run does not change.

**What remains is the converse premise: the snapshot is taken to be the predecessor of the live file
it is merged into.** That needs two things, and neither is checked:
- **(a)** the snapshot was taken before any backfill write. Finding 1: nothing checks this when the dir
  is new.
- **(b)** nothing else has written the live file since. Finding 2: nothing checks this, and the backup
  is kept forever.

This is "Written data outlives the fix" in its persisted-claim form. The backup is persisted under a
name that claims "pre-split" and "current", and nothing verified either claim when it was written or
when it is reused. Both fixes verify the claim from the artefact itself: the `in_wsg` columns of the
`.part`, and the backed-up `provenance.json` against the live one.

## Enumeration: every write the backfill makes or calls

| # | write (site) | re-run "done" predicate | made true only by this write completing? | work list read from |
|---|---|---|---|---|
| 1 | backup copies x3 (:114-121) | `file.exists(dest)` | yes for copies made by this code (`.part`, md5, then a same-directory rename) | literal file list. **"Pre-split" is not verified (finding 1)** |
| 2 | scenario, `_by_` and classified layers (:245) | live layer present AND has `in_wsg` | yes: layer creation and inserts are one transaction (kill test, 22 points) | backup. Sound only under (a). **Input is the backup even when the live layer exists (finding 2)** |
| 3 | transition layer (`fp_write_transition`:142) | live present AND has `in_wsg` | yes, same transaction | backup (`trans_expected`). `old` is from the backup (finding 2; the reproduction gate covers a moved tif) |
| 4 | bridge (`fp_write_bridge`:171, via #3 or :253) | bridge present AND has `in_wsg` | yes: `in_wsg` reaches a bridge only through `fp_bridge_build` over a split layer, in one transaction | `trans_expected` and `attribute_by`. It reads the live split transition layer and the `_by_` layer #2 wrote earlier in the same run |
| 5 | stale bridge removal (`fp_write_bridge`:183) | bridge absent | yes | **not re-attempted when `attribute_by` is NULL** (`need_bridge` requires it). A kill between #3 and the removal leaves a pre-split bridge forever. Latent: every `config/*/area.yml` sets `attribute_by` today |
| 6 | composition table (`fp_composition_build`:318) | `comp_current()`: the columns, plus the sibling's digest and rows re-derived from the table | yes, together with #7 | backup (`clyr` or `tlyr`) or `do_trans`. It reads the live scenario layer, which #2 has already rewritten in this run |
| 7 | composition sibling (`fp_prov_set_sibling`, temp + rename) | as #6 | yes: a sibling that matches the table can only come from the build that wrote the table | as #6 |
| 8 | `outputs.transition_patches` (`fp_prov_set_outputs`) | none: it runs every time `trans_expected` is TRUE, compares, and writes nothing when equal | yes, by state (the row count on disk) | backup (`trans_expected`). Its restore is a non-atomic `writeBin`, the same shape as the existing `fp_prov_restamp`; out of scope |
| — | database | none written: `fp_disturbance_tag`, `fp_wsg_polygon` and the overlay reads only SELECT (grep) | — | — |

**Refusals against writes.** All data refusals still come before the first layer write (:244), and the
premises run at :238-239. After the writes come only verifiers: the feature counts, the final sweep
:261-264, and `fp_prov_set_outputs`, which restores the bytes. Round 3 moved the backup ahead of the
refusals. That is harmless by itself, since a refused run leaves a true copy, but it is the widening
described in finding 2.

## Checked and fine

- **The round-3 backup construction.** `.part`, md5, then rename, with the rename checked. A stale
  `.part` is unlinked first. The source sidecar check comes before the first read of either gpkg; the
  only earlier read is `subbasins.gpkg`.
- **The existing backups were made by the pre-fix code, and they are complete.** All 24 under
  `data/backup/20261018_wsg_split/` pass `quick_check` read-only. Their header bytes 18-19 are `01 01`
  (rollback journal), and not one layer carries `in_wsg`, so they are pre-split.
  `dunc_after_backfill/` sits under the same root and holds split files (4 and 6 layers with `in_wsg`).
  No area is named that, so the script never reads it.
- **DUNC carries no `wsg_split` repair because its step 3 was re-run under the new code**
  (landcover run 2026-10-18T22:37:59Z, 1,446 pieces, 147 outside). It was not missed by the backfill.
- **The lost-layer recovery path, when BACKUP is the original.** It re-split `all_ff02`
  byte-identical to the published layer, and `fp_prov_set_outputs` reported "already as given".
- **The `need_bridge` rewrite.** It dropped the `has_col(tlyr, in_wsg)` clause, but `!do_trans` together
  with `trans_expected` implies that clause.
- **`fp_rast_cells` over split scenario pieces** rasterises once with `touches = FALSE`, so a cell is
  never counted twice by the composition.

~/Projects/repo/floodplains/planning/active/review-round4.md
