# composition-check.R — assert the composition table (#108) means what it says.
#
# Two sections:
#   offline (always) -- fp_composition() on a 4 x 4 hand-built grid, against an expected table built
#                       by a plain per-cell loop over the same matrices (no terra), so the reference
#                       is not the code under test. Each rule has an arm that must go red if broken.
#   live (area arg)  -- the written table against things it was NOT derived from:
#                       * its `change` ha against the transition layer's sum(area_ha) (vectors)
#                       * each overlay's cell ha against the vector area floodplain ∩ overlay
#                       * an any-touch in_<name> on the patches wherever the table has change cells
#                         inside <name> (any-touch is a superset of cell-centre, so the reverse
#                         is not a check) -- which is what tells an empty in_alr from a failed fetch
#                       * the provenance record re-derived from the table and the rasters
#
# usage: Rscript scripts/floodplain_lcc/composition-check.R                    # offline only
#        Rscript scripts/floodplain_lcc/composition-check.R <area> [scenario]  # + live

suppressMessages({library(sf); library(terra)})
sf::sf_use_s2(FALSE)
lcc <- here::here("scripts", "floodplain_lcc")
source(file.path(lcc, "fp_provenance.R"))
source(file.path(lcc, "fp_disturbance.R"))
source(here::here("scripts", "fp_raster.R"))
source(file.path(lcc, "fp_composition.R"))

fails <- 0L
ok <- function(label, cond, detail = "") {
  if (isTRUE(cond)) {
    message("  PASS  ", label, if (nzchar(detail)) paste0("  (", detail, ")") else "")
  } else {
    fails <<- fails + 1L
    message("  FAIL  ", label, if (nzchar(detail)) paste0("  (", detail, ")") else "")
  }
}
# Refused BY THE GUARD, not merely erroring (disturbance-check.R's rule).
refused <- function(expr) inherits(tryCatch({ force(expr); NULL }, error = function(e) e),
                                   "fp_composition_error")

# ---------------------------------------------------------------------------------------------
message("\noffline: a 4 x 4 grid, every status and both overlays")
# ---------------------------------------------------------------------------------------------
classes <- c(`1` = "Water", `2` = "Trees", `5` = "Crops", `11` = "Rangeland")
F <- c( 2,  2,  2, 2,    2, 2, 11, 11,    1, 1, 5,  5,   NA, NA,  2, NA)
T <- c( 2, 11, 11, 2,    2, 2,  5, 11,    1, 2, 11, 5,   NA,  2, NA, NA)
sieve <- c(3, 11)                      # changed cells the 1 ha sieve removed
TR <- ifelse(is.na(F) | is.na(T), NA, F * 1000 + T); TR[sieve] <- NA
ALR <- c(2, 3, 7, 13)                  # 13 is outside the footprint: must not be counted
WET <- c(3, 9)
grid <- function(v) terra::rast(nrows = 4, ncols = 4, xmin = 0, xmax = 40, ymin = 0, ymax = 40,
                                crs = "EPSG:32610", vals = v)
ind  <- function(i) { v <- rep(NA_real_, 16); v[i] <- 1; v }
ov   <- list(alr = grid(ind(ALR)), wetland = grid(ind(WET)))

# the reference: a per-cell loop, no terra
ref <- do.call(rbind, lapply(1:16, function(i) {
  if (is.na(F[i]) && is.na(T[i])) return(NULL)
  st <- if (is.na(F[i]) || is.na(T[i])) "nodata" else if (F[i] == T[i]) "stable" else
    if (is.na(TR[i])) "sieved" else "change"
  data.frame(from_code = F[i], to_code = T[i], status = st,
             in_alr = i %in% ALR, in_wetland = i %in% WET)
}))
# Counted by a string key, not stats::aggregate(), which silently drops a group whose `by` holds NA
# -- exactly the nodata rows (code-check-r.md, "stats::aggregate() has three separate silent behaviours").
key0 <- function(d) paste(d$from_code, d$to_code, d$status, d$in_alr, d$in_wetland)
ref_n <- table(key0(ref))
key <- function(d) paste(key0(d), d$cells)
ref <- data.frame(k = names(ref_n), cells = as.integer(ref_n))
ref$key <- paste(ref$k, ref$cells)

comp <- fp_composition(grid(F), grid(T), grid(TR), ov, classes)
ok("every (class pair, status, overlay) combination and count matches the per-cell reference",
   setequal(key(comp), ref$key) && nrow(comp) == nrow(ref), sprintf("%d rows", nrow(comp)))
ok("the footprint is the cells non-NA in EITHER endpoint (14 of 16)", sum(comp$cells) == 14)
ok("cell 13, inside an overlay but outside the footprint, is not counted",
   sum(comp$cells[comp$in_alr]) == 3)
ok("ha = cells x cell area (10 m cells -> 0.01 ha)", isTRUE(all.equal(comp$ha, comp$cells * 0.01)))
ok("statuses: 7 stable, 3 change, 2 sieved, 2 nodata",
   identical(as.numeric(tapply(comp$cells, factor(comp$status, FP_COMP_STATUS), sum)), c(7, 3, 2, 2)))
ok("class names come from the code map; an NA endpoint has no name",
   all(comp$from_class[comp$from_code %in% 11] == "Rangeland") && all(is.na(comp$to_class[is.na(comp$to_code)])))
ok("ALR and wetland are independent columns (cell 3 is in both)",
   sum(comp$cells[comp$in_alr & comp$in_wetland]) == 1)
# Premise arm: transition.tif carries STABLE cells, so "trans non-NA" alone would call them change.
ok("premise: the fixture's transition raster holds stable cells (non-NA != changed)",
   sum(!is.na(TR) & F == T, na.rm = TRUE) > 0)

comp0 <- fp_composition(grid(F), grid(T), NULL, list(), classes)
ok("no transition raster -> every changed cell is sieved, none `change`",
   !any(comp0$status == "change") && sum(comp0$cells[comp0$status == "sieved"]) == 5)
ok("no overlays -> no in_ columns, same footprint", !any(grepl("^in_", names(comp0))) && sum(comp0$cells) == 14)

TRbad <- TR; TRbad[1] <- 2011
ok("must-fail arm: a transition raster from a different run is refused",
   refused(fp_composition(grid(F), grid(T), grid(TRbad), ov, classes)))
TRna <- TR; TRna[14] <- 2002
ok("must-fail arm: a transition cell where an endpoint is NA is refused",
   refused(fp_composition(grid(F), grid(T), grid(TRna), ov, classes)))
ok("a class code with no name is refused", refused(fp_composition(grid(F), grid(T), grid(TR), ov, classes[-1])))
ok("unnamed overlays are refused", refused(fp_composition(grid(F), grid(T), grid(TR), unname(ov), classes)))
off <- terra::rast(nrows = 4, ncols = 4, xmin = 5, xmax = 45, ymin = 0, ymax = 40, crs = "EPSG:32610", vals = 1)
ok("an overlay off the classified grid is refused",
   refused(fp_composition(grid(F), grid(T), grid(TR), list(alr = off), classes)))

# membership: cell CENTRE, not any-touch
tri <- sf::st_sf(geom = sf::st_sfc(sf::st_polygon(list(rbind(c(0, 40), c(4, 40), c(0, 36), c(0, 40))))),
                 crs = 32610)                                # grazes cell 1's corner, misses its centre
cen <- sf::st_sf(geom = sf::st_sfc(sf::st_polygon(list(rbind(c(3, 33), c(7, 33), c(7, 37), c(3, 37), c(3, 33))))),
                 crs = 32610)                                # covers cell 1's centre (5, 35)
ok("fp_rast_cells: a polygon grazing a cell without its centre does not claim it",
   is.na(terra::values(fp_rast_cells(tri, grid(F)))[1]))
ok("fp_rast_cells: a polygon over the centre claims the cell",
   identical(as.numeric(terra::values(fp_rast_cells(cen, grid(F)))[1]), 1))
ok("must-fail arm (premise): any-touch DOES claim the grazed cell, so the rule is load-bearing",
   identical(as.numeric(terra::values(terra::rasterize(terra::vect(tri), grid(F), touches = TRUE,
                                                        background = NA))[1]), 1))
ok("fp_rast_cells: zero polygons give an all-NA grid, not an error",
   all(is.na(terra::values(fp_rast_cells(tri[0, ], grid(F))))))

# summary: shares of the floodplain use in_floodplain cells, change uses the footprint
FPC <- c(1:12)                                     # cells 13-16 (the bottom row) are the ring
compf <- fp_composition(grid(F), grid(T), grid(TR), c(list(floodplain = grid(ind(FPC))), ov), classes)
sm <- fp_composition_summary(compf)
ok("summary: floodplain = in_floodplain cells (12), footprint = 14",
   isTRUE(all.equal(sm$floodplain_ha, 0.12)) && isTRUE(all.equal(sm$footprint_ha, 0.14)))
ok("summary: ALR = ALR cells inside the floodplain (3), change in ALR = 2 of 3 change cells",
   isTRUE(all.equal(sm$alr_ha, 0.03)) && isTRUE(all.equal(sm$change_in_alr_ha, 0.02)) &&
     isTRUE(all.equal(sm$change_in_alr_share, 2 / 3)))
ok("summary: in_floodplain is the denominator, never itself a reported overlay",
   is.null(sm$floodplain_share) && is.null(sm$change_in_floodplain_ha))

# digest
d1 <- fp_composition_digest(comp)
ok("the table digest ignores row order", identical(d1, fp_composition_digest(comp[nrow(comp):1, ])))
c2 <- comp; c2$cells[1] <- c2$cells[1] + 1
ok("must-fail arm: one cell more moves the digest", !identical(d1, fp_composition_digest(c2)))
c3 <- comp; c3$in_alr[1] <- !c3$in_alr[1]
ok("must-fail arm: flipping a membership moves the digest", !identical(d1, fp_composition_digest(c3)))

# ---------------------------------------------------------------------------------------------
# live
# ---------------------------------------------------------------------------------------------
a <- commandArgs(TRUE)
if (is.na(a[1])) {
  message("\nlive: SKIPPED -- no area given. Offline properties only.")
} else {
  area <- a[1]
  acfg <- yaml::read_yaml(here::here("config", area, "area.yml"))
  scen <- if (!is.na(a[2])) a[2] else acfg$primary_scenario %||% paste0(acfg$species, "_ff04")
  yrs  <- sort(acfg$change_interval %||% c(2017L, 2023L))
  dir  <- here::here("data", area)
  gpkg <- file.path(dir, "floodplain_landcover.gpkg")
  lyr  <- sprintf("composition_%s_%d_%d", scen, yrs[1], yrs[2])
  tlyr <- sprintf("transition_%s_%d_%d", scen, yrs[1], yrs[2])
  message(sprintf("\nlive: area=%s scenario=%s layer=%s", area, scen, lyr))
  lyrs <- sf::st_layers(gpkg)$name
  ok("the composition layer exists", lyr %in% lyrs)
  if (lyr %in% lyrs) {
    comp <- sf::st_read(gpkg, lyr, quiet = TRUE)
    ok("item keys present and single-valued", all(c("wsg", "species", "scenario") %in% names(comp)) &&
         length(unique(comp$scenario)) == 1 && identical(unique(comp$scenario), scen))
    ok("status values are the declared four", all(comp$status %in% FP_COMP_STATUS))
    chg <- comp$status == "change"
    in_cols <- grep("^in_", names(comp), value = TRUE)

    ok("in_floodplain present (the population shares of the floodplain use)", "in_floodplain" %in% in_cols)
    fpc <- comp$in_floodplain %in% TRUE

    # (1) change == the transition layer, an independent vectorisation of the same cells. ONE-SIDED:
    # step 3 intersects the patches with the sub-basins and recomputes their area, so change cells the
    # sub-basin boundary clips lose area on the patch side and never on this one. Measured 2026-10-02:
    # NECR cells 4,730.0 ha vs patches 4,712.6 ha (+0.37%). A multi-sub-basin area (neexdzii) needs
    # its own measurement before this bound is reused.
    tr <- sf::st_read(gpkg, tlyr, quiet = TRUE, promote_to_multi = FALSE)
    v_ha <- sum(tr$area_ha); c_ha <- sum(comp$ha[chg])
    rel <- (c_ha - v_ha) / v_ha
    ok("change ha >= the transition layer's sum(area_ha), by under 1% (sub-basin clipping only)",
       rel >= -1e-6 && rel < 0.01, sprintf("cells %.1f ha vs patches %.1f ha, %+.2f%%", c_ha, v_ha, 100 * rel))
    # The vector floodplain against in_floodplain: the cell-centre rule, measured on the area itself.
    fp  <- sf::st_read(file.path(dir, "floodplain.gpkg"), layer = scen, quiet = TRUE)
    fpv <- sum(as.numeric(sf::st_area(fp))) / 1e4
    ok("in_floodplain ha agrees with the vector floodplain area within 1%",
       abs(sum(comp$ha[fpc]) - fpv) / fpv < 0.01, sprintf("cells %.1f ha vs vector %.1f ha", sum(comp$ha[fpc]), fpv))

    # (2) each overlay's cell ha against the vector intersection, and (3) any-touch superset
    dst <- fp_disturbance_validate(yaml::read_yaml(here::here("config", "disturbance.yml")))
    conn <- DBI::dbConnect(RPostgres::Postgres())
    for (s in dst$context) {
      col <- paste0("in_", s$name)
      ok(sprintf("%s is a column of the table", col), col %in% in_cols)
      if (!col %in% in_cols) next
      p <- sf::st_transform(.dst_fetch(conn, s, fp, yrs), sf::st_crs(fp))
      v <- if (nrow(p)) sum(as.numeric(sf::st_area(sf::st_intersection(sf::st_union(fp), sf::st_union(p))))) / 1e4 else 0
      cc <- sum(comp$ha[fpc & comp[[col]]])
      # On in_floodplain cells, not the footprint: the footprint's touches=TRUE ring sits outside the
      # polygon, and land abutting the floodplain is exactly where ALR fields are (NECR: 17,809 ha on
      # the footprint vs 16,894.7 ha vector). Cell-centre against a vector area differs by half a
      # cell along every edge, so 2% is generous; measured 0.05% for NECR's ALR.
      ok(sprintf("%s: in_floodplain cell ha agrees with the vector floodplain intersection within 2%% (or both ~0)", s$name),
         (v < 1 && cc < 1) || abs(cc - v) / max(v, 1e-9) < 0.02,
         sprintf("cells %.1f ha vs vector %.1f ha", cc, v))
      ok(sprintf("%s: change inside <= change, inside <= floodplain", s$name),
         sum(comp$ha[chg & comp[[col]]]) <= c_ha && cc <= sum(comp$ha[fpc]))
      if (col %in% names(tr)) {
        need <- sum(comp$cells[chg & comp[[col]]]) > 0
        ok(sprintf("%s on the patches is consistent with the table (change cells inside => some patch tagged)", col),
           !need || any(tr[[col]] %in% TRUE),
           sprintf("%d change cells inside; %d patches tagged", as.integer(sum(comp$cells[chg & comp[[col]]])),
                   sum(tr[[col]] %in% TRUE)))
      } else {
        message(sprintf("  INFO  %s not on %s yet (forward-only; fire_tag.R adds it)", col, tlyr))
      }
    }
    DBI::dbDisconnect(conn)

    # (4) provenance, re-derived
    prov <- jsonlite::fromJSON(file.path(dir, "provenance.json"), simplifyVector = FALSE)
    lc <- prov$landcover[[scen]]; cp <- lc$composition
    ok("provenance landcover[scenario].composition is recorded", !is.null(cp))
    if (!is.null(cp)) {
      ok("recorded table digest re-derives from the written table",
         identical(cp$outputs$table_content_sha256, fp_composition_digest(comp)))
      ok("recorded layer name and row count match", identical(cp$outputs$layer, lyr) &&
           identical(as.integer(cp$outputs$rows), nrow(comp)))
      ok("the composition was computed from the classified rasters step 3 recorded",
         identical(unlist(cp$inputs$classified_content_sha256),
                   unlist(lc$inputs$classified_content_sha256[as.character(yrs)])))
      ok("...and from the transition step 3 recorded",
         identical(cp$inputs$transition_content_sha256, lc$outputs$transition_content_sha256))
      # Not re-derived from the parsed JSON: a round trip changes types (I() arrays, NA -> null), and
      # provenance-check.R never re-derives a recorded hash from disk for the same reason.
      ok("inputs_hash / outputs_hash recorded and well-formed",
         all(grepl("^sha256:[0-9a-f]{64}$", c(cp$inputs_hash %||% "", cp$outputs_hash %||% ""))))
    }

    # (5) an independent reference where one exists: the accuracy module's FWA-wetland composition
    # (reference_composition-wetland.R: terra::freq over a mask, same fetch, same centre rule) counts
    # wetland cells over the WHOLE footprint, so it must equal the table's footprint in_wetland exactly.
    wref <- file.path(dir, "accuracy", "wetland_composition.csv")
    if (file.exists(wref) && "in_wetland" %in% in_cols && identical(scen, acfg$primary_scenario %||% scen)) {
      w <- utils::read.csv(wref)
      w <- sum(w$ha[w$zone == "fwa_wetland" & w$year == yrs[1]])
      cw <- sum(comp$ha[comp$in_wetland & !is.na(comp$from_code)])
      ok("footprint in_wetland matches the accuracy module's FWA-wetland count (to 0.1 ha)",
         abs(cw - w) < 0.1, sprintf("%.2f vs %.2f ha", cw, w))
    }

    # the #108 numbers, derived here and stated nowhere in prose (#77)
    sm <- fp_composition_summary(comp)
    message("  INFO  ", paste(sprintf("%s=%s", names(sm),
                                       ifelse(grepl("share", names(sm)), sprintf("%.3f", unlist(sm)),
                                              sprintf("%.1f", unlist(sm)))), collapse = "; "))
  }
}

message(if (fails == 0) "\nALL PASS" else sprintf("\n%d FAIL", fails))
quit(status = if (fails == 0) 0L else 1L)
