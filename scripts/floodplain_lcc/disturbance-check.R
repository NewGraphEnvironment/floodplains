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
#   live (area arg)  -- the area's real transition layer after `fire_tag.R <area>`: context columns
#                       present, and every cause column identical to a snapshot taken before the
#                       re-tag. No default area (#91): a bare run checks nothing live and says so.
#
# usage: Rscript scripts/floodplain_lcc/disturbance-check.R                 # offline only
#        Rscript scripts/floodplain_lcc/disturbance-check.R <area> <snapshot.rds>  # + live

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
geom_clash <- wetland; geom_clash$carry <- list("geom")
ok("carrying the patches' geometry column is refused at tag time",
   refused(fp_disturbance_tag(patches, list(geom_clash), NULL, fetch = stub)))

# ---------------------------------------------------------------------------------------------
# live: the area's real layer after `fire_tag.R <area>` (#91: no default area)
# ---------------------------------------------------------------------------------------------
a <- commandArgs(TRUE)
if (is.na(a[1])) {
  message("\nlive: SKIPPED -- no area given. Offline properties only; this run says nothing about ",
          "any area's layers.")
} else {
  area <- a[1]; snap_path <- a[2]
  gpkg <- here::here("data", area, "floodplain_landcover.gpkg")
  lyrs <- sf::st_layers(gpkg)$name
  tlyr <- grep("^transition_.*[0-9]$", lyrs, value = TRUE)
  message(sprintf("\nlive: area=%s  gpkg=%s  layers=%s", area, gpkg, paste(tlyr, collapse = ",")))
  ok("exactly one live transition layer", length(tlyr) == 1, paste(tlyr, collapse = ","))
  ok("no legacy `_disturbance` / `_fire` sibling (#55)",
     !any(grepl("^transition_.*_(disturbance|fire)$", lyrs)),
     paste(grep("_(disturbance|fire)$", lyrs, value = TRUE), collapse = ","))
  dst <- yaml::read_yaml(here::here("config", "disturbance.yml"))
  tr  <- sf::st_drop_geometry(sf::st_read(gpkg, tlyr[1], quiet = TRUE))
  ctx_cols <- unlist(lapply(dst$context, function(s) c(paste0("in_", s$name), unlist(s$carry))))
  ok("every context column is present", all(ctx_cols %in% names(tr)),
     paste(setdiff(ctx_cols, names(tr)), collapse = ","))
  # The core set the validator protects must be exactly what step 3 writes, or the guard protects
  # a list that merely happens to agree with the writer (one fact derived twice).
  tag_cols <- unlist(lapply(c(dst$sources, dst$context),
                            function(s) c(paste0("in_", s$name), unlist(s$carry))))
  ok("the protected core columns are exactly the layer's non-tag columns",
     setequal(setdiff(names(tr), tag_cols), FP_PATCH_CORE),
     paste(sort(setdiff(names(tr), tag_cols)), collapse = ","))
  ok("item keys stay the last columns, as step 3 writes them",
     identical(tail(names(tr), 3), c("wsg", "species", "scenario")))
  if (is.na(snap_path) || !file.exists(snap_path)) {
    ok("a pre-retag snapshot was supplied for the cause-column comparison", FALSE, snap_path)
  } else {
    snap <- readRDS(snap_path)
    keep <- intersect(names(snap), setdiff(names(tr), ctx_cols))
    ok("patch set identical to the snapshot", identical(sort(tr$patch_id), sort(snap$patch_id)),
       sprintf("%d vs %d patches", nrow(tr), nrow(snap)))
    a1 <- tr[order(tr$patch_id), keep]; a0 <- snap[order(snap$patch_id), keep]
    rownames(a1) <- rownames(a0) <- NULL
    ok("every cause, carried and core column is identical to the snapshot",
       identical(a1, a0), paste(keep[!vapply(keep, function(k) identical(a1[[k]], a0[[k]]),
                                             logical(1))], collapse = ","))
  }
}

message(if (fails == 0) "\nALL PASS" else sprintf("\n%d FAIL", fails))
quit(status = if (fails == 0) 0L else 1L)
