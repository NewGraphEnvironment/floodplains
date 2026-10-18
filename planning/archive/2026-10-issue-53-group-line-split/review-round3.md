# Review round 3: branch 53-floodplains-cross-watershed-group-bounda (#53, #138)

**Scope.** The diff `57e1a9a...HEAD` (fda228a) from review-prompt-round3.md. I read every changed file
from disk, and also the unchanged callers and readers of every changed function (accuracy module,
habitat join, run_region, review_build-qgis, channel probe, composition_build, provenance-check 7c).

**What I ran.** Everything was read-only on the repo and `data/`, and every write went to the
scratchpad. `git status` was the same before and after.
- The offline checks on HEAD: `wsg_split-check.R`, `composition-check.R` and `disturbance-check.R`.
  All three print ALL PASS.
- A WKB comparison of the backed-up pre-split scenario layer against `fl_valley_poly()` of the
  floodplain raster, on sloc, kisp, larl, pcea, neexdzii (`co_ff04`) and dunc (the plan review). This
  tests 03's AOI claim. The geometry is identical in native CRS and in EPSG:4326 in all six.
- Two kill tests in the scratchpad: one on the backup copy step, one on `st_write(delete_layer = TRUE)`.
  They are described under the findings.

## Findings

- **[severity: fragile]** scripts/floodplain_lcc/gpkg_backfill-split.R:203-209: **the backup's resume
  predicate is "the file exists"**, so a backup that never finished is kept forever and nothing
  verifies it.
  - **The defect.** The loop copies each file and checks its md5. On a later run,
    `if (file.exists(dest)) { message("backup kept"); next }` skips both the copy and the md5 check.
    Three ways to leave a bad `dest`:
    - a run killed during `file.copy()`;
    - `file.copy()` failing part way (disk full), which hits `stop("backup failed")`;
    - the md5 check firing, which hits `stop("backup differs")` and leaves the differing copy behind.
  - **What happens next.** The re-run reports "backup kept: ..." and goes on to rewrite the published
    layers. The only rollback it promised is now a truncated or wrong file.
  - **Reproduced** in the scratchpad with the same code shape:
    - a 1.5 GB "gpkg", copy killed after 0.6 s, left a 1,153,826,816-byte `dest`;
    - the second run printed `backup kept: bk/area/floodplain_landcover.gpkg`;
    - `cmp` said the two files differ.
  - **Size of the window.** Real files are 78-141 MB, so the kill window is short. The two `stop()`
    paths are not timing-dependent: one firing is enough to poison every later run.
  - **The same block skips a convention check.** It never checks for `-journal`, `-wal` or `-shm`
    sidecars or for WAL mode before a byte copy of the main file, which code-check-spatial.md
    ("Restoring a GeoPackage from a copy") requires. None exist on disk today (checked).
  - **Fix.** Copy to `<dest>.part`, verify the md5, then `file.rename()` and check its return, as
    `fp_prov_write()` does. Then a `dest` that exists is always a complete, verified copy. Refuse a
    source that has sidecars or a WAL-mode header.

- **[severity: fragile]** scripts/floodplain_lcc/gpkg_backfill-split.R:95-97, :111, :168, :227: **the
  to-do list is read from the file the run is rewriting**, so a layer lost mid-write drops off it.
  - **The defect.** `sf::st_write(..., delete_layer = TRUE)` deletes the layer in its own commit and
    writes the replacement in a later one. A run killed between the two leaves a hot journal whose
    rollback removes the layer entirely.
  - **Reproduced** in the scratchpad: a gpkg with `all_ff02` and `all_ff04`, `all_ff04` rewritten with
    300,000 features, killed 1.5 s in. Once the journal was rolled back, `st_layers()` listed only
    `all_ff02`.
  - **The re-run cannot see it.** It builds `split_lyrs` from `sf::st_layers(fpg)` / `(lcg)` on the
    live file. A lost scenario, `_by_` or classified layer is simply not listed. A lost transition
    layer takes the "absent" branch (:168), and `fp_prov_set_outputs` is skipped because it is gated on
    the layer's presence (:227). The run ends `Done: <area>`, which breaks the header's promise that
    "a run killed half way is finished by running it again".
  - **Not silent at first.** The first re-run fails loudly: GDAL's read-only `st_layers()` refuses a
    hot journal ("attempt to write a readonly database"). It becomes silent once anything opens the
    file for update and rolls the journal back, for example QGIS, `sqlite3`, or any `st_write`.
  - **What still catches some of it.** provenance-check 7c catches a lost classified or transition
    layer, and composition-check errors on a lost primary scenario layer. Nothing catches a lost
    `all_ff02`/`all_ff06` or `_by_` layer: `wsg_split-check.R` iterates only the layers it finds.
  - **Recoverable**, from the backup, as long as finding 1 did not also happen.
  - **Fix.** Take the expected layer set from the backup copy, which predates every write and which
    the run never modifies. Every backup layer matching the patterns must exist in the live file; a
    missing one is re-split from the backup copy, or the run refuses and names it.

## The mechanism

**Each consumer leaned on a property that the old structure guaranteed by construction, and the
diff took the construction away.** Before #53:
- a step wrote one artefact;
- a script's only write was its last act;
- a module lived in one file;
- a transition row was a patch.

So "this artefact is present", "this check came before the write", "this file is sourced" and "sum
the rows" were each true without anyone checking them. #53 raised every one of those counts:
- the bridge and the composition are second writes inside a step;
- the backfill writes before its last check;
- the step code now spans `fp_wsg.R` and `fp_lulc_vectors.R`;
- a row is a piece.

Each consumer kept the old assumption, and the earlier rounds found one consumer at a time.

For the resume class, the shared assumption has a precise form: **the state of the artefact being
modified tells you how far the operation got.** That only holds when each artefact's "done" can be
produced only by that artefact's own completed and verified write, and when the work list comes from
something the run cannot change. All four resume instances so far break it:
- round 1: the bridge was decided from the transition layer;
- round 2: the composition was decided from the table's columns;
- this round: the backup was decided by its presence, and the to-do list was read from the live file.

## Enumeration

**Every write and its resume predicate**
| write | resume predicate | sound? |
|---|---|---|
| backfill: backup copies | `file.exists(dest)` | **no**, finding 1 |
| backfill: scenario, `_by_` and classified layers | live `st_layers` grep + `has_col(in_wsg)` | yes, except for a layer lost mid-write (finding 2) |
| backfill: transition layer | live presence + `!has_col(in_wsg)` | same hole as the row above, finding 2 |
| backfill: bridge | its own state: absent, or lacks `in_wsg` (round 1 fix) | yes. A bridge lost mid-write is absent, so it is rebuilt |
| backfill: composition table + sibling | the columns, plus the sibling's digest and row count re-derived from the table (round 2 fix) | yes. A table lost mid-write is absent, so it is rebuilt while the transition layer exists |
| backfill: `outputs.transition_patches` | layer rows on disk, every run; `fp_prov_write` is temp + rename, and the repair restores the bytes on a mismatch | yes |
| step 2 / step 3 | none of their own; they re-run whole. run_region's marker ordering is unchanged | yes. run_region's cache does not know about #53, but every split-aware reader branches on the `in_wsg` column, and an unsplit area is consistent with itself |
| attribute_tag.R | none claimed; `_by_`, then `fp_write_bridge` (write or remove) | yes |
| composition_build.R | none claimed; premise, then build | yes |

**Every refusal, and whether a write comes before it**
| site | verdict |
|---|---|
| backfill | Every data refusal comes before the backup and the writes: conservation, keys, areas, WKB, cause columns, `fp_composition_premise`, `fp_prov_outputs_premise`. After the writes come only verifiers: the feature count; `fp_composition()`'s raster-derived refusals, whose inputs already built the previous table, and whose DB fetch failures `comp_current` makes resumable; and `fp_prov_set_outputs`, which re-runs the premise and restores the bytes. Sound. |
| attribute_tag.R | The transition-layer refusal comes before the DEM and the attribution (round 2 fix), and `fp_wsg_polygon` before the write. Sound. |
| step 3 | `fp_wsg_polygon(cfg)` comes after the raster writes. That is the same window the DB-dependent tagging already had, and the digest guards plus a step 3 re-run cover it. Not a new class. |
| step 2 | `fp_wsg_polygon` comes before the VCA. A `fp_wsg_split` failure between the raster write and the record write would be possible, but the 24-area sweep never saw one, and `st_write` already sat in that window. Not a new class. |
| `fp_composition_build` | The premise comes before the table write. Sound. |

**Every caller of a changed function, and what it sources.** All sound:
- `run_area.R`;
- `gpkg_backfill-split.R`;
- `attribute_tag.R` (`fp_region`, `fp_wsg`, `fp_lulc_vectors`; it does no tagging);
- `composition_build.R` (`fp_region`, `fp_wsg`);
- `floodplain_probe-whole-fwa.R` (round 1 fix);
- `wsg_split-check.R` (sources `fp_region` in its live section);
- `region_acceptance-report.R` (the summary needs nothing new);
- `provenance-check.R` (needs only the digest);
- `disturbance-check.R`, `fire_tag.R` and the accuracy scripts (`fp_disturbance.R`);
- `readme_functions.R` (needs only sf and yaml).

**Every reader of patch totals, or of a layer that is now split**
| reader | verdict |
|---|---|
| composition-check (1) | in_wsg branch, and the footprint compared exactly. Sound. |
| region_acceptance-report | patches and bridge filtered to in_wsg; the coverage table compares like with like. Sound. |
| fire_tag.R | the report and the context lines use `own`. Sound. |
| readme attribution figure | filtered. It is on `co_ff04`, which is unsplit, so the filter does nothing today. Sound. |
| `fp_fig_region_totals` | vector in_wsg, plus cell open water. Sound. |
| bridge-check | reconciles all pieces against the bridge, which also covers all pieces. Consistent. |
| disturbance-check | row-level checks; the snapshot comparison includes `in_wsg` as a core column. Sound. |
| provenance-check 7c | `transition_patches` = rows. Sound. |
| run_region post-verify km² | the whole delineation, as before. Sound. |
| habitat join and `fl_valley_join` | deduplicate per cell. Sound. |
| review_build-qgis | stable sort, same order on both sides. Sound. |
| sample_draw-pilot | NECR design on `ch_ff04` (#140, accepted). |
| publish layer | stac_floodplains_bc#98. |

**The author's enumeration of the backfill's writes** leaves out the backup copies (finding 1). It
also does not say that the layer list itself is derived from live state (finding 2). Its other five
entries are correct as described.

## Checked and fine

- **The round 2 fixes.** `comp_current()` requires the sibling's digest and row count. attribute_tag
  refuses before the DEM fetch and writes through `fp_write_bridge`. Both are in place.
- **No other own-species scenario has landcover.** The backfill touches only the primary scenario's
  landcover layers. No area holds landcover for a non-primary scenario of its own species, so nothing
  is left unsplit (checked over all 24 `provenance.json`).
- **The summary loop.** `fp_composition_summary`'s generic loop now also emits
  `wsg_ha`/`change_in_wsg_ha`, and `fp_composition_build`'s message uses them (seen in the write
  logs).

~/Projects/repo/floodplains/planning/active/review-round3.md
