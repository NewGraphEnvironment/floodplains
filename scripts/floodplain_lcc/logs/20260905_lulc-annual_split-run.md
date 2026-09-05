# Annual IO LULC series run across two machines — bulk, necr, lnth, kotl

**2026-09-05 · issue #79 · four areas, split m1 / m4**

`lulc_annual: true` turns the classified series from endpoints-plus-midpoint into every year of
`change_interval`. This is the run that produced the seven-year series for the four step-3-ready
areas, plus the cross-machine control that made splitting them safe.

Bulk pipeline output is the gitignored `logs/runs/20260905_lulc-annual_*` set; this file is the
committed evidence.

## Why a control was needed, and what it actually tested

The work was split across two machines, so anything that differs between them is a confound. m4 was
levelled to m1 on every package where an exact match was reachable — `drift` 0.8.0 -> **0.13.0**
(>= 0.10.0 is not optional: 0.8.0 fetches a single STAC page and would have truncated KOTL's item
set into a wrong raster with no error), `sf` -> 1.1.2, `gdalcubes` -> 0.7.4.

`terra` could not be matched: m1 has 1.9.34 and CRAN current is 1.9-46, so no plain install lands
on m1's version. It was left at **1.9.11**, which made terra the *only* remaining difference and the
control a test of exactly one variable. `fp_raster_content_sha256()` exists (#64) to be
container-invariant across precisely this gap.

Control: `run_area.R neexdzii 3` on m4, code unchanged, against m1's committed baseline.

| field | m1 baseline | m4 control |
|---|---|---|
| `landcover[co_ff04].outputs_hash` | `sha256:504624f6…` | **identical** |
| `transition_content_sha256` | `sha256:1e379aee…` | **identical** |
| `transition_patches` | 2032 | 2032 |
| `classified_content_sha256` 2017 / 2020 / 2023 | — | **all three identical** |
| `run$toolchain.terra` | 1.9.34 | 1.9.11 |
| `inputs.drift.version` | 0.8.0 | 0.13.0 |

The baseline was written under drift **0.8.0**, so the content survived a drift minor-version jump
*and* the terra gap. `inputs_hash` moved, correctly and only because the recorded `drift` stamp is
part of `inputs`.

## The runs

Both machines ran `Rscript scripts/run_area.R <area> 3` — step 3 only, so every area's floodplain
geometry and sub-basins are the bytes step 2 last wrote. Smallest area first on each machine, so a
scaling data point landed before the large one.

| area | machine | bbox Mcells | wall | peak RSS | change patches |
|---|---|---|---|---|---|
| necr | m4 | 55 | 9.2 min | 17.8 GB | 5 692 |
| kotl | m4 | 203 | 32.4 min | **54.3 GB** | 4 929 |
| lnth | m1 | 62 | 14.4 min | 16.5 GB | 2 753 |
| bulk | m1 | 168 | 34.9 min | 20.6 GB | 7 161 |

Wall clock: m4 41.6 min, m1 49.3 min, **49.3 min total** against 91.9 min if run sequentially.

`bulk`'s 7 161 patches match the figure `CLAUDE.md` records for its 2026-09-02 run exactly —
independent corroboration that the transition did not move.

**Peak RSS does not track grid size, and the pattern is worth knowing before sizing a machine.**
KOTL at 203 Mcells peaked at 54.3 GB while BULK at 168 Mcells peaked at 20.6 GB — 2.6x the memory
for 1.2x the cells. NECR (55 Mcells, 17.8 GB) also peaked *above* LNTH (62 Mcells, 16.5 GB). The
plausible cause is that terra sizes its in-memory working set against **available RAM**, and the two
large runs were on different machines (m4 128 GB, m1 64 GB) — so the number may describe the host
rather than the job. It was not isolated and should not be quoted as a per-area requirement. What
the numbers do support: 64 GB was sufficient for the largest area actually run on it.

## Throughput, and why the split was worth doing

The io-lulc COGs are in `ai4edataeuwest` (West Europe); both machines share one WiFi gateway.
Measured on a real asset, 50 MB range:

| | alone | concurrent |
|---|---|---|
| m4 | 2.05 MB/s | 2.59 MB/s |
| m1 | 3.08 MB/s | 2.47 MB/s |
| combined | — | **5.06 MB/s** |

Combined exceeds either machine alone, so a single stream does not saturate the uplink — the limit
is per-connection long-haul latency, not local bandwidth. Note m4 is the *slower* single stream
despite the faster processor: the split is worth doing, and the processor is not the reason.

## Every year was genuinely re-fetched

All four baselines were produced under drift 0.8.0, whose untiled cache keys predate the 0.10.0
change, so nothing was served from cache. That matters for what the acceptance proves: the three
shared years were re-derived from Planetary Computer and their digests still matched, rather than
being read back off disk. (drift's `stac_cache_key()` excludes `years`, so a warm cache would have
made that assertion vacuous.)

A 1.1 GB copy of m1's drift cache was rsynced to m4 beforehand on the assumption it would hit. It
did not, for the reason above. Harmless — LAN minutes — but the rationale was wrong and is recorded
here rather than repeated.

## Acceptance

Per area, via the repo's own tool. `provenance_ab-compare.R` reports a differing `inputs_hash` as a
**failure**, and under #79 it must differ, so the expected failure set is named and grepped for
rather than read from an exit code:

| entry | inputs | outputs | datetime |
|---|---|---|---|
| `landcover[<scen>]` | DIFFER (7 years, 7 digests, new `item_hash`, drift 0.8.0 -> 0.13.0) | same | moved |
| `network[*]`, `floodplain[*]` | same | same | SAME — steps 1-2 did not re-run |

All four areas returned **rc=0** on the full set: `years` = 2017..2023, seven per-year digests, the
2017 / 2020 / 2023 digests unchanged element-wise, `transition_content_sha256` and
`transition_patches` unchanged, `outputs_hash` unchanged, `inputs_hash` moved, exactly seven
`classified_*` gpkg layers and seven `.tif`s with no eighth, `provenance-check.R` green, and
`bridge-check.R` green on the three areas carrying `attribute_by` (kotl has none).

Disturbance attribution survived on all four — `in_fire` and `in_harvest` present and populated,
m4 reaching m1's `fresh-db` over tailscale. That is not incidental: `readme_functions.R` **stops**
when those columns are missing, and `bulk` is the README's `FIG_AREA`.

**Two cross-machine confirmations beyond the control.** necr and kotl were regenerated on m4 under
terra 1.9.11 / drift 0.13.0, and their shared-year digests matched baselines produced on m1 under
terra 1.9.34 / drift 0.8.0. The control established the property on a fixture; these are the same
result on published areas.

## What a consumer will see move

Neither is a defect; both are flagged on `stac_floodplains_bc#59`.

- `floodplain_landcover.gpkg` **bytes** move for every area even where content does not — rewriting
  one layer into an existing GeoPackage is not byte-stable (#45). Byte equality answers "same
  build?", not "same content?".
- `nge:landcover_key` moves for all four with no land-cover change, because the publish layer maps
  it to `inputs$item_hash`, built from the *requested* years — seven year-lines instead of three,
  from the identical 14-item STAC response.

## Not done here

- **PINE** — dropped from #79. Its `data/` predates `flooded` 0.5.0, so step 3 would classify over a
  floodplain the repo has declared dead rather than superseded. Tracked with MCGR in #76, which now
  asks for both to arrive with `lulc_annual` already on so neither is run twice.
- **gdalcubes in provenance** (#80) — it writes every landcover cell and is in no field. Levelled to
  0.7.4 on both machines so this run carries no unrecorded difference, but recording it needs a
  per-section key set, because making it a required `KEYS_TOOLCHAIN` member would fail
  `provenance-check.R` on the `floodplain[*]` entries #79 deliberately does not re-run.
- **`item_ids_complete`** (#81) — cannot be FALSE on drift >= 0.10; the `next` link it reads is
  stripped before it reaches callers. Pre-existing; it matters more now that seven `item_ids` groups
  ride behind it.
