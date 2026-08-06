# publish_hint.R — tell the operator how to publish what a run just produced (#32).
#
# floodplains does NOT call the publish layer. The coupling is one-way and stays that way:
# stac_floodplains_bc PULLS from $FLOODPLAINS_DATA, and this repo knows nothing about it beyond the
# message below. Shelling out to a sibling repo would point the dependency arrow both ways and break
# the layering (a driver shouldn't reach into the publish layer). So the "producer hook" is advisory:
# it prints the next command, the operator runs it.
#
# The stac side is TWO steps and the order matters: run_pipeline.sh rebuilds data/stac from this
# repo's outputs; catalogue_release.sh validates -> syncs -> registers -> verifies. Naming only the
# release would publish a stale build.

fp_publish_hint <- function(areas, steps = NULL) {
  if (nzchar(Sys.getenv("FP_NO_PUBLISH_HINT", ""))) return(invisible(NULL))
  # Only steps 2 and 3 write published assets (floodplain.gpkg / floodplain_landcover.gpkg +
  # rasters). A step-1-only run built a network and has nothing new to publish.
  if (!is.null(steps) && !any(c("2", "3") %in% as.character(steps))) return(invisible(NULL))

  bar <- strrep("-", 78)
  message("\n", bar)
  message("Publish ", paste(areas, collapse = ", "), " to the STAC catalogue:")
  message("  cd ../stac_floodplains_bc")
  message("  bash scripts/run_pipeline.sh        # rebuild data/stac from these outputs")
  message("  bash scripts/catalogue_release.sh   # validate -> sync -> register -> verify")
  message("Both are idempotent. Retract an item with scripts/item_unregister.sh.")
  message("Suppress this note with FP_NO_PUBLISH_HINT=1.")
  message(bar)
  invisible(NULL)
}
