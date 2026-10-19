# Code-check termination: enumeration of gpkg_backfill-split.R's writes (#53)

**Why an enumeration.** Rounds 2, 3 and 4 each found a defect inside an earlier round's fix, all in
one class: resuming an interrupted backfill.
- **Mechanism, as round 3 named it:** "the state of the artefact being modified is taken to say how
  far the operation got". That holds only if two things are true.
  - Each artefact's done-state can be produced only by its own completed, verified write.
  - The work list is read from something the run cannot change.
- **Round 4's residual:** that the backup is the live file's immediate predecessor. Nothing checked it.

A reviewer reporting Clean does not end that; only showing every member of the set satisfies both
conditions does.

The set is every write the script makes, found by grepping it and the functions it calls for
`st_write`, `st_delete`, `fp_prov_*`, `file.copy`, `file.rename`, `writeBin` and `unlink`. Rows 1–8
are round 4's table, re-derived after commit d34e3e3.

| # | write | re-run "done" predicate | only this write can make it true? | work list / input from |
|---|---|---|---|---|
| 1 | backup copies ×3 | `file.exists(dest)` | yes: `.part` → md5 → **refused if any layer carries `in_wsg`** → rename | literal list; pre-split now verified at creation and again on read (`split_any`) |
| 2 | scenario, `_by_`, classified layers | live layer present and has `in_wsg` | yes: one transaction per layer (kill test at 22 points, round 4) | work list: the backup. Input: **the live layer while it exists**, the backup's only once the live file has lost it |
| 3 | transition layer | live present and has `in_wsg` | yes, same | as #2. The reproduction gate (WKB, or key and area) compares against that input |
| 4 | bridge | bridge present and has `in_wsg` | yes: `in_wsg` reaches a bridge only through `fp_bridge_build` | `trans_expected` |
| 5 | stale bridge removal | bridge absent | yes | **now re-attempted with `attribute_by` unset too** (round 4's latent note) |
| 6–7 | composition table + sibling | columns present, and the sibling's digest and rows re-derive from the table | yes, jointly | backup or `do_trans` |
| 8 | `outputs.transition_patches` | none: compared every run, and nothing is written when equal | yes, by state | `trans_expected` |
| — | database | none: SELECT only | — | — |

**The predecessor premise (round 4, findings 1 and 2) is now checked on every write run.**
- The backup has no split layer.
- The backup's `provenance.json` equals the live one on `floodplain` and on `landcover[<scen>].inputs`.
  So no step 2 or step 3 has run since the backup, and a lost layer restored from it is the same run's
  layer.

**Evidence** (scratch copies under the session scratchpad; the real `data/` written only by the sweep):
- A new BACKUP dir over a half-split SLOC is refused, and the `.part` is removed.
- With the original backup, the lost `all_ff02` is re-split.
- A live `all_ff06` rewritten unsplit (10,000.8 ha, against the backup's 15,657.8 ha) is split from
  the live layer.
- A moved floodplain record is refused.
- A no-op write sweep over all 24 real areas left every file byte-identical (md5), with every premise
  holding: 24 of 24 rc=0, all byte-identical (2026-10-18 23:38–23:49 UTC); sloc re-checked after the row-5 edit.

**Hot journal.** The refusal names the recovery: one read-write open, never deleting the sidecar
(round 4, finding 3).

**DRY.** A dry run reads the same work list a write run would: the backup, when there is one
(round 4, finding 4).
