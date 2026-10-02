# Code-check round 3, reviewer p4 (#103 staged diff): enumerating the "rows in hand → whole set" mechanism

This is a terminating enumeration, not an open pass. It covers every site in the staged diff where code
decides something about a whole (a set of points, frames, tiles, strata, cells, columns, themes, layers,
files or years) from a subset, a sample, a cache, a count, a name or a return code.

**How it was checked.** All probes were read-only or ran on scratchpad copies.
- No pipeline script was run against repo paths.
- Remote orthophoto reads went through a copy of the native VRT in the scratchpad, with
  `GDAL_PAM_ENABLED=NO`. Every URL was redacted from the output.
- `accuracy-check.R` reports **ALL PASS**. `git status` is unchanged, and no `.aux.xml`, `-wal` or
  `-shm` was left in the project.

## Enumeration

| # | site | the whole being judged | evidence actually read | holds? |
|---|------|------------------------|------------------------|--------|
| 1 | fp_accuracy.R:125-172 `fp_acc_strata` (prior) | which footprint cells are stratum 19 | `chg & !is.na(prior)`, cell level, placed after wetland and before causes | **yes**. Only published change takes 19. Precedence is pinned by accuracy-check 107-133. |
| 2 | fp_accuracy.R:138-141 stray check (causes only) | the cause flags come from the same run as transition.tif | per-cause count of cells off `chg` | **yes**. prior is cell level by design, so it has no stray check. |
| 3 | fp_accuracy.R:112-116 `fp_acc_strata_table` | the set of strata the design can hold | `prior = !is.null(prior)` | **yes**. 19 is in the table whenever prior is given. A drawn-empty 19 is handled by row 11. |
| 4 | fp_accuracy.R:205-216 `fp_acc_imagery_themes` share | whether an epoch covers ≥ 25% of the **sample** | unique covered point_ids / `n_points` (the caller's `nrow(smp)`) | **yes**, given row 18 for the coverage itself. |
| 5 | fp_accuracy.R:212 `digital` | "this year's frames are digital" | media of the **nearest** frame per point only | **yes for NECR**. All 1,376 2012 frames in the 5 km bbox are `Digital - Colour` (live BCDC pull). In a mixed year, a fallback film frame is either skipped by fly and counted, or dropped by terra::vrt (row 27). |
| 6 | fp_accuracy.R:224-234 `fp_acc_quiet_urls` | "no condition leaving these calls names the private endpoint" | the `https?://…` regex over condition messages | **NO**: finding 1. |
| 7 | fp_accuracy.R:239-260 `fp_acc_ortho_items` completeness | every item that intersects the bbox | `items_fetch()`, which follows `next` links | **yes, measured**. The first page held 500 items and `matched` was NULL. The fetch followed `next` to **777** items. A network error on a page propagates as an error, not as a short list. |
| 8 | fp_accuracy.R:246 one collection | "the catalogue is one collection" | `length(collections) != 1` → stop | **yes** |
| 9 | fp_accuracy.R:249 `$value` (warnings dropped) | the request succeeded completely | the return value | **yes**. 0 warnings were measured, and a short page cannot warn (row 7). |
| 10 | sample_draw-pilot.R:51-54 lookback refusal | every lookback entry tagged on the patches has a stratum | config names vs `FP_ACC_PRIOR_NAME` | **yes**. An empty `lookback:` gives `character(0)`. |
| 11 | sample_draw-pilot.R:96-98 empty-stratum note | "stratum 19 was drawn" | `s$strata$stratum` (the strata drift found cells for) | **yes** |
| 12 | sample_draw-pilot.R:70, 131-136 design.json `lookback` | the record of the prior window that was drawn | `.dst_window(prior_src, change_interval)`, the same derivation the fetch uses (fp_disturbance.R:164-175) | **yes**. A missing lookback writes `null`. |
| 13 | sample_draw-pilot.R:113-121 label guard | existing labels stay valid against the redraw | `setdiff` of labelled ids + `fp_acc_design_check` on every labelled row | **yes**. Labels are a subset by nature, so checking each one present is the whole check. |
| 14 | accuracy_estimate.R:47-53 lookback guard | the config's prior stratum is the one the design drew | `lookback` length only | **yes**, at the same strength as the existing causes-by-name guard. The estimate reads only the committed record. Types match after `simplifyVector` (round 1). |
| 15 | accuracy-check.R:107-133 prior arms | the precedence of stratum 19 | 6 cases + table + label + a no-prior must-fail arm | **yes, each can fail**. Moving the prior `ifel` below wetland fails `prior_beats_wetland`. Moving it above causes fails `fire_beats_prior`. A stray check on prior fails `prior_stable`/`prior_sieved`. |
| 16 | accuracy-check.R:142-150 form arms | each committed form offers exactly `FP_ACC_IMAGERY` | `setequal` over the XPath values. The must-fail arm drops `orthophoto`. | **yes**. An empty glob crashes the must-fail arm (`[1]` → NA) instead of passing. An XPath that matches nothing fails `setequal`. The form embedded in a project is accepted (round 1, the archived pre-#103 project). |
| 17 | imagery_index-dated.R:46-52 ortho 100 m bbox | every item covering any point | the bbox of all buffered points (each point lies inside it) | **yes** (777 items, row 7) |
| 18 | imagery_index-dated.R:52-58 ortho coverage = `st_intersects(point, item geometry)` | "a dated orthophoto **image** exists at this point" | the STAC item geometry | **NO**: finding 2 (measured, 25 of 229). |
| 19 | imagery_index-dated.R:63-65 air photo 5 km bbox | every frame whose footprint covers a point | frame **centres** inside the bbox of points + 5 km | **yes for every themed year**. 2012 covers 480 of 480. For film at ≤1:40k, a frame centred >5 km outside the outermost point can be missed, so `n_images` / coverage undercount for edge points. Film is never themed or built, so this is informational only. |
| 20 | imagery_index-dated.R:72-80 DEM only for unsized frames | footprints of every frame | `fly_footprint(ph)`, then the DEM for `need` | **yes**. `need` = the digital frames, so no roll is split (round 2). |
| 21 | imagery_index-dated.R:84-97 nearest-frame choice | the least oblique covering frame per point-year | the minimum centroid distance among frames whose footprint contains the point | **yes** |
| 22 | imagery_index-dated.R:100-109 merge with design | every sample point appears, with its design key | `setdiff(design, out)` filled with `NA` rows, then an inner `merge` | **yes**. All 480 points are present (measured). |
| 23 | imagery_build-dated.R:58-61 index ↔ sample | the index is about **this** sample, complete | `setequal` of point sets + `fp_acc_design_check` on the first row per point | **yes**. Every row of a point carries the same design columns, from the merge. |
| 24 | imagery_build-dated.R:64-70 stale VRT removal | the VRTs on disk = the epochs themed now | filenames vs `want` | **yes for un-themed epochs**. A themed epoch whose build yields nothing (`next` at :157) keeps its previous VRT. This is folded into finding 4. |
| 25 | imagery_build-dated.R:79-81 300 m boxes / tile filter | the tiles a reviewer looks at | `st_intersects(item, boxes)` + cog + non-NA href | **yes**. 0 of 777 items lack `assets$image$href` (measured), and all are COGs. |
| 26 | imagery_build-dated.R:85-87 single-zone check | one CRS across the year's tiles | `unique(f$epsg)` from `proj:epsg` | **yes**. All 777 are EPSG 3157. If the property were absent (all NA, so length 1), buildvrt skips mismatched tiles and row 27 stops the run. |
| 27a | imagery_build-dated.R:95-102 ortho VRT count | every requested tile is in the VRT | unique `SourceFilename` count vs `nrow(f)` | **yes**. A total failure makes `gdal_utils` stop (sf 1.1.2 `if (ret) stop`), so a stale `src` is never counted. 241 sources (round 2). |
| 27b | imagery_build-dated.R:159 air photo VRT | every georeferenced frame is in the VRT | `terra::vrt()`'s return; **no count** | **NO (latent)**: finding 3 |
| 28 | imagery_build-dated.R:136-153 fallback loop | each covered point ends with a georeferenced frame if any exists | per open point, the first untried frame | **yes**. `tried` grows by ≥1 each pass, so it terminates. A download failure is counted, not retried (round 1, accepted). |
| 29 | imagery_build-dated.R:148-151 `overwrite = TRUE`, `okg` | the frames georeferenced in this run | `success` + `file.exists(dest)` after a fresh write | **yes**. The thumbnail cache is fly's (`file.size > 0`), and all 480 points read data in `airphoto_2012.vrt` (measured). |
| 30 | imagery_build-dated.R:154-156 `n_none` | covered points with no frame | `cov` points minus points of `good` | **yes**. The message says "of covered points", which is accurate. |
| 31 | review_build-qgis.R:109-120 patches refresh | the display copy matches the published layer | attribute **content**, sorted by `(name_basin, patch_id)` | **yes, measured**. The key is unique (0 duplicates of 5,692). It is `identical()` on the live files, so there is no rewrite every run. A fresh round-trip is also identical. Geometry is not compared, but a step-3 re-run moves `area_ha`, and `fire_tag.R` keeps geometry. |
| 32 | review_build-qgis.R:147-150 orphan removal | dated layers = dated VRTs on disk | tree names vs VRT filenames | **NO**: finding 4. The layer goes, its theme stays. |
| 33 | review_build-qgis.R:142, 151-158 dated layers added | the dated epochs that are current for this sample | **VRT presence on disk** | **NO (low)**: finding 4 |
| 34 | review_build-qgis.R:161-168 theme rows | one theme per image layer present + Review | tree names ∩ derived names | **yes** for the themes it writes (`on_missing_layer = "error"` and `intersect`). It does not cover themes it should delete (finding 4). |
| 35 | review_build-qgis.R:134 vs :163 S2 names | chip layer names = theme layer names | the same `sub("_"," ")` expression in both places | **yes**. Both places derive the name identically, so they agree. The window `same_season` gives "S2 same season_2017", which is odd but consistent. |

## Findings (rows that do not hold)

### 1. [MEDIUM] fp_accuracy.R:223-234: `fp_acc_quiet_urls` leaks the private endpoint's HOSTNAME on any network failure

The redaction regex removes `https?://…` URLs only. curl (via httr, which rstac uses) puts the bare host
in its error text, so a DNS failure, refused connection or timeout on the catalogue request goes through
with the host intact.

**Measured in the scratchpad** with a fake endpoint. The probe passed `force_version` so that the
version probe did not fail first.

```
Error : probe failed: Error while requesting '<url>'.
Could not resolve hostname [secret-host-r3probe.invalid]:
Could not resolve host: secret-host-r3probe.invalid
```

Connection refused gives `Could not connect to server [127.0.0.1]: Failed to connect to 127.0.0.1 port 9`.
A timeout gives `Timeout was reached [10.255.255.1]`.

**Scenario.** The catalogue is unreachable, or a pagination request times out, during an
`imagery_index-dated.R` or `imagery_build-dated.R` run. CLAUDE.md captures such runs with `> log 2>&1`,
and `scripts/landcover_accuracy/logs/` is committed to this public repo. The log then publishes the
endpoint's host, which is the part of `FP_ORTHO_STAC` the header promises never reaches a log.

GDAL's tile errors are not affected: they carry full URLs (round 2's probe), and the regex catches those.

**Fix.** Also redact the literal host, and any port, of `Sys.getenv("FP_ORTHO_STAC")` and of the item
hrefs, with `fixed = TRUE` after the regex. Alternatively, on error, report only that the request failed
and the condition class, and drop the message text.

### 2. [MEDIUM] imagery_index-dated.R:52-58: orthophoto coverage is the STAC item geometry, not image data, so 25 of 229 indexed points have no orthophoto

The index records a point as covered by Orthophoto 2021 whenever an item's geometry intersects it.

**Measured** through a scratchpad copy of `orthophoto_2021_native.vrt`, reading pixels remotely:

| indexed? | data | NA | zero |
|---|---|---|---|
| no  | 0   | 67 | 184 |
| yes | 204 | 0  | 25  |

- For each of the 25 indexed points that read zero, **exactly one** tile's DstRect contains the point,
  and **that tile itself reads 0,0,0 there**: the tile's collar or no-data fill, inside the item's
  geometry. This is not an artefact of mosaic order.
- Separately, in 150 sampled overlap positions within 150 m of indexed points, the mosaic was **never**
  black where some tile had data. So overlap painting does not destroy imagery; only the coverage
  claim is wrong.

**Consequences:**
- The committed `reference/necr/imagery.csv` claims a 0.15 m dated orthophoto at 25 points (10.9% of
  its orthophoto coverage) where the reviewer will see black.
- The theme rule runs on the inflated share: 47.7% claimed vs **42.5%** true. That is still over the 25%
  bar in NECR. In an area near the bar, the overstatement themes an epoch that does not meet it.

**Fix.** Index coverage by data, not by footprint. Read one pixel per (point, item) through `/vsicurl/`
inside `fp_acc_quiet_urls`: 229 points took well under a minute here. Count a point covered only if
some band is non-zero, or not equal to the tile's nodata. Alternatively, keep the footprint join and
have the build report "N of M indexed points read no image data" after the VRT is written.

### 3. [LOW, latent] imagery_build-dated.R:159: the air photo VRT has no source count, unlike the orthophoto one

`terra::vrt()` drops a file whose band count or CRS differs from the first. It reports this only as a
warning, `[vrt] vrt did not use 1 of the 2 files` (probed in the scratchpad: 4-band + 2-band, and
EPSG 3005 + 3157). The run then prints "N frames georeferenced", counting frames that are not in the
VRT. In Rscript, the whole `if (any(themes$source == "airphoto")) {…}` block is one top-level
expression, so fly's per-batch warnings and this one are deferred together. Above 10 of them, they
collapse to "There were N warnings".

**Trigger.** A themed year whose fallback reaches a film frame. Row 5's `digital` is judged from the
nearest frames only, and mixed media within a year is real here: 1985-1989 and 2000 are BW + colour.
The other trigger is a frame georeferenced into another band layout.

**Not live in NECR.** The 2012 frames are all digital, the VRT holds 1000 sources = 250 × 4, and all 480
points read data.

**Fix.** Mirror the orthophoto check: the unique `SourceFilename` count in `airphoto_<y>.vrt` must equal
`length(unique(dest))`, else stop.

### 4. [LOW] review_build-qgis.R:147-168: removing an orphan dated layer leaves its map theme, and dated layers are added from VRT presence alone

**(a) The orphan's theme survives.** `rfp_qgs_layer_rm()` removes the layer, but `rfp_qgs_theme_set()`
only replaces the themes it is given (rfp 0.87.0 docs: "A theme of the same name is *replaced*"; removal
is `rfp_qgs_theme_rm()`).

Measured on a scratchpad copy of the live `.qgs`: after `rfp_qgs_layer_rm(…, "Orthophoto 2021")`, the
`visibility-preset` "Orthophoto 2021" is still there, holding the five base layers and no imagery. So
when an epoch stops earning a theme, the reviewer keeps a theme by that name that shows no image, and
the header's "rewritten on every run so they always match the layers present" is false.

The same applies to an "S2 …" theme whose chip VRT is gone.

Fix: call `rfp::rfp_qgs_theme_rm(qgs, nm)` in the orphan loop. More generally, remove every existing
theme that matches `^(S2 |Orthophoto |Air photo )` and is not in `imgs` before `theme_set`.

**(b) Presence on disk stands in for "current".** review_build never consults `imagery.csv`. Take the
documented pilot → full step:
1. `sample_draw-pilot.R`
2. `review_build-qgis.R`, which appends the new points

This keeps `orthophoto_2021.vrt` and `airphoto_2012.vrt` built for the old points. The new points get
black or empty imagery under those themes, and an epoch that no longer meets 25% keeps its theme.

The cleanup that round 2 added lives only in `imagery_build-dated.R`. That script refuses at :58 until
the index is re-run, and it keeps a themed epoch's old VRT when nothing new georeferences (:157).

The effect is visible to the reviewer, not a silent mislabel, hence LOW.

Fix: in review_build, apply the same `setequal(unique(img$point_id), smp$point_id)` test before adding
dated layers. When it fails, skip them with a message naming `imagery_index-dated.R` →
`imagery_build-dated.R`.

## Verdict

Enumeration complete: 36 rows. 31 hold, several of them by measurement against the live catalogue or
files (rows 5, 7, 25, 26, 29, 31). The 5 that do not hold make four findings:
- **2 MEDIUM:** the hostname leak, and footprint-as-coverage overstating orthophoto coverage by 25 points.
- **2 LOW:** the air photo VRT count, and the stale theme / VRT-presence pair.

Two of the findings sit inside round-2 fixes, and both are the same class one level down:
- **Finding 1** is the redaction helper. It judges "no endpoint leaves" from the URL-shaped substrings
  in hand.
- **Finding 4a** is the orphan removal. It judges "themes match layers" from the themes it writes, not
  from the themes that exist.
