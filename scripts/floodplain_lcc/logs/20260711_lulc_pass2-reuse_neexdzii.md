# fp_lulc Pass-2 reuse — validation + speedup (#11, corrected #13)

**Date:** 2026-07-11 · **Stack:** drift 0.6.0, terra 1.9.34 · **AOI:** neexdzii `co_ff04`
(14 sub-basins) · **Change:** Pass 2 crops+masks Pass 1's `classified_all` per sub-basin instead
of re-fetching STAC.

> **Correction (this file first reported a FALSE result).** The initial reuse code called
> `terra::crs(classified_all)` — but `classified_all` is a *list*, so Pass 2 errored
> (`crs` on `"list"`) and halted **before** writing `lulc_summary.rds`. The run still exited 0
> (wrapper), and the A/B compare then read the *unchanged* baseline file against its own backup —
> a trivial "identical / 12.4×" that was an artifact of the crash, not a validated result. Fixed
> in #13 (crop/mask each list element; get CRS from `classified_all[[1]]`). Numbers below are the
> real, post-fix run, verified by: no `Execution halted`, `lulc_summary.rds` newer than run start,
> all 14 sub-basins processed.

## Speedup (real — Pass 2 executed)

| run | STAC queries | real (s) |
|---|---|---|
| baseline (re-fetch per sub-basin) | 15 (1 Pass 1 + 14 Pass 2) | 631 |
| reuse (crop+mask Pass 1) | **1** | **54.9** |

**11.5× faster.** Pass 2's 14 fetches become in-memory crop/mask (~4 s for all 14 on top of the
~51 s Pass 1).

## Correctness — near-identical, NOT byte-identical

Per-sub-basin `lulc_summary` (245 rows) vs the true baseline (14 independent fetches):
- total area 52,632.3 → 52,629.7 ha (**−2.58 ha, 0.005%**); max per-row delta **2.21 ha**
  (0.4% of a 519 ha class·basin·year); 46/245 rows differ > 0.5 ha.
- Cause: the reuse assigns every sub-basin from the **single floodplain grid**; independent
  fetches each land on their **own auto-UTM grid**, so boundary pixels shift. The reuse is
  arguably *more* consistent — sub-basins cleanly partition one grid rather than re-gridding, so
  they sum to the whole-floodplain total without boundary double-count/gap.
- Whole-floodplain **tree loss unchanged at 943.13 ha** (Pass 1 untouched).

## Verdict

Adopt: 11.5× faster, sub-basin summaries within 0.005% (VCA-noise band) and arguably more
internally consistent, whole-floodplain numbers unchanged. Impact scales with sub-basin count
(neexdzii 15→1 fetches); whole-WSG groups (1 sub-basin) halve their fetch.

**Process lesson:** a wrapper exit 0 is NOT "the work finished." Gate on `Execution halted` +
the output file's mtime before trusting any A/B — the crash-before-write masqueraded as a perfect
result.
