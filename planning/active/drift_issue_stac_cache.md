# drift issue draft — `dft_stac_fetch` cache key omits the AOI → wrong data returned for a second area

**Repo:** NewGraphEnvironment/drift · **Severity:** high (silent wrong data, no error) · **Version seen:** 0.2.2

## Summary

`dft_stac_fetch()` caches fetched rasters at `file.path(cache_source_dir, paste0(yr, ".nc"))`
(`R/dft_stac_fetch.R:103`) — keyed only by **source** and **year**, with **no AOI component**. Any
two calls with the same `source`/`year` but different `aoi` collide: the second call finds the
first call's NetCDF, skips the fetch (when `force = FALSE`, the default), and returns the **first
AOI's raster masked to the second AOI**. No warning, no error — just wrong data.

## Evidence (real occurrence)

Running two BC watershed areas through a floodplain/LULC pipeline that calls
`dft_stac_fetch(source = "io-lulc", years = c(2017, 2020, 2023))`:

1. Area A (Neexdzii, a reach of the Bulkley) ran first → populated
   `~/Library/Caches/drift/io-lulc/{2017,2020,2023}.nc` with Neexdzii's extent. Correct output.
2. Area B (MORR / Morice, ~80 km west, larger) ran second → `dft_stac_fetch` found the cache files
   and returned **Neexdzii's** rasters, masked to the MORR floodplain.

Cache extent vs. AOIs (EPSG:32609, metres):

| | E min–max | N min–max |
|---|---|---|
| cache `io-lulc/*.nc` | 645443–696463 | 6000758–6056578 |
| **Neexdzii** fp bbox | 645444–696461 | 6000762–6056573 | ← cache == Area A |
| **MORR** fp bbox | 566715–651331 | 5948369–6035818 | ← what Area B should have gotten |

Result: MORR's land cover was classified over only the ~3% where the Neexdzii cached extent
overlaps the MORR floodplain (near the shared Bulkley/Morice confluence); "tree loss" came out
22 ha of Bulkley-valley agricultural transitions instead of the true MORR figure.

## Secondary bug: `force = TRUE` cannot overwrite

`force = TRUE` routes to the fetch branch and calls `gdalcubes::write_ncdf(cube, cache_file)`
without removing the existing file first. When the cache file exists, `write_ncdf` errors:

```
Error: File already exists, please change the output filename or set overwrite = TRUE
```

So `force = TRUE` cannot be used to bypass a stale/colliding cache — the user must manually delete
the file (or call `dft_cache_clear()`).

## Fix

1. **Put the AOI in the cache key.** Hash the AOI (bbox + geometry) into the filename, e.g.
   `paste0(yr, "_", substr(rlang::hash(list(sf::st_bbox(aoi_target), sf::st_geometry(aoi_target))), 1, 12), ".nc")`.
   Preserves caching for repeat runs of the *same* AOI while eliminating cross-AOI collisions.
   (Also fold `res`, `crs`, `aggregation` into the key, since they change the output too.)
2. **Fix `force = TRUE`** to `unlink(cache_file)` before `write_ncdf` (or pass an overwrite arg).
3. **Defensive check (optional):** on a cache hit, verify the cached raster's extent covers the
   requested AOI bbox; if not, re-fetch. Catches any residual key collision.

## Minimal repro

```r
library(drift)
a <- sf::st_as_sf(sf::st_sfc(sf::st_buffer(sf::st_point(c(-126.75, 54.41)), 0.1), crs = 4326))
b <- sf::st_as_sf(sf::st_sfc(sf::st_buffer(sf::st_point(c(-127.75, 54.05)), 0.1), crs = 4326))  # ~65 km west
ra <- dft_stac_fetch(a, source = "io-lulc", years = 2020)  # fetches
rb <- dft_stac_fetch(b, source = "io-lulc", years = 2020)  # returns a's cached raster, masked to b -> mostly NA
# terra::ext(rb[["2020"]]) matches a, not b
```

## Workaround until fixed

`dft_cache_clear(source = "io-lulc")` (or `force = TRUE` after manually `unlink()`-ing the file)
before fetching a different AOI.
