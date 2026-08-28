# Findings — deterministic GeoPackage writes (#45) + collection id (#41)

## Determinism probe, run at plan time (2026-08-28)

Probed against the real `data/morr/floodplain.gpkg` (7.5 MB, two species), not #45's 3-point
fixture. sf 1.1.2 / GDAL 3.8.5.

| probe | result | consequence |
|---|---|---|
| A — two writes of identical data, no pin | **differ** | confirms #45 at real scale |
| B — `Sys.setenv(OGR_CURRENT_DATE=…)` alone, no per-call argument | **identical** | GDAL reads config options from the environment, so the fix is one line per entry point, not 13 call-site edits |
| C — the real incremental sequence (`append = file.exists` + `delete_layer = TRUE`) | **identical** | the #23 multi-species write pattern is not itself a source of churn |
| D — rewrite one layer into an existing file (a step-3-only rerun) | **differ** | SQLite free-page state; bounds the guarantee |
| E — GeoTIFF via `terra::writeRaster` | **identical** | rasters already deterministic; no terra change, no COG change |

`config_options=` is available on `st_write` (sf 1.1.2) as a per-call fallback if the env route
ever stops holding.

### Why the env route over per-call `config_options`

13 `st_write` call sites across 5 files. Editing each one is repetitive and silently incomplete the
moment a 14th is added. `Sys.setenv()` covers every write in the process — including `st_delete`
and anything added later — for one line per entry point.

`packages.R` alone is NOT sufficient: `gpkg_backfill-wsg.R` and `fire_tag.R` are standalone CLIs
that do not source it (verified by reading their headers). Four entry points need the call.

## Decision: what to pin the stamp to

Fixed epoch `2000-01-01T00:00:00.000Z` (the value #45 verified). The stamp is deliberately
information-free — provenance belongs to #33's run record and the STAC properties, not a SQLite
housekeeping column no consumer queries. The alternative (derive from config hash / source date)
keeps the field meaningful but reintroduces churn whenever a config field changes without changing
the output, and encodes it in a form no consumer can decode.

## Prior art: bcgov/FIT_changedetector

Semantic change detection between two geodata sets: sha1 over `normalize()` +
`set_precision(precision, "pointwise")` geometry plus selected attributes, records classified
NEW / DELETED / UNCHANGED / MODIFIED_{ATTR,GEOM,BOTH} (`src/fit_changedetector/diff.py:113-145`).

**Does not replace the pin** — STAC `file:checksum` hashes the *bytes* of the published asset, and
no semantic diff makes a churning byte-checksum stable.

Three contributions:

1. **The right shape for probe D's fallback.** A content hash is invariant to SQLite page layout,
   layer write order and free-page state — exactly what breaks byte-identity on a partial rerun.
2. **`normalize()` before hashing** is a correctness detail we would likely have missed. Two
   topologically identical polygons with different ring order/start vertex hash differently without
   it. `code-check.md`'s cache-key section says to hash WKB rather than the sfc but says nothing
   about canonicalizing geometry first. NOTE: `sf::st_normalize()` rescales to the unit bbox and is
   NOT GEOS `normalize` — the sf equivalent needs verifying before that advice is written down.
3. **`add-hash-key`** gives features a content-stable identity across rebuilds — what #30's item key
   and #27's patch-level QA would each want.

**Not taken as a dependency**: Python/geopandas (conda) into an R pipeline, lifecycle Experimental,
and `compare` requires a primary key our layers do not carry. Its value would be on the transition
patch layer (thousands of patches with attributes), not `floodplain.gpkg` — a record diff over one
dissolved MULTIPOLYGON says only "MODIFIED_GEOM".

## #41 — scope

Two separable asks in one issue body:

- **The README id** (in scope here): `README.md:60` and `:100`. `:113`/`:118` and
  `scripts/publish_hint.R` correctly name the *repo* and must be left alone.
- **Publish the transition layer as its own asset** (split out): 38.1 MB bundle vs 5.8 MB layer,
  against a ~550 MB Mergin finalize ceiling. That work is in `stac_floodplains_bc`, which already
  reads the transition layer at `01_stage.R:81` and can extract it itself. Doing it producer-side
  would add an output for a consumer-side need and blur the one-way coupling.

## Phase 2 measurement: what the guarantee is, and where it stops

**A full rebuild into an absent file is byte-reproducible.** Verified through the pipeline's own
write shape on both real fixtures:

| fixture | layers | size | result |
|---|---|---|---|
| `data/morr/floodplain.gpkg` | 7 | 7.5 MB | identical, twice |
| `data/morr/floodplain_landcover.gpkg` | 18 | 79 MB | identical, twice (6.6 s) |

Cold path verified too: with `FP_GPKG_NO_PIN=1` the same rebuilds differ, so a pass means the pin
and not luck.

**`VACUUM` does not close the partial-rerun gap — but it isolates it to three bytes.** After
`VACUUM`, a file that had one layer rewritten differs from a fresh full rebuild in exactly 3 bytes
of the SQLite header, with identical page count and identical content:

| offset | field | fresh rebuild | after partial rerun |
|---|---|---|---|
| 24–27 | file change counter | `0x2f` (47) | `0x36` (54) |
| 40–43 | schema cookie | `0x6d` (109) | `0x82` (130) |
| 92–95 | version-valid-for | `0x2f` | `0x36` |

(28–31 database size in pages: `0x725` in both. `cmp -l` reports 3 differing bytes out of 7.5 MB.)

These are **write-history counters**, not content. The change counter records how many times the
database has been modified and the schema cookie how many times its schema changed; a
`delete_layer` + recreate is a schema change. By definition they cannot be normalized to a
content-derived value — they exist to record that history.

So `VACUUM` is **not adopted**: it adds a step, does not reach byte equality, and the residual
delta is unstable by design. (Cost was not the reason — two VACUUMs on 7.5 MB took 0.07 s.)

**The consequence, stated plainly:** byte equality answers "is this the same build?", not "is this
the same content?". For a partial rerun the second question needs a content hash over normalized
geometry plus attributes — the FIT_changedetector shape — which is follow-up work, not this PR.
Filed rather than half-built.
