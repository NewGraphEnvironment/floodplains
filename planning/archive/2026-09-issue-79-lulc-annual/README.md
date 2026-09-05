## Outcome

Added an opt-in per-area `lulc_annual` key so step 3 fetches every year of `change_interval`
(2017-2023) instead of the endpoints plus midpoint, and re-ran step 3 for **bulk, necr, lnth,
kotl** so drift's `dft_rast_break_class()` has the full annual series (drift#62). The pipeline
change is one line at `03_lulc_classify.R:49` plus the config key — everything downstream already
iterated `names(classified_all)`, and the transition reads `change_interval`, never the fetched
year set, so it does not move.

Three things planning changed about the issue as filed. **PINE was dropped**: its `data/` predates
`flooded` 0.5.0, so step 3 would have classified land cover over a floodplain the repo already
calls dead rather than superseded — it and MCGR are tracked in #76, which now asks for both to
arrive with `lulc_annual` on so neither runs twice. **The proposed A/B gate could not have
failed** — drift's `stac_cache_key()` excludes `years` and the STAC query range is
`min..max` either way, so comparing shared years across a 3-year and 7-year run would have
asserted a file equals itself; the acceptance became a named expected-failure set for
`provenance_ab-compare.R`, which reports a moved `inputs_hash` as a failure and under this change
must. **The 23.6 min cost figure described a tiled path** no committed config takes.

The run was split across two machines, which needed a control first because any difference between
them is a confound. m4 was levelled to m1 on drift, sf and gdalcubes; terra could not be matched,
which left it the single variable, and the control passed on it. Two follow-ups were split out
rather than folded in: **#80** (gdalcubes writes every landcover cell and is in no provenance
field — recording it needs a per-section key set, because a required `KEYS_TOOLCHAIN` member would
fail `provenance-check.R` on the `floodplain[*]` entries this issue deliberately does not re-run)
and **#81** (`item_ids_complete` cannot be FALSE on drift >= 0.10). Downstream,
`stac_floodplains_bc#61` was split out of stac#59 for the same reason — #59 bundled a code
generalization, a collection-wide policy decision and a data operation behind three different
blockers.

## Measurement

Cross-machine control, neexdzii on m4 against m1's baseline: `outputs_hash`, transition digest,
patch count (2032) and all three per-year `classified_content_sha256` **identical**, across terra
1.9.11 vs 1.9.34 **and** drift 0.8.0 vs 0.13.0. necr and kotl reproduced the same result on real
published areas. This is `fp_raster_content_sha256()` (#64) demonstrated rather than asserted.

| area | machine | bbox Mcells | wall | peak RSS | change patches |
|---|---|---|---|---|---|
| necr | m4 | 55 | 9.2 min | 17.8 GB | 5 692 |
| kotl | m4 | 203 | 32.4 min | 54.3 GB | 4 929 |
| lnth | m1 | 62 | 14.4 min | 16.5 GB | 2 753 |
| bulk | m1 | 168 | 34.9 min | 20.6 GB | 7 161 |

49.3 min wall against 91.9 sequential. bulk's 7 161 patches match CLAUDE.md's recorded 2026-09-02
figure exactly, corroborating that the transition did not move.

**Peak RSS does not track grid size** — KOTL at 203 Mcells peaked 2.6x higher than BULK at 168
Mcells, on different hosts. Plausibly terra sizing its working set against available RAM, but it
was not isolated and must not be quoted as a per-area requirement. What holds: 64 GB sufficed for
the largest area run on it.

Download throughput, real io-lulc asset in West Europe over one shared gateway: m4 2.05 MB/s alone,
m1 3.08 alone, **5.06 combined**. One stream does not saturate the uplink, so the split adds real
throughput — and m4 is the *slower* single stream despite the faster processor, which is why "is it
faster here?" had to be measured rather than reasoned from the chip.

Two wrong turns kept because they are the evidence: the cache was rsynced to m4 on the assumption
it would hit, and it did not — all four baselines were built under drift 0.8.0, whose keys predate
the 0.10.0 change. That made every year genuinely re-fetched, which is *better* for the acceptance
than the plan assumed. And two harness bugs of mine were caught by in-band markers rather than exit
codes: a waiter that reported completion mid-run (local `sleep` is blocked in this harness) and an
acceptance call that omitted the scenario `bridge-check.R` needs, failing on chinook necr.

## Evidence

`scripts/floodplain_lcc/logs/20260905_lulc-annual_split-run.md` (committed), over the gitignored
`scripts/floodplain_lcc/logs/runs/20260905_lulc-annual_*` set.

Closed by: commits ca38e4c, c64e1b9 / PR pending
