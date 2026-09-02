# #65 live verification — `inputs`/`outputs` digests, neexdzii + bulk

Date: 2026-09-02. Machine: m1 (single machine — see "What is NOT verified" below).
Branch: `65-provenance-records-the-recipe-not-the-ca`.

Every run gated on the **in-band error count and the output mtime**, never the wrapper's exit code
(`scripts/floodplain_lcc/logs/` convention; see `/tmp/fp65/verify_runs.sh` in-session). All three
runs reported `errors=0` and a `provenance.json` newer than a marker touched at run start.

## Baseline, captured BEFORE any run

So parity is checkable rather than asserted.

```
neexdzii  streams_co3            1915 segments, 673.5 km
          floodplain_co_ff02.tif 131.37 km2  sha256:bf2c4b0cd900f9dc...
          floodplain_co_ff04.tif 142.82 km2  sha256:8eb759465c44c159...
          floodplain_co_ff06.tif 149.99 km2  sha256:9c2b058078190c11...
          transition.tif                     sha256:1e379aeed3059fcd...
bulk      streams_co3            6858 segments, 2205.7 km
          floodplain_co_ff04.tif 386.53 km2  sha256:aceae2548a7f7c90...
```

## 1. The change is output-neutral

Every artefact digest after the re-run is **byte-identical to its baseline**, including the
floodplain rasters written through the newly pinned `datatype = "FLT4S"`. Parity contract unmoved:
**673.5 km / 142.82 km²**, 153,836 valley cells at 928.4114 m².

The `datatype` pin was separately measured a no-op: writing the same raster with and without the
argument produces identical bytes.

## 2. A/B — two full neexdzii passes against identical code

```
entry                          inputs   outputs  datetime
network[co3]                   same     same     moved
floodplain[co_ff02]            same     same     moved
floodplain[co_ff04]            same     same     moved
floodplain[co_ff06]            same     same     moved
landcover[co_ff04]             same     same     moved

PASS — every config-derived entry present in both, inputs_hash and outputs_hash
       identical, run.datetime_utc moved.
```

`datetime` moving is the part that matters: without it, comparing a file against an untouched copy
of itself passes the hash check perfectly, which is what a run that crashed before writing produces.

## 3. The pre/post-subset split, measured

neexdzii and bulk are both `network_source: fresh` GRABs on watershed group **BULK**, species co,
min_order 3 — one subset to a reach, one whole group. So the split predicts an identity and a
difference, from two INDEPENDENT runs of two different areas, and both hold to the byte:

| | `inputs` (pre-subset) | `outputs` (post-subset) |
|---|---|---|
| neexdzii (subset) | `fcfd9d31…` | `1f88bf8b…` |
| bulk (whole WSG)  | `fcfd9d31…` | `fcfd9d31…` |

- pre-subset digests **identical** across the two areas — they read the same network
- neexdzii's post-subset **differs** from its pre-subset — the subset removed something
- bulk's pre == post — a whole-WSG area has no subset to apply

`7c` asserts the last of these directly for any whole-WSG area, so it is a standing check rather
than a one-off observation.

Nothing had to be built to get this test — it falls out of two areas that already existed.

## 4. The defect, isolated

The issue's own criterion — *"GRAB from `fresh` and from `fresh_default`, assert the two network
hashes DIFFER"* — passes:

```
fresh           6858 segments   2205.7 km   sha256:37edc39d40a8f574...
fresh_default   6879 segments   2214.6 km   sha256:2a2432328e5fd30a...
divergence +0.40%   digests DIFFER: TRUE
```

**But it is not a discriminating test, and that is worth recording.** `read_schema` and
`network_source` are both in `inputs` and differ between those two GRABs, so the pre-#65 hash would
have differed too — for a reason that has nothing to do with the network's content.

The test that isolates the defect is *same source, different data*. One segment's `length_metre`
changed by 1 cm, every other `inputs` field byte-identical:

```
PRE-#65  fresh          sha256:06d09a81b64b5174...
         fresh, 1cm off sha256:06d09a81b64b5174...   -> IDENTICAL   (the defect)
POST-#65 fresh          sha256:6516edff1b1015f7...
         fresh, 1cm off sha256:88b587d60561aaa1...   -> DIFFER
```

## 5. The wrong value, fixed

```
before   inputs.link_config_name = "default"    link_log.config_name = "bcfishpass"
after    inputs.link_config_name = "bcfishpass" (source: link_log)
```

Both neexdzii and bulk GRAB from `fresh`, and every row in `fresh.log` reports `bcfishpass`, so
**every area in every region was recording the wrong methodology** — not just this one.

## 6. bulk

```
[19:48:50Z] start bulk_p1 (bulk)
[20:46:08Z] OK    bulk_p1 (errors=0, provenance rewritten after marker)
```

57 minutes, dominated by the per-watercourse attribution (#40 records it at 12–14x the delineation)
and a step-3 STAC fetch that hit drift's cache. All five entries present, guard PASS including 7c:

```
network[co3]        n_segments 6858 == 6858        streams_content_sha256 re-derives
                    whole-WSG: pre- and post-subset digests agree
floodplain[co_ff02] valley_cells 370201            digest re-derives
floodplain[co_ff04] valley_cells 415100            digest re-derives
floodplain[co_ff06] valley_cells 445227            digest re-derives
landcover[co_ff04]  transition_patches 7161 == 7161 (feature count)  digest re-derives
```

Every floodplain raster digest is byte-identical to the baseline captured before any run
(`68fc02c0…`, `aceae254…`, `d373bc67…`), so bulk is output-neutral too. `link_config_name` reads
**`bcfishpass`** (source `link_log`) where it read `default`.

**bulk was published to STAC recently**, which is why it was chosen: it is the area whose provenance
a consumer is most likely to be reading right now, and it was the one asserting the wrong
methodology.

## 7. The guard the verification produced

Round 3 measured that every property in `provenance-check.R` was about a KEY SET and none about a
VALUE: all eight published `outputs` values were mutated one at a time in a real record and the
guard printed PASS on all eight. That is how `transition_patches` shipped at 48 against 2032.

`7c RECONCILE` closes the class — it re-derives every published `outputs` value from the artefact it
names. Its own positive control is in this branch's history: run against the record written one
commit earlier, it is **red on exactly the one stale value** (the network digest, whose column set
had just changed) and green on the other fourteen.

Two arms are honest about being weaker than they look: the digest comparisons are semi-circular,
verifying "the record describes THIS file" rather than "this file is correct". That is still the
property that broke when a zero-transition run digested the previous run's raster.

## What is NOT verified

**Cross-machine.** This is one machine. #63's two-machine A/B is the check that would settle
whether `dem_content_sha256` is stable across toolchains — `fl_dem_aoi()` crops and reprojects, so
its cell values are GDAL/PROJ warp output, and #63 compared the DEM's *geometry* across m1 and m4
but never its heights. The response is decided in advance and written at the call site in
`02_floodplain_model.R`: if a two-machine run shows the digest moving with the data unchanged, it
moves to `outputs` (diagnostic, not required to match) rather than being deleted.

`fp_pkg_stamp`'s free-text `sha_source` was removed from `inputs` in this branch precisely so that
such a run would be readable — with it in place, a real content difference and a sibling checkout
being one release ahead produced the same observation.
