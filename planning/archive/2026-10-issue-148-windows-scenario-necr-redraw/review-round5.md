# /code-check round 5: `git diff 2e5dccb...HEAD` (cb9c25e, c56b09f)

## Checklist read

`code-check.md`, prose under `## Mechanisms` (table rows skipped): all fourteen sections, with
"One fact derived twice" and "Verification that reads its own output" read closely. The R, shell,
spatial and Python files were not needed: the diff touches no code.

## Findings

- **[severity: bug]** `scripts/landcover_accuracy/logs/20261024_chip_build-composite_necr.md:26-29`,
  `research/landcover_accuracy.md:470-471`, `planning/active/findings.md:74`,
  `planning/active/progress.md:17`. The 2023 log's one `repoprted` line is credited to the wrong chip,
  so the drift#87 claim built on it has no support. The diff says the warning was for `32_00004`,
  that drift did not refuse that chip, and that this "shows the check does not see every failed read
  (drift#87)". The log points instead to `19_00001`, the chip drift's chunk check **did** refuse.
  - The gdalcubes `##` / `[WARNING]` lines are block-buffered. They do not reach the log when they
    are produced. In the 2023 log they come in ten contiguous blocks that roughly double in size:
    1, 2, 4, 7, 14, 28, 56, 112, 224 and 446 lines, at lines 12, 17, 27, 44, 79, 155, 298, 583,
    1155 and 2299. They were found with an awk block scan for `^##` / `^\[WARNING\]`.
  - The last block runs from line 2299 to 2744: 446 lines with no R line between them. It sits just
    after the 4th `Querying STAC` that follows `450 / 480 points` at line 2282. That 4th query is
    point 454, which is `32_00004` (2023 manifest order: `which(m$point_id=="32_00004")` = 454).
    Crediting the warning to that chip is a reading of where the block was flushed, not of when the
    line was written. Nothing that slow produces 446 lines during one point.
  - Counting through the stream gives a different chip. There are **648** `##` lines before the
    `[WARNING]` at line 2499 (`awk 'NR<2499' | grep -c '^##'`). At about 2 lines per cube, that is
    the 324th to 325th fetched cube. There are **325** `Querying STAC` lines before drift's
    `19_00001 ... gdalcubes could not read 1 of 1 chunk` message at line 1789: 6 cached plus 325
    fetched, so point 331 (manifest order 331). `32_00004` would sit near the 448th fetched cube,
    about 896 lines in.
  - So the `repoprted` line is almost certainly gdalcubes reporting the 19_00001 failure that drift
    caught. It is not a failure that drift missed.
  - The re-fetch of `32_00004` agrees with this. The aside copy and the cached chip are identical
    (`identical(values(a), values(b))` TRUE, `compareGeom` TRUE). That is what a chip that never
    failed would give.
  - The sentence "its `chunk_status` recorded no failure" also has no producer. No committed or
    data-side artefact holds a chunk_status reading for 32_00004.
  - **Remedy:** restate the line as gdalcubes' warning for 19_00001, which drift refused and which
    was fetched again on the full pass. Drop the drift#87 inference from all four places.

- **[severity: fragile]** `scripts/landcover_accuracy/logs/20261024_chip_build-composite_necr.md:26`
  and `:28-29` ("with no warning"). The `grep -c repoprted` gate cannot see the end of any of these
  logs, so its zeros do not cover every chip.
  - The buffered stream is never flushed at exit. The 2017, 2018 and 2020 logs each hold **895**
    `##` lines for **473** fetched cubes; about 946 would be expected. The last `##` line is at
    2740-2744 of 2845, and nothing follows the final 447-line block. So the gdalcubes output for
    roughly the last 25 cubes of each one-window log was never written, and a failed-read warning
    there would read as 0.
  - The full pass is worse. `chip_build_all_ff04_full.log` has 3 queries and only 3 `##` lines, and
    none follow the third query at line 1367, which is the 19_00001 re-fetch. Its output never
    reached the log, so "0 in the full pass" does not cover that chip.
  - `chip_build_all_ff04_full2.log` has 1 query and 1 `##` line. So "fetched again with no warning"
    rests on a stream that had flushed only its first line.
  - The chips themselves look sound: the maximum NA is 0% in 2023 and at most 8.1% elsewhere.
  - **Remedy:** state that the grep covers only the flushed part of each log, or force unbuffered
    output (for example `stdbuf -o0`/`-e0`, or a flush) before the grep is treated as a gate. The
    same blind spot likely applies to the `20261002` "no failed-read line" claim at
    `research/landcover_accuracy.md:465`. That line is outside this diff and was not checked here.

- **[severity: bug, minor]** `scripts/landcover_accuracy/logs/20261024_chip_build-composite_necr.md:29`
  and `planning/active/progress.md:17` say "0 of 11,907 **cells** differ". The chip is 63 x 63 x 3:
  `dim()` gives 63 63 3 and `ncell()` gives 3,969. So 11,907 is band values (3 x 3,969), not cells:
  0 of 3,969 cells, or 0 of 11,907 band values.

## Re-derived and holding (no finding)

- **Chip build log**
  - Per-window chips, missing and minutes (479/1/174.7, 480/0/207.6, 480/0/174.6, 478/2/560.4)
    match each log's last line.
  - The three failures and their messages are at 2017:1534, 2023:113 and 2023:1789.
  - The full pass gave 1,920 / 0 missing / 6.0 min, and full2 gave 2.8 min.
  - The manifest has 1,920 rows: 480 points, 4 windows each, a set equal to `sample.gpkg`'s
    `point_id`.
  - NA share per chip, median 0 in every window. Maxima are 1.01% (2017), 8.06% (2018, 1 chip over
    5%), 1.11% (2020) and 0 (2023).
  - The single process ran from 22:18:12Z (birth time) to 22:51:06Z, with 27 cache files written
    before 22:51:10Z and 7+7+7+6 `cached` lines. That is 1,974 s / 27 = 73 s a chip.
  - 31.5 s for 2026-09-30 is 946.2 min / 1,800. Run end 08:22:57Z (full2 mtime).
  - The four refetched chips (1_00025, 16_00030, 19_00001 and 32_00004) are the only cache files
    newer than 08:12Z.
  - windows.csv matches. Every point moved: 0 of 480 locations are shared with the
    `5ea92e7:reference/necr/sample.gpkg` draw.
  - The review projects' `labels.gpkg` hold 480 and 75 rows, with 0 non-empty `ref_from`, `ref_to`,
    `label_status`, `confidence` or `imagery`.
- **Model labels log**
  - render.json gives seed 1792830297, 480 sheets, n_batch 40, rendered at 08:30:49Z, with S2 years
    2017/2018/2020/2023, Wayback 2017/2023 and dated `airphoto_2012.vrt`. The render log gives
    5.9 min.
  - The audit JSONs match: 40 rows, 41 reads and 0 violations/missing/extra in all 12 batches.
    Model `claude-opus-5-5`, and the last `extracted_utc` is 08:48:20Z.
  - Every transcript sha256 equals the audit's, and the 12-hex prefixes in the table match.
  - Tool calls are 41 Read plus 1 SubagentHandback in each batch.
  - Tokens (last context plus last output) run from 108,638 to 118,339, which rounds to 109-118k.
  - Transcript spans run from 174.5 to 262.1 s. "175" holds if it was taken from the Agent
    duration; it was not re-derivable to the second.
  - Batch 6 is the only hand-back with text after its csv fence (1,001 chars; lengths only, no text
    read).
  - `labels_model.csv` sha256 equals `reference/necr/labels_model.sha256` (`084dafcd3563…`).
  - The counts are label_status 476 / 4 (0.8%), confidence 270 / 172 / 38, and imagery 243 / 225 / 12.
- **Other checks**
  - "the first was spawned at 08:31:28Z" could not be checked from the artefacts: the first
    transcript event is 08:31:56Z. Not flagged.
  - The referenced paths exist: `logs/20261023_model_labels_necr.md`, and drift#87 ("Failed gdalcubes
    chunk reads are silent…").
  - The `extract` prompt check (`labels_import-model.R:81`) compares `trimws(sent)` with
    `batch_prompt(b)`.
  - `accuracy-check.R` gives ALL PASS (rc 0) and wrote no file in the repo.
  - No machine path, private URL or `FP_ORTHO_STAC` value appears in the diff.
