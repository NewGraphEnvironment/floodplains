# wsg_split-check.R — assert the group-line split (#53) means what it says.
#
# Two sections:
#   offline (always) -- fp_wsg.R on hand-built geometry, and fp_split_patches() against drift's own
#                       zoned dft_transition_vectors() on a tiny raster: the reference for "the inside
#                       rows are what step 3 wrote before" is drift, not the code under test. Each
#                       rule has an arm that must go red if it is broken.
#   live (area arg)  -- the written layers: every published layer of the area's species carries
#                       in_wsg, the pieces sit on the side of the group line they claim, the patch
#                       key is unique, and (with FP_SPLIT_BACKUP=<dir> holding the pre-split
#                       floodplain.gpkg / floodplain_landcover.gpkg) the inside totals equal the
#                       clipped totals that were there before.
#
# usage: Rscript scripts/floodplain_lcc/wsg_split-check.R                    # offline only
#        Rscript scripts/floodplain_lcc/wsg_split-check.R <area> [scenario]  # + live

suppressMessages({library(sf); library(terra)})
sf::sf_use_s2(FALSE)
lcc <- here::here("scripts", "floodplain_lcc")
source(file.path(lcc, "fp_wsg.R"))
`%||%` <- function(a, b) if (is.null(a)) b else a

fails <- 0L
ok <- function(label, cond, detail = "") {
  if (isTRUE(cond)) {
    message("  PASS  ", label, if (nzchar(detail)) paste0("  (", detail, ")") else "")
  } else {
    fails <<- fails + 1L
    message("  FAIL  ", label, if (nzchar(detail)) paste0("  (", detail, ")") else "")
  }
}
area_of <- function(x) as.numeric(sf::st_area(x))
rect <- function(x0, x1, y0, y1) sf::st_polygon(list(rbind(c(x0, y0), c(x1, y0), c(x1, y1), c(x0, y1), c(x0, y0))))

# ---------------------------------------------------------------------------------------------
message("\noffline: fp_wsg_split on hand-built rows")
# ---------------------------------------------------------------------------------------------
crs <- 3005
wsg <- sf::st_sf(watershed_group_code = "AAAA", geom = sf::st_sfc(rect(0, 100, 0, 100), crs = crs))
x <- sf::st_sf(
  id = c("inside", "straddle", "outside", "edge_out", "gc"),
  v  = 1:5,
  geom = sf::st_sfc(
    rect(10, 20, 10, 20),                                   # wholly inside
    rect(90, 110, 10, 20),                                  # crosses the line
    rect(120, 130, 10, 20),                                 # wholly outside
    rect(100, 110, 50, 60),                                 # outside, shares an EDGE with the group
    sf::st_multipolygon(list(rect(90, 110, 0, 20)[[1]] |> list(), rect(100, 110, 40, 60)[[1]] |> list())),
    crs = crs))
sp <- fp_wsg_split(x, wsg)

cons <- tapply(area_of(sp), sp$id, sum)[x$id]
ok("every row's pieces conserve its area", isTRUE(all.equal(as.numeric(cons), area_of(x))),
   paste(sprintf("%s %.0f", x$id, cons), collapse = ", "))
ok("every column is kept, plus in_wsg", all(c("id", "v", "in_wsg") %in% names(sp)) && is.logical(sp$in_wsg) &&
     !anyNA(sp$in_wsg))
ok("a row crossing the line becomes two rows, inside then outside, same attributes",
   identical(sp$in_wsg[sp$id == "straddle"], c(TRUE, FALSE)) && all(sp$v[sp$id == "straddle"] == 2L))
ok("a row on one side stays one row", sum(sp$id == "inside") == 1 && sum(sp$id == "outside") == 1 &&
     isTRUE(sp$in_wsg[sp$id == "inside"]) && isFALSE(sp$in_wsg[sp$id == "outside"]))
ok("a shared edge yields no zero-area inside piece", sum(sp$id == "edge_out") == 1 && isFALSE(sp$in_wsg[sp$id == "edge_out"]))
ok("a polygon + line intersection (GEOMETRYCOLLECTION) is reduced to its polygon",
   !any(sf::st_geometry_type(sp) == "GEOMETRYCOLLECTION") &&
     isTRUE(all.equal(area_of(sp[sp$id == "gc" & sp$in_wsg, ]), 200)))
ok("premise: the raw intersection for that row IS a GEOMETRYCOLLECTION, so the reduction is load-bearing",
   sf::st_geometry_type(suppressWarnings(sf::st_intersection(sf::st_geometry(x)[5], sf::st_geometry(wsg)))) ==
     "GEOMETRYCOLLECTION")
ok("in_wsg pieces lie inside the group, the others outside",
   all(area_of(suppressWarnings(sf::st_difference(sp[sp$in_wsg, ], sf::st_geometry(wsg)))) < 1e-9) &&
     all(area_of(suppressWarnings(sf::st_intersection(sf::st_geometry(sp[!sp$in_wsg, ]), sf::st_geometry(wsg)))) < 1e-9))
inn_only <- suppressWarnings(sf::st_intersection(x, sf::st_geometry(wsg)))
ok("must-fail arm: inside pieces alone do NOT conserve the rows (the remainder is load-bearing)",
   !isTRUE(all.equal(sum(area_of(inn_only)), sum(area_of(x)))))
ok("a layer that already carries in_wsg is refused (a second split would be silent duplication)",
   inherits(tryCatch(fp_wsg_split(sp, wsg), error = function(e) e), "error"))

# ---------------------------------------------------------------------------------------------
message("\noffline: fp_split_patches against drift's own zoned vectorisation")
# ---------------------------------------------------------------------------------------------
# 20 x 20 cells of 10 m. Three change patches: one inside the group, one across its east edge, one
# outside; the rest stable. drift with zones= is what step 3 ran before #53.
r <- terra::rast(nrows = 20, ncols = 20, xmin = 0, xmax = 200, ymin = 0, ymax = 200, crs = "EPSG:32610",
                 vals = 2002L)
v <- terra::values(r)[, 1]
cell <- function(c0, c1, r0, r1) as.vector(outer((r0:r1 - 1) * 20, c0:c1, "+"))
v[cell(2, 4, 2, 4)]   <- 2011L          # inside
v[cell(9, 13, 9, 12)] <- 2011L          # straddles x = 100
v[cell(16, 18, 2, 3)] <- 2005L          # outside
terra::values(r) <- v
levels(r) <- data.frame(id = c(2002L, 2005L, 2011L),
                        transition = c("Trees -> Trees", "Trees -> Crops", "Trees -> Rangeland"))
grp <- sf::st_sf(name_basin = "AAAA", watershed_group_code = "AAAA",
                 geom = sf::st_sfc(rect(0, 100, 0, 200), crs = 32610))
attr(grp, "zones_are_wsg") <- TRUE
clipped   <- drift::dft_transition_vectors(r, zones = grp, zone_col = "name_basin", changes_only = TRUE)
unclipped <- drift::dft_transition_vectors(r, changes_only = TRUE)
pp <- fp_split_patches(unclipped, grp, "name_basin", grp)

inn <- pp[pp$in_wsg, ]
# Values, not containers: row names and the sfc's cached bbox differ by construction (the bbox of a
# subset), so the comparison is over the attribute VALUES and the geometry's WKB bytes.
vals <- function(d) { d <- sf::st_drop_geometry(d); rownames(d) <- NULL; d }
same_rows <- function(a, b) identical(vals(a)[names(vals(b))], vals(b)) &&
  identical(sf::st_as_binary(sf::st_geometry(a)), sf::st_as_binary(sf::st_geometry(b)))
ok("the inside rows ARE drift's zoned output: identical attribute values and WKB, in order",
   same_rows(inn, clipped),
   sprintf("%d inside rows, %d drift rows", nrow(inn), nrow(clipped)))
ok("premise: drift's zoned output is CLIPPED (it drops area the unzoned one keeps)",
   sum(area_of(clipped)) < sum(area_of(unclipped)))
ok("inside + outside pieces conserve the unzoned patches' area",
   isTRUE(all.equal(sum(area_of(pp)), sum(area_of(unclipped)))))
ok("whole-WSG: in_wsg is exactly 'has a sub-basin'", identical(pp$in_wsg, !is.na(pp$name_basin)))
ok("the straddling patch keeps ONE patch_id across its two rows",
   any(table(pp$patch_id) == 2) && all(tapply(pp$in_wsg, pp$patch_id, function(z) length(unique(z)) == length(z))))
ok("the (name_basin, patch_id, in_wsg) key is unique", !anyDuplicated(paste(pp$name_basin, pp$patch_id, pp$in_wsg)))

# Subset area: interior sub-basins inside a larger group. A piece outside every sub-basin keeps
# name_basin NA; the group line then splits whatever crosses it.
sub_zone <- sf::st_sf(name_basin = "inner", geom = sf::st_sfc(rect(0, 60, 0, 200), crs = 32610))
grp2 <- sf::st_sf(watershed_group_code = "AAAA", geom = sf::st_sfc(rect(0, 100, 0, 200), crs = 32610))
attr(grp2, "zones_are_wsg") <- FALSE
ps <- fp_split_patches(unclipped, sub_zone, "name_basin", grp2)
ok("subset: pieces conserve the patches' area", isTRUE(all.equal(sum(area_of(ps)), sum(area_of(unclipped)))))
ok("subset: ground outside every sub-basin but inside the group is name_basin NA, in_wsg TRUE",
   any(is.na(ps$name_basin) & ps$in_wsg))
ok("subset: the (name_basin, patch_id, in_wsg) key is unique",
   !anyDuplicated(paste(ps$name_basin, ps$patch_id, ps$in_wsg)))
ok("must-fail arm: WITHOUT in_wsg the key collides (the straddler's two NA-basin pieces)",
   anyDuplicated(paste(ps$name_basin, ps$patch_id)) > 0)

# ---------------------------------------------------------------------------------------------
message("\noffline: fp_wsg_polygon and fp_floodplain_whole")
# ---------------------------------------------------------------------------------------------
td <- tempfile("wsgchk"); dir.create(td)
sf::st_write(sf::st_sf(name_basin = "aaaa", watershed_group_code = "AAAA", geom = sf::st_geometry(wsg)),
             file.path(td, "subbasins.gpkg"), layer = "subbasins", quiet = TRUE)
fp_wsg_subbasin <- function(conn, wsg, name_basin = NULL) stop("DB reached")
gw <- fp_wsg_polygon(list(watershed_group = "AAAA", dir_out = td), conn = "no-db")
ok("whole-WSG: the group polygon is read from subbasins.gpkg, no database", isTRUE(attr(gw, "zones_are_wsg")) &&
     isTRUE(all.equal(area_of(gw), 1e4)))
ok("must-fail arm: a subbasins.gpkg for ANOTHER group goes to the database",
   grepl("DB reached", tryCatch(fp_wsg_polygon(list(watershed_group = "BBBB", dir_out = td), conn = "no-db"),
                                error = function(e) conditionMessage(e))))
fw <- fp_floodplain_whole(sp[sp$id == "straddle", ])
ok("fp_floodplain_whole: split pieces re-join to one feature of the same area",
   nrow(fw) == 1 && isTRUE(all.equal(area_of(fw), area_of(x[2, ]))))
one <- x[1, ]
ok("fp_floodplain_whole: an unsplit one-row layer passes through untouched", identical(fp_floodplain_whole(one), one))
unlink(td, recursive = TRUE)

# ---------------------------------------------------------------------------------------------
# live
# ---------------------------------------------------------------------------------------------
a <- commandArgs(TRUE)
if (is.na(a[1])) {
  message("\nlive: SKIPPED -- no area given. Offline properties only.")
} else {
  area <- a[1]
  acfg <- yaml::read_yaml(here::here("config", area, "area.yml"))
  scen <- if (!is.na(a[2])) a[2] else acfg$primary_scenario
  sp_  <- sub("_.*$", "", scen)
  yrs  <- sort(acfg$change_interval %||% c(2017L, 2023L))
  dir  <- here::here("data", area)
  cfg  <- list(watershed_group = acfg$watershed_group, dir_out = dir)
  rm(fp_wsg_subbasin)
  source(file.path(lcc, "fp_region.R"))
  g <- fp_wsg_polygon(cfg)
  message(sprintf("\nlive: area=%s scenario=%s wsg=%s (group polygon from %s)", area, scen, cfg$watershed_group,
                  if (isTRUE(attr(g, "zones_are_wsg"))) "subbasins.gpkg" else "fwapg"))
  side_ok <- function(lyr, tol_m2 = 1) {
    gg <- sf::st_union(sf::st_geometry(sf::st_transform(g, sf::st_crs(lyr))))
    a_in  <- sum(area_of(suppressWarnings(sf::st_difference(sf::st_geometry(lyr[lyr$in_wsg, ]), gg))))
    a_out <- if (any(!lyr$in_wsg)) sum(area_of(suppressWarnings(sf::st_intersection(sf::st_geometry(lyr[!lyr$in_wsg, ]), gg)))) else 0
    c(a_in = a_in, a_out = a_out)
  }
  fpg <- file.path(dir, "floodplain.gpkg")
  fl  <- grep(paste0("^", sp_, "_ff[0-9]+(_by_.+)?$"), sf::st_layers(fpg)$name, value = TRUE)
  for (l in fl) {
    x <- sf::st_read(fpg, layer = l, quiet = TRUE)
    ok(sprintf("%s carries in_wsg, never NA", l), "in_wsg" %in% names(x) && !anyNA(x$in_wsg))
    if (!"in_wsg" %in% names(x)) next
    s <- side_ok(x)
    ok(sprintf("%s: pieces sit on the side they claim (< 1 m2 across the line)", l), all(s < 1),
       sprintf("in-but-outside %.3f m2, out-but-inside %.3f m2", s[1], s[2]))
    if (!grepl("_by_", l))
      ok(sprintf("%s: at most one row per side", l), !anyDuplicated(x$in_wsg))
    m <- sum(area_of(x[!x$in_wsg, ])) / sum(area_of(x))
    message(sprintf("  INFO  %s: %.1f ha, %.2f%% outside %s", l, sum(area_of(x)) / 1e4, 100 * m, cfg$watershed_group))
  }
  lcg  <- file.path(dir, "floodplain_landcover.gpkg")
  tlyr <- sprintf("transition_%s_%d_%d", scen, yrs[1], yrs[2])
  tr <- sf::st_read(lcg, layer = tlyr, quiet = TRUE, promote_to_multi = FALSE)
  ok(sprintf("%s carries in_wsg", tlyr), "in_wsg" %in% names(tr) && !anyNA(tr$in_wsg))
  if ("in_wsg" %in% names(tr)) {
    ok("patch key (name_basin, patch_id, in_wsg) is unique", !anyDuplicated(paste(tr$name_basin, tr$patch_id, tr$in_wsg)))
    if (isTRUE(attr(g, "zones_are_wsg")))
      ok("whole-WSG: in_wsg is exactly 'has a sub-basin'", identical(tr$in_wsg, !is.na(tr$name_basin)))
    s <- side_ok(tr)
    ok("patches sit on the side they claim (< 1 m2 across the line in total)", all(s < 1),
       sprintf("%.3f / %.3f m2", s[1], s[2]))
    message(sprintf("  INFO  %s: %d rows, %.1f ha in, %.1f ha out", tlyr, nrow(tr), sum(tr$area_ha[tr$in_wsg]),
                    sum(tr$area_ha[!tr$in_wsg])))
  }
  cl <- grep(sprintf("^classified_%s_[0-9]{4}$", scen), sf::st_layers(lcg)$name, value = TRUE)
  ok("every classified layer carries in_wsg", length(cl) > 0 && all(vapply(cl, function(l)
    "in_wsg" %in% names(sf::st_read(lcg, query = sprintf('SELECT * FROM "%s" LIMIT 1', l), quiet = TRUE)), logical(1))))
  bk <- Sys.getenv("FP_SPLIT_BACKUP", "")
  if (nzchar(bk)) {
    b_tr <- sf::st_read(file.path(bk, "floodplain_landcover.gpkg"), layer = tlyr, quiet = TRUE, promote_to_multi = FALSE)
    rel <- abs(sum(tr$area_ha[tr$in_wsg %in% TRUE & !is.na(tr$name_basin)]) - sum(b_tr$area_ha)) / sum(b_tr$area_ha)
    ok("the inside patch total equals the clipped total from before the split (1e-9 relative)", rel < 1e-9,
       sprintf("%.4f vs %.4f ha", sum(tr$area_ha[tr$in_wsg %in% TRUE & !is.na(tr$name_basin)]), sum(b_tr$area_ha)))
    b_fp <- sf::st_read(file.path(bk, "floodplain.gpkg"), layer = scen, quiet = TRUE)
    n_fp <- sf::st_read(fpg, layer = scen, quiet = TRUE)
    ok("the split floodplain conserves the whole delineation's area (1e-6 relative)",
       abs(sum(area_of(n_fp)) - sum(area_of(b_fp))) / sum(area_of(b_fp)) < 1e-6)
  } else message("  INFO  FP_SPLIT_BACKUP unset: before/after totals not compared")
}

message(if (fails == 0) "\nALL PASS" else sprintf("\n%d FAIL", fails))
quit(status = if (fails == 0) 0L else 1L)
