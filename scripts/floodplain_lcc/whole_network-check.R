# whole_network-check.R — assert whole-network mode (#104) offline: no database, no data/.
#
# `species: all` is a token that reaches SQL, so what it must never do is checked against the SQL
# itself: the whole-network read joins no access table and filters no access column; the species read
# is BYTE-IDENTICAL to what step 1 ran before the read was lifted into fp_network_sql() (so the lift
# moves no existing area's network); only the exact token takes the whole path; a species region refuses
# it in both directions while a `network: whole` region may convert a species area (#125); and the habitat table is keyed per watershed group and digests by content.
# Every predicate is also run against a mutated input it must reject.
#
# usage: Rscript scripts/floodplain_lcc/whole_network-check.R

suppressMessages({library(yaml); library(fs)})
source(here::here("scripts", "floodplain_lcc", "fp_region.R"))
source(here::here("scripts", "floodplain_lcc", "fp_provenance.R"))
source(here::here("scripts", "floodplain_lcc", "01_network_extract.R"))

n_fail <- 0L
check <- function(ok, what) {
  ok <- isTRUE(ok)
  if (!ok) n_fail <<- n_fail + 1L
  cat(if (ok) "  ok   " else "  FAIL ", what, "\n", sep = "")
}
errs <- function(expr) inherits(tryCatch(expr, error = function(e) e), "error")
sha  <- function(x) digest::digest(x, algo = "sha256", serialize = FALSE)
fmt  <- function(x) if (is.null(x)) "NULL" else paste(format(x), collapse = ",")

cat("the mode predicate\n")
check(fp_whole_network(list(species = "all")), "species 'all' is the whole network")
for (sp in list("co", "bt", "al", "ALL", "all ", c("all", "co"), NULL, NA_character_)) {
  check(!fp_whole_network(list(species = sp)),
        sprintf("species [%s] is NOT the whole network", fmt(sp)))
}

cat("\nwhat a whole-network area must also set\n")
wcfg <- list(name = "t", species = "all", attribute_by = "blue_line_key", network_source = "fresh")
check(!errs(fp_whole_network_validate(wcfg)), "attribute_by blue_line_key + network_source passes")
check(errs(fp_whole_network_validate(modifyList(wcfg, list(attribute_by = NULL)))),
      "must-fail: no attribute_by is refused (no keyed layer to join to)")
check(errs(fp_whole_network_validate(modifyList(wcfg, list(attribute_by = "gnis_name")))),
      "must-fail: attribute_by other than blue_line_key is refused")
check(errs(fp_whole_network_validate(modifyList(wcfg, list(network_source = NULL)))),
      "must-fail: a BUILD (no network_source) is refused")
check(!errs(fp_whole_network_validate(list(name = "t", species = "co"))),
      "a species area is not held to the whole-network rules")

cat("\nthe species read is unchanged by the lift\n")
# sha256 of the streams_sql step 1 built at commit 3e0b943 (before the lift) for these arguments,
# measured by evaluating that commit's sprintf block verbatim. A pinned literal, not a re-derivation:
# deriving it from the new function would compare the function with itself.
GOLDEN_SPECIES_SQL <- "b8a25cd66b56213206c139f4073b78fbda08afe6d64da5bfd0646e376058f9fd"
sp_sql <- fp_network_sql("fresh_default", "KOTL", "bt", 3)
check(identical(sha(sp_sql), GOLDEN_SPECIES_SQL), "species SQL is byte-identical to the pre-lift read")
check(!identical(sha(sub("IN (1, 2)", "IN (1,2)", sp_sql, fixed = TRUE)), GOLDEN_SPECIES_SQL),
      "must-fail: a one-character change to the species SQL moves the digest")

cat("\nthe whole read joins and filters no access\n")
no_access <- function(q) !grepl("access", q, fixed = TRUE) && grepl("stream_order >= 2", q, fixed = TRUE)
wh_sql <- fp_network_sql("fresh", "DUNC", "all", 2)
check(no_access(wh_sql), "whole SQL: no streams_access join, no access_ column, order >= 2")
check(grepl("watershed_group_code = 'DUNC'", wh_sql, fixed = TRUE), "whole SQL: scoped to the group")
check(!no_access(sp_sql), "must-fail: the predicate rejects the species SQL")
check(!no_access(sub("stream_order >= 2", "stream_order >= 3", wh_sql, fixed = TRUE)),
      "must-fail: the predicate rejects a whole SQL at another floor")
check(no_access(fp_bcfp_km_sql("all", 2, "DUNC")), "freshness reference: no access predicate in whole mode")
check(grepl("access_bt IN (1,2)", fp_bcfp_km_sql("bt", 3, "KOTL"), fixed = TRUE),
      "freshness reference: species mode keeps its access predicate")
for (sp in list("ALL", "a; DROP", c("bt", "co"), NA_character_, 3)) {
  check(errs(fp_network_sql("fresh", "DUNC", sp, 2)), sprintf("refuses species [%s]", fmt(sp)))
}

cat("\nregions: a species region refuses the whole network, a whole region takes it (#125)\n")
check(errs(fp_region_refuse_whole(c("bt", "all"), "test")), "a region species list naming 'all' is refused")
check(errs(fp_region_mode(list(species = c("bt", "all")))), "fp_region_mode refuses a species list naming 'all'")
check(!errs(fp_region_refuse_whole(c("bt", "wct"), "test")), "a species region is not refused")
base <- data.frame(scenario_id = "bt_ff04", species = "bt", run = TRUE)
base_all <- data.frame(scenario_id = "all_ff04", species = "all", run = TRUE)
scratch <- fs::path(tempdir(), "whole_network_check")
fs::dir_create(scratch)
owned <- function(sp) fp_region_owned(list(species = sp, min_order = 3L), "DUNC", sp)
whole_reg <- list(network = "whole", network_source = "fresh")
# Built by hand, not through fp_region_owned(): that refuses a whole region with no network_source
# itself, so the plan's own validation would never be reached and this arm would pass without it.
no_src <- list(name = "dunc", watershed_group = "DUNC", species = "all", min_order = 2L,
               schema = "dunc", primary_scenario = "all_ff04", attribute_by = "blue_line_key")
check(errs(fp_region_plan(scratch, no_src, base_all)),
      "fp_region_plan refuses an 'all' area with no network_source (step 1 would)")
check(!errs(fp_region_plan(scratch, c(no_src, list(network_source = "fresh")), base_all)),
      "must-fail control: the same owned list with a network_source plans")
check(!errs(fp_region_plan(scratch, fp_region_owned(whole_reg, "DUNC"), base_all)),
      "a whole region plans a new whole-network area")
yaml::write_yaml(list(name = "dunc", watershed_group = "DUNC", species = "all", min_order = 2L),
                 fs::path(scratch, "area.yml"))
check(errs(fp_region_plan(scratch, owned("bt"), base)),
      "fp_region_plan refuses to reconcile an existing whole-network area into a species item")
check(!errs(fp_region_plan(scratch, fp_region_owned(whole_reg, "DUNC"), base_all)),
      "a whole region reconciles an existing whole-network area")
yaml::write_yaml(list(name = "dunc", watershed_group = "DUNC", species = "bt", min_order = 3L),
                 fs::path(scratch, "area.yml"))
check(!errs(fp_region_plan(scratch, owned("bt"), base)),
      "must-fail control: the same species plan on a species area is not refused")
check(!errs(fp_region_plan(scratch, fp_region_owned(whole_reg, "DUNC"), base_all)),
      "a whole region converts a species area")
fs::dir_delete(scratch)

cat("\nthe habitat table\n")
hq <- fp_habitat_sql("fresh", "DUNC", "bt")
check(grepl("USING (id_segment, watershed_group_code)", hq, fixed = TRUE),
      "habitat join is keyed per group (id_segment is numbered per watershed group)")
check(!grepl("USING (id_segment)", hq, fixed = TRUE), "habitat join is not on id_segment alone")
check(!grepl("s.id_segment", hq, fixed = TRUE), "habitat table carries no id_segment")
check(grepl("streams_habitat_[a-z]{2,4}$", fp_habitat_tables_sql("fresh"), fixed = TRUE),
      "species tables are discovered by a pattern the long view does not match")
check(!grepl("^streams_habitat_[a-z]{2,4}$", "streams_habitat_long_vw"),
      "must-fail control: the discovery pattern rejects streams_habitat_long_vw")
for (bad in list(c("fresh; x", "DUNC", "bt"), c("fresh", "dunc", "bt"), c("fresh", "DUNC", "B"))) {
  check(errs(fp_habitat_sql(bad[1], bad[2], bad[3])),
        sprintf("habitat SQL refuses (%s)", paste(bad, collapse = ", ")))
}

hab <- data.frame(
  blue_line_key = c(1, 1, 2, 1, 2), downstream_route_measure = c(0, 500, 0, 0, 0),
  upstream_route_measure = c(500, 900, 300, 500, 300), stream_order = c(3, 3, 2, 3, 2),
  length_metre = c(500, 400, 300, 500, 300), species = c("bt", "bt", "bt", "wct", "wct"),
  accessible = c(TRUE, TRUE, FALSE, TRUE, TRUE), spawning = c(TRUE, FALSE, FALSE, FALSE, FALSE),
  rearing = c(TRUE, TRUE, FALSE, TRUE, NA), lake_rearing = FALSE, wetland_rearing = FALSE,
  stringsAsFactors = FALSE)
d0 <- fp_habitat_content_sha256(hab)
check(identical(d0, fp_habitat_content_sha256(hab[c(5, 3, 1, 4, 2), ])), "digest ignores row order")
h_int <- hab; for (k in FP_HABITAT_VAL) if (is.logical(h_int[[k]])) h_int[[k]] <- as.integer(h_int[[k]])
check(identical(d0, fp_habitat_content_sha256(h_int)),
      "digest is the same whether flags read back logical or integer (a gpkg round trip)")
flip <- hab; flip$spawning[2] <- TRUE
check(!identical(d0, fp_habitat_content_sha256(flip)), "must-fail: one flipped flag moves the digest")
swap <- hab; swap$species <- c("wct", "wct", "wct", "bt", "bt")
check(!identical(d0, fp_habitat_content_sha256(swap)),
      "must-fail: the same rows under other species codes move the digest")
na <- hab; na$rearing[5] <- FALSE
check(!identical(d0, fp_habitat_content_sha256(na)), "must-fail: NA and FALSE digest apart")

cat(if (n_fail) sprintf("\nFAIL: %d check(s)\n", n_fail) else "\nPASS\n")
quit(status = as.integer(n_fail > 0))
