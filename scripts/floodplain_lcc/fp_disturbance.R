# fp_disturbance.R — config-driven, layer-agnostic disturbance attribution (#19).
#
# Generalizes the fire-only fire_tag.R prototype. Given land-cover-change patches (the transition
# layer) and a list of disturbance SOURCES (config, not code), tag each patch with, per source:
#   in_<name>      : does the patch overlap any source polygon within the change window?
#   <carry attrs>  : the DOMINANT overlapping feature's carried attributes (largest intersection area)
# Attribution is ADDITIVE — a patch may match several sources (burned AND salvage-logged). The
# residual (matches no source) is the classification-noise floor.
#
# A source is a config entry (see config/disturbance.yml):
#   name      short id -> in_<name>
#   table     fwapg schema.table (loaded via bc2pg)
#   geom_col  geometry column
#   year_col  temporal field used to window to the change interval
#   carry     source columns copied onto the patch from the dominant overlapping feature
#   filter    OPTIONAL extra SQL predicate (e.g. a pest-species subset)
#   window    OPTIONAL [from, to] override (default = the change interval passed in)
#
# The AOI bbox is pushed into the SQL WHERE server-side (ST_Intersects + ST_MakeEnvelope) so a
# province-wide layer (e.g. consolidated cutblocks) never streams the whole table into R.
#
# CONTEXT entries (#95) -- config/disturbance.yml `context:` -- are tagged by the same code and are
# NOT causes. An FWA wetland says where a patch is, not why it changed, so it has no year and no
# window, and fp_disturbance_report() never sees it: callers pass only `sources:` to the report, and
# the README attribution figure reads only `sources:` (fp_readme_sources). Filed under sources, an
# in_wetland would shrink the "not yet attributed" share for a reason that explains nothing.
# fp_disturbance_validate() enforces the split, since the only difference between the two lists
# in the tagging code is whether the query carries a year predicate.

suppressMessages({library(sf); library(dplyr)})

`%|null|%` <- function(a, b) if (is.null(a)) b else a

# The columns step 3 writes on every change patch (03_lulc_classify.R) before and after tagging.
# A carried attribute is copied onto the patch under its OWN name, so carrying one of these would
# silently overwrite the patch's value -- fwa_wetlands_poly has an `area_ha`, and carrying it would
# have replaced every wetland patch's area with the wetland's. disturbance-check.R's live section
# asserts this set equals a real layer's non-tag columns, so it cannot drift from the writer.
FP_PATCH_CORE <- c("patch_id", "transition", "area_ha", "name_basin", "from_class", "to_class",
                   "wsg", "species", "scenario")

# Every key a `sources:` or `context:` entry may carry. `confidence` is documentation (a label).
FP_DST_ENTRY_KEYS <- c("name", "table", "geom_col", "year_col", "carry", "filter", "window",
                       "confidence")

.dst_refuse <- function(...) {
  stop(structure(class = c("fp_disturbance_config_error", "error", "condition"),
                 list(message = paste0("config/disturbance.yml: ", ...), call = NULL)))
}

# A carried column copied under the name of a patch column (or its geometry) would overwrite it.
.dst_core_clash <- function(s, geom_col = NULL) {
  # Case-folded: an upper-case carry (`AREA_HA`, as DataBC documents its columns) comes back from
  # Postgres folded to lower case and would land on the same column.
  reserved <- c(FP_PATCH_CORE, "geom", "geometry", geom_col)
  clash <- unlist(s[["carry"]])[tolower(unlist(s[["carry"]])) %in% tolower(reserved)]
  if (length(clash))
    .dst_refuse("`", s[["name"]], "` carries ", paste(clash, collapse = ", "),
                ", which would overwrite the change patch's own column")
}

# Validate the whole parsed config/disturbance.yml (both lists) before anything is tagged. Every
# rule here guards a failure that would otherwise run to completion with wrong columns.
fp_disturbance_validate <- function(dst) {
  unknown <- setdiff(names(dst), c("sources", "context"))
  if (length(unknown))
    .dst_refuse("unknown top-level key(s) ", paste(unknown, collapse = ", "),
                " -- only `sources:` and `context:` are read, so these entries would be dropped")
  # Entry keys are checked on the RAW entry: a misspelt optional key (`filtr:`, `cary:`, `windw:`)
  # is otherwise read as absent, and the entry runs unfiltered, uncarried or on the default window.
  # Checked before the list tag is attached, so an entry cannot carry its own `.list` either.
  for (lst in c("sources", "context")) {
    for (s in dst[[lst]]) {
      bad <- setdiff(names(s), FP_DST_ENTRY_KEYS)
      if (length(bad))
        .dst_refuse("`", lst, "` entry `", s[["name"]] %|null|% "?", "` has unknown key(s) ",
                    paste(bad, collapse = ", "), "; known: ", paste(FP_DST_ENTRY_KEYS, collapse = ", "))
    }
  }
  entries <- c(lapply(dst[["sources"]], function(s) c(s, list(.list = "sources"))),
               lapply(dst[["context"]], function(s) c(s, list(.list = "context"))))
  for (s in entries) {
    for (f in c("name", "table", "geom_col")) {
      v <- s[[f]]
      if (!is.character(v) || length(v) != 1 || !nzchar(v))
        .dst_refuse("a `", s[[".list"]], "` entry has no single `", f, "`")
    }
    if (s[[".list"]] == "sources" && is.null(s[["year_col"]]))
      .dst_refuse("source `", s[["name"]], "` has no `year_col`; a cause must be windowed to the change ",
                  "interval (an undated overlay belongs under `context:`)")
    if (s[[".list"]] == "context" && (!is.null(s[["year_col"]]) || !is.null(s[["window"]])))
      .dst_refuse("context `", s[["name"]], "` has a `year_col`/`window`; context is undated -- a dated ",
                  "overlay that explains change belongs under `sources:`")
    .dst_core_clash(s)
  }
  # Case-folded, like the core clash: GeoPackage field names are case-insensitive, so `fire` and
  # `Fire` pass a case-sensitive check and abort st_write -- after the STAC fetch, not at load.
  nm <- vapply(entries, function(s) s[["name"]], character(1))
  if (anyDuplicated(tolower(nm)))
    .dst_refuse("name(s) used twice: ", paste(unique(nm[duplicated(tolower(nm))]), collapse = ", "))
  carry <- unlist(lapply(entries, function(s) unlist(s[["carry"]])))
  owned <- c(paste0("in_", nm), carry)
  if (anyDuplicated(tolower(owned)))
    .dst_refuse("column(s) written by two entries: ",
                paste(unique(owned[duplicated(tolower(owned))]), collapse = ", "))
  invisible(dst)
}

# The SQL for one entry: its carried columns + geometry, limited server-side to the AOI bbox
# (EPSG:4326 xmin/ymin/xmax/ymax), and windowed to the change interval only when the entry has a
# year_col -- which validation makes true of every source and false of every context entry.
.dst_query <- function(src, bbox4326, window) {
  w     <- src[["window"]] %|null|% window
  carry <- paste(c(unlist(src[["carry"]]), paste(src[["geom_col"]], "AS geom")), collapse = ", ")
  when  <- if (!is.null(src[["year_col"]]))
    sprintf("%s BETWEEN %d AND %d AND ", src[["year_col"]], as.integer(w[1]), as.integer(w[2])) else ""
  filt  <- if (!is.null(src[["filter"]]) && nzchar(src[["filter"]])) paste0(" AND (", src[["filter"]], ")") else ""
  sprintf(
    "SELECT %s
       FROM %s
      WHERE %sST_Intersects(%s, ST_Transform(ST_MakeEnvelope(%.8f,%.8f,%.8f,%.8f,4326), ST_SRID(%s)))%s",
    carry, src[["table"]], when,
    src[["geom_col"]], bbox4326[["xmin"]], bbox4326[["ymin"]], bbox4326[["xmax"]], bbox4326[["ymax"]],
    src[["geom_col"]], filt)
}

# Fetch one entry's polygons intersecting the patches' AOI bbox (and, for a source, the window).
# The box makes two corner-only round trips (patch CRS -> 4326 here, 4326 -> table SRID in SQL), and
# a rectangle's corners do not bound its reprojected edges: unpadded, ~74 m of a 200 x 150 km box
# fell outside the query, so an overlay lying only in that strip was never fetched. Padding by
# `pad` CRS units (the transition layers are projected, in metres -- UTM) covers it; the extra polygons are dropped by st_intersects.
.dst_fetch <- function(conn, src, patches, window, pad = 1000) {
  box <- sf::st_buffer(sf::st_as_sfc(sf::st_bbox(patches)), pad, joinStyle = "MITRE")
  env <- sf::st_bbox(sf::st_transform(box, 4326))
  sf::st_read(conn, query = .dst_query(src, env, window), quiet = TRUE)
}

# Tag `patches` (an sf; one row per change patch) with in_<name> + carry columns for each entry --
# sources and context alike. Rows are joined back by POSITION, never by `patch_id`: step 3 numbers
# patches per sub-basin, so an id repeats across basins (neexdzii: 2032 rows, 1973 ids), and an
# id join handed one basin's carried values to a different basin's untagged patch. Returns the augmented sf. window = c(from, to) change interval
# (per-source override via src[["window"]]; ignored for context). `fetch` is injectable so
# disturbance-check.R can run the tagging with no database.
fp_disturbance_tag <- function(patches, sources, conn, window = c(2017, 2023), fetch = .dst_fetch) {
  geom_col <- attr(patches, "sf_column")
  # Checked here as well as in fp_disturbance_validate(): fire_tag.R and any direct caller reach
  # this without going through fp_read_config().
  for (src in sources) .dst_core_clash(src, geom_col)
  patches    <- sf::st_make_valid(patches)
  target_crs <- sf::st_crs(patches)

  for (src in sources) {
    nm     <- src[["name"]]
    in_col <- paste0("in_", nm)
    poly   <- fetch(conn, src, patches, window)
    # A carry the fetch did not return would otherwise vanish: poly[[a]] is NULL and assigning
    # NULL drops the column, silently. Postgres folds unquoted identifiers to lower case, so
    # `carry: [FIRE_YEAR]` is the likely way to get here.
    lost <- setdiff(unlist(src[["carry"]]), names(poly))
    if (length(lost))
      .dst_refuse("`", src[["name"]], "` carries ", paste(lost, collapse = ", "), ", which ",
                  src[["table"]], " did not return (Postgres returns lower-case names)")

    patches[[in_col]] <- FALSE
    # Typed NA, taken from the fetched column (st_read keeps types on a zero-row result). A bare NA
    # is logical, and GDAL writes an all-NA logical as Integer(Boolean): fire_year was Boolean in
    # four areas that happened to have no burned patch, so one column had two types across areas.
    for (a in unlist(src[["carry"]])) patches[[a]] <- poly[[a]][rep(NA_integer_, nrow(patches))]
    if (nrow(poly) == 0) next

    poly <- sf::st_make_valid(sf::st_transform(poly, target_crs))
    patches[[in_col]] <- lengths(sf::st_intersects(patches, poly)) > 0

    # dominant overlapping feature (largest intersection area) -> carry its attributes
    idx <- which(patches[[in_col]])
    if (length(idx)) {
      hit <- sf::st_sf(._row = idx, geom = sf::st_geometry(patches)[idx])
      inter <- suppressWarnings(sf::st_intersection(hit, poly))
      if (nrow(inter)) {
        inter$._ov <- as.numeric(sf::st_area(inter))
        dom <- sf::st_drop_geometry(inter) |>
          dplyr::group_by(._row) |>
          dplyr::slice_max(._ov, n = 1, with_ties = FALSE) |>
          dplyr::ungroup()
        for (a in unlist(src[["carry"]])) patches[[a]][dom$._row] <- dom[[a]]
      }
    }
  }
  patches
}

# Same VALUES, whatever the storage type. A carried column read back from a gpkg is double, or
# logical when it was all-NA (the Boolean defect #95 fixed in fp_disturbance_tag); a fresh tag
# produces the fetched type. identical() would call every such column "moved". Used by fire_tag.R's
# compare-before-write and disturbance-check.R's before/after comparison -- one definition of
# "unchanged" for both.
fp_same_values <- function(x, y) {
  if (length(x) != length(y) || !identical(is.na(x), is.na(y))) return(FALSE)
  x <- x[!is.na(x)]; y <- y[!is.na(y)]
  # Numbers compare as exact doubles: as.character() keeps 15 significant digits, so it called
  # 0.1 + 0.2 and 0.3 "the same" and would have hidden a recomputed area.
  num <- function(v) is.numeric(v) || is.logical(v)
  if (num(x) && num(y)) identical(as.double(x), as.double(y))
  else identical(as.character(x), as.character(y))
}

# Report the Trees->non-Trees loss split by source + additive residual (the noise floor).
# `sources` must be CAUSES only. An undated (context) entry is refused rather than counted: the
# report cannot tell a wetland from a fire by its column, so the list it is handed is the only
# thing keeping in_wetland out of the residual.
fp_disturbance_report <- function(patches, sources, area = "") {
  undated <- vapply(sources, function(s) is.null(s[["year_col"]]), logical(1))
  if (any(undated))
    .dst_refuse("fp_disturbance_report() was given context entr",
                if (sum(undated) == 1) "y " else "ies ",
                paste(vapply(sources[undated], function(s) s[["name"]], character(1)), collapse = ", "),
                "; pass `sources:` only -- context locates change, it never explains it")
  # `[[`, not `$`: on a data frame `$` partial-matches, so an absent column can answer with a longer
  # name's values, and a NULL makes `loss` empty and the report print zeros.
  for (k in c("from_class", "to_class", "area_ha"))
    if (is.null(patches[[k]])) .dst_refuse("the patches have no `", k, "` column")
  loss <- patches[patches[["from_class"]] == "Trees" & patches[["to_class"]] != "Trees", ]
  tot  <- sum(loss[["area_ha"]])
  in_cols <- vapply(sources, function(s) paste0("in_", s[["name"]]), character(1))
  # A missing column is NULL, `%in%` makes it zero-length, and OR-ing that into the running mask
  # empties the mask -- the residual then sums nothing and the report says everything is explained.
  absent <- setdiff(in_cols, names(patches))
  if (length(absent))
    .dst_refuse("the patches were never tagged with ", paste(absent, collapse = ", "),
                " -- re-tag (fire_tag.R) before reporting, or the residual reads 0")

  cat(sprintf("\n=== %s Trees->non-Trees LOSS vs disturbance ===\n", toupper(area)))
  cat(sprintf(" total loss      : %.1f ha\n", tot))
  for (ic in in_cols) {
    ha <- sum(loss[["area_ha"]][loss[[ic]] %in% TRUE])
    cat(sprintf(" %-15s: %.1f ha (%.0f%%)\n", ic, ha, 100 * ha / tot))
  }
  any_in <- Reduce(`|`, lapply(in_cols, function(ic) loss[[ic]] %in% TRUE),
                   rep(FALSE, nrow(loss)))
  resid  <- sum(loss[["area_ha"]][!any_in])
  cat(sprintf(" residual (noise): %.1f ha (%.0f%%)\n", resid, 100 * resid / tot))
  invisible(loss)
}
