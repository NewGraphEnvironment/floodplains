# Code review — round 1 (#122, branch 122-cache-the-step-2-dem-per-area-nrcan-s-s3 vs main)

## Clean

No issues found.

### What was checked

- `fp_dem.R`:
  - The key: per-feature WKB, buffer coerced to double, CRS WKT digest, source, Last-Modified/ETag, flooded version, every `fp_toolchain()` member.
  - The NA/empty refusal in `fp_dem_key_hash`.
  - The hit path: the sidecar key plus a file-digest match.
  - The miss path:
    - the post-fetch HEAD;
    - `on.exit` cleanup registered inside the function, so it fires;
    - the `file.remove`/`file.rename` return values, which are checked;
    - the sidecar as commit marker. Removed before the tif is replaced and written after, so any crash point leaves a miss, never an old key over a new file.
    - the stale PAM sidecar removal.
  - The HEAD reads its status from curl. `parse_headers_list` keeps only the final response after a redirect, and the ETag has its quotes stripped.
- `02_floodplain_model.R`:
  - `out_dir` and `buf` are defined before use.
  - The stem `paste0(cfg$species, cfg$min_order)` equals the suffix of `streams_lyr`, so `dem_cache_reconcile`'s path derived from `network_layer` agrees, including `all2` for whole-network.
  - `dem_cache[FP_DEM_CACHE_RECORD]`: every name exists in `info()`.
  - `fp_prov_run(...)` passes `dem_cache` through.
  - The hit digest comes from the file and the miss digest from the object. They are equal because the round trip is checked.
- `attribute_tag.R`:
  - Reads the same layer with the same `st_zm`, so the AOI key matches step 2.
  - Uses the recorded `dem_buffer_m`. The `$` reads are exact matches.
  - A missing scenario record stops cleanly.
  - The digest check is against the recorded value. A miss there is the correct way to verify a key change with the same cells, so it is not a defect.
- `provenance-check.R`:
  - The resolver-string gate in `viol_keys` (`dem_old`), including an NA or absent resolver, which is held to the new keys.
  - `dem_cache_reconcile` ordering: path vs network layer, then same-key sidecar contradiction, then file digest, then skip.
  - 5h and the section 3 arms.
  - The 7c call site: `dd` is in scope.
  - The only "raster newer than its stamp" check (#126) is landcover-only, so a replaced DEM cache cannot trip it.
- Downstream:
  - `stac_floodplains_bc/scripts/01_stage.R` stages rasters by explicit name, and its `*.tif` globs run over its own `data/raw`, so `dem_<sp><order>.tif` is never published.
  - Its provenance reader rejects unknown top-level keys only, so `inputs$dem_source` and `run$dem_cache` do not break publishing.
- Other callers of `fp_floodplain()`: `run_area.R` and the probe anchor. Both source `fp_dem.R`, and `fp_raster.R`/`fp_provenance.R` are already loaded in both.
- Ran `Rscript scripts/floodplain_lcc/dem_cache-check.R`: PASS (0 failures), including the networked HEAD arms.
- Ran `Rscript scripts/floodplain_lcc/provenance-check.R`: PASS, with 5h and the #122 section 3 arms all ok.

### Observed, not a defect (no action needed)

- In `dem_cache_reconcile`, a cache whose sidecar is missing or unreadable is treated as "another key". A file that digests differently then skips, with the message "replaced under another key since". With no sidecar, that message is slightly inaccurate. The verdict, though, is the honest one: it is the state a crash mid-miss leaves, and `fp_dem_cached()` re-fetches on the next run.
