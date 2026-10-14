## Outcome

Step 2 now caches the cropped, reprojected MRDEM-30 DEM per area, as `data/<area>/dem_<sp><order>.tif` with a JSON sidecar, through `scripts/floodplain_lcc/fp_dem.R`. `attribute_tag.R` reads through the same cache.

- **The key** covers the streams' WKB, buffer, CRS, source URL, the object's Last-Modified and ETag, the flooded version and the whole `fp_toolchain()`. A hit also needs the file to digest as recorded.
- **Fails closed.** The HEAD request the key needs is never skipped, and an NA toolchain member stops the run.
- **The driver owns the URL.** The user decided in planning that `FP_DEM_SOURCE` is passed as `source =`, so provenance records `inputs$dem_source`. That closes the "DEM identity recorded as absent" gap from #33.
- **Provenance checks.** `provenance-check.R` requires the new keys by the `dem_resolver` string (a content rule, not a date), and 7c now reconciles `dem_content_sha256` against the cached file.

What was learned:
- **The plan review's blocker was real.** `attribute_tag.R` used `max_width` as its DEM buffer, so any value other than 2000 would have fetched a DEM on another grid, replaced step 2's cache and then failed the extent check. It now reads step 2's recorded buffer and checks the digest.
- **The first cutover was a wall-clock time.** It would have turned red any entry that pre-#122 code wrote after it.
- **The "warp output is double" premise behind the FLT8S choice was false.** The output is float32-exact. FLT8S stays because it is lossless whatever terra returns.
- **Code-check round 3 found a wording defect inside round 2's fix.** An enumeration of all 120 added comment lines then found three more false claims. Every one of them was text written before the behaviour settled.

## Measurement

neexdzii, 2026-10-13, steps 2 and 3, run cold, re-keyed and warm, plus `attribute_tag.R`:

- **The DEM digest was unchanged.** `sha256:192ea21e380f…` is the #117 re-baseline value. So passing the URL explicitly, and handing step 2 a file-backed FLT8S DEM, reproduces the DEM byte for byte.
- **The outputs were unchanged.** Every floodplain, landcover and composition `outputs_hash` held, and the attribution layer stayed at 105 rows and 252.1233 km².
- **What moved:** only `dem_resolver` and the new `dem_source`, and therefore floodplain `inputs_hash`.
- **Timings.** A cache hit took 0.29–0.61 s, against a 14.7–16.5 s fetch from the bucket today. The issue's motivating case is BULK at 2,240 s wall against 51 s CPU (2026-10-11); BULK was not re-run here, which is #125's job.
- **Float32-exact output:** all 2,935,855 non-NA cells of neexdzii's DEM, on terra 1.9.50.

## Evidence

`scripts/floodplain_lcc/logs/20261013_dem_cache_neexdzii.md`

Code review: `review-round1.md` to `review-round3.md` in this directory. The plan review's findings and what was done with each are in `findings.md`.

Closed by: PR #130
