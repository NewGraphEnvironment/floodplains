# disturbance-check.R — assert context overlays locate change without ever explaining it (#95).
#
# config/disturbance.yml carries two lists. `sources:` are CAUSES: fp_disturbance_report() counts
# every in_<source> as explaining tree loss, and the README attribution figure reads the same list.
# `context:` entries (FWA wetlands) tag the same patches so they can be found, and must never move
# the attribution residual. An in_wetland filed under sources would shrink "not yet attributed" for
# a reason that explains nothing, and nothing would fail -- the numbers would just be wrong.
#
# Two sections:
#   offline (always) -- the validator, the SQL builder, the carry-collision guard, and the residual
#                       with and without a context entry, on synthetic patches through a stub fetch.
#                       Each property has an arm that must go red if the rule is broken.
#   live (area arg)  -- every transition layer of the area: context columns present, typed, and set
#                       exactly where in_<name> is TRUE; core columns match FP_PATCH_CORE. Given a
#                       snapshot taken before `fire_tag.R <area>`, every cause column and the
#                       geometry (WKB) must be unchanged. No default area (#91): a bare run checks
#                       nothing live and says so.
#
# usage: Rscript scripts/floodplain_lcc/disturbance-check.R                          # offline only
#        Rscript scripts/floodplain_lcc/disturbance-check.R snapshot <area> <out.rds>  # before a re-tag
#        Rscript scripts/floodplain_lcc/disturbance-check.R <area> [snapshot.rds]      # + live

suppressMessages({library(sf); library(dplyr); library(yaml)})
sf::sf_use_s2(FALSE)
source(here::here("scripts", "floodplain_lcc", "fp_disturbance.R"))

fails <- 0L
ok <- function(label, cond, detail = "") {
  if (isTRUE(cond)) {
    message("  PASS  ", label, if (nzchar(detail)) paste0("  (", detail, ")") else "")
  } else {
    fails <<- fails + 1L
    message("  FAIL  ", label, if (nzchar(detail)) paste0("  (", detail, ")") else "")
  }
}
# Refused BY THE GUARD, not merely erroring: a missing function or a typo also raises, and an arm
# that accepts any error passes against code that does not exist (it did, before Phase 2).
refused <- function(expr) inherits(tryCatch({ force(expr); NULL }, error = function(e) e),
                                   "fp_disturbance_config_error")
# ...and the mirror: "accepted" means the call RAN. `!refused()` would pass on any other error too.
accepted <- function(expr) !inherits(tryCatch({ force(expr); NULL }, error = function(e) e), "error")

fire <- list(name = "fire", table = "s.fire", geom_col = "geom", year_col = "fire_year",
             carry = list("fire_year"))
harvest <- list(name = "harvest", table = "s.cut", geom_col = "geom",
                year_col = "harvest_start_year_calendar",
                carry = list("harvest_start_year_calendar"))
wetland <- list(name = "wetland", table = "s.wet", geom_col = "geom",
                carry = list("waterbody_poly_id"))
dst_ok <- list(sources = list(fire, harvest), context = list(wetland))

# ---------------------------------------------------------------------------------------------
message("\nvalidator: a config that breaks a rule is refused, not silently run")
# ---------------------------------------------------------------------------------------------
ok("a well-formed sources + context config is accepted",
   accepted(fp_disturbance_validate(dst_ok)))
ok("the committed config/disturbance.yml is accepted",
   accepted(fp_disturbance_validate(yaml::read_yaml(here::here("config", "disturbance.yml")))))

no_year <- fire; no_year$year_col <- NULL
ok("a source with no year_col is refused (it would be silently un-windowed)",
   refused(fp_disturbance_validate(list(sources = list(no_year)))))
dated_ctx <- wetland; dated_ctx$year_col <- "yr"
ok("a context entry WITH a year_col is refused (context is undated by definition)",
   refused(fp_disturbance_validate(list(sources = list(fire), context = list(dated_ctx)))))
windowed_ctx <- wetland; windowed_ctx$window <- list(2017, 2023)
ok("a context entry with a window is refused",
   refused(fp_disturbance_validate(list(sources = list(fire), context = list(windowed_ctx)))))
dup_name <- wetland; dup_name$name <- "fire"
ok("a name used in both lists is refused (two writers of one in_<name> column)",
   refused(fp_disturbance_validate(list(sources = list(fire), context = list(dup_name)))))
dup_carry <- wetland; dup_carry$carry <- list("fire_year")
ok("a carry column shared by two entries is refused (the second overwrites the first)",
   refused(fp_disturbance_validate(list(sources = list(fire), context = list(dup_carry)))))
no_table <- wetland; no_table$table <- NULL
ok("an entry with no table is refused",
   refused(fp_disturbance_validate(list(sources = list(fire), context = list(no_table)))))
for (core in c("area_ha", "patch_id", "from_class", "wsg")) {
  clash <- wetland; clash$carry <- list(core)
  ok(sprintf("carrying `%s` is refused (it would overwrite the patch's own column)", core),
     refused(fp_disturbance_validate(list(sources = list(fire), context = list(clash)))))
}
typo <- fire; typo$filtr <- "fire_size_ha > 1"
ok("a misspelt entry key is refused (`filtr:` would run the source unfiltered)",
   refused(fp_disturbance_validate(list(sources = list(typo)))))
shadow <- no_year; shadow$.list <- "context"
ok("an entry cannot smuggle its own `.list` tag past the year_col rule",
   refused(fp_disturbance_validate(list(sources = list(shadow)))))
cased <- harvest; cased$name <- "Fire"
ok("names differing only in case are refused (GeoPackage fields are case-insensitive)",
   refused(fp_disturbance_validate(list(sources = list(fire, cased)))))
ok("an unknown top-level key is refused (a typo like `contxt:` would drop every entry)",
   refused(fp_disturbance_validate(c(dst_ok, list(contxt = list(wetland))))))

# ---------------------------------------------------------------------------------------------
message("\nquery: the year window applies to causes and only to causes")
# ---------------------------------------------------------------------------------------------
bb <- c(xmin = -125, ymin = 53, xmax = -124, ymax = 54)
q_src <- .dst_query(fire, bb, c(2017, 2023))
q_ctx <- .dst_query(wetland, bb, c(2017, 2023))
ok("a source's query is windowed to the change interval",
   grepl("fire_year BETWEEN 2017 AND 2023", q_src, fixed = TRUE))
ok("a context entry's query has no year predicate", !grepl("BETWEEN", q_ctx, fixed = TRUE))
ok("both queries are bbox-limited server-side",
   grepl("ST_Intersects", q_src) && grepl("ST_Intersects", q_ctx))

# ---------------------------------------------------------------------------------------------
message("\ntagging: context columns land, cause columns and the residual do not move")
# ---------------------------------------------------------------------------------------------
sq <- function(x0, y0, s = 100) sf::st_polygon(list(rbind(c(x0, y0), c(x0 + s, y0),
                                                          c(x0 + s, y0 + s), c(x0, y0 + s),
                                                          c(x0, y0))))
patches <- sf::st_sf(
  patch_id = 1:4, transition = "Trees -> Rangeland", area_ha = 1,
  from_class = "Trees", to_class = "Rangeland",
  geom = sf::st_sfc(sq(0, 0), sq(200, 0), sq(400, 0), sq(600, 0), crs = 3005))
# patch 1 burned; patch 2 in a wetland; patch 3 both; patch 4 neither.
polys <- list(
  fire    = sf::st_sf(fire_year = 2021L, geom = sf::st_sfc(sq(10, 10, 50), sq(410, 10, 50), crs = 3005)),
  wetland = sf::st_sf(waterbody_poly_id = c(11L, 13L),
                      geom = sf::st_sfc(sq(210, 10, 50), sq(420, 20, 50), crs = 3005)),
  harvest = sf::st_sf(harvest_start_year_calendar = integer(0),
                      geom = sf::st_sfc(crs = 3005)))
stub <- function(conn, src, patches, window) polys[[src$name]]
residual <- function(tagged, sources) {
  out <- capture.output(fp_disturbance_report(tagged, sources, "check"))
  as.numeric(sub(".*residual \\(noise\\): *([0-9.]+) ha.*", "\\1", grep("residual", out, value = TRUE)))
}

t_src <- fp_disturbance_tag(patches, list(fire, harvest), NULL, fetch = stub)
t_all <- fp_disturbance_tag(patches, list(fire, harvest, wetland), NULL, fetch = stub)
ok("in_wetland and its carried id land on the patches",
   all(c("in_wetland", "waterbody_poly_id") %in% names(t_all)) &&
     identical(t_all$in_wetland, c(FALSE, TRUE, TRUE, FALSE)) &&
     identical(t_all$waterbody_poly_id, c(NA, 11L, 13L, NA)))
ok("cause columns are identical with and without the context entry",
   identical(sf::st_drop_geometry(t_all)[names(sf::st_drop_geometry(t_src))],
             sf::st_drop_geometry(t_src)))
r_src <- residual(t_src, list(fire, harvest))
r_all <- residual(t_all, list(fire, harvest))
ok("the attribution residual is unchanged by a context entry", identical(r_src, r_all),
   sprintf("%.1f ha vs %.1f ha", r_src, r_all))
# MUST-FAIL ARM: the same wetland counted as a cause. If this ever matches, the residual check above
# cannot distinguish "context is excluded" from "context never tagged anything".
wet_as_src <- c(wetland, list(year_col = "yr"))
r_leak <- residual(t_all, list(fire, harvest, wet_as_src))
ok("must-fail arm: filing wetland under sources DOES shrink the residual", r_leak < r_all,
   sprintf("%.1f ha < %.1f ha", r_leak, r_all))
t_again <- fp_disturbance_tag(t_all, list(fire, harvest, wetland), NULL, fetch = stub)
ok("re-tagging an already-tagged layer reproduces it (fire_tag.R's path)",
   identical(sf::st_drop_geometry(t_again), sf::st_drop_geometry(t_all)))
ok("must-fail arm: the report REFUSES a context entry rather than counting it",
   refused(fp_disturbance_report(t_all, list(fire, harvest, wetland), "check")))
ok("a carried column stays typed when nothing matches (not Boolean on write)",
   is.integer(t_src$harvest_start_year_calendar) && is.integer(t_all$waterbody_poly_id),
   paste(class(t_src$harvest_start_year_calendar), class(t_all$waterbody_poly_id)))

# patch_id is numbered per sub-basin, so it repeats across basins. Two patches share id 1: the one
# in basin A sits in a wetland, the one in basin B does not. An id join gave B the wetland's key.
dup <- sf::st_sf(patch_id = c(1L, 1L), transition = "Trees -> Rangeland", area_ha = 1,
                 name_basin = c("A", "B"), from_class = "Trees", to_class = "Rangeland",
                 geom = sf::st_sfc(sq(200, 0), sq(800, 0), crs = 3005))
t_dup <- fp_disturbance_tag(dup, list(wetland), NULL, fetch = stub)
ok("carried values follow the ROW, not a repeated patch_id",
   identical(t_dup$in_wetland, c(TRUE, FALSE)) && identical(t_dup$waterbody_poly_id, c(11L, NA)),
   paste(t_dup$waterbody_poly_id, collapse = ","))

# The README figure's cause list is the other reader of the file; it must not see context names.
source(here::here("scripts", "readme_functions.R"), local = (rf <- new.env()))
dst_live <- yaml::read_yaml(here::here("config", "disturbance.yml"))
ok("the README figure's cause list excludes every context name",
   !any(vapply(dst_live$context, function(s) s$name, character(1)) %in%
          rf$fp_readme_sources(here::here("config", "disturbance.yml"))))

ok("must-fail arm: the report refuses patches missing a source's in_ column (it read 0 ha)",
   refused(fp_disturbance_report(t_src[, setdiff(names(t_src), "in_harvest")],
                                 list(fire, harvest), "check")))
upper <- wetland; upper$carry <- list("AREA_HA")
ok("an upper-case carry of a core column is refused (Postgres folds it onto area_ha)",
   refused(fp_disturbance_validate(list(sources = list(fire), context = list(upper)))))
lost <- wetland; lost$carry <- list("WATERBODY_POLY_ID")
ok("a carry the fetch did not return is refused, not silently dropped",
   refused(fp_disturbance_tag(patches, list(lost), NULL, fetch = stub)))

# `$` partial-matches: with no sources, `cfg$disturbance` would have returned a `disturbance_context`
# list and step 3 would have tagged and logged wetlands as causes (a key that existed only mid-branch;
# caught in review). The mechanism is any cfg key that is a strict prefix
# of another, so sweep every cfg key the scripts use rather than pinning this one pair.
src_files <- list.files(here::here("scripts"), pattern = "[.]R$", recursive = TRUE, full.names = TRUE)
tx <- unlist(lapply(src_files, readLines, warn = FALSE))
k1 <- sub("cfg[$]", "", unlist(regmatches(tx, gregexpr("cfg[$][A-Za-z_][A-Za-z0-9_]*", tx))))
k2 <- gsub("cfg\\[\\[\"|\"\\]\\]", "",
           unlist(regmatches(tx, gregexpr("cfg\\[\\[\"[A-Za-z0-9_]+\"\\]\\]", tx))))
keys <- sort(unique(c(k1, k2)))
pairs <- which(outer(keys, keys, function(x, y) x != y & startsWith(y, x)), arr.ind = TRUE)
pairs <- data.frame(prefix = keys[pairs[, 1]], longer = keys[pairs[, 2]])
mine <- pairs$prefix %in% c("disturbance", "context_overlays") |
  pairs$longer %in% c("disturbance", "context_overlays")
ok("no cfg key is a prefix of the disturbance/context keys (or vice versa)", !any(mine),
   paste(sprintf("%s<%s", pairs$prefix[mine], pairs$longer[mine]), collapse = ","))
if (any(!mine))
  message("  INFO  other cfg prefix pairs (not this check's; #97): ",
          paste(sprintf("%s<%s", pairs$prefix[!mine], pairs$longer[!mine]), collapse = ", "))

geom_clash <- wetland; geom_clash$carry <- list("geom")
ok("carrying the patches' geometry column is refused at tag time",
   refused(fp_disturbance_tag(patches, list(geom_clash), NULL, fetch = stub)))

# ---------------------------------------------------------------------------------------------
# live: an area's real layers, before and after `fire_tag.R <area>` (#91: no default area)
# ---------------------------------------------------------------------------------------------
# The checker owns the snapshot format, so a comparison never depends on how someone saved one:
# per transition layer, the attribute table plus each row's geometry as WKB.
a <- commandArgs(TRUE)
live_layers <- function(area) {
  gpkg <- here::here("data", area, "floodplain_landcover.gpkg")
  if (!file.exists(gpkg)) stop("no gpkg: ", gpkg, call. = FALSE)
  lyrs <- sf::st_layers(gpkg)$name
  list(gpkg = gpkg, all = lyrs, transition = grep("^transition_.+_[0-9]{4}_[0-9]{4}$", lyrs, value = TRUE))
}
# The layer's declared schema, read from the GeoPackage's own tables rather than through sf, so no
# reader default can normalise it away: per-column declared types, the geometry type and srs_id.
# Read-only (a plain dbConnect on a gpkg is a writer that has not written yet).
read_schema <- function(gpkg, lyr) {
  con <- DBI::dbConnect(RSQLite::SQLite(), gpkg, flags = RSQLite::SQLITE_RO)
  on.exit(DBI::dbDisconnect(con))
  ti <- DBI::dbGetQuery(con, sprintf("PRAGMA table_info(%s)", DBI::dbQuoteIdentifier(con, lyr)))
  gc <- DBI::dbGetQuery(con, "SELECT geometry_type_name, srs_id FROM gpkg_geometry_columns
                              WHERE table_name = ?", params = list(lyr))
  list(types = setNames(ti$type, ti$name), geometry = gc$geometry_type_name, srs_id = gc$srs_id)
}
read_layer <- function(gpkg, lyr) {
  # promote_to_multi = FALSE, or both sides of the comparison are promoted the same way and a re-tag
  # that turned every POLYGON into a MULTIPOLYGON compares byte-identical -- it did, on necr and bulk.
  x <- sf::st_read(gpkg, lyr, quiet = TRUE, promote_to_multi = FALSE)
  o <- order(x[["name_basin"]], x[["patch_id"]])   # the key; patch_id alone repeats across basins
  list(schema = read_schema(gpkg, lyr),
       attrs = sf::st_drop_geometry(x)[o, , drop = FALSE],
       wkb   = vapply(sf::st_as_binary(sf::st_geometry(x)[o]), function(r) paste(r, collapse = ""),
                      character(1)))
}

if (identical(a[1], "snapshot")) {
  if (is.na(a[2]) || is.na(a[3])) stop("usage: disturbance-check.R snapshot <area> <out.rds>")
  L <- live_layers(a[2])
  snap <- setNames(lapply(L$transition, function(l) read_layer(L$gpkg, l)), L$transition)
  saveRDS(snap, a[3])
  message(sprintf("snapshot: %s -> %s (%s)", a[2], a[3], paste(L$transition, collapse = ",")))
  quit(status = 0L)
}

if (is.na(a[1])) {
  message("\nlive: SKIPPED -- no area given. Offline properties only; this run says nothing about ",
          "any area's layers.")
} else {
  area <- a[1]; snap_path <- a[2]
  L <- live_layers(area)
  message(sprintf("\nlive: area=%s  gpkg=%s  layers=%s", area, L$gpkg, paste(L$transition, collapse = ",")))
  ok("at least one transition layer", length(L$transition) > 0)
  ok("no legacy `_disturbance` / `_fire` sibling (#55)",
     !any(grepl("^transition_.*_(disturbance|fire)$", L$all)),
     paste(grep("_(disturbance|fire)$", L$all, value = TRUE), collapse = ","))
  dst <- yaml::read_yaml(here::here("config", "disturbance.yml"))
  tag_cols <- unlist(lapply(c(dst$sources, dst$context),
                            function(s) c(paste0("in_", s$name), unlist(s$carry))))
  ctx_cols <- unlist(lapply(dst$context, function(s) c(paste0("in_", s$name), unlist(s$carry))))
  snap <- if (!is.na(snap_path) && file.exists(snap_path)) readRDS(snap_path) else NULL

  for (lyr in L$transition) {
    message("  -- ", lyr)
    cur <- read_layer(L$gpkg, lyr); tr <- cur$attrs
    ok("every context column is present", all(ctx_cols %in% names(tr)),
       paste(setdiff(ctx_cols, names(tr)), collapse = ","))
    for (s in dst$context) {
      in_c <- tr[[paste0("in_", s$name)]]
      ok(sprintf("in_%s tagged something (an empty fetch would leave it all FALSE)", s$name),
         sum(in_c %in% TRUE) > 0, sprintf("%d patches", sum(in_c %in% TRUE)))
      for (k in unlist(s$carry)) {
        ok(sprintf("`%s` is set exactly where in_%s is TRUE", k, s$name),
           identical(!is.na(tr[[k]]), in_c %in% TRUE))
        ok(sprintf("`%s` is typed, not Boolean", k), !is.logical(tr[[k]]), class(tr[[k]])[1])
      }
    }
    # The core set the validator protects must be exactly what step 3 writes, or the guard protects
    # a list that merely happens to agree with the writer (one fact derived twice).
    ok("the protected core columns are exactly the layer's non-tag columns",
       setequal(setdiff(names(tr), tag_cols), FP_PATCH_CORE),
       paste(sort(setdiff(names(tr), tag_cols)), collapse = ","))
    ok("item keys stay the last columns, as step 3 writes them",
       identical(tail(names(tr), 3), c("wsg", "species", "scenario")))

    if (is.null(snap)) {
      message("  SKIP  before/after comparison -- no snapshot given (run `snapshot` before fire_tag.R)")
    } else if (is.null(snap[[lyr]])) {
      ok("the snapshot covers this layer", FALSE, lyr)
    } else if (is.null(snap[[lyr]]$schema$types)) {
      # An older snapshot has no schema; comparing NULL types would pass vacuously.
      ok("the snapshot records the layer schema (retake it with this version)", FALSE, lyr)
    } else {
      s0 <- snap[[lyr]]
      ok("patch set identical to the snapshot, by (name_basin, patch_id)",
         identical(paste(tr$name_basin, tr$patch_id), paste(s0$attrs$name_basin, s0$attrs$patch_id)),
         sprintf("%d vs %d patches", nrow(tr), nrow(s0$attrs)))
      ok("no snapshot column was dropped by the re-tag", !length(setdiff(names(s0$attrs), names(tr))),
         paste(setdiff(names(s0$attrs), names(tr)), collapse = ","))
      keep  <- setdiff(intersect(names(s0$attrs), names(tr)), ctx_cols)
      moved <- keep[!vapply(keep, function(k) fp_same_values(tr[[k]], s0$attrs[[k]]), logical(1))]
      ok("every cause, carried and core column holds the same values as the snapshot",
         !length(moved), paste(moved, collapse = ","))
      ok("declared geometry type and srs_id unchanged",
         identical(cur$schema[c("geometry", "srs_id")], s0$schema[c("geometry", "srs_id")]),
         sprintf("%s/%s vs %s/%s", cur$schema$geometry, cur$schema$srs_id,
                 s0$schema$geometry %||% "?", s0$schema$srs_id %||% "?"))
      # Declared field types, for every column the snapshot had. The one permitted move is the
      # repair #95 makes: an all-NA carry that step 3 wrote BOOLEAN comes back typed.
      t0 <- s0$schema$types; t1 <- cur$schema$types[names(t0)]
      moved_t <- names(t0)[!(t0 == t1 | (t0 == "BOOLEAN" & names(t0) %in% tag_cols &
                                          !grepl("^in_", names(t0))))]
      ok("declared field types unchanged (BOOLEAN -> typed allowed for carries)", !length(moved_t),
         paste(sprintf("%s: %s -> %s", moved_t, t0[moved_t], t1[moved_t]), collapse = "; "))
      ok("geometry is byte-identical to the snapshot (WKB, unpromoted)", identical(cur$wkb, s0$wkb),
         if (length(cur$wkb) == length(s0$wkb)) sprintf("%d rows differ", sum(cur$wkb != s0$wkb))
         else "row counts differ")
    }
  }
}

message(if (fails == 0) "\nALL PASS" else sprintf("\n%d FAIL", fails))
quit(status = if (fails == 0) 0L else 1L)
