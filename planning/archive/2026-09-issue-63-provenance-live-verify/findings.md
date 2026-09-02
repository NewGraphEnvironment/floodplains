# Findings — Verify #33's provenance block against a live database (#63)

## Issue context

#33 shipped the per-area provenance block (PR #62). Its first acceptance criterion had two halves;
the offline half was fully exercised (31 guard assertions each shown able to fail, a live-STAC A/B,
a producer/guard key-drift check verified red on a one-character typo). The half that needs a
database had never run.

#63 was filed on a **false premise** — "postgres is not running". It was running the whole time
(`fresh-db`, postgis, up 7 weeks, healthy on `0.0.0.0:5432`). The probe was wrong twice:
`pg_isready` with no `-h` tests the unix socket a containerised server never creates, and the `PG*`
vars live in `~/.Renviron`, which R reads and bash does not. Connecting properly closed most of the
issue and surfaced a genuine bug (`pq__text` aborting the provenance write, fixed in 2406548).

## Pre-flight, measured 2026-09-02 before any run

All read-only, from m1.

| fact | value |
|---|---|
| `fresh-db` | up 7 weeks (healthy), `0.0.0.0:5432`; `pg_isready -h localhost` = accepting connections |
| province-wide rebuild (the stated remaining blocker) | **finished** — 34 groups under `run_uid 20260901_234743-6628379d`, last `fresh.log` write 01:25:14Z, no R/link processes running |
| BULK log row | `run_uid 20260901_234743-6628379d`, `link_version 0.50.0`, `link_sha 689146867a5f00f94ec2e8085ddae36996e64379`, `link_dirty f`, 00:18:57Z → 00:27:25Z |
| freshness guard (BULK, access_co in (1,2), order ≥ 3) | grab **2205.70 km** vs `fresh.streams_vw_bcfp` **2205.57 km** = **0.006% dev** against a 2% tolerance |
| network stability across the rebuild | all **1915** `streams_co3` segments on disk are present in the rebuilt `fresh`; max `abs(length_metre)` diff = **0** |
| parity numbers off the pre-run outputs | **673.5 km / 142.8 km² / 770.0 ha** |
| `provenance.json` | **absent from every `data/<area>/`** — the A/B creates it from scratch, so this is a cold-path test |

### Parity measurement method (pins the three numbers)

```r
sum(as.numeric(st_length(streams_co3))) / 1000                        # 673.5 km
sum(as.numeric(st_area(co_ff04))) / 1e6                               # 142.8 km²
sum(area_ha[from_class == "Trees"])  # transition_co_ff04_2017_2023   # 770.0 ha
```

### m1 package state (pre-Phase-3)

| pkg | installed | RemoteSha | checkout | checkout SHA |
|---|---|---|---|---|
| link | 0.47.3 | – | 0.50.0 | 2b5a435 |
| flooded | 0.5.0 | – | 0.6.0 | 1eaaaa0 |
| drift | 0.8.0 | – | 0.10.0 | b61f002 |
| fresh | 0.33.0 | 7f12d99… | 0.33.0 | dc48ca4 |

All four checkouts clean (`--untracked-files=no`).

`fp_pkg_stamp` therefore reads `unresolved (checkout … is X, installed is Y)` for link, flooded and
drift, and resolves via `RemoteSha` for fresh. **Note the `fresh` row:** installed RemoteSha
7f12d99 ≠ checkout dc48ca4, but the *versions* match, so tier 2 (RemoteSha) answers first and the
mismatch is not visible in the stamp.

### m4 state (pre-Phase-4)

Reachable over tailscale (`100.66.235.69`), has `~/Projects/repo/floodplains`, and
`pg_isready -h 100.101.213.2` from m4 answers **accepting connections** — m1's `pg_hba.conf` ends
`host all all all scram-sha-256`, so a remote connection with credentials is allowed.

| item | m4 |
|---|---|
| floodplains | f0d6fb3 (issue #39 merge — pre-#33 entirely) |
| link / flooded / drift / fresh installed | 0.40.2 / **0.3.0** / 0.6.0 / 0.33.0 |
| checkouts | link 3ac4a24 (0.45.2), flooded 8d169ce (0.3.1), drift a34f0ea (0.7.0), fresh 7f12d99 (0.33.0) |
| `PG*` in `~/.Renviron` | **absent** |
| docker | daemon not running |

flooded **0.3.0** predates the 0.5.0 bankfull units fix, so an unaligned m4 run would differ by
~16% on the floodplain for a reason that has nothing to do with provenance determinism.

Two probe traps met on m4 and worth recording: a non-login `ssh` shell has neither `psql` nor
`pg_isready` on `PATH` (both are under `/opt/homebrew/bin`, added by the login profile), so the
first probe reported them missing when they are installed. `bash -lc` is the fix.

## Errors Encountered

| Error | Resolution |
|-------|------------|
| `psql: ERROR: function round(double precision, integer) does not exist` | `length_metre` is `double precision`; cast before rounding — `sum(length_metre)::numeric/1000.0` |
| `ssh m4 'pg_isready'` → `command not found` | Non-login shell has no `/opt/homebrew/bin`; use `ssh m4 'bash -lc "…"'` |

## Phase 2 — live results (m1, pass 1)

### `lnk_log_read()` wholesale read: confirmed against a live row

Installed link is **0.47.3**, whose `cols_log` names 26 columns. The row that reached
`provenance.json` carries **30**, including `run_uid`, `bcfp_pin_source`, `crate_version`,
`bcfp_model_run_id`, `host`, `run_id` and `fresh_sha_source` — fields the installed link does not
name. This is the claim the whole design rests on (`SELECT *`, never destructured into named
fields) and it had never been exercised against a database.

### The `pq__text` fix works against a real driver value

`species` reached the JSON as a proper array — `["BT","CH","CO","PK","SK","ST"]` — not as the raw
Postgres literal `"{BT,CH,CO,PK,SK,ST}"` and not as an aborted write. `wsg_upstream` likewise
(`["KISP","KLUM","LSKE","ZYMO"]`). 2406548 is confirmed live on the exact code path that could
only ever be reached with a database attached.

### Three of the issue's checkboxes, answered

- `link_log` non-null, `link_log_note` absent (null)
- `config_hash` = `sha256:19e3a05688…`, **identical** to what `fresh.log` holds for BULK
- `run_uid` = `20260901_234743-6628379d` — **populated**, contradicting #33 §5's prediction
- `link_log$link_sha` = `689146867a…`, `link_dirty` false — **populated**, and distinct from
  `fp_pkg_stamp("link")`, which correctly reads
  `unresolved (checkout at /Users/airvine/Projects/repo/link is 0.50.0, installed is 0.47.3)`.
  The issue body conflated the two.

Freshness guard, as predicted: `grabbed 2206 km vs bcfp 2206 km = 0.0% dev (tol 2%, guard=strict)`.

### FINDING — on a GRAB, `inputs.link_config_name` records a config that did not build the network

`01_network_extract.R:290` hardcodes `link_config_name = "default"`. That is correct on a BUILD,
where the repo deliberately uses the `default` bundle (natural barriers = gradient + falls only,
`subsurfaceflow` OFF — the documented NewGraph methodology decision).

It is **wrong on a GRAB**. The link log row for BULK reports `config_name = bcfishpass`, and every
row in `fresh.log` is `bcfishpass` — so the network neexdzii actually reads was built under the
config the repo explicitly chose *not* to use. The two configs differ in the natural-barrier set,
which is a material difference, not a label.

Three things make this the "a value nothing reads is wrong silently" shape:

- Nothing cross-checks `link_config_name` against `link_log$config_name`, though both sit in the
  same section of the same file, one nested inside the other.
- The guard cannot catch it: `provenance-check.R` asserts the key is *present*, which it is.
- It reaches the most-published case. Per CLAUDE.md the GRAB path "is the only way most published
  areas get a config_hash at all, since they GRAB and never build" — so the areas most likely to be
  published are exactly the ones carrying the wrong config name.

Corroborated independently: CLAUDE.md records that a `default` build runs a median **+0.7%** over
the bcfp reference, while this GRAB measured **0.0%** — consistent with `fresh` being a bcfishpass
build, not a default one.

Not fixed in this issue (it is a #33 design defect, not a verification failure) — filed as a
follow-up.

## Phase 4 — m4 preparation

Brought m4 to m1's post-Phase-3 package state. Reproducing a `fp_pkg_stamp` means reproducing the
**install route**, not just the version, because the resolver answers in tiers.

| pkg | m4 after prep | matches m1 (post-Phase-3)? |
|---|---|---|
| link | 0.50.0, sha 2b5a435…, source `git`, dirty FALSE | ✓ (once m1 is reinstalled) |
| drift | 0.8.0, `unresolved (checkout … drift is 0.10.0, installed is 0.8.0)` | ✓ identical string |
| fresh | 0.33.0, sha 7f12d99…, source `RemoteSha` | ✓ |
| flooded | 0.5.0, `unresolved (checkout … flooded is 0.3.1, installed is 0.5.0)` | ✗ — m1 says `is 0.6.0` |

R is 4.5.2 on both machines.

**The flooded row is the predicted (b)-class artifact, now concrete rather than hypothetical.**
m4's `flooded` checkout carries uncommitted work, so it was deliberately left where it was
(stash → install from the v0.5.0 tag → return to the original commit → pop; WIP restored byte-for-
byte, stash list empty). Both machines therefore run **byte-identical flooded 0.5.0 code** while
their `inputs.flooded` stamps differ — because the string names a checkout that did not run. The
floodplain section's `inputs_hash` must differ between the machines for that reason alone, and the
substantive comparison has to be done field-by-field with the package stamps set aside.

## Errors Encountered (cont.)

| Error | Resolution |
|-------|------------|
| m4 `git checkout v0.5.0` → `local changes would be overwritten` | Uncommitted WIP in the checkout. `git stash push -u`, install from the tag, return to the **original** commit, `git stash pop` — returning to the original commit rather than m1's HEAD is what keeps the pop conflict-free |

## Phase 2 — the A/B, and what the first attempt cost

**The first pass 1 aborted, and the wrapper still exited 0.** `caffeinate -s Rscript …` reported
success over an `Execution halted`. This is the trap `CLAUDE.md` records, met live: the gate has to
be the in-band error count, not the wrapper's status.

It also broke the *other* half of the gate. The run died in step 3, but step 2 had already written
its sections — so `provenance.json` was newer than the run-start marker and the `-nt` test passed
on a run that never finished. The mtime gate is necessary and **not sufficient**.

### The bug that aborted it

`tapply(bridge$overlap_frac, pk, max)` — *arguments must have same length*. `pk` is the composite
patch key, hoisted into a standalone vector before the zero-area filter and reused after it, so
dropping one row left it one element too long.

- **Trigger, measured:** a single intersection pair of **9.9e-5 m²** (0.1 mm²). `overlap_ha` is
  `round(ov_ha, 4)`, so it lands on exactly `0.0000` and the filter drops it. 4312 pairs in, 4311 out.
- **Introduced by 36145d3** — itself the fix for #54's per-tenant `patch_id`, which hoisted the key
  out of the frame. Before it, the call read `bridge$patch_id` off the *filtered* frame and the
  lengths could not disagree.
- **Why it had never fired:** 36145d3 landed 2026-09-01 07:46:33, and the last neexdzii run wrote
  its outputs at 07:45. One minute. The area that exercises this code is the only multi-sub-basin
  area in the repo.

Fixed by filtering `inter`/`ov_ha` before anything is derived, keeping the rounded test so output is
unchanged. Verified in both directions: **restored bug reproduces the error exactly**; patched gives
**4311 rows — the prior committed output**, and `bridge-check.R` passes all seven assertions
(apportioned tree loss reconciles 770.02 vs 770.02 ha).

One number moved, and it moved to the truth: `unbridged patches` went **0 → 1**. The old count was
computed against the stale pre-filter key, so the sliver patch was reported as bridged when the row
representing it had been dropped.

### The A/B result

Two full passes, both 0 in-band errors, output rewritten between them.

| entry | inputs_hash | run.datetime_utc |
|---|---|---|
| `network[co3]` | same | moved |
| `floodplain[co_ff02]` | same | moved |
| `floodplain[co_ff04]` | same | moved |
| `floodplain[co_ff06]` | same | moved |
| `landcover[co_ff04]` | same | moved |

`classified_sha256` — the digest of the three classified GeoTIFFs, the field most likely to move —
is **identical across passes**, as is `item_hash`. `item_ids_complete` is `true`, so no STAC
pagination hole. **Parity unmoved: 673.5 km / 142.8 km² / 770.0 ha**, all three to the digit.

### The guard could not have gated this, and now can

Every property in `provenance-check.R` was of the form *"every entry PRESENT is well-formed"*. The
aborted run left **4 of 5** entries and the script exited **0**. Added a §7b inventory assertion
that derives the expected set from `config/<area>/` (`area.yml` + `flood_scenarios.csv`, honouring
the `FP_SPECIES` / `FP_PRIMARY_SCENARIO` overrides) and asserts each is present. Demonstrated
against the real aborted file: `FAIL — MISSING: landcover[co_ff04]`.

`provenance_ab-compare.R` now lives in the repo so the A/B is re-derivable, and carries the same
inventory check — a comparison over the *union* of two files is blind to an entry missing from
**both**, which is exactly the shape a partial run leaves on both sides of a re-run.

## Phase 3 — link 0.50.0

Installed link 0.50.0 from the clean checkout at 2b5a435, then `run_area.R neexdzii 1`.

| | pass 2 (link 0.47.3) | step 1 (link 0.50.0) |
|---|---|---|
| `inputs.link.version` | 0.47.3 | 0.50.0 |
| `inputs.link.sha` | `null` | `2b5a435de9c7a5cc…` |
| `inputs.link.sha_source` | `unresolved (checkout … is 0.50.0, installed is 0.47.3)` | `git` |
| `inputs.link.dirty` | `null` | `false` |
| network `inputs_hash` | `sha256:a42b4a3f…` | `sha256:6bf36027…` — **moved, correctly** |

- `sha_source` is the literal `"git"`. `fp_git_state` returns that one string; it does **not**
  name which of the two walk tiers answered, so an assertion expecting "git-walk tier" would fail.
- **The `floodplain` and `landcover` blocks are byte-identical** after the step-1-only re-run —
  checked as a serialized comparison of the sub-objects, not by comparing the inert `inputs_hash`
  strings, which would have compared equal even if the surrounding blocks had re-serialized
  differently. `fp_prov_set`'s forward-only per-section merge is confirmed at the byte level.
- **`link_log` is byte-identical across the version change, 30 columns both times.** This is the
  strongest available evidence for the wholesale-read design: installed link went 0.47.3 → 0.50.0,
  its `cols_log` changed, and the recorded row did not — because `lnk_log_read()` is a `SELECT *`
  and the row is never destructured. It also settles the link#262 `log_recompute` question for
  BULK: no recompute row shadows the model row here.

## Errors Encountered (cont.)

| Error | Resolution |
|-------|------------|
| `caffeinate` wrapper exit 0 over `Execution halted` | Gate on the in-band error count; the wrapper reports its own status, not the job's |
| `-nt` mtime gate satisfied by a run that died in step 3 | Step 2 writes provenance before step 3 runs. Necessary, not sufficient — pair it with the inventory assertion |
| `ERROR: column " @ " does not exist` from an `Rscript -e` over ssh | Three shells of quoting. Write the R to a file and `scp` it — the rule already in CLAUDE.md |

## Phase 4 — the cross-machine leg, and what it caught

m4 ran the identical commit (d320330) against **m1's database over tailscale**, so the machine is
the only variable. 0 in-band errors, output rewritten, 6m55s wall clock.

**The science is identical on both machines**, to every digit measured:

| | m1 | m4 |
|---|---|---|
| network | 673.48 km | 673.48 km |
| floodplain `co_ff04` | 142.823 km² | 142.823 km² |
| floodplain tree loss | 770.02 ha | 770.02 ha |
| change patches | 2032 | 2032 |

And yet **three of the five `inputs_hash` values differ.** Two classes, and only one is a defect.

### (b) Predicted artifact — a stamp that names a checkout, not the code that ran

`floodplain[*]` differs in exactly one field, `inputs.flooded`, and the two machines are running
**byte-identical flooded 0.5.0**:

```
m1: sha_source "unresolved (checkout at /Users/airvine/Projects/repo/flooded is 0.6.0, installed is 0.5.0)"
m4: sha_source "unresolved (checkout at /Users/airvine/Projects/repo/flooded is 0.3.1, installed is 0.5.0)"
```

Every substantive field — `dem_ncell`, `dem_res_m`, `dem_crs_epsg`, the thresholds, `crs_epsg`,
`subbasin_source` — is identical. So `inputs_hash` moved because of a **sibling repo's checkout
state**, which is not an input to anything. `network[co3]`'s hash, by contrast, is **identical
across the two machines** — the strongest single result in this issue, and only possible because
both machines' link checkouts sit at the same commit.

### (c) Real defect — `classified_sha256` is a container hash, not a content hash

`landcover[co_ff04]` differs in `classified_sha256`, and this one is not about checkouts.

```
2017  geometry_identical=TRUE  cells=28291615  differing=0  bytes m1=969220 m4=979248  delta=+10028
2020  geometry_identical=TRUE  cells=28291615  differing=0  bytes m1=981296 m4=991324  delta=+10028
2023  geometry_identical=TRUE  cells=28291615  differing=0  bytes m1=974362 m4=984390  delta=+10028
```

**28.3 million cells per year, zero differing**, identical dimensions, extent, CRS, resolution,
compression (LZW), block size and 256-entry palette — and a different digest. The byte delta is
*exactly* +10028 on all three years, which is the signature of a fixed metadata block rather than
compression noise.

Root cause, read out of the TIFF directory: **tag 42112 (`GDAL_METADATA`)** is 382 bytes on m1 and
5396 on m4. The tag sets are otherwise identical. m4's terra (1.9.11) carries the NetCDF-side
attributes of the gdalcubes intermediate — `crs#GeoTransform`, `crs#spatial_ref`,
`data#add_offset`, `data#grid_mapping`, `data#scale_factor` — into the GeoTIFF header; m1's terra
(1.9.34) drops them. Same GDAL 3.8.5 on both.

**Why this matters more than it looks.** #33 chose the raster digest over the STAC item ids for a
good reason — ids restate the request, the digest measures the output — and CLAUDE.md records the
supporting claim as *"terra GeoTIFF writes are byte-deterministic; one changed cell moves the
hash"*. The first half holds **within one toolchain** and fails across two. The consequence is that
`nge:landcover_key`, published as a STAC property, is machine-specific: a consumer diffing two
builds sees churn with no content change, which is precisely the false-positive #45 removed from
the GeoPackage. CLAUDE.md already states the right principle one artifact over — *"byte equality
answers 'same build?', not 'same content?'; the latter needs a content hash over normalized
geometry"* — the landcover digest inherited the conflation without the caveat.

**And it would be undiagnosable from the file.** `terra` and `sf` are not in the provenance stamps
at all — only link, flooded, drift and fresh — so the one toolchain difference that moved the
digest is the one thing the record does not carry. m1 runs terra 1.9.34 / sf 1.1.2, m4 terra 1.9.11
/ sf 1.1.0.

Filed as a follow-up; not fixed here, because the remedy is a design decision (hash cell values +
geometry rather than file bytes, and/or record the writer toolchain) rather than a verification
step.

### What the cross-machine leg proves, stated exactly

- The pipeline is **reproducible across machines in its outputs** — every published number agrees.
- `inputs_hash` is **not** reproducible across machines today, for two distinct reasons, one
  cosmetic (a sibling checkout's version) and one substantive (a container digest standing in for a
  content digest).
- The failure #33 exists to detect — *two machines, same code, different answers* — did not occur
  in the science. It occurred in the detector.
