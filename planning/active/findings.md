# Findings — Support multiple species per area (#23)

## Issue context

The pipeline is one-species-per-area: `area.yml` carries a single `species`, a run writes
per-species outputs into `data/<area>/`. We want a second species to coexist with the first in the
same `data/<area>/` gpkgs (MORR chinook alongside coho), without destroying the coho outputs. Today
it can't: hardcoded coho layer names, whole-gpkg wipes each run, and scenario selection not filtered
by species.

## Plan-agent review — findings that shaped the plan (2026-07-18)

An adversarial Plan-agent review of the first design caught what the initial pass missed:

1. **BLOCKER — `03_lulc_classify.R:105` `file.remove(floodplain_landcover.gpkg)`.** The first design
   wrongly called step 3 "already multi-species safe" (citing per-layer `delete_layer=TRUE`). Step 3
   has the SAME whole-file wipe as 01/02. A chinook run would destroy the coho `classified_co_*` +
   `transition_co_*` layers. Fix: drop L105; L112's `append = file.exists()` already handles it.
2. **BLOCKER — `run_region.R:131` hardcoded `layer = "streams_co3"`.** The network-layer rename is a
   repo-wide contract change; run_region's coverage gate reads `streams_co3` and would report
   `FAIL(empty network)` for every chinook batch group. L135 is already species-aware (`paste0(sp,
   "_ff04")`) — match it: `paste0("streams_", sp, min_order)`.
3. **Gap/Blocker — generic `lulc_summary.rds` (03:184) clobber.** Consumed by `05:80`, the external
   report, and `run_region.R:117-120` (the "group complete, skip" cache key). Last species to run
   step 3 wins. Resolution for this issue: document it as a last-writer-wins active-scenario pointer;
   the per-scenario `lulc_summary_<scenario>.rds` is the durable store. Consumers stay coho (scope).
4. **Assumption — `primary_scenario` prefix surgery is fragile.** Don't regex-swap `co`→`ch`; use
   explicit `FP_PRIMARY_SCENARIO`, default `paste0(species,"_ff04")` only when unset, and guard.
5. **Env var > CLI arg** for species selection: `fp_read_config` is the override home,
   `run_region.R:124` uses `system2` positional args (env propagates free), and the repo idiom is
   "override at runtime without editing committed config."
6. **Verified safe:** `sf` 1.1.1 `st_write` to a character `.gpkg` path accepts `append=TRUE` +
   `delete_layer=TRUE` together (guard only on the DBI branch); replaces named layer, preserves
   siblings — the idiom `03:112` already uses. Named-layer reads mean orphan layers never enter the
   measured numbers, so parity is read-safe. Still gate parity on a CLEAN `data/neexdzii/`.
7. **Gaps:** waterbodies write (01:207) needs the same append/delete idiom; stamp sidecar (01:224)
   should be species-suffixed; orphan layers persist if a scenario's `run` flips TRUE→FALSE
   (acceptable, named-layer reads unaffected — document).
8. **Scope confirmed coho-only (out):** `05:55/98/130`, `04:65` — downstream zones/prioritization
   stay coho. "MORR chinook modelled" = data-layer coexistence only.

## Run results
(to be filled during Phase 4)
