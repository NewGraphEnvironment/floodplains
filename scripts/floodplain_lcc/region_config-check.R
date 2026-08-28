# region_config-check.R — assert run_region.R cannot destroy hand-maintained area config (#44).
#
# run_region.R used to regenerate area.yml and flood_scenarios.csv wholesale on every invocation and
# delete break_points.csv, silently losing the second species' scenario rows (undoing #23), every
# citation, and the break points — under DRY=1 as well as a real run. The destroyed columns are
# documentation-only (step 2 reads none of citations/ecological_process/min_order/anchor_order), so
# nothing failed and no error was raised; `git status` was the only signal. A guard is the only thing
# that turns that back into a loud failure.
#
# Runs against a TEMP COPY of the real configs, so the check itself can never damage what it guards.
# No database: fp_region_plan is pure, which is the whole point of factoring it out of the runner.
#
# usage: Rscript scripts/floodplain_lcc/region_config-check.R

suppressMessages({library(yaml); library(readr); library(fs)})
source(here::here("scripts", "floodplain_lcc", "fp_region.R"))

fails <- 0L
ok <- function(label, cond, detail = "") {
  if (isTRUE(cond)) {
    message("  PASS  ", label, if (nzchar(detail)) paste0("  (", detail, ")") else "")
  } else {
    fails <<- fails + 1L
    message("  FAIL  ", label, if (nzchar(detail)) paste0("  (", detail, ")") else "")
  }
}

# Same shape as run_region.R's generator; duplicated deliberately so the check exercises the plan
# rules rather than importing the runner (which opens a Postgres connection at load).
base_scenarios <- function(sp, min_order = 3) data.frame(
  scenario_id = paste0(sp, c("_ff01","_ff02","_ff04","_ff06","_ff08","_ff12")),
  species = sp, min_order = min_order, anchor_order = 1,
  flood_factor = c(1, 2, 4, 6, 8, 12),
  slope_threshold = 9, max_width = 2000, cost_threshold = 2500,
  size_threshold = 5000, hole_threshold = 2500,
  lakes = TRUE, wetlands = TRUE, wetland_filter = "network",
  run = c(FALSE, TRUE, TRUE, TRUE, FALSE, FALSE),
  description = "", ecological_process = "", citations = "", stringsAsFactors = FALSE)

owned_for <- function(w, sp, extra = list()) {
  c(list(name = tolower(w), watershed_group = w, species = sp, min_order = 3,
         schema = tolower(w), primary_scenario = paste0(sp, "_ff04")), extra)
}

scratch <- fs::path(tempdir(), "region_config_check")
fs::dir_create(scratch)
on.exit(fs::dir_delete(scratch), add = TRUE)
copy_cfg <- function(area) {
  d <- fs::path(scratch, area)
  if (fs::dir_exists(d)) fs::dir_delete(d)
  fs::dir_copy(here::here("config", area), d)
  d
}

# ---------------------------------------------------------------------------------------------
message("\n#44 acceptance: a region run preserves hand-maintained area config")
# ---------------------------------------------------------------------------------------------

# MORR is the worst case: two species, 12 citations, and a break_points.csv that decides which
# sub-basin branch step 2 takes. skeena.yml resolves it to coho with attribute_by = gnis_name.
d <- copy_cfg("morr")
before_csv <- readr::read_csv(fs::path(d, "flood_scenarios.csv"), show_col_types = FALSE)
# Compare the FILE, not two read_csv results: tibbles carry `spec`/`problems` attributes that differ
# between reads of the same bytes, so identical() on them tests the reader, not the file.
before_md5 <- unname(tools::md5sum(fs::path(d, "flood_scenarios.csv")))
before_bp  <- readLines(fs::path(d, "break_points.csv"), warn = FALSE)
p <- fp_region_plan(d, owned_for("MORR", "co", list(attribute_by = "gnis_name")), base_scenarios("co"))
fp_region_write(p)
after_csv <- readr::read_csv(fs::path(d, "flood_scenarios.csv"), show_col_types = FALSE)

ok("MORR keeps both species' scenario rows",
   identical(sort(unique(after_csv$species)), c("ch", "co")),
   paste(sort(unique(after_csv$species)), collapse = "+"))
ok("MORR keeps all 6 ch_* rows", sum(grepl("^ch_", after_csv$scenario_id)) == 6L,
   paste(sum(grepl("^ch_", after_csv$scenario_id)), "rows"))
ok("MORR keeps every citation",
   sum(nzchar(trimws(after_csv$citations))) == sum(nzchar(trimws(before_csv$citations))),
   paste(sum(nzchar(trimws(after_csv$citations))), "of",
         sum(nzchar(trimws(before_csv$citations)))))
ok("MORR flood_scenarios.csv is byte-identical",
   identical(before_md5, unname(tools::md5sum(fs::path(d, "flood_scenarios.csv")))))
ok("MORR break_points.csv survives",
   fs::file_exists(fs::path(d, "break_points.csv")) &&
     identical(before_bp, readLines(fs::path(d, "break_points.csv"), warn = FALSE)))
ok("the region's own keys are applied",
   identical(yaml::read_yaml(fs::path(d, "area.yml"))$attribute_by, "gnis_name"))

# BULK: single species, 6 citations. Nothing about it should change at all.
d <- copy_cfg("bulk")
before <- readLines(fs::path(d, "flood_scenarios.csv"), warn = FALSE)
before_yml <- readLines(fs::path(d, "area.yml"), warn = FALSE)
p <- fp_region_plan(d, owned_for("BULK", "co", list(attribute_by = "gnis_name")), base_scenarios("co"))
fp_region_write(p)
ok("BULK flood_scenarios.csv is byte-identical",
   identical(before, readLines(fs::path(d, "flood_scenarios.csv"), warn = FALSE)))

# ---------------------------------------------------------------------------------------------
message("\nOwnership rule: the region owns its keys, the area owns the rest")
# ---------------------------------------------------------------------------------------------

# Area-owned keys must survive. tile_size/subset are exactly the kind of hand-set value the old
# wholesale rewrite discarded without a word.
d <- copy_cfg("bulk")
y <- yaml::read_yaml(fs::path(d, "area.yml")); y$tile_size <- 20000; y$subset <- "reach"
yaml::write_yaml(y, fs::path(d, "area.yml"))
p <- fp_region_plan(d, owned_for("BULK", "co"), base_scenarios("co"))
fp_region_write(p)
after <- yaml::read_yaml(fs::path(d, "area.yml"))
ok("area-owned keys survive a region run",
   identical(after$tile_size, 20000L) || identical(after$tile_size, 20000),
   "tile_size")
ok("area-owned subset survives", identical(after$subset, "reach"))

# THE REGRESSION THAT MATTERS. A naive merge (modifyList) preserves too much: dropping
# network_source from the region file would leave it stale in area.yml and the group would keep
# GRABbing when it was meant to BUILD -- a new silent divergence introduced by the fix.
d <- copy_cfg("bulk")
y <- yaml::read_yaml(fs::path(d, "area.yml")); y$network_source <- "fresh_default"
yaml::write_yaml(y, fs::path(d, "area.yml"))
p <- fp_region_plan(d, owned_for("BULK", "co"), base_scenarios("co"))   # region no longer sets it
fp_region_write(p)
ok("a dropped region-owned key is CLEARED, not left stale",
   is.null(yaml::read_yaml(fs::path(d, "area.yml"))$network_source), "network_source")

# ---------------------------------------------------------------------------------------------
message("\nComments and file shape survive an area.yml update")
# ---------------------------------------------------------------------------------------------

# yaml::write_yaml round-trips the DATA and discards every comment. Losing 8 lines of rationale from
# config/bulk/area.yml to a region run is the same class of silent damage as #44 itself, so the
# writer edits only the lines it owns.
d <- copy_cfg("bulk")
before_lines <- readLines(fs::path(d, "area.yml"), warn = FALSE)
n_comments   <- sum(grepl("^\\s*#", before_lines))
p <- fp_region_plan(d, owned_for("BULK", "co", list(attribute_by = "gnis_name")), base_scenarios("co"))
fp_region_write(p)
after_lines <- readLines(fs::path(d, "area.yml"), warn = FALSE)
ok("comment lines survive an update",
   sum(grepl("^\\s*#", after_lines)) == n_comments, paste(n_comments, "comments"))
ok("the added region-owned key is present",
   identical(yaml::read_yaml(fs::path(d, "area.yml"))$attribute_by, "gnis_name"))
ok("only added lines changed; nothing else was re-emitted",
   all(before_lines %in% after_lines), paste(length(after_lines) - length(before_lines), "line(s) added"))

# A changed value is edited in place, and its trailing comment stays with it.
d <- copy_cfg("bulk")
p <- fp_region_plan(d, owned_for("BULK", "bt"), base_scenarios("bt"))   # species co -> bt
fp_region_write(p)
after <- readLines(fs::path(d, "area.yml"), warn = FALSE)
ok("changed value edited in place", any(grepl("^species: bt", after)))
ok("its trailing comment is kept",
   any(grepl("^species: bt\\s+# coho runs the whole Bulkley", after)))
ok("no duplicate species key", sum(grepl("^species:", after)) == 1L)

# An area-owned block (MORR's publish targets) must come through untouched.
d <- copy_cfg("morr")
p <- fp_region_plan(d, owned_for("MORR", "co", list(attribute_by = "gnis_name")), base_scenarios("co"))
fp_region_write(p)
tg <- yaml::read_yaml(fs::path(d, "area.yml"))$targets
ok("area-owned targets block survives", length(tg) == 2L &&
     identical(tg[[2]]$scenario, "ch_ff06"))
ok("a new scalar key did not land inside the block",
   identical(yaml::read_yaml(fs::path(d, "area.yml"))$attribute_by, "gnis_name"))

# ---------------------------------------------------------------------------------------------
message("\nCold path: the create path every new group takes")
# ---------------------------------------------------------------------------------------------

# Testing only the merge path would exercise none of this -- and every new group runs it.
d <- fs::path(scratch, "newgroup")
p <- fp_region_plan(d, owned_for("XXXX", "bt"), base_scenarios("bt"))
ok("plan reports create for an absent config dir", p$area_mode == "create" && p$scenarios_mode == "create")
fp_region_write(p)
ok("area.yml created", fs::file_exists(fs::path(d, "area.yml")))
new_csv <- readr::read_csv(fs::path(d, "flood_scenarios.csv"), show_col_types = FALSE)
ok("flood_scenarios.csv created with 6 rows", nrow(new_csv) == 6L)
ok("no break_points.csv invented", !fs::file_exists(fs::path(d, "break_points.csv")))

# ---------------------------------------------------------------------------------------------
message("\nAppend path: a region whose species has no rows yet")
# ---------------------------------------------------------------------------------------------

d <- copy_cfg("bulk")   # coho only
p <- fp_region_plan(d, owned_for("BULK", "bt"), base_scenarios("bt"))
ok("plan reports append, not rewrite", p$scenarios_mode == "append", p$scenarios_action)
fp_region_write(p)
after <- readr::read_csv(fs::path(d, "flood_scenarios.csv"), show_col_types = FALSE)
ok("both species present after append",
   identical(sort(unique(after$species)), c("bt", "co")))
ok("the original coho citations survived the append",
   sum(nzchar(trimws(after$citations[after$species == "co"]))) == 6L)

# ---------------------------------------------------------------------------------------------
message("\nIdempotence: a second run is a no-op")
# ---------------------------------------------------------------------------------------------

d <- copy_cfg("morr")
owned <- owned_for("MORR", "co", list(attribute_by = "gnis_name"))
fp_region_write(fp_region_plan(d, owned, base_scenarios("co")))
snap <- vapply(fs::dir_ls(d), function(f) unname(tools::md5sum(f)), character(1))
p2 <- fp_region_plan(d, owned, base_scenarios("co"))
ok("second plan reports no change", !isTRUE(p2$changed),
   paste(p2$area_action, "/", p2$scenarios_action))
fp_region_write(p2)
ok("second write leaves every file byte-identical",
   identical(snap, vapply(fs::dir_ls(d), function(f) unname(tools::md5sum(f)), character(1))))

message("")
if (fails > 0L) {
  stop(fails, " check(s) FAILED — run_region.R can still lose hand-maintained config (#44).",
       call. = FALSE)
}
message("PASS: all region config checks green.")
