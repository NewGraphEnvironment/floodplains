# #33 — Record run provenance per area

Every run now writes `data/<area>/provenance.json`: what produced the outputs, machine-readable,
for `stac_floodplains_bc#17` to publish as STAC item properties. Three sections written by the step
that knows the facts, each split into `inputs` (byte-stable across reruns, summarised by
`inputs_hash`) and `run` (the run event). `provenance-check.R` enforces the split with no database.

Unblocks stac#17. Forward-only: an area carries a block once re-run.

## Measurement

The central design decision changed twice under measurement, both times because a candidate
fingerprint turned out to describe the **request** rather than the **response**:

| candidate | detects an upstream reprocess? | why |
|---|---|---|
| `stac_cache_key()` (as issued) | **no** | hashes AOI + request params, nothing about the items |
| STAC item id hash (as planned) | **no** | id is `<tile>-<year>`; no `created`/`updated`; href fixed |
| `sha256(classified_<yr>.tif)` (shipped) | **yes** | the bytes that actually entered the model |

Verified live against `io-lulc-annual-v02`, and the raster digest verified byte-deterministic
across writes (two writes 1.2 s apart identical; one changed cell moves the hash).

Two values proved **unrecordable** and are written as explicit absences rather than guesses:

- the DEM URL — `terra::sources()` on `fl_dem_aoi()`'s cropped-and-projected return is `""` in
  memory and a *random per-process temp path* when terra spills, which would have differed every
  run while looking like a real value
- a package git SHA where the checkout version disagrees with the install (link checkout 0.49.0 vs
  installed 0.47.3) — the checkout HEAD describes code that did not run

Also corrected: **16 of 19 areas GRAB from `fresh`, not `fresh_default`**, so the issue's caveat
that `run_uid` would be null "because the schema predates link#262" is false for most areas.

## The wrong turns, kept

The guard found four defects while it was being written, three fixed in the writer rather than the
test: a checkout SHA for a different installed version, a CRAN `RemoteSha` that is a version string
(`"1.1-2"`), duplicate keys from `c()`, and `$` partial-matching `link_log` to `link_log_note`. The
producer/guard key-drift scanner was wrong on its first two drafts — a regex version reported 1 key
where there are 9, and an AST version died on R's **empty symbol** in `row[1, ]`. Both failed
loudly, which was luck; a scanner wrong in the reassuring direction would have reported MATCH for
nothing. Hence the positive control shipped beside it.

A plan review raised 7 blockers; 2 verified genuine and fixed (including the item-id one above),
3 partly already handled, 2 mitigated rather than restructured with the reasons recorded.

## Evidence

`planning/archive/2026-09-issue-33-run-provenance/findings.md` — every measurement above with the
probe output. `review-33.md` — the plan review and its disposition.

## Not done

The **neexdzii end-to-end A/B and the parity-fixture re-check are outstanding**: postgres is not
running on the machine this was built on, so `lnk_log_read()` has never executed against a live
`fresh.log`. Everything else was exercised, including a two-run A/B through the real writer against
live STAC showing `inputs_hash` identical and `run.datetime_utc` moving.
