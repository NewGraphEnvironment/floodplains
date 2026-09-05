# Findings — Annual IO LULC series (2017-2023) (#79)

## The change itself is one line

`03_lulc_classify.R:49` is the only construction of `years`. Everything downstream iterates
generically: the `classified_hashes` loop (:120-129) and the gpkg classified layers (:161-173) both
walk `names(classified_all)`; the transition (:112-115) and its layer name (:180) use `yrs[1]`/
`yrs[2]` from `change_interval`, never `years`. No `length(years) == 3` assumption exists, and
`years[2]` is never indexed — every `[2]` in the file is `yrs[2]`.

The `available_years` guard the issue asks for **already exists** at :90-95 as
`setdiff(years, lc_available)`, which covers seven years with no edit.

## The originally-proposed A/B gate could not fail

Two independent reasons, both measured.

- **drift's cache key excludes `years`.** Cache files are `<year>_<key>.<ext>`. On m4:
  `2017_6f898b8379ee.nc`, `2020_6f898b8379ee.nc`, `2023_6f898b8379ee.nc` — one key, three years.
  So re-running with seven years re-reads the three old ones off disk byte-for-byte. An A/B on the
  shared years would assert a file equals itself.
- **The STAC query range is identical either way.** `dft_stac_fetch` builds
  `min(years)-01-01/max(years)-12-31`, which is `2017-01-01/2023-12-31` for both `c(2017,2020,2023)`
  and `2017:2023`. The committed log
  `scripts/floodplain_lcc/logs/runs/20260902_032619_run-area_neexdzii_prov-m4.log:461-462` records
  `14 items returned` (2 tiles x 7 years) for a **three-year** request, and `fp_provenance.R:665`
  says the same in prose: "a 2017/2020/2023 fetch returns seven items and reads three".

Parity of the shared years is therefore a code-inspection fact, not something an A/B can establish.
The acceptance is restated below in terms that can actually fail.

## Acceptance, restated

`scripts/floodplain_lcc/provenance_ab-compare.R` is already the right tool, but run naively it
reports success as failure: its property 2 is "`inputs_hash` is IDENTICAL per entry", and under #79
`landcover[<scen>].inputs_hash` **must** differ (seven years, seven digests, a new `item_hash`).
It also fails when `run.datetime_utc` does not move — and steps 1-2 do not re-run.

Expected outcome per area, grepped rather than read from the exit code:

| entry | inputs | outputs | datetime |
|---|---|---|---|
| `landcover[<scen>]` | **DIFFER** | same | moved |
| `network[*]` | same | same | **SAME** |
| `floodplain[*]` | same | same | **SAME** |

Anything else is a defect. Plus, element-wise: the 2017/2020/2023 `classified_content_sha256`
values unchanged, `outputs.transition_content_sha256` and `transition_patches` unchanged, exactly
seven `classified_<scen>_*` gpkg layers and no eighth, and `provenance-check.R <area>` green.

## PINE is out, and the reason is the AOI vintage

`data/pine/` has no `provenance.json`; `rasters/bt_ff04/*.tif` are dated 2026-07-12. That predates
`flooded` 0.5.0, whose bankfull fix CLAUDE.md describes as making the previous contract "dead, not
merely superseded". Running step 3 there classifies land cover over a floodplain the repo has
already declared wrong, and stamps fresh landcover provenance beside two absent sections —
`provenance-check.R` 7b would then report `network[bt3]` and `floodplain[bt_ff04]` MISSING, and
`run_region.R:173` would begin treating pine as cached-complete.

PINE and MCGR are the only 2 of 23 area dirs with no provenance; #76 tracks both. #76's own remedy
for PINE (`network_guard: warn`, on the working belief that `fresh.streams_vw_bcfp` is the stale
side) needs steps 1-2-3, which is a different issue with a different acceptance.

## The cost figure describes a path these runs will not take

None of bulk/necr/lnth/kotl sets `tile_size` — it appears in no committed config — so the issue's
"23.6 min at `tile_size = 20000`" was an `FP_TILE_SIZE` run. CLAUDE.md records tiling as
benchmarked and rejected under #8 (FRAN at 20 km is 0.79x, i.e. untiled is faster).

The real new cost is downstream of the fetch. `terra::as.polygons()` runs once per year (:161-173),
so 7x not 3x; and Pass 2 (:380-382) builds a cropped/masked grid per year, which for a whole-WSG
area with one sub-basin is the entire grid again. That is the load, and KOTL at 203 Mcells is the
OOM candidate.

## Machine facts

| | m1 | m4 |
|---|---|---|
| chip / cores / RAM | M1 Max, 10, 64 GB | M4 Max, 16, 128 GB |
| drift | 0.13.0 | 0.8.0 |
| terra / sf / gdalcubes | 1.9.34 / 1.1.2 / 0.7.4 | 1.9.11 / 1.1.0 / 0.7.3 |
| GDAL | 3.8.5 | 3.8.5 |
| area data | all 23 | neexdzii only, and its provenance is schema_version 1 |
| database | `fresh-db` container up | none; m1:5432 reachable over Tailscale |

**drift 0.8.0 on m4 is a correctness problem, not just a parity one.** Paging to exhaustion landed
at 0.10.0; before that the fetch is a single `get_request()`. neexdzii's 14 items fit one page,
KOTL's will not, and a truncated item set is a wrong raster with no error.

**gdalcubes writes every cell and is recorded nowhere.** `fp_toolchain()` (`fp_provenance.R:728-737`)
returns terra/sf/gdal/geos/proj. The two machines differ (0.7.3 vs 0.7.4). Closed both ways: level
the version, and add it to `fp_toolchain()` + `KEYS_TOOLCHAIN` + `TOOLCHAIN_FIXTURE`.

## Measured: bbox drives the fetch, and the split

| area | poly km2 | bbox km2 | waste | Mcells | machine |
|---|---|---|---|---|---|
| kotl | 676.1 | 20282 | 30.0x | 203 | m4 |
| bulk | 386.5 | 16777 | 43.4x | 168 | m1 |
| lnth | 151.8 | 6179 | 40.7x | 62 | m1 |
| necr | 396.5 | 5549 | 14.0x | 55 | m4 |
| (pine) | 379.7 | 20626 | 54.3x | 206 | dropped |

Method validated: it gives neexdzii 28 Mcells against CLAUDE.md's measured 28,291,615.

## Measured: the split adds real throughput

Same WiFi, same gateway; a real io-lulc COG in `ai4edataeuwest` (West Europe).

| | alone | concurrent |
|---|---|---|
| m4 | 2.05 MB/s | 2.59 MB/s |
| m1 | 3.08 MB/s | 2.47 MB/s |
| combined | — | **5.06 MB/s** |

Combined exceeds either machine alone, so one stream does not saturate the uplink — the limit is
per-connection long-haul latency. m4 is the *slower* single stream despite the faster processor,
which is why the split is worth doing and the processor is not the reason.

## Errors Encountered

| Error | Resolution |
|-------|------------|
| `sysctl: command not found` over ssh | Non-interactive ssh has a minimal PATH; use absolute paths (`/usr/sbin/sysctl`) |
| `SyntaxError: f-string: unmatched '('` in an ssh'd python one-liner | Quoting layer, not the code; pipe the script over ssh stdin with a quoted heredoc |
| `curl` returned 248 bytes from the io-lulc blob | Planetary Computer assets need a SAS token from `/api/sas/v1/token/io-lulc` |
