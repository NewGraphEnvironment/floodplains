# fp_dem.R — the step-2 DEM, cached per area (#122).
#
# flooded::fl_dem_aoi() crops and reprojects MRDEM-30 from NRCan's bucket on every call and never
# writes the result. That bucket has served at ~145 KB/s (measured 2026-10-11), so BULK's fetch took
# 2,240 s of wall time against 51 s of CPU, paid again on every step-2 re-run and every
# attribute_tag.R run. fp_dem_cached() writes the DEM beside the area's outputs and reads it back
# when its key matches.
#
# THE DRIVER OWNS THE SOURCE URL (decided 2026-10-13). Step 2 used to pass `source = NULL` and let
# flooded resolve its default, and its comments refused to restate the URL because a RECORDED copy
# would drift from the one flooded actually fetched. Passing the URL removes that risk: flooded
# fetches exactly what is named here, so the record cannot disagree with the fetch. The cost is
# that a new flooded default does not reach this repo until FP_DEM_SOURCE changes, which is why
# dem_cache-check.R asserts the two still agree and says so when they part.
#
# THE KEY covers everything that decides the grid or the values:
#   - the AOI: a digest of the streams' WKB, row by row. It is stricter than a bbox (the grid comes
#     from the bbox of the BUFFERED geometry, which a streams bbox only approximates), and it is
#     order-dependent, which can only cause a false miss, never a false hit;
#   - buffer, target CRS, source URL;
#   - the object's Last-Modified AND ETag: NRCan re-deriving MRDEM in place keeps the URL;
#   - the flooded version: 0.7.0 pinned the grid (flooded#67), and a later release may move it again;
#   - the warp toolchain: terra's GDAL and PROJ, which warp the DEM, and sf's PROJ, which still picks
#     the source read window (flooded#78). #117 was a PROJ upgrade moving the DEM ~1.3 m with the
#     data unchanged. A cache without these in its key would keep the old DEM alive and hide exactly
#     that shift, and `run$toolchain` (recorded from THIS session) would describe a warp that did
#     not produce the cells. With them in the key, a hit means the cached DEM is what this session
#     would have fetched.
#
# FAILS CLOSED. The key needs a HEAD request to the source. If that fails, step 2 stops: a key that
# cannot be built is never treated as a match, and a cold fetch needs the network anyway.

FP_DEM_SOURCE <- paste0("/vsicurl/https://canelevation-dem.s3.ca-central-1.amazonaws.com/",
                        "mrdem-30/mrdem-30-dtm.tif")

# Bumped when the key's ingredients change, so an old sidecar can never match a new key by accident.
FP_DEM_KEY_SCHEMA <- 1L

# Last-Modified + ETag of a /vsicurl/ http(s) source, from a HEAD request.
#
# The status is read from curl, never inferred (code-check-r: download.file() never reports it).
# Anything but 200, or a 200 without both headers, is an error: the key would otherwise be built
# from a missing version and match a sidecar written from another missing version.
fp_dem_object_version <- function(source = FP_DEM_SOURCE, timeout = 60) {
  url <- sub("^/vsicurl/", "", source)
  if (identical(url, source) || !grepl("^https?://", url)) {
    stop("fp_dem_object_version: only /vsicurl/http(s) sources are supported, got '", source, "'",
         call. = FALSE)
  }
  h <- curl::new_handle(nobody = TRUE, followlocation = TRUE, timeout = timeout)
  res <- tryCatch(curl::curl_fetch_memory(url, handle = h), error = function(e) {
    stop("cannot reach the DEM source to build its cache key (", conditionMessage(e), "): ", url,
         ". Step 2 needs the network for this HEAD request even when the DEM is cached.",
         call. = FALSE)
  })
  if (!identical(as.integer(res$status_code), 200L)) {
    stop("HEAD ", url, " returned HTTP ", res$status_code, "; the DEM cache key cannot be built",
         call. = FALSE)
  }
  hd <- curl::parse_headers_list(res$headers)
  lm <- hd[["last-modified"]]
  et <- hd[["etag"]]
  if (is.null(lm) || is.null(et) || !nzchar(lm) || !nzchar(et)) {
    stop("HEAD ", url, " returned no Last-Modified/ETag; the DEM cache key cannot be built",
         call. = FALSE)
  }
  list(last_modified = lm, etag = gsub('"', "", et, fixed = TRUE))
}

# The cache key, as a list. PURE: every ingredient is an argument, so dem_cache-check.R can move each
# one and watch the hash move, with no network and no DEM.
#
# The AOI digest hashes each feature's WKB and then the sequence of those hashes with the count, so
# two features cannot run together into the bytes of one.
fp_dem_key <- function(streams, buffer, target_crs, source, object_version,
                       flooded = as.character(utils::packageVersion("flooded")),
                       toolchain = fp_toolchain()) {
  wkb <- sf::st_as_binary(sf::st_geometry(streams), endian = "little")
  per <- vapply(wkb, function(b) digest::digest(as.raw(b), algo = "sha256", serialize = FALSE), "")
  aoi <- digest::digest(paste(c(length(per), per), collapse = "\n"), algo = "sha256",
                        serialize = FALSE)
  list(
    schema         = FP_DEM_KEY_SCHEMA,
    aoi_sha256     = aoi,
    aoi_features   = length(per),
    buffer_m       = as.numeric(buffer),
    target_crs     = digest::digest(sf::st_crs(target_crs)$wkt, algo = "sha256", serialize = FALSE),
    source         = source,
    last_modified  = object_version$last_modified,
    etag           = object_version$etag,
    flooded        = flooded,
    gdal_terra     = toolchain$gdal_terra,
    proj_terra     = toolchain$proj_terra,
    proj_sf        = toolchain$proj)
}

# One hash over the key. Fixed JSON so neither a print option nor a list's R attributes reach it.
fp_dem_key_hash <- function(key) {
  if (any(vapply(key, function(v) length(v) != 1L || is.na(v), logical(1)))) {
    # An NA toolchain member would hash as the literal "NA" and two unknowns would match each other.
    stop("DEM cache key has a missing or non-scalar ingredient: ",
         paste(names(key)[vapply(key, function(v) length(v) != 1L || is.na(v), logical(1))],
               collapse = ", "), call. = FALSE)
  }
  paste0("sha256:", digest::digest(as.character(jsonlite::toJSON(key, auto_unbox = TRUE, digits = NA)),
                                   algo = "sha256", serialize = FALSE))
}

# Which sidecar ingredients differ from `key`, for the message on a miss.
fp_dem_key_diff <- function(old, key) {
  nm <- union(names(old), names(key))
  nm[!vapply(nm, function(n) identical(as.character(old[[n]]), as.character(key[[n]])), logical(1))]
}

# The DEM for `streams` + `buffer`, reprojected to `target_crs`, from `dir/dem_<stem>.tif` when its
# sidecar `dir/dem_<stem>.json` carries the same key and the file still digests to what the sidecar
# recorded; otherwise fetched, written and recorded.
#
# `stem` is `<species><min_order>`, keyed like streams_<sp><order> (#23), so two species in one area
# keep two caches rather than evicting each other.
#
# Written FLT8S, not FLT4S: the warp is bilinear and terra holds the result as double, so a float
# write would round it and the cached DEM would not be the one the digest describes (the probe's
# dem_common.tif made the same call). The write is checked by digest before it is committed.
#
# `fetch` is flooded::fl_dem_aoi; it is an argument only so dem_cache-check.R can count fetches
# offline.
#
# Returned FILE-BACKED on both paths, so a hit and a miss hand step 2 the same kind of object, and
# with attr "fp_dem_cache" carrying what provenance records.
fp_dem_cached <- function(streams, buffer, target_crs, dir, stem, source = FP_DEM_SOURCE,
                          fetch = flooded::fl_dem_aoi) {
  tif <- file.path(dir, paste0("dem_", stem, ".tif"))
  js  <- file.path(dir, paste0("dem_", stem, ".json"))
  ver <- fp_dem_object_version(source)
  key <- fp_dem_key(streams, buffer, target_crs, source, ver)
  kh  <- fp_dem_key_hash(key)

  info <- function(status, sha) list(status = status, key_sha256 = kh, source = source,
                                     last_modified = ver$last_modified, etag = ver$etag,
                                     path = basename(tif), dem_content_sha256 = sha)

  reason <- "no cached DEM"
  if (file.exists(js) && file.exists(tif)) {
    side <- tryCatch(jsonlite::read_json(js), error = function(e) NULL)
    if (is.null(side) || is.null(side$key_sha256)) {
      reason <- "sidecar unreadable"
    } else if (!identical(side$key_sha256, kh)) {
      reason <- paste0("key differs (", paste(fp_dem_key_diff(side$key, key), collapse = ", "), ")")
    } else {
      dem <- terra::rast(tif)
      sha <- fp_raster_content_sha256(dem)
      if (identical(sha, side$dem_content_sha256)) {
        message("  DEM cache hit: ", basename(tif), " (", substr(kh, 8, 19), ")")
        attr(dem, "fp_dem_cache") <- info("hit", sha)
        return(dem)
      }
      reason <- "cached file no longer matches its recorded digest"
    }
  }
  message("  DEM cache miss: ", reason, " -- fetching")

  t0  <- Sys.time()
  dem <- fetch(streams, source = source, buffer = buffer, target_crs = target_crs)
  message("  DEM fetched in ", round(as.numeric(difftime(Sys.time(), t0, units = "secs")), 1), " s")
  sha <- fp_raster_content_sha256(dem)

  tmp <- tempfile("dem_", tmpdir = dir, fileext = ".tif")
  fp_rast_write(dem, tmp, overwrite = TRUE, datatype = "FLT8S")
  if (!identical(fp_raster_content_sha256(tmp), sha)) {
    unlink(tmp)
    stop(basename(tif), " does not round-trip the fetched DEM; not caching it", call. = FALSE)
  }
  # The sidecar is the commit marker, so it goes first on the way out and last on the way in: a crash
  # between the two renames leaves a tif with no sidecar, which is a miss, never an old key over a new
  # file.
  if (file.exists(js) && !file.remove(js)) stop("cannot remove stale ", js, call. = FALSE)
  if (!file.rename(tmp, tif)) { unlink(tmp); stop("cannot move the DEM into ", tif, call. = FALSE) }
  tmpj <- tempfile("dem_", tmpdir = dir, fileext = ".json")
  jsonlite::write_json(list(key_sha256 = kh, dem_content_sha256 = sha, key = key,
                            written_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")),
                       tmpj, auto_unbox = TRUE, pretty = TRUE, digits = NA)
  if (!file.rename(tmpj, js)) { unlink(tmpj); stop("cannot write ", js, call. = FALSE) }

  out <- terra::rast(tif)
  attr(out, "fp_dem_cache") <- info("miss", sha)
  out
}
