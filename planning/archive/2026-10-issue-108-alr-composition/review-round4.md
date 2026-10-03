# Code-check round 4 — #108 terminating enumeration (2026-10-02)

Reviewer: subagent, read-only on the repo, data/ and the DB. Values and writes were enumerated with
grep over the current files, not recalled: `cfg$`/`cfg[[`, `fp_prov_read`, `file.exists`,
`terra::rast`, `st_read`, `dft_class_table`, `dbConnect`/`dbGetQuery`/`.dst_fetch` and
`fp_raster_content_sha256` in `fp_composition_build()` (fp_composition.R:174-297), plus
`st_write|st_delete|unlink|saveRDS|fp_prov_set|fp_rast_write` in fp_composition.R,
composition_build.R and 03_lulc_classify.R. Live state was read with a read-only python parse of
every `data/*/provenance.json` and a listing of `data/*/lulc_summary*.rds`.

## Enumeration

### Values consumed

| # | value | source at build time | guarded before any write? | tied in provenance-check? |
|---|---|---|---|---|
| 1 | landcover[scen] record | provenance.json now (fp_composition.R:178) | yes, refused if absent (:180) | n/a, it is the reference |
| 2 | floodplain[scen] run time | provenance.json now | yes, but by ORDERING only (:189). Step 2 writes the tif (02:232) and the gpkg layer (02:238) before its record (02:247), so a step-2 re-run that dies inside `fp_prov_set` passes the ordering check with a new polygon | yes, indirectly: 7c re-derives `floodplain_content_sha256` from the tif (provenance-check.R:1736), which goes bad in every abort window of step 2. `viol_composition`'s floodplain arm does not fire there (both hashes are the old record's) |
| 3 | change_interval | area.yml now (composition_build.R:35-38) or cfg (step 3) | yes, against `lc_rec$inputs$change_interval` (:197-200) | yes (`viol_composition` arm) |
| 4 | classified endpoint tifs | `rasters/<scen>/classified_<yr>.tif` now | **yes**, content digest against the record (:211-216). Key shapes verified live: the record is keyed "2017".."2023", and the necr/bulk composition was recorded at 21:25Z, after the guard landed (file mtime 21:24Z) | yes |
| 5 | transition.tif, or its absence | file now | **yes** (:212, :217). An NA digest round-trips as JSON `null`, which `%\|\|% NA_character_` reads back as NA, so a zero-change record compares equal | yes |
| 6 | class names | raster RAT (PAM sidecar) + drift table now | refusal only for a code with no name | no (accepted in round 3) |
| 7 | floodplain polygon | floodplain.gpkg layer now (:232) | see row 2 | see row 2 |
| 8 | context overlays | DB + disturbance.yml now | n/a | self-recorded (accepted) |
| 9 | item keys wsg/species | transition layer, else the scenario prefix (composition_build.R:47-56); cfg in step 3 | n/a | the published layer (accepted). Read before the digest guard, but the guard still refuses before any write |
| 10 | `classes` refusal, `-1`/`-2` encoder refusals, lon/lat, overlay count | computed | yes, all inside `fp_composition()` before :270 | — |

### Writes, in order, and what can still fire after each

| write | refusals still reachable after it | state left | reported by |
|---|---|---|---|
| 03:138/158/165: tifs written or unlinked | the gpkg writes, disturbance DB, bridge, Pass 2 | new rasters; old record, old composition, old markers (pre-existing: the old saveRDS sat after Pass 2 too) | 7c classified re-derive. composition_build.R now **refuses** (rows 4/5) |
| 03:443: delete every `composition_<scen>_YYYY_YYYY` (stop at :445 if a delete fails) | :445, the unlink, and `fp_prov_set` | the old record names a table that is gone | 7c "names X, which is not in the gpkg" |
| 03:451: unlink both summaries | `fp_prov_set` (mtime, assert_unique/serializable) | as above, plus no marker | 7c (as above); run_region re-runs |
| 03:454: `fp_prov_set(landcover)`, which drops the old composition sibling | **every refusal in fp_composition_build**: ordering (only on clock skew), span and digests (cannot fire, since they were just written), the DB connect / `.dst_fetch` / `dbGetQuery` calls, OOM in `lapp`/`rasterize`, the class and encoder refusals | fresh landcover record, **no composition record, no table, no marker** | the run's own exit status; run_region (FAIL(run), then re-runs); composition-check.R live arm 1, if someone runs it. **7c prints `ok … no composition table yet (forward-only, #108)`** (the finding below) |
| fp_composition.R:270: `st_write` | `fp_prov_set_sibling`: lazy `value` (`fp_composition_digest`, `fp_toolchain`), no-entry, mtime, `fp_prov_write` asserts | table with no record | 7c "exists with no composition record" (the mtime case is accepted) |
| :272 sibling write | `fp_composition_summary` + the message in step 3 | composition complete, markers absent | run_region re-runs the group (time only) |
| 03:502-503: saveRDS markers | none | complete | — |

The `composition_build.R` path writes only :270 and :272, and never writes a marker.

### run_region resume key (`lulc_summary_<sp>_ff04.rds`)

- **Region areas.** `primary_scenario` is region-owned and set to `paste0(sp, "_ff04")`
  (run_region.R:116). Step 3 runs `cfg$primary_scenario` and writes/unlinks
  `lulc_summary_<scenario_id>.rds` (03:451, 03:502), so the key names the file step 3 writes.
- **morr.** A ch run (`FP_SPECIES=ch FP_PRIMARY_SCENARIO=ch_ff06`) unlinks and rewrites only
  `lulc_summary_ch_ff06.rds` and the shared file, never `lulc_summary_co_ff04.rds`. Round 3's
  masking sequence is closed.
- **neexdzii.** It is in no region file, so the key never applies.
- **Migration.** All 22 landcover entries on disk have their `lulc_summary_<key>.rds`, mcgr and
  pine included, so the first region run after merge caches exactly the groups it cached before.
- **Side effect, time only.** A `composition_build.R` repair leaves the marker absent, so the next
  region run redoes the whole group (fetch included), although 03:501 names the repair as the
  alternative.

## Findings

- **[fragile] scripts/floodplain_lcc/provenance-check.R:1867-1868, with
  scripts/floodplain_lcc/03_lulc_classify.R:454-497.** This is the one row that is neither guarded
  nor tied.
  - **The state.** Step 3 writes `landcover[<scen>]`, which drops the old composition sibling (the
    stale table was deleted at :443). It then calls `fp_composition_build`. Every refusal or abort
    in that function falls after the record write: DB down at the context fetch, OOM in
    `lapp`/`rasterize` (03:500 names both), or a deterministic refusal such as an unnamed class.
    Any of them leaves a **post-#108** entry with a fresh record, no composition and no table.
  - **How it is reported.** 7c reads that entry exactly like a pre-#108 one and prints `ok … no
    composition table yet (forward-only, #108)`. Round 3's fix (the per-scenario marker) makes
    region groups re-run. It does nothing for run_area-only areas (neexdzii, morr ch via
    `FP_SPECIES`), where the only signal is the exit code of the run that failed. That is round 1's
    fail-toward-pass outcome, now on the non-region path.
  - **A discriminator already on disk.** Step 3 unlinks `lulc_summary_<key>.rds` at :451 and
    rewrites it only at :502, after the composition. A landcover entry with no composition **and**
    no marker is therefore a step 3 that did not finish. A pre-#108 entry always has its marker:
    all 22 entries on disk do, measured.
  - **Fix.** In 7c's final `else`, `bad()` when `!file.exists(file.path(dd, paste0("lulc_summary_",
    e$key, ".rds")))`; keep `ok(forward-only)` otherwise. A `composition_build.R` repair does not
    trip it, because it adds the composition and the arm is only reached when there is none.
  - **Must-fail arm.** The same marker-absent, composition-absent state.
