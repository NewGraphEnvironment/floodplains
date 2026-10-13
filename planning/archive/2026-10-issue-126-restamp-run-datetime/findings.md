# Findings — PR #85's in-place repair left run.datetime_utc behind the rasters (#126)

## Issue context

## What changes if we do it

`stac_floodplains_bc` can republish `necr_ch_ff04` and `kotl_bt_ff04` to pick up the #83 /
PR #85 container fix. Right now it **cannot**: `01_stage.R` refuses both areas, so
NewGraphEnvironment/stac_floodplains_bc#68 is blocked, and the 30 stray tags stay live.

## What happens if we never do it

The two repaired areas can never be republished from this tree — not for #68, not for anything
later — until something re-runs their landcover step in full. The repair is on disk and
unpublishable.

## What happens

PR #85 repaired the rasters **in place** and left `landcover.<scen>.run.datetime_utc`
untouched, so the files are now newer than the record that describes them. The publish layer's
freshness guard (`scripts/fp_provenance.R:462-490` in stac_floodplains_bc) compares each staged
raster's mtime against that stamp and stops:

```
Error: provenance.json necr_ch_ff04: 7 staged raster(s) are NEWER than the provenance record
that describes them (classified_2017.tif … classified_2023.tif) — newer than the section's run
stamp 2026-09-05T19:14:08Z. … Not publishing a fingerprint of bytes other than the ones shipped.
```

Measured 2026-10-12, and it picks out exactly the two repaired areas and no others:

| area | section run stamp | newest classified raster | staging |
|---|---|---|---|
| `necr` | `2026-09-05T19:14:08Z` | `2026-09-05T22:44:28Z` | **refuses** |
| `kotl` | `2026-09-05T19:46:31Z` | `2026-09-05T22:47:07Z` | **refuses** |
| `lnth` | `2026-09-05T19:17:07Z` | `2026-09-05T19:16:33Z` | ok |
| `bulk` | `2026-09-05T19:52:01Z` | `2026-09-05T19:50:08Z` | ok |

There is no override flag, by design.

The repair touched exactly the seven classified rasters and left `transition.tif` alone in
both areas (`necr` 22:43:48–22:44:28 vs transition 19:13:48; `kotl` 22:44:45–22:47:07 vs
19:45:26), which is itself evidence the repair did only what #83 claimed.

## The record is what is wrong, not the guard

`nge:produced_datetime` is published **from this very field**. In stac_floodplains_bc,
`scripts/fp_provenance.R:67`:

```r
produced_datetime = list(section = "landcover", path = c("run", "datetime_utc")),
```

and the comment above it (`:40`) says what it means: *"the LANDCOVER step's run timestamp …
the last one to touch the transition layer the published figures are aggregated from, so its
timestamp is the one that describes what was published."*

So the two areas currently report a production time of `19:14:08Z` for rasters produced at
`22:43–22:44`. **That is the dishonest state, and it exists now** — the guard is reporting it
accurately rather than being inconvenienced by it. A stamp is a record of when these bytes
came to be; the bytes came to be during the repair.

The pixel measurement below is therefore not a case for letting the stamp stand. It is
evidence for upstream that the repair was clean, and it is worth having for that:

```
necr_ch_ff04 2017: pixels IDENTICAL   gdalcubes tags published=30 repaired=0
necr_ch_ff04 2018: pixels IDENTICAL   gdalcubes tags published=30 repaired=0
kotl_bt_ff04 2017: pixels IDENTICAL   gdalcubes tags published=30 repaired=0
kotl_bt_ff04 2018: pixels IDENTICAL   gdalcubes tags published=30 repaired=0
```

sha256 over the decoded band. Independently, folding the current on-disk
`classified_content_sha256` over all seven years reproduces the `nge:landcover_key` both items
are serving **exactly**, so the content fingerprint is untouched — which is the field that
answers "did the values change", and it says no.

## Remedy: re-stamp the section

**Re-stamp `landcover.<scen>.run.datetime_utc` as part of any in-place repair.** The guard then
passes untouched, no publish-layer change is needed, and `nge:produced_datetime` becomes
correct for the first time since the repair.

**An earlier revision of this issue recommended the opposite and was wrong.** It proposed a
separate `run.container_repaired_utc` compared as `max(run stamp, repair stamp)`, on the
grounds that re-stamping would make `produced_datetime` "dishonest". That has it backwards:
the field means when these rasters were produced, so the honest value is the repair time, and
the proposal was schema whose purpose was to stop a published provenance value from moving.
These hashes and stamps exist to **track which iteration is live**, not to hold a published
artifact still — a new iteration moving them is them working. It was also a two-repo change
bought for nothing.

If the nature of the run is worth recording — a container repair is genuinely not a full
landcover re-run, and a consumer might want to know — that is an **additional** descriptive
field alongside a moved `run.datetime_utc`, never a second reference for the freshness
comparison.

Either way the publish layer should not grow an override: the guard caught a real
inconsistency, and the fix belongs in the record.
## Related

- #83 / PR #85 — the container fix this repair implements
- NewGraphEnvironment/stac_floodplains_bc#68 — blocked by this
- NewGraphEnvironment/stac_floodplains_bc#59 — the publish whose pre-publish gate found #83
- #117 — also about provenance describing something other than what shipped, different field

## Errors Encountered

| Error | Resolution |
|-------|------------|

## Measured while building (2026-10-13)

- `fp_prov_hash()` serializes `2017L` and `2017` identically (JSON), so it cannot see a type
  change; the re-stamp's "nothing else moved" comparison uses `identical()` on parsed JSON.
- `$toolchain` on a repair entry partial-matched a sibling `toolchain_recorded` and read FALSE
  where the check asked for an absent toolchain. Field renamed `backfilled`; checks use `[[`.
- Live 7c before the backfill: necr `ch_ff04` and kotl `bt_ff04` each FAIL with 7 late classified
  rasters; bulk `co_ff04` and lnth `ch_ff04` pass.

| Error | Resolution |
|-------|------------|
| 5g integer->double must-fail passed through fp_prov_hash | compare parsed objects with identical() |
| 5g backfill arm read `toolchain_recorded` via `$toolchain` | renamed to `backfilled`; `[[` in checks |
