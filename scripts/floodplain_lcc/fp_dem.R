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
#   - the whole toolchain fp_toolchain() records: terra's GDAL and PROJ, which warp the DEM; sf's
#     PROJ, which still picks the source read window (flooded#78); GEOS, whose st_buffer() vertices
#     set the bbox both windows come from; and the terra and sf versions themselves. #117 was a PROJ
#     upgrade moving the DEM ~1.3 m with the data unchanged. A cache without these in its key would keep the old DEM alive and hide exactly
#     that shift, and `run$toolchain` (recorded from THIS session) would describe a warp that did
#     not produce the cells. With them in the key, a hit means the cached DEM is what this session
#     would have fetched.
#
# FAILS CLOSED. The key needs a HEAD request to the source. If that fails, step 2 stops: a key that
# cannot be built is never treated as a match, and a cold fetch needs the network anyway. The same
# holds for a toolchain member fp_toolchain() cannot read (NA): step 2 stops rather than hash "NA".

FP_DEM_SOURCE <- paste0("/vsicurl/https://canelevation-dem.s3.ca-central-1.amazonaws.com/",
                        "mrdem-30/mrdem-30-dtm.tif")

# Bump this whenever the key's ingredients change, so an old sidecar can never match a new key by
# accident. (Still 1: the ingredients changed during #122's review, before any sidecar was released.)
FP_DEM_KEY_SCHEMA <- 1L

# The toolchain members the key carries: everything fp_toolchain() returns.
FP_DEM_KEY_TOOLCHAIN <- c("terra", "sf", "gdal", "geos", "proj", "gdal_terra", "proj_terra")

# What step 2 records as run$dem_cache, and what provenance-check.R requires there. One list, read by
# both, so the producer and the guard cannot drift apart.
FP_DEM_CACHE_RECORD <- c("status", "key_sha256", "path", "last_modified", "etag")

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
  miss_tc <- setdiff(FP_DEM_KEY_TOOLCHAIN, names(toolchain))
  if (length(miss_tc)) stop("toolchain lacks ", paste(miss_tc, collapse = ", "), call. = FALSE)
  c(list(
    schema         = FP_DEM_KEY_SCHEMA,
    aoi_sha256     = aoi,
    aoi_features   = length(per),
    buffer_m       = as.numeric(buffer),
    target_crs     = digest::digest(sf::st_crs(target_crs)$wkt, algo = "sha256", serialize = FALSE),
    source         = source,
    last_modified  = object_version$last_modified,
    etag           = object_version$etag,
    flooded        = flooded),
    stats::setNames(lapply(FP_DEM_KEY_TOOLCHAIN, function(k) toolchain[[k]]),
                    paste0("tc_", FP_DEM_KEY_TOOLCHAIN)))
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
# Written FLT8S, which cannot lose whatever terra returns. On terra 1.9.50 the warp's output is
# float32-exact (measured: all 2,935,855 non-NA cells of neexdzii's DEM), so FLT4S would round-trip
# today, but that is a terra internal and not a contract. The write is checked by digest before it
# is committed either way.
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

  # The object may have been replaced during a long fetch (BULK's took 37 min). Asking again closes
  # that window: a version that moved means these cells may be from either, so nothing is cached.
  ver2 <- fp_dem_object_version(source)
  if (!identical(ver2, ver)) {
    stop("the DEM source changed during the fetch (", ver$etag, " -> ", ver2$etag, "); re-run step 2",
         call. = FALSE)
  }

  # A leading dot so the temp names never match dem_*.tif; removed on any exit, including a stop()
  # inside fp_rast_write().
  tmp  <- tempfile(".dem_tmp_", tmpdir = dir, fileext = ".tif")
  tmpj <- tempfile(".dem_tmp_", tmpdir = dir, fileext = ".json")
  on.exit(unlink(c(tmp, paste0(tmp, ".aux.xml"), tmpj)), add = TRUE)
  fp_rast_write(dem, tmp, overwrite = TRUE, datatype = "FLT8S")
  if (!identical(fp_raster_content_sha256(tmp), sha)) {
    stop(basename(tif), " does not round-trip the fetched DEM; not caching it", call. = FALSE)
  }
  # The sidecar is the commit marker, so it goes first on the way out and last on the way in: a crash
  # between the two renames leaves a tif with no sidecar, which is a miss, never an old key over a new
  # file.
  if (file.exists(js) && !file.remove(js)) stop("cannot remove stale ", js, call. = FALSE)
  # A PAM sidecar (written by anyone opening the old file in QGIS) would otherwise describe the new one.
  unlink(paste0(tif, ".aux.xml"))
  if (!file.rename(tmp, tif)) stop("cannot move the DEM into ", tif, call. = FALSE)
  jsonlite::write_json(list(key_sha256 = kh, dem_content_sha256 = sha, key = key,
                            written_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")),
                       tmpj, auto_unbox = TRUE, pretty = TRUE, digits = NA)
  if (!file.rename(tmpj, js)) stop("cannot write ", js, call. = FALSE)

  out <- terra::rast(tif)
  attr(out, "fp_dem_cache") <- info("miss", sha)
  out
}
