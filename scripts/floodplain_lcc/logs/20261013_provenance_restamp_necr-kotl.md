# Re-stamping landcover `run.datetime_utc` after the #83 container repair: necr, kotl

**2026-10-13 · issue #126 · follows `20260905_raster-tags_strip_necr-kotl.md` (#83, PR #85)**

`data/` is gitignored, so this file is the committed evidence for a change to two
`provenance.json` files.

## What was wrong

PR #85 rewrote the seven `classified_<yr>.tif` files in `necr` (`ch_ff04`) and in `kotl` (`bt_ff04`)
in place, and left `landcover.<scen>.run.datetime_utc` where step 3 had put it. That field is
published as `nge:produced_datetime`, and stac_floodplains_bc's staging guard
(`fp_prov_rasters_current`) refuses any raster newer than it, so neither area could be staged
(stac_floodplains_bc#68).

## Before: the new 7c arm fails on exactly these two

`provenance-check.R <area>`, run before anything was written:

```
necr  FAIL  landcover[ch_ff04]: no raster newer than run$datetime_utc 2026-09-05T19:14:08Z -- LATE: classified_2017.tif … classified_2023.tif
kotl  FAIL  landcover[bt_ff04]: no raster newer than run$datetime_utc 2026-09-05T19:46:31Z -- LATE: classified_2017.tif … classified_2023.tif
bulk  ok    landcover[co_ff04]: no raster newer than run$datetime_utc 2026-09-05T19:52:01Z
lnth  ok    landcover[ch_ff04]: no raster newer than run$datetime_utc 2026-09-05T19:17:07Z
```

Each of necr and kotl reported exactly one problem, this one. The plan review's read-only scan
of all 23 landcover entries under `data/` found late rasters only in these two, 7 each.

## The run

The files were snapshotted (`cp -p`) first.

| step | necr | kotl |
|---|---|---|
| `raster_strip-tags.R` with no `BACKFILL` | refused: 7 late rasters "not repaired by this run"; md5 unchanged | not run (same code path) |
| `DRY=1 BACKFILL=1` | would re-stamp to `2026-09-05T22:44:28Z` | would re-stamp to `2026-09-05T22:47:07Z` |
| `BACKFILL=1` | `19:14:08Z -> 22:44:28Z` | `19:46:31Z -> 22:47:07Z` |
| second `BACKFILL=1` run | `current`, md5 unchanged | `current`, md5 unchanged |

The stamps are the newest repaired raster's mtime floored to the second (necr 22:44:28.047,
kotl 22:47:07.600). Those are the same times as the #126 issue table. Before re-stamping, each
of the 14 late rasters was re-digested and matched its recorded `classified_content_sha256`,
and each was checked for stray tags (none).

Each entry's `run` gained one record:

```json
"repairs": [{ "kind": "container_strip", "issue": 83,
              "datetime_utc": "2026-09-05T22:44:28Z", "previous_datetime_utc": "2026-09-05T19:14:08Z",
              "files": ["classified_2017.tif", "…", "classified_2023.tif"],
              "backfilled": true, "backfilled_utc": "2026-10-13T03:39:35Z" }]
```

`backfilled` means this run re-stamped a repair that an earlier run made. The toolchain that
did the repair on 2026-09-05 was not recorded at the time, so no `toolchain` is given; today's
would be wrong. `run.toolchain` is unchanged and still describes the step-3 run.

## After

- **Only `run` moved.** The files were compared parsed (`read_json`, keys sorted), not as text,
  because re-serialising re-flows lines. Each matches its snapshot exactly once that entry's
  `run` is removed, including `inputs_hash`, `outputs_hash` and necr's `composition` sibling.
  Inside `run`, everything except `datetime_utc` and the new `repairs` is identical.
- **`provenance-check.R necr` / `kotl`:** both pass, and the late-raster arm reads `ok`.
- **The publish guard:** stac_floodplains_bc's own `fp_prov_rasters_current()` was run read-only,
  with the arguments `01_stage.R:260-264` passes (7 classified + `transition.tif`):

  ```
  necr_ch_ff04   7 classified + transition: PASS
  kotl_bt_ff04   7 classified + transition: PASS
  bulk_co_ff04   7 classified + transition: PASS
  ```

  Fed the pre-backfill necr snapshot, the same call stops with
  `7 staged raster(s) are NEWER than the provenance record`, which reproduces the #126 refusal.
  Nothing was staged or published. The stac tree had no changes afterwards.

## What it unblocks

stac_floodplains_bc#68, the rebuild and republish of the necr and kotl COGs that picks up the
#83 strip, can now stage `necr_ch_ff04` and `kotl_bt_ff04`. `nge:produced_datetime` will carry
the repair time. The rebuild itself is a job for that repo.
