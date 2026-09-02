# #63 — Verify #33's provenance block against a live database

**Closed 2026-09-02.** #33 shipped the per-area `provenance.json` with its offline half fully
exercised; the half needing a database had never run. This issue ran it: a two-pass A/B on m1, a
link-version check, and the same pipeline on m4 reading m1's database over tailscale.

**Outcome: PASS**, plus two bugs and five design holes that only a live, two-machine run could
reach. The issue was itself filed on a false premise ("postgres is down" — a bad probe), which is
why so much of it fell out on first contact with a working connection.

## Measurement

**The A/B.** Five of five entries, `inputs_hash` identical across two passes, `run.datetime_utc`
moved in every entry, `provenance-check.R` green. Parity unmoved: **673.5 km / 142.8 km² /
770.0 ha**. `classified_sha256` and `item_hash` identical across passes; freshness guard 0.006%
against a 2% tolerance.

**The wholesale-read design, demonstrated rather than asserted.** Installed link 0.47.3 names 26
columns in `cols_log`; the recorded row carries **30**. Reinstalling to 0.50.0 left it byte-identical
at 30. That is the claim #33 rests on, tested for the first time.

**Two of #33's predictions were wrong.** `run_uid` is populated, not null (§5 measured
`fresh_default`; neexdzii GRABs from `fresh`). And the issue conflated `link_log$link_sha` — written
by link at pipeline time, populated — with `fp_pkg_stamp("link")`, which describes the *installed*
package and was correctly NA while install and checkout disagreed.

**Cross-machine: the science agrees, the detector does not.** m4 ran the identical commit against
m1's database. Every published number matched to every digit (673.48 km / 142.823 km² / 770.02 ha /
2032 patches) and `network[co3]`'s hash was identical across machines. Three of five hashes still
differed — one cosmetic, one substantive:

```
2017  geometry_identical=TRUE  cells=28291615  differing=0  bytes m1=969220 m4=979248  delta=+10028
2020  geometry_identical=TRUE  cells=28291615  differing=0  bytes m1=981296 m4=991324  delta=+10028
2023  geometry_identical=TRUE  cells=28291615  differing=0  bytes m1=974362 m4=984390  delta=+10028
```

28.3M cells, zero differing, identical extent/CRS/resolution/LZW/palette — different digest, by a
constant +10,028 bytes. TIFF tag **42112 (`GDAL_METADATA`)**: 382 bytes under terra 1.9.34, 5,396
under 1.9.11. So `nge:landcover_key` is a *container* hash, machine-specific (#64) — and
undiagnosable from the record, because terra and sf are not among the stamped packages.

**A bug the wrapper hid.** Step 3 aborted and `caffeinate` exited **0**; the `-nt` mtime gate passed
too, because step 2 writes before step 3 runs. Only the in-band error count caught it. The bug: the
#54 bridge hoists its patch key into a standalone vector before the zero-area filter and reuses it
after. Trigger a single **9.9e-5 m²** pair that `round(ov_ha, 4)` sends to `0.0000` ha. Introduced by
36145d3 — the fix for #54's per-tenant key — which landed **one minute after** the last neexdzii run,
and neexdzii is the only multi-sub-basin area.

## The wrong turns, kept

- The issue's own premise was false, and #33's archive had recorded the same misdiagnosis. Both
  corrected before this work started.
- **Round 2's fix reproduced the class it was fixing.** It gated a message on
  `isTRUE(sf::st_delete(...))` on the stated premise that `st_delete` returns FALSE on failure. Half
  true: with the containing directory read-only, GDAL fails, the layer survives, and it returns
  **TRUE**. Round 3 caught it; verified independently before acting. The fix is to re-read the layer
  list — measure the output, not what the library says it did.
- A print of the resolved repo root was added and placed *before* the variable existed. Caught by
  re-running, not by reading.
- The comparator's PASS line claimed "every config-derived entry present" even when no area was
  given and no inventory had run.

## What landed

- `03_lulc_classify.R` — the bridge key fix, plus stale-layer cleanup hoisted where all three
  reachable "no bridge this run" paths meet it (the fourth is #68, named rather than claimed).
- `provenance-check.R` — a §7b **inventory assertion** deriving the expected entry set from the area
  config. The old guard exited 0 on the 4-of-5 file the abort left: every property it had was "every
  entry PRESENT is well-formed", and an absent entry has no presence to be malformed.
- `provenance_ab-compare.R` — **new**, so the A/B is re-derivable. Exercised against four inputs
  built to break it, including two fail-toward-pass shapes: an entry absent from *both* files, and
  `inputs_hash` absent from both (`identical(NULL, NULL)` is `TRUE`).

## Follow-ups

#64 (landcover digest — gates `stac_floodplains_bc#17`), #65 (GRAB config name + no content pin),
#66 (`fp_pkg_stamp` path/checkout in the hash), #67 (`link_log` published unfiltered),
#68 (zero-patch run stamps over stale layers).

## Evidence

- `scripts/floodplain_lcc/logs/20260902_provenance_live-verify_neexdzii.md` — the committed record.
- `scripts/floodplain_lcc/logs/runs/20260902_*_run-area_neexdzii_*` — the six run logs (gitignored).
- `findings.md` here carries the per-phase measurements; `review-round[1-3].md` the code-check rounds.

Closing commits on branch `63-verify-33-s-provenance-block-against-a-l`; PR linked from #63.
