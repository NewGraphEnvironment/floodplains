# Code-check round 3 — #122 DEM cache (branch diff, planning/ excluded)

## Mechanism

Prose written against the design, or against a draft, before the behaviour settled, and then
patched for the one instance a reviewer named rather than re-derived from the code. Round 2 fixed
the header's "no network" claim by counting the arms under the section heading ("the last three
arms") instead of the arms that actually call curl. Two of the three findings below are the same
shape: a count or an order stated from the layout of the code, not from what it does.

## Findings

- **[severity: fragile]** scripts/floodplain_lcc/dem_cache-check.R:6-7 — the header says "The last
  three arms ("the HEAD request fails closed") make real HEAD requests: offline they FAIL rather
  than skip." Only two do. The first arm, `fp_dem_object_version("/data/local/dem.tif")`, stops on
  the `/vsicurl/` guard before `curl_fetch_memory` is reached, so it makes no request and passes
  offline. Reproduced by tracing `curl::curl_fetch_memory` to throw (offline simulated): arm 1 is
  pass with 0 requests, arm 2 is FAIL with 1 request, arm 3 is FAIL with 2 requests. This is the
  round-2 fix, and it is still wrong. A reader who sees 2 failures offline would expect 3 and go
  looking for a third cause. The arm labels themselves are correct: "(needs network)" is on exactly
  the two that need it. Fix: "The last two arms ... make real HEAD requests".

- **[severity: fragile, low]** scripts/floodplain_lcc/provenance-check.R `dem_cache_reconcile`
  comment ("In order: ... the file digesting as recorded is a match, whatever the sidecar's key;
  under the recorded key, a file or a sidecar digest that differs from the record is a mismatch"),
  and CLAUDE.md's "A digest match passes." The code checks the same-key sidecar digest BEFORE it
  digests the file. So a file that digests as recorded, under a same-key sidecar whose
  `dem_content_sha256` differs, returns `mismatch`, not `match`. Reproduced with a 4x5 FLT8S
  fixture: verdict "mismatch", why "dem_co3.json records sha256:SOMETHING_ELSE under the entry's own
  key". That state needs a sidecar edited by hand (the writer records the file's own digest), so
  the behaviour is defensible. The stated order and "a digest match passes" are not what the code
  does, though. Either move the sidecar-contradiction arm into the listed order (third becomes
  second) or say "a digest match passes unless the entry's own sidecar contradicts the record".

- **[severity: fragile, low]** scripts/floodplain_lcc/dem_cache-check.R:5 ("The fetch and the HEAD
  request are replaced by counting fakes") and the section heading "hit and miss, with a counting
  fake for the fetch and the HEAD request". The HEAD replacement is `function(source, ...) ver`,
  which counts nothing. Only the mid-fetch arm's fake counts (`n_head`), and no arm asserts a HEAD
  count, for example "a hit makes exactly one HEAD". It is harmless as it stands. But it claims a
  HEAD count is observed when it is not, and CLAUDE.md's "a cached DEM still makes one HEAD request"
  is pinned by no arm.

## Claims checked and found TRUE (no action)

- Log `20261013_dem_cache_neexdzii.md`:
  - Window 23:12Z–23:25Z (the stamps read 23:12:44 and 23:24:54).
  - Toolchain incl. GEOS 3.13.0, Last-Modified and ETag (warm provenance `run`).
  - Baseline at 22:19Z (`before.json` floodplain datetime 22:19:31Z).
  - Cold 16.5 s and re-key 14.7 s fetches.
  - The re-key miss message lists `gdal_terra, proj_terra, proj_sf, tc_*`.
  - Warm and attribute_tag hits.
  - `dem_content_sha256` is `192ea21e380f…` in all four records.
  - Only `dem_resolver`, `dem_source` and `inputs_hash` differ, on all three floodplain entries.
  - Landcover inputs/outputs hashes and composition `outputs_hash` are unchanged, and the network
    is unchanged.
  - `dem_cache.status` reads miss/miss/hit.
  - 7c reports a match for co_ff02/04/06.
  - composition-check ALL PASS.
  - 105 groups in every attribution run.
  - The ab-compare STABILITY consequence holds (it compares `inputs_hash`).
  - LIVE re-run here: miss 2.8 s and hit 0.1 s, PASS. That agrees with the log's 3.3 s / 0.1 s to
    within network variance.
- The neexdzii DEM is float32-exact, with 2,935,855 non-NA cells: re-measured on
  `data/neexdzii/dem_co3.tif` (FLT8S), 0 of 2,935,855 cells change on a float32 round trip.
- BULK 2,240 s wall vs 51 s CPU (`dem.log`: 2240.71 real / 50.82 user). 145 KB/s measured
  2026-10-11 and the 84 GB COG (issue #122 body, filed 2026-10-11).
- `fl_dem_aoi` (flooded 0.7.0):
  - The bbox comes from the `st_buffer()` geometry, so GEOS matters.
  - The source read window comes from an unpinned `sf::st_transform`, so sf's PROJ matters.
  - The default URL equals `FP_DEM_SOURCE`.
  - `fl_valley_attribute` stops on `compareGeom`, which is the extent check attribute_tag.R's
    comment names.
- Step 2's `buf <- 2000`, and all 150 `max_width` values across `config/*/flood_scenarios.csv` are
  2000 ("equals step 2's 2000 in every table today").
- `fp_toolchain()` returns NA_character_ for an unreadable member, and `fp_dem_key_hash` refuses
  NA ("stops step 2 rather than hashing NA").
- The probe's replay dir is `unlink()`ed before use ("the replay dir is fresh, so a miss").
- stac_floodplains_bc's reader whitelists top-level keys only, so `inputs$dem_source` and
  `run$dem_cache` do not block publishing.
- `provenance-check.R` offline: PASS. `dem_cache-check.R` (LIVE=1): PASS (0 failures).
