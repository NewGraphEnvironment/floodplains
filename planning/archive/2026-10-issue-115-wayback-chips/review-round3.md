# Code-check round 3 (#115): artifact currency

Read: the diff (`cc_diff3.patch`), every changed file in full, `review-round2.md`, and the
checklist's mechanism sections. I did not read all 6,558 lines of the checklist line by line. I
read the "Mechanisms" part of `code-check.md` in full, grepped the R and spatial files for the
traps this diff can reach (inode, hard links, in-place writes, caches, `saveRDS`), and went
through the rest by its index. Every probe ran in the scratchpad. Nothing under the repo or
`data/` was written.

## Mechanism

**An artifact was treated as current because a proxy for its inputs matched. The input set that
actually makes it current was not part of the check.**

- R1's two fixes and R2's `wb_ok()` fix are all instances of it:
  - the cache was keyed without its bbox;
  - the kept-chip key was the clip's bbox, not the clip itself;
  - the point set was not compared.
- R1's basename `list.files` and R2's early manifest are a variant: the check looked at a
  different population, or a different moment, from the one being certified.
- The remedy each time was the same. Name every input the artifact is a function of, and put
  each one in the key or the guard.
- Round 3 finds the same shape once more in each of three places:
  - B's hard-linked tree, where the "same inode" proxy is `NULL == NULL`;
  - `cells.gpkg` and `built.csv`, where the point_id or review_id set stands in for the point's
    *location*;
  - the WMS descriptions, where the release and zoom stand in for the template and the cache
    path.

## Enumeration

| artifact | what makes it current | checked? |
|---|---|---|
| `meta/<release>_L<L>_<bbkey>.rds` | release, layer, query bbox, query params, Esri's metadata for the release | Release, layer and bbox are in the key. The params (outFields, precision) are not. A params change would error loudly on a missing column rather than serve stale data. `saveRDS(meta_query())` leaves no file when the query errors (probed). **Holds.** |
| `waybackconfig.json` release list | today's Esri catalogue | Fetched live every run, never cached. `wayback.csv` is a deliberate snapshot of it. **Holds.** |
| `reference/<area>/wayback.csv` | sample point set, design columns (location), endpoints, release list at index time | `fp_acc_wayback_read`: one row per (point, endpoint), and `fp_acc_design_check` on stratum/cell/map_class. **Holds.** |
| `wms/<release>_z<zoom>.xml` | release, zoom, the XML template (`fp_acc_wayback_wms_xml`), the absolute cache path | Name = release + zoom only; `if (!file.exists(xml))`. **Does not hold**: F4 |
| GDAL tile cache (`tiles/`) | the tile URL, assuming release tiles are immutable | The cache is keyed by request URL. A deduplicated tile 301-redirects to an earlier release's tile, which is itself an archive tile. I found no evidence that a published release's tiles change. To my knowledge GDAL caches only 200 responses, so a 204/404 zero block is not persisted; I did not check this in source. GDAL WMS's documented cache defaults (Expires 7 d, MaxSize 64 MB) can evict tiles. That costs a refetch only, so "a re-run fetches nothing it already has" is optimistic but harmless. **Holds.** |
| kept chip `dated/wayback_<yr>/<review_id>.tif` | review_id→point_id, release, zoom, clip polygon (whole point set), `tr` (sample-mean latitude), build code | The `same` test covers point_id, release_id, zoom, own_key (the clip coordinates) and file existence. `tr` = `ground_res(lat)` and the build code are not covered. A grown sample can move `tr` by 0.05 m; that is benign, because the VRT is `-resolution highest` and the pixel check still runs over kept chips. FORCE=1 covers a code change. **Holds (benign gaps).** |
| `dated/wayback_<yr>.vrt` | the chip set on disk | Rebuilt every run, with the `n_in == length(chips)` check and the per-point pixel check. **Holds for A.** It is written **in place** (same inode, probed), which matters for B: F1. |
| `built.csv` (manifest) | the whole build: point set *and point locations* (Voronoi), the key, wayback.csv's choice, the guards passing | Unlinked at start and written after the guards (R2 fix). `wb_ok()` checks: the (point, endpoint) set, review_id→point_id against the key, and release_id against wayback.csv. It does not check point **location**. **Does not hold** under a redraw: F3 |
| `cells.gpkg` | key_here review_ids **and their cells** (geometry), the design grid, capture columns | `cells_attr()` compares review_id + capture columns only, and the read-back guard uses the same function. Geometry is never compared. **Does not hold** under a redraw: F2 |
| B's hard-linked `chips/` and `dated/` | each file is A's current inode | `identical(file.info(dst)$ino, file.info(src)$ino)`. R's `file.info()` has **no `ino` column**, so this is `identical(NULL, NULL)` and always TRUE. **Does not hold**: F1 |
| project layers ("<yr> Esri capture …") | VRT present and `wb_ok()` passing | Added when the name is absent, and removed as an orphan whenever `wb_built` is NULL. The style is applied once only (pre-existing pattern, same as the dated layers). **Holds.** |
| themes | the current layer set | Rewritten every run, with foreign themes removed. **Holds.** |
| cells layer style / labels form | committed qml | `rfp_qgs_style_set` every run. **Holds.** |
| `labels.gpkg` imagery values | `FP_ACC_IMAGERY` ⇔ `labels_form.qml` | Checked in `accuracy-check.R`. Old `esri` values stay valid. **Holds.** |

## Findings

- **[medium]** `scripts/landcover_accuracy/fp_accuracy.R:798` (`fp_acc_link_tree`), reached from
  `review_build-qgis.R:117-118`. **B never picks up a chip that A rebuilt.**
  - The "already linked" test is `identical(file.info(dst)$ino, file.info(src)$ino)`. R 4.5.2's
    `file.info()` returns `size isdir mode mtime ctime atime uid gid uname grname`, with no
    inode (probed). Both sides are `NULL`, so every existing `dst` is skipped. The header's "a
    rewritten source (new inode) is relinked" is never true.
  - `wayback_build-chips.R` is the builder that hits this. It rebuilds a chip under the same name
    with `unlink(f)` and then a write, so A gets a new inode. Two things trigger that rebuild:
    - a re-index picks another release, because Esri published a new one;
    - the sample grows, so a Voronoi cell moves.
  - Meanwhile `buildvrt -overwrite` rewrites `wayback_<yr>.vrt` **in place**: a hard link sees the
    new sources (probed). So B ends up with three artifacts out of step:
    - A's new VRT;
    - A's new labels, because `wb_ok()` reads A's manifest and passes;
    - its own **old** chip files.
  - Probed in a scratch copy. A rebuilt `0001.tif` with value 200 and a new extent. B re-ran
    `fp_acc_link_tree(..., prune = "^w")`, which relinked **0** files and left B's chip at
    value 50. B's VRT then read **NA** at both test points.
  - When the rebuilt chip has the same zoom and clip (a new release only, so `-te`/`tr` are
    unchanged), the dimensions match. B then draws the **old** capture without error, under a
    cell label naming the **new** capture's date.
  - The consequence: labeller B judges different imagery from labeller A, under a date that is
    false for what is on screen. That corrupts the agreement measure, and it is the one thing
    #115 exists to prevent.
  - The `accuracy-check.R` arm cannot reach this. Its fixture never rewrites a source; it only
    adds files and removes them.
  - Fix:
    - compare `fs::file_info(c(dst, src))$inode` (fs is already in `scripts/packages.R`; probed
      that it returns equal inodes for a hard-linked pair), or simply unlink and relink every
      file;
    - add an arm that rewrites a source under the same name and asserts B follows.
  - Pre-existing in the helper, but this diff is the first caller to rely on relinking. The
    same blind spot affects any rebuilt S2 chip or orthophoto file in B.

- **[low]** `scripts/landcover_accuracy/review_build-qgis.R:274-287`. **`cells.gpkg` currency
  ignores geometry.**
  - `cells_attr()` drops the geometry and compares review_id + capture columns only. The
    read-back guard reuses it.
  - The cell squares are a function of `key$cell`. After a redraw (the ids are kept; see
    CLAUDE.md, "A `point_id` is not an identity"), the old key refuses, and the only way forward
    is regenerating `review_key.csv`. Same seed, n0 = 0 and the same sorted ids give the
    **same** review_id↔point_id permutation, so the regenerated key keeps the review_id set
    1..n.
  - With no capture columns on either side, `cells.gpkg` is therefore never rewritten:
    - an area with no Wayback build;
    - a run where `wb_ok()` is NULL both before and after the redraw.
  - The reviewer then gets squares around the old cells, under the new points.
  - The diff rewrote this condition and its comment ("rewritten whenever its keyed set …"). The
    pre-diff `setequal(review_id)` had the same hole.
  - Fix: carry `cell` in `cells.gpkg` (it is not a leak: `labels.gpkg` already carries it, and
    `fp_acc_blind_leaks` does not list it), or compare the geometry's coordinates in
    `cells_attr()`.

- **[low]** `scripts/landcover_accuracy/review_build-qgis.R:243-268` (`wb_ok()`) with
  `wayback_build-chips.R:233-245`. **`built.csv` records no point location**, so the
  point_id-set check is a proxy for "same Voronoi cells".
  - Under the redraw path above, three steps follow in order:
    1. regenerating the key gives the same review_id↔point_id map;
    2. `wayback.csv` must be re-indexed, since its design check refuses otherwise;
    3. a `review_build-qgis.R` run before the rebuild then passes every check in `wb_ok()`
       whenever the re-indexed releases coincide with the old ones.
  - The project then serves chips clipped around the **old** locations, labelled with the old
    capture dates. A full coincidence over 960 rows is unlikely, so this is low, but it is the
    R2 class with location in place of membership.
  - Fix: write `cell` (or all of `FP_ACC_DESIGN_KEY`) into `built.csv`, which lives outside the
    project so blindness is unaffected, and run `fp_acc_design_check(b, smp_design, man)` in
    `wb_ok()`.

- **[low]** `scripts/landcover_accuracy/wayback_build-chips.R:107`. **A WMS description is
  written once and never refreshed.**
  - `if (!file.exists(xml)) writeLines(...)` names the file by release and zoom. Its content is
    also a function of two things the name does not carry:
    - `fp_acc_wayback_wms_xml`'s template (ZeroBlockHttpCodes, BandsCount, the ServerUrl form);
    - the **absolute** `dir_tiles` path.
  - So a template fix silently never reaches a release already described, and every chip warped
    through that release keeps the old behaviour. A moved checkout or a copied `data/` points
    GDAL's cache at the old absolute path.
  - Fix: write it unconditionally. It is 761 bytes.

The rest of the checklist found nothing new beyond round 2:
- `$` partial matching;
- `match()` and NA;
- `paste()` with a zero-length argument;
- `nzchar(NA)`;
- `tryCatch(warning =)`;
- `mask()` `touches` consistency;
- bbox from the reprojected polygon;
- sf and terra linking different GDALs (3.8.5 and 3.13.0 here; no currency effect);
- `saveRDS` on an erroring object (no file left; probed);
- blindness of chip names, VRT sources and cells columns.
