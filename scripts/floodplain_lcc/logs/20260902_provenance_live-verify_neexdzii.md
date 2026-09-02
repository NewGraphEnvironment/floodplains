# Provenance block verified against a live database — neexdzii, two machines

**2026-09-02 · issue #63 · verifies #33 (PR #62)**

#33 shipped the per-area `provenance.json` with its offline half fully exercised. The half needing a
database had never run. This is that run: a two-pass A/B on m1, a link-version check, and the same
pipeline on a second machine reading m1's database over tailscale.

## What was run

Logs are the gitignored `scripts/floodplain_lcc/logs/runs/20260902_*_run-area_neexdzii_*` set
(bulk pipeline output; this file is the committed evidence).

| leg | command | log suffix |
|---|---|---|
| pass 1 (aborted) | `caffeinate -s Rscript scripts/run_area.R neexdzii 1,2,3` | `025955_…_prov-ab-pass1` |
| pass 1 | same, after the bridge fix | `030918_…_prov-ab-pass1` |
| pass 2 | same | `031512_…_prov-ab-pass2` |
| link 0.50.0 | `Rscript scripts/run_area.R neexdzii 1` | `032444_…_prov-step1-link050` |
| step-3 regression | `Rscript scripts/run_area.R neexdzii 3` | `033539_…_step3-regression` |
| m4 | `run_area.R neexdzii 1,2,3`, `PGHOST` → m1 over tailscale | `032619_…_prov-m4` (on m4) |

Every leg gated on the **in-band error count and the output mtime**, never the wrapper's exit
status. That was not ceremony: the first attempt at pass 1 aborted in step 3 and `caffeinate`
still reported **exit 0**.

Re-derive the A/B with `scripts/floodplain_lcc/provenance_ab-compare.R <a.json> <b.json> neexdzii`.

## Result

**PASS.** Five of five entries, `inputs_hash` identical per entry, `run.datetime_utc` moved in every
entry, and the parity contract unmoved: **673.5 km / 142.8 km² / 770.0 ha**.

### The link log row, read wholesale — the design claim, finally tested

Installed link was **0.47.3**, whose `cols_log` names 26 columns. The recorded row carries **30** —
`run_uid`, `bcfp_pin_source`, `crate_version`, `bcfp_model_run_id`, `host`, `run_id`,
`fresh_sha_source`. `lnk_log_read()` is a `SELECT *` and the row is never destructured, so a column
the *database* has arrives whether or not the installed link names it. Reinstalling to 0.50.0 left
the row **byte-identical at 30 columns**, which is the claim demonstrated rather than asserted.

Two of #33's predictions were wrong, and the live row settled both:

- `run_uid` **is** populated (`20260901_234743-6628379d`). #33 §5 predicted null on the grounds that
  the source schema predates link#262; that was measured against `fresh_default`, and neexdzii
  GRABs from `fresh`.
- `link_log$link_sha` **is** populated (`689146867a…`). The issue body conflated it with
  `fp_pkg_stamp("link")`; the former is written by link at pipeline time, the latter describes the
  *installed* package and correctly read `unresolved` while installed (0.47.3) and checkout (0.50.0)
  disagreed. After reinstalling from the checkout it resolves to `2b5a435…`, `sha_source` `"git"`,
  `dirty` false.

`config_hash` matches `fresh.log` for BULK exactly. The freshness guard measured
**0.006% divergence** (2205.70 km grabbed vs 2205.57 km bcfp reference) against a 2% tolerance.

### A bug only a live run could reach

RPostgres returns `text[]` as class `pq__text` — not a list, `length()` 1, the element a raw Postgres
array literal. Fixed in 2406548 before this run; confirmed here on the only code path that ever sees
a driver value: `species` and `wsg_upstream` reach the JSON as proper arrays.

### A second bug, found by running it

Step 3 aborted: `tapply(bridge$overlap_frac, pk, max)` — *arguments must have same length*. The #54
bridge hoists its composite patch key into a standalone vector, filters zero-area rows out of the
frame, then reuses the stale vector. Trigger: **one intersection pair of 9.9e-5 m²**, which
`round(ov_ha, 4)` sends to `0.0000` ha.

Introduced by 36145d3 — the fix for #54's per-tenant `patch_id` — which landed **one minute after**
the last neexdzii run. neexdzii is the only multi-sub-basin area in the repo, so nothing else
exercises this path. Fixed; restored-bug reproduces the error, patched reproduces the prior
**4311 rows** exactly. One number moved and moved to the truth: `unbridged patches` 0 → 1, the old
count having been taken against the stale key.

## Cross-machine: the science agrees, the detector does not

m4 ran the identical commit against m1's database. **Every published number matches to every digit
measured** — 673.48 km, 142.823 km², 770.02 ha, 2032 patches — and `network[co3]`'s `inputs_hash` is
**identical across the two machines**.

Three of the five hashes still differ, for two reasons that must not be conflated.

**A stamp that names a checkout, not the code that ran.** The `floodplain[*]` entries differ in
exactly one field, `inputs.flooded`, while both machines run byte-identical flooded 0.5.0:
`sha_source` embeds the *checkout's* version (0.6.0 on m1, 0.3.1 on m4) and an absolute `$HOME`
path. Every substantive field is identical.

**`classified_sha256` is a container hash, not a content hash.** This is the substantive finding.

```
2017  geometry_identical=TRUE  cells=28291615  differing=0  bytes m1=969220 m4=979248  delta=+10028
2020  geometry_identical=TRUE  cells=28291615  differing=0  bytes m1=981296 m4=991324  delta=+10028
2023  geometry_identical=TRUE  cells=28291615  differing=0  bytes m1=974362 m4=984390  delta=+10028
```

28.3 million cells per year, **zero differing**; identical dimensions, extent, CRS, resolution, LZW
compression, block size and 256-entry palette. The delta is *exactly* +10028 on all three years —
a fixed block, not compression noise. Read out of the TIFF directory: tag **42112
(`GDAL_METADATA`)** is 382 bytes on m1 and 5396 on m4, the tag sets otherwise identical. m4's terra
(1.9.11) carries the gdalcubes NetCDF attributes — `crs#GeoTransform`, `crs#spatial_ref`,
`data#add_offset`, `data#grid_mapping`, `data#scale_factor` — into the GeoTIFF header; m1's terra
(1.9.34) drops them. Same GDAL 3.8.5 on both.

CLAUDE.md records *"terra GeoTIFF writes are byte-deterministic; one changed cell moves the hash"*.
That holds **within one toolchain** and fails across two. So `nge:landcover_key`, published as a STAC
property, is machine-specific — the same false-positive churn #45 removed from the GeoPackage,
where CLAUDE.md already states the principle: *byte equality answers "same build?", not "same
content?"*. And it would be undiagnosable from the file, because **terra and sf are not in the
provenance stamps at all** — only link, flooded, drift and fresh.

## Guards this run added

`provenance-check.R` exited **0** on the file the aborted run left: every property it had was of the
form *"every entry PRESENT is well-formed"*, and 4 of 5 entries were present. The `-nt` mtime gate
passed too, because step 2 writes before step 3 runs. Added a **§7b inventory assertion** deriving
the expected entry set from the area config, and landed `provenance_ab-compare.R` so the A/B is
re-derivable. Both exercised against input built to break them, including two fail-toward-pass
shapes: an entry absent from **both** files, and `inputs_hash` absent from both — `identical(NULL,
NULL)` is `TRUE`, so that would have read as agreement.

## Follow-ups filed

The A/B is clean and the design has four named holes. Three of the four are only visible from a
second machine or a live database, which is why they survived #33's offline verification.

| issue | hole |
|---|---|
| #64 | `nge:landcover_key` hashes the GeoTIFF container, not the landcover — it moves between machines that agree on every cell |
| #65 | on a GRAB, `link_config_name` names a config that did not build the network, and `inputs_hash` pins nothing about the network it read |
| #66 | `fp_pkg_stamp` puts a sibling checkout's version and an absolute `$HOME` path inside `inputs_hash` |
| #67 | `link_log` is read wholesale and published unfiltered — `host` and `run_id` reach STAC properties with no whitelist |

## Environment

m1: R 4.5.2, terra 1.9.34, sf 1.1.2, GDAL 3.8.5, link 0.47.3 → 0.50.0, flooded 0.5.0, drift 0.8.0,
fresh 0.33.0. m4: R 4.5.2, terra 1.9.11, sf 1.1.0, GDAL 3.8.5, same four package versions.
Database: `fresh-db` (postgis) on m1, `fresh` schema rebuilt 2026-09-01/02 under
`run_uid 20260901_234743-6628379d`.
