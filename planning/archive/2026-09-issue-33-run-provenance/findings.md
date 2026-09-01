# Findings — Record run provenance per area (#33)

## Measured at plan time, 2026-09-01

### `stac_cache_key()` is a fingerprint of the REQUEST, not the response

`drift/R/dft_stac_fetch.R:210-227` hashes AOI WKB (in the target CRS), `res`, `target_crs`, `dt`,
`aggregation`, `resampling`, `stac_url`, `collection`, `asset`, and `tile_size` when non-NULL.
It hashes **nothing about the items returned**. So if Planetary Computer re-ingests
`io-lulc-annual-v02`, the key is unchanged and the stale cache is served — the exact failure this
issue was written to catch. It is also `@noRd`.

`attr(result, "stac_items") <- items` (`R/dft_stac_fetch.R:192`) has been present since drift's
first commit (`git log -S` → `361b7aa Add core pipeline`), so it is available in every drift
version the repo supports. That is the content pin, and it needs no upstream change.

Consequence for `NewGraphEnvironment/stac_floodplains_bc#17`: `nge:landcover_key` should be a hash
over the resolved item ids, not drift's cache key. That issue names the cache key explicitly and
needs a correction note.

### io-lulc items carry `datetime = NULL`

Probed live against `https://planetarycomputer.microsoft.com/api/stac/v1`, collection
`io-lulc-annual-v02`, bbox `-127.5 53.8 -126.5 54.6`, 2017-01-01/2023-12-31:

```
09U-2023  datetime=NULL  start=2023-01-01T00:00:00Z  end=2024-01-01T00:00:00Z
09U-2022  datetime=NULL  start=2022-01-01T00:00:00Z  end=2023-01-01T00:00:00Z
...
09U-2017  datetime=NULL  start=2017-01-01T00:00:00Z  end=2018-01-01T00:00:00Z
```

Grouping ids by `properties$datetime` would yield **empty groups, silently**. `start_datetime` is
the field. Guard it with an absolute assertion that every requested year resolves to ≥1 id, since
an empty group is otherwise indistinguishable from a year the AOI genuinely does not cover.

### Planetary Computer returns no `numberMatched`

Same probe: `names(doc)` is `type, links, features, numberReturned`. `numberMatched` is NULL and
`numberReturned == length(features)`, so it cannot detect truncation. drift calls
`rstac::get_request()` with no `items_fetch()` (`R/dft_stac_fetch.R:127-134`), so the result is
**one page**. The only honest completeness test is the presence of a `rel="next"` link. For the
probed AOI: `links rel: self, root, self` → no `next`, page complete.

### The query returns years that are never read

drift searches `paste0(min(years), "-01-01/", max(years), "-12-31")`, so a 2017/2020/2023 fetch
gets 7 items back and reads 3. Recording all 7 would misrepresent what produced the output.

### Item hrefs carry SAS credentials

`rstac::items_sign(sign_fn = rstac::sign_planetary_computer())` runs at `R/dft_stac_fetch.R:134`
**before** the attribute is attached, so every asset href in `attr(result, "stac_items")` carries a
short-lived SAS token (`?st=…&se=…&sig=…`). Record ids and non-secret properties only.

### `lnk_log_read()` is `SELECT *`, so version skew is not a blocker

`link/R/lnk_log.R:428`. Installed link is **0.47.3**; the checkout is **0.49.0**. The installed
signature is `function (conn, cfg, aoi = NULL, latest = TRUE)` — no `run_uid`, no `phase` — and the
installed `cols_log` has 26 columns without `run_uid` or `bcfp_pin_source`. But because the read is
`SELECT *`, a column the *database* has arrives regardless of what the installed package names. So
reading the row wholesale is robust to the skew, and this is why link#264 is off the critical path.

### `.lnk_pkg_git_sha()` resolves to NA for link/drift/flooded here

Measured:

```
link     Version=0.47.3 RemoteType=local  RemoteSha=NULL
fresh    Version=0.33.0 RemoteType=github RemoteSha=7f12d99115b7d20302d5ed043188cb870f90f83b
drift    Version=0.8.0  RemoteType=local  RemoteSha=NULL
flooded  Version=0.5.0  RemoteType=local  RemoteSha=NULL
```

Three of the four are local installs with no `RemoteSha`, and `find.package()` on a local install
returns the *library* path, whose parent is not the checkout — so link's `.git` walk returns NA
too. This is why every stamp in this repo reads `link: 0.47.3 (sha NA)`. `fp_pkg_stamp()` adds a
`~/Projects/repo/<pkg>` tier and records `sha_source` so an NA is diagnosable rather than mute.

### The MRDEM-30 URL is not resolvable from `formals()`

`flooded::fl_dem_aoi` has `source = NULL` as its formal; the URL is built inside the body
(`flooded/R/fl_dem_aoi.R:81-86`). Hardcoding it in this repo would duplicate package knowledge the
core principle forbids, so `dem_source` is taken from `terra::sources(dem)` on the returned object
— measuring the output rather than restating an input.

By contrast, `drift::dft_stac_fetch`'s `res`/`crs`/`dt`/`aggregation`/`resampling` **are** formal
defaults (`10`, `NULL`, `"P1Y"`, `"first"`, `"near"`) and `fp_lulc` passes none of them, so reading
`formals()` records what actually ran.

### `run_area.R` dispatches steps independently

`scripts/run_area.R:130-141` — `run_area.R morr 3` is a normal invocation. So a single writer at
the end of the run would have nothing to record for skipped steps, and would either blank or
fabricate them. Each step writes its own section; the file is a merge.

## Errors Encountered

| Error | Resolution |
|-------|------------|
| `psql: connection to server on socket "/tmp/.s.PGSQL.5432" failed` | Postgres is not running on this machine. All DB-touching verification (the neexdzii A/B, a live `lnk_log_read`) is deferred; everything else is offline-verifiable. |

## Found during Phase 1, by the guard itself

Four defects, none visible by reading. Three were fixed in the **writer**, not the test.

### A checkout SHA is not evidence about the installed package

The first `fp_pkg_stamp("link")` returned `24b3bee…` from `~/Projects/repo/link` — which is
**0.49.0**, while the installed link is **0.47.3**. That SHA describes code that did not run.
A confident wrong SHA is strictly worse than `NA`: an `NA` prompts a question, a wrong SHA does
not. `fp_pkg_stamp()` now compares the checkout's `DESCRIPTION` Version against the installed
version and refuses the tier on a mismatch, naming both in `sha_source`.

### A CRAN/PPPM install puts a version string in `RemoteSha`

Measured: `packageDescription("sf")$RemoteSha` is `"1.1-2"`. Published as a git SHA that is a
wrong-shaped value nothing downstream could resolve. Now shape-checked against `^[0-9a-f]{7,40}$`.

### `c()` appends, so a key present in both halves lands twice

`c(nul(KEYS), list(item_ids_complete = TRUE))` produced a list with `item_ids_complete` **twice**;
`$` then returns the first (the `NA`), so a later assignment appears to take and does not. It
surfaced as two unrelated-looking failures three checks apart. `fp_prov_write()` now refuses a
duplicate key at the boundary via `fp_prov_assert_unique()`, so the symptom cannot recur silently.

### `$` on a list partial-matches — `link_log` resolved to `link_log_note`

The nastiest of the four, and directly relevant to any consumer of this file. With `link_log`
absent and `link_log_note` present, `body$link_log` returns **the note**, so an
`is.null()` guard reads as "the row is present" and then reports nine missing fields. The same
trap sits on `inp$item_ids` → `item_ids_complete`. `provenance-check.R` reads every parsed-JSON
body with `[[`, and carries a premise assertion pinning the partial match so the reason for the
convention cannot be edited away by someone tidying.

## Found during Phases 2-4

### `lakes` / `wetlands` / `wetland_filter` are CSV columns step 2 never reads

`grep` over `02_floodplain_model.R` returns nothing for all three. They are in
`flood_scenarios.csv` and in the plan's field list, but recording them would claim an input that
did not affect the output. Omitted deliberately.

### A DBI row is not JSON

`link`'s log carries `timestamptz` (POSIXct) and `text[]` (a one-element list holding a character
vector). Serialized as-is, jsonlite formats the timestamp in the **session's** timezone, so the
same row would produce different bytes on two machines and the determinism check would fail for a
reason that is not a content change. `fp_prov_scalar()` forces UTC ISO 8601 and unwraps the array,
and marks array-valued fields with `I()` so a single-species area and a two-species area agree on
the field's *shape* rather than `auto_unbox` collapsing the length-1 case to a scalar. Verified by
serializing the same row under `TZ=America/Vancouver` and `TZ=UTC` and comparing bytes.

### The key-drift scanner was wrong on its first two drafts

The first was a regex/indentation scan and reported **1** key where there are 9 — a MISMATCH for
every section, which read as a real defect until the `link_log` row (extracted by a different
path) came back MATCH and served as the positive control. The second parsed the AST but died on
`row[1, ]`: R's **empty symbol** in an argument list, which makes any variable bound to it a
*missing argument*, so `is.null()`, `is.call()` and even the `tryCatch` guard all error with
"argument is missing". `deparse()` is the one operation that handles it, returning `""`.

Both drafts failed loudly, which was luck. A scanner wrong in the reassuring direction would have
reported MATCH for nothing — hence the positive control now shipped alongside the check.

## Plan review: what was verified, and what was done

The Plan agent raised 7 blockers. Two were verified and are genuine — including one against the
design decision I had recommended to the user.

### B1 CONFIRMED — STAC item ids cannot detect an upstream reprocess

Measured live against `io-lulc-annual-v02`:

```
id                : 09U-2023
property keys     : datetime, end_datetime, io:tile_id, proj:bbox, proj:epsg,
                    proj:shape, proj:transform, start_datetime, supercell
created? FALSE      updated? FALSE
unsigned href     : .../io-annual-lulc-v02/09U_20230101-20240101.tif
```

The id is `<tile>-<year>` — a deterministic function of tile and year — the blob path is fixed, and
there is no `created` or `updated`. **If Microsoft re-derives 2023 in place, every id and every
href is byte-identical and so is any hash over them.** `stac_cache_key()` fails the same test;
item ids were a second request-side fingerprint, not a content pin.

**Fix: digest the classified rasters.** `rasters/<scenario>/classified_<yr>.tif` is the landcover
as it actually entered the model — measuring the output rather than restating the request. Verified
deterministic: two terra writes of identical values 1.2 s apart are byte-identical, and one changed
cell moves the hash. It also closes B7 for free, because the digest describes the bytes that were
read regardless of whether they came from a cache hit.

The item ids stay — they name what was read — but they are now labelled an identity, and
`classified_sha256` is the field that can fail. **stac#17's `nge:landcover_key` should be this.**

### B2 CONFIRMED — `terra::sources()` cannot return the DEM URL

`fl_dem_aoi()` always crops and reprojects, so the returned raster is derived. Measured on terra
1.9.34:

```
sources(rast(file))                     -> /…/file.tif
sources(crop(...))                      -> ""    inMemory TRUE
sources(project(...))                   -> ""    inMemory TRUE
sources(crop(...)) with todisk=TRUE     -> /private/tmp/…/spat_d54416755d68_54596_Sskvi….tif
```

Both branches are unusable and the disk branch is worse: a **random per-process temp path** that
differs every run, recorded as `dem_source` — a plausible-looking string that would silently break
byte-stability on exactly the large AOIs where it matters. Replaced with `dem_resolver` naming the
package default plus the raster's measurable geometry (`dem_crs_epsg`, `dem_res_m`, `dem_ncell`);
the URL stays recoverable from `flooded`'s version. Exposing it belongs upstream in `flooded`.

### B3 — already handled

`fp_prov_write()` already pins `null = "null"`, `na = "null"` and `digits = NA`, and the reader uses
`simplifyVector = FALSE`. Verified: `{"wsg_upstream": null}`, not `{}`.

### B4 — mitigated, not restructured

Per-section files would remove the read-modify-write entirely, but the merged file was the user's
explicit choice. Mitigated instead: a corrupt file aborts and names itself rather than silently
starting fresh; the write is atomic via same-directory tempfile plus a checked `file.rename()`; and
a **lost-update check** compares the file's mtime across the read-modify-write, turning a silent
overwrite into a loud abort. Areas and species must be run sequentially, which is what
`run_region.R` and the documented `FP_SPECIES` workflow already do.

### B5 CONFIRMED and fixed

`run_region.R:152-156` skips a cached group entirely, so its provenance stays whatever the last real
run wrote while the group reports `ok(cached)` and still reaches the publish hint. Now an **absent**
`provenance.json` invalidates the cache — so the forward-only rollout self-heals on the next region
run instead of being frozen out by the very cache — and a present one has its date printed and
carried into the coverage CSV.

The scenario lookup reads whichever landcover section exists rather than guessing `<sp>_ff04`;
MORR's chinook is `ch_ff06`, so the guess would have reported "date unread" for a group with a
perfectly good record.

### B6 — fixed

The disjointness check passed when `run` was absent (set arithmetic on nothing is silent), so it
now asserts `run` exists, is non-empty and carries `datetime_utc` **before** testing the
intersection. `item_ids_complete = FALSE` is now a FAILURE rather than a note — a `next` link means
drift's single-page fetch was truncated, so the raster was built from a partial item set, which is
a wrong raster and not a metadata caveat. The declared-key check is now a **whitelist**: an
undeclared key is reported, which a denylist grep for secret shapes can always be outrun by.

### Not adopted, with reasons

- **Reuse the existing `lnk_config("default")` at `01:231` for the log read.** Deliberately kept
  separate. Setting `$pipeline$schema <- read_schema` on the object passed to `lnk_stamp()` would
  change what the *stamp* describes — the "records the working-tree config, not the schema it
  grabbed from" gap #52 lists. Two objects, two purposes.
- **Per-section files instead of the merged file.** The user chose the merged shape; mitigated
  above rather than overridden.

### Corrected: the schema this repo GRABs from is `fresh`, not `fresh_default`

16 of 19 areas set `network_source: fresh`, including the neexdzii parity fixture and morr; only
kotl, larl and sloc use `fresh_default`. Issue #33 §4/§5 says `fresh_default` throughout, so its
caveat that `run_uid` will be null "because the schema predates link#262" is probably false for
most areas — `fresh` was rebuilt 2026-08-31/09-01. Null-filling stays correct either way; the
acceptance criterion that *expects* null does not. The issue needs a correction note.
