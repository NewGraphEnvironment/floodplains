# #65 — Provenance records the recipe, not the cake

## Outcome

`data/<area>/provenance.json` split every entry into `inputs` (byte-stable, hashed) and `run` (the
run event, not hashed) — but two of the three sections hashed a **description of the job** and
nothing about the data, and one recorded a value that was simply wrong. The network's hashed set
held the watershed group, the species and package versions, with `link_log` sitting outside it as a
sibling; the floodplain's held VCA parameters plus `dem_ncell`/`dem_res_m`, which pin the grid and
not the elevations. So an upstream rebuild moved nothing. Every section now carries `outputs` +
`outputs_hash` beside `inputs` + `inputs_hash`, never folded together, because "same answer from
different data" and "different answer" are two findings and one hash cannot report both.

The network digest is taken **pre-subset** into `inputs` and **post-subset** into `outputs`: the
reach subset is `st_transform` + `st_intersects`, so a post-subset digest inside `inputs` would have
made `inputs_hash` a function of the sf build — the cross-machine churn #64 removed, one field over.
`id_segment` was rejected as the key (numbered per group during generation) in favour of the
FWA-native composite. `link_config_name` was a hardcoded `"default"` that was wrong on **every**
GRAB, and since every area in every region GRABs, every published area was asserting a methodology
it had not used.

Three review rounds found five bugs, and the third found the mechanism behind them: every property
in the guard read a key set, a shape or a vocabulary, and none read a **value** — eight published
values were mutated one at a time in a real record and the guard passed on all eight. `7c RECONCILE`
closes that class by re-deriving each published `outputs` value from the artefact it names.

## Measurement

- **Output-neutral.** Every raster digest on both areas is byte-identical to a baseline captured
  before any run. Parity contract unmoved: **673.5 km / 142.82 km²** (153,836 valley cells).
- **The split test**, from two independent runs of two areas: neexdzii's pre-subset digest and
  bulk's whole-WSG digest are the same value (`fcfd9d31…`); neexdzii's post-subset is its own
  (`1f88bf8b…`).
- **The defect isolated.** Same source, one segment's length changed by 1 cm, every other `inputs`
  field byte-identical: pre-#65 the two hashes are **identical**, post-#65 they differ. The issue's
  own criterion (`fresh` vs `fresh_default`, +0.40% divergence) passes but is **not discriminating**
  — `read_schema` is in `inputs` and differs between those two GRABs, so the old hash would have
  differed for a reason unrelated to content.
- **`transition_patches` was 42x wrong** — 48 recorded against 2032 actual features — because
  drift's `summary` is one row per transition class-pair. Inside `outputs_hash`, headed for STAC.
- **`channel_width` was missing from the digest.** `fl_valley_confine()` auto-buffers by it;
  tripling every width left both network digests byte-identical while adding ≥ 2.7 km² (+1.9%) of
  floodplain.
- **Signed zero moves a digest.** Written as a premise on the assumption it could not (`identical(-0,
  0)` is TRUE) and the assertion went red — `digest()` hashes serialized bytes. Unreachable for the
  Int8 landcover, live for the float rasters this added.
- **`fp_norm_block` mutation counts re-measured**: NA collapse alone 3 FAILs, signed zero 1, the
  cast 0, all three 5. The comment's old 2-and-3 went stale the moment this issue's own assertions
  landed.
- **The `datatype = "FLT4S"` pin is a no-op on bytes** — measured identical with and without.

### Wrong turns, kept

The network digest was first specified post-subset on the reasoning that it measured "what step 2
reads". Two things were wrong with that: it imports PROJ/GEOS into the hashed half, and 02 re-reads
from the GeoPackage anyway, so the identity claimed did not hold. The first `outputs` key reused the
input digest's name and tripped the overlap arm of the guard written in the same change. And three
guard mutants built by *adding* to the fixture stopped being mutants as later phases gave every
section an `outputs` block — rebuilt by removal and by moving the scope.

## Evidence

`scripts/floodplain_lcc/logs/20260902_provenance_outputs_live-verify.md` — the full run record.
Review findings: `review-round1.md`, `review-round2.md`, `review-round3.md` in this directory.

## Follow-ups

- **#73** — roll the fields out to the remaining 18 areas (forward-only; only neexdzii had a
  `provenance.json` before this branch, so that debt predates #65).
- **#72** — vector outputs still have no content digest.
- `stac_floodplains_bc` needs its own change for `schema_version = 2` and the `outputs` sibling.
- Round 3 declined to call the branch terminal and named `fl_valley_attribute` as the one place its
  enumeration did not reach. Carried forward rather than dropped.

Closed by: PR #74
