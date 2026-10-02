# Code-check round 2, reviewer p4 (#103 staged diff): reviewing the round-1 fixes

Probes ran read-only against the committed `reference/necr/*` and the built `dated/` VRTs. Hrefs were
never printed, and the GDAL probe ran in the scratchpad on a fake URL. No pipeline script was run.

## The mechanism behind round 1

Both round-1 defects made the same assumption: **evidence from the rows in hand was taken to answer
a question about the whole set.**

- `fly_georef` was handed the batch being fetched. A frame's bearing is a property of its roll, so
  the batch could not supply it.
- The staleness guard read the file's own mtime. "Is this index about this sample?" is a property
  of the content, so the mtime could not answer it.

The round-1 fixes cure the two instances. The new design check carries the same assumption one
level down. It can only judge the rows that `imagery.csv` contains, but it is used to answer whether
the index is complete for the sample. That is finding 1.

## Findings

- **[MEDIUM] scripts/landcover_accuracy/imagery_build-dated.R:55-58** (plus fp_accuracy.R:225-245).
  The new content check only fails when a row is present and disagrees. A missing row never fails
  it, and `imagery.csv` is sparse by construction: `merge(design, out)` in the index drops every
  point that no epoch covers.
  - **When it bites:** the pilot-to-full growth path that CLAUDE.md and sample_draw-pilot.R both
    document ("keep SEED and raise N"). The old points keep their ids and cells, so
    `fp_acc_design_check` passes and `setdiff(img$point_id, smp$point_id)` is empty. Nothing
    refuses the run, and every new point is missing from the index.
  - **Measured:** on the committed files, doubling the sample (480 new ids) without re-indexing,
    `fp_acc_design_check` returns TRUE. `fp_acc_imagery_themes(img, nrow(smp2))` then drops
    Orthophoto 2021 from 47.7% to 23.9%, below the 25% bar. The build stops theming the orthophoto
    without any error.
  - **It compounds:** review_build-qgis.R:139 adds every `dated/*.vrt` it finds on disk, so the
    stale `orthophoto_2021.vrt` from the previous build still gets a layer and a theme. That VRT
    covers only the old points' tiles. Presence on disk is standing in for "currently themed".
  - **Moved points:** a redraw that only moves points with no index row also passes. That cannot
    happen in NECR today, where 2012 covers 480 of 480 points.
  - **Fix:** make completeness checkable. Either write a row for every sample point (an
    uncovered marker), or require `setequal(unique(img$point_id), smp$point_id)` with uncovered
    points represented. A point set alone is not enough, because growth keeps the old ids.

- **[MEDIUM] scripts/landcover_accuracy/imagery_build-dated.R:96-97.** One failure here does two
  separate things.
  - **It is swallowed and miscounted.** `sf::gdal_utils("buildvrt", ...)` returns TRUE when a
    `/vsicurl/` tile cannot be opened. GDAL skips the tile and raises only an R warning. Probe in the
    scratchpad, 3 sources with 1 unreachable: the return was `TRUE`, the VRT held 2 sources, and the
    warnings were `HTTP response code on https://example.invalid/secret/tile.tif: 0` and
    `Can't open /vsicurl/https://example.invalid/secret/tile.tif. Skipping it`. The
    `file.exists(out)` check passes. Line 102 then reports `nrow(f)` tiles, the number requested,
    not the number in the VRT. The warnings are deferred to the end of the top-level block. Above
    10 of them, Rscript prints only "There were N warnings", so a network blip or an expired href
    ships a mosaic with holes under a message that claims every tile.
  - **It leaks the private endpoint.** Those same warning strings carry the full catalogue href.
    CLAUDE.md asks for every run to be captured with `> log 2>&1`, and `scripts/landcover_accuracy/logs/`
    is committed to a public repo. A build log from a run where any tile failed would publish the
    endpoint. The index header's promise ("never written ... in a log") does not hold on this path.
  - **Fix:** wrap the buildvrt call in `withCallingHandlers()`. Count the warnings and muffle them
    (or redact them). Then compare the `<SourceFilename>` count in the written VRT with
    `nrow(f) * nbands`, and `stop()` without the href when they differ.
  - **Today's state:** the existing `orthophoto_2021_native.vrt` holds 723 source entries, which is
    241 tiles at 3 bands. Whether that equals `nrow(f)` cannot be checked without the endpoint.

- **[LOW] scripts/landcover_accuracy/imagery_build-dated.R:30-31, 138 (fly's `overwrite = FALSE`).**
  The georeferenced-frame cache is keyed by filename only. A `georef/*.tif` written under a
  different `photos_sf` is kept and returned with `success = TRUE`. That covers the old batch-only
  context, where `fly_bearing` takes the i-1 neighbour when i+1 is absent, so the rotation differs.
  It also covers a different DEM or a different fly version. Line 141's
  `file.exists(geo$dest)` therefore stands in for "georeferenced correctly".
  - **Not live for NECR:** all 250 files in `dated/airphoto_2012/georef/` have mtimes of
    01:45-01:46, a single fresh write. The written-data-outlives-the-fix case only arises if
    someone re-runs over an older `georef/` directory.
  - **Fix:** a one-line note in the header, or clear `georef/` whenever `phy` or the DEM changes.

- **[LOW] scripts/landcover_accuracy/review_build-qgis.R:112-117.** Two problems with the
  patches.gpkg rebuild.
  - **The trigger is the column set, not the content.** A re-tag that changes values but keeps the
    columns leaves the reviewer's display copy stale, with no message. Examples: `fire_tag.R` after
    a lookback-length change, or a step-3 re-run.
  - **`unlink(pat_gpkg)` removes only the main file.** QGIS opens GeoPackages in WAL mode. The plan
    has this script re-run while the project may be open (the "once more to add the S2 layers"
    step), and a `patches.gpkg-wal`/`-shm` left beside a freshly written file can be applied to it.
    The file is a display copy, so this is recoverable by deleting and re-running. Unlink the
    sidecars too, or refuse when they exist.

- **[LOW] research/landcover_accuracy.md:116 and :181.** Two doc errors.
  - **Line 116:** "172 ha of Rangeland→Trees" disagrees with the measured 176.8 ha in
    findings.md:100 and in the draft follow-up issue. The 176.8 comes from the re-tag log.
  - **Line 181:** "The seven that gave it cells moved". Eight strata gave cells. Stratum 14 lost 2
    cells (178.77 → 178.75 ha) and kept its points, as the 2026-10-02 log says. The ha in the
    log's table sums to 453.39 only with stratum 14's 0.02 included.

## Where the mechanism reaches, checked and clean

- **`fly_georef(…, phy)`:** fixed correctly. Download failures are filtered out before georef and
  counted, and the warning is no longer suppressed. Note that fly's "N of M frames have no flight
  bearing" warning now counts over the year's whole set, not over the fetched frames. Per-frame
  skips are still counted in the build's "not" figure, so nothing is lost.
- **imagery_index-dated.R:88 `fly_footprint(ph[need, ], dem)`:** hands fly a subset, but `need`
  equals the digital frames, and digital rolls are not mixed with sized film. No frame loses a
  neighbour.
- **The 5 km bbox clip of `ph`:** this is also a subset, but a covering frame's ±1 neighbours lie
  well inside the buffered bbox. The rebuilt run's 250/250 corroborates that.
- **The air photo VRT:** 1000 sources (250 frames × 4 bands), every one with
  `UseMaskBand>true` and `relativeToVRT="1"`. Overlapping frames composite on alpha, so a masked
  border does not punch a hole in the frame under it.
- **The design check's must-fail arm:** a mutated `cell` on a present row is refused, and the
  message names the point. Type mismatch (int in the csv, num in the gpkg) is harmless, because
  the check goes through `as.numeric`.
- **Stratum 19:**
  - the window is derived through `.dst_window` (2002–2016, not the interval);
  - precedence is cause > prior > wetland > transition, and each accuracy-check arm fails if the
    `ifel` moves;
  - the change-cell sum is 472,998, exact;
  - design.json carries `lookback`.
- **review_build themes:**
  - every base layer name exists in the .qgs;
  - `paste("S2", character(0))` yields "S2 ", which `intersect()` drops;
  - an empty `imgs` gives `rbind(df, NULL)`.
- **Hrefs:** none in `imagery.csv` or in the diff. The dated VRTs are gitignored (`.gitignore:3`).
