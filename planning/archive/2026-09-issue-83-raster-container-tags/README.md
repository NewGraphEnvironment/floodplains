## Outcome

`classified_*.tif` written on terra 1.9.11 carried 30 gdalcubes/NetCDF tags in TIFF tag 42112 —
two of them contradicting the raster they sat on, one leaking a `/tmp` path — and a `CreateCopy`
in `stac_floodplains_bc` carried them into the published COGs. The cause needed no new experiment:
the #79 annual run had already been split across two machines with terra left as the only
unlevelled package, so the discriminator was read out of each area's own `provenance.json`, the
field #64 exists to make this diagnosable. The fix is a **pin**, not a machine upgrade —
`scripts/fp_raster.R` strips the container and then re-reads the written file and refuses to
continue, and all three `writeRaster` sites route through it. `provenance-check.R` §5f guards it
offline; §7 now re-derives every `classified_content_sha256` from its raster, which was the one
recorded digest never reconciled against its artefact. `raster_strip-tags.R` reconciled the 14
files already on disk.

What the work actually turned on was **not** the diagnosis, which was settled in the first hour,
but a series of wrong measurements — three of them mine, each stated confidently before being
checked. `gdal_edit.py -unsetmd` was rejected for destroying the RAT and does not: the test had
copied the `.tif` without its `.aux.xml` and compared it against an original that had one. The
repair's first draft then deleted that sidecar as a regenerable statistics cache and silently
removed the published class names while every checksum agreed. And two figures ("116 tifs", "512
category rows") were stated rather than counted, each in three places, so fixing one would have
left the others reading as corroboration. Three review rounds plus a plan review found eight
further defects, and the last of them was **inside** a fix: §5f's must-fail arm never called
`fp_rast_write`, so gutting the refusal left the section 14 of 14 green — on the one line the
prose nominated as load-bearing. The loop ended by enumeration rather than by a quiet round, once
the reviewer named the mechanism: on this machine three raster states (no metadata, exactly
`AREA_OR_POINT`, tags in a sidecar) produce one observation, and every earlier defect was that
collapse at some level.

## Measurement

- **Discriminator, 4 areas:** terra 1.9.34 (bulk, lnth, m1) → 0 stray tags; terra 1.9.11 (necr,
  kotl, m4) → 30 tags on all 7 years. Read from `provenance.json`, not re-measured.
- **Blast radius:** 184 `.tif` across 23 areas — 88 classified, 72 floodplain, 24 transition —
  **14 dirty**, all classified in necr and kotl. The first sweep said 116 and globbed 112, missing
  step 2's outputs entirely.
- **Which terra ops carry metadata:** `crop` / `mask` / `deepcopy` preserve (5 of 5 tags);
  `classify` / `app` / `ifel` / `r*1` / `patches` drop (0). So `transition.tif` is clean because
  `dft_rast_transition()` rewrites values — *not* because it "builds a new raster", which was the
  first answer written and is wrong: `mask()` builds one and is how the tags arrive.
- **`rast(<gdalcubes .nc>)` on 1.9.34 yields 0 metags**, so the divergence is on the read side and
  the strip is a **no-op on m1**. The refusal, not the strip, is what carries the assurance here.
- **Repair route, four candidates:** every GDAL in-place variant grows the file ~54 kB per run
  (1,699,519 → 1,753,590 → 1,807,660 → 1,861,730) and is not byte-idempotent; the terra rewrite is
  10 kB smaller and is the fixed pipeline's own path. One permitted deviation, the nodata palette
  entry `255: 0,0,0,0` → `255: 255,255,255,0`, alpha 0 both ways.
- **Acceptance:** 0 stray tags across all 184 tifs; 14 of 14 `classified_content_sha256` re-derive
  against digests recorded before the repair existed; class names present on all 14;
  `provenance-check.R` green on necr, kotl, bulk, lnth, neexdzii (necr and kotl reported *7 of 7
  dirty* before). `run_area.R neexdzii 3` re-fetched every year and reproduced `outputs_hash`,
  2032 patches and every content digest to the byte; `inputs_hash` moved on exactly one of 26
  fields, `drift.version` 0.8.0 → 0.13.0.
- **Guard proven able to fail five ways**, one per collapsed state: strip disabled, unguarded
  `metags<- NULL`, refusal gutted, reader made PAM-sensitive, allowlist emptied — five distinct red
  sets. And the repair's unchecked `file.rename` demonstrated: without the check it reported
  `Repaired 1 of 1`, exit 0, on a file still carrying its tags.

## Evidence

`scripts/floodplain_lcc/logs/20260905_raster-tags_strip_necr-kotl.md` — the repair's committed
record, since `data/` is gitignored. The cause rests on
`scripts/floodplain_lcc/logs/20260905_lulc-annual_split-run.md`, which predates this issue.

Follow-ups filed rather than folded in: NewGraphEnvironment/drift#63 (the tags originate in
`dft_stac_fetch()`), #84 (`STATISTICS_MEAN=-9999` rides into every published COG on every area),
and stac_floodplains_bc#59 (necr and kotl need a COG rebuild to pick this up).

Closed by: PR (branch `83-classified-tif-carry-30-stray-gdalcube`)
