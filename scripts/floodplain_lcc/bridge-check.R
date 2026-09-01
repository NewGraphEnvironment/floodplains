# bridge-check.R — assert the patch<->watercourse bridge reconciles (#54).
#
# The bridge exists because the floodplain is exploded two incompatible ways: change patches are
# DISJOINT, per-watercourse attribution rows deliberately OVERLAP (#40). That overlap is exactly what
# makes a naive join wrong, and it is subtle enough that the first version of this feature shipped a
# spec error -- `overlap_frac` was documented as the apportionment weight, but because the rows
# overlap it sums to ~2.3 per patch and overstated the basin total by 83%. These checks are what
# caught it, so they are worth keeping rather than trusting the columns to stay correct.
#
# No database. Reads only what a consumer would read.
#
# usage: Rscript scripts/floodplain_lcc/bridge-check.R [area] [scenario]
#        defaults: morr co_ff04

suppressMessages({library(sf)})
sf::sf_use_s2(FALSE)

a        <- commandArgs(TRUE)
area     <- if (!is.na(a[1])) a[1] else "morr"
scenario <- if (!is.na(a[2])) a[2] else "co_ff04"

lc <- here::here("data", area, "floodplain_landcover.gpkg")
if (!file.exists(lc)) stop("no floodplain_landcover.gpkg for '", area, "'", call. = FALSE)
lyrs  <- sf::st_layers(lc)$name
t_lyr <- grep(paste0("^transition_", scenario, "_[0-9]{4}_[0-9]{4}$"), lyrs, value = TRUE)
b_lyr <- sub("^transition_", "patch_watercourse_", t_lyr)
if (!length(t_lyr))       stop("no transition layer for ", area, "/", scenario, call. = FALSE)
if (!b_lyr %in% lyrs)     stop("no bridge layer ", b_lyr, " -- run step 3 with attribute_by set",
                               call. = FALSE)

tp <- sf::st_read(lc, layer = t_lyr, quiet = TRUE)
br <- sf::st_read(lc, layer = b_lyr, quiet = TRUE)
key <- setdiff(names(br), c("patch_id","name_basin","overlap_ha","overlap_frac","apportion_weight",
                            "wsg","species","scenario"))
# patch_id is per-sub-basin. Join on the PAIR or a multi-sub-basin area silently mis-reconciles:
# match() takes the first row sharing an id, so a patch in basin A is credited basin B's area.
# Older bridges predate the name_basin column; fall back so the check still runs against them.
# Decide the scheme ONCE, from the bridge (the older artifact), and apply it to both sides. Deciding
# per object is the bug it looks like a fix for: the transition layer always carries name_basin while
# a pre-fix bridge does not, so the two sides key differently and match nothing.
use_basin <- "name_basin" %in% names(br)
pk_of <- function(x) if (use_basin)
  paste(x$name_basin, x$patch_id, sep = "\u00a6") else as.character(x$patch_id)
tp_pk <- NULL; br_pk <- NULL
message("Area: ", area, " | ", t_lyr, " (", nrow(tp), " patches) | ", b_lyr, " (", nrow(br),
        " pairs, key = ", key, ")")

fails <- 0L
ok <- function(label, cond, detail = "") {
  if (isTRUE(cond)) message("  PASS  ", label, if (nzchar(detail)) paste0("  (", detail, ")") else "")
  else { fails <<- fails + 1L
         message("  FAIL  ", label, if (nzchar(detail)) paste0("  (", detail, ")") else "") }
}

# --- the invariant that makes apportionment meaningful ---
tp_pk <- pk_of(tp); br_pk <- pk_of(br)
w <- tapply(br$apportion_weight, br_pk, sum)
ok("apportion_weight sums to 1 per patch", max(abs(w - 1)) < 0.01,
   sprintf("max deviation %.4f", max(abs(w - 1))))

# --- reconciliation: the check that caught the original spec error ---
tl     <- tp[tp$from_class == "Trees" & tp$to_class != "Trees", ]
tl_pk  <- pk_of(tl)
keep   <- br_pk %in% tl_pk
bl     <- br[keep, ]; bl_pk <- br_pk[keep]
bl$loss <- tl$area_ha[match(bl_pk, tl_pk)]
tot <- sum(tl$area_ha); ap <- sum(bl$loss * bl$apportion_weight)
ok("apportioned tree loss reconciles to the ungrouped total",
   abs(ap - tot) / tot < 0.005, sprintf("%.2f vs %.2f ha (%.3f%%)", ap, tot, 100*(ap-tot)/tot))

# overlap_frac must NOT be usable as a weight -- if it ever sums to 1 the two columns have been
# conflated somewhere upstream and the distinction this table exists to make has been lost.
f <- mean(tapply(br$overlap_frac, br_pk, sum))
ok("overlap_frac is distinct from apportion_weight (sums > 1, as the rows overlap)", f > 1.05,
   sprintf("mean per-patch sum %.3f", f))

# --- union coverage: how much of a patch any watercourse reaches ---
u <- tapply(br$overlap_frac, br_pk, max)
ok("union coverage >= 0.90 mean", mean(u) >= 0.90, sprintf("%.4f", mean(u)))
unbridged <- sum(!tp_pk %in% br_pk)
ok("few patches reach no watercourse at all", unbridged / nrow(tp) < 0.01,
   paste(unbridged, "of", nrow(tp)))

# --- ordering of the three semantics, on the largest watercourse ---
big <- names(sort(tapply(br$overlap_ha, br[[key]], sum), decreasing = TRUE))[1]
sel <- bl[[key]] == big
inc <- sum(bl$loss[sel]); apw <- sum(bl$loss[sel] * bl$apportion_weight[sel])
exc <- sum(bl$loss[sel & bl$overlap_frac >= 1 & bl$apportion_weight >= 1])
ok("inclusive >= apportioned >= exclusive", inc >= apw && apw >= exc,
   sprintf("%s: %.1f >= %.1f >= %.1f ha", big, inc, apw, exc))

# --- no geometry was duplicated to build it ---
ok("bridge is non-spatial (patches not duplicated)",
   !"geom" %in% names(br) && is.null(attr(br, "sf_column")),
   paste(nrow(tp), "patches unchanged"))

message("")
if (fails > 0L) stop(fails, " bridge check(s) FAILED for ", area, "/", scenario, call. = FALSE)
message("PASS: bridge reconciles for ", area, "/", scenario, ".")
