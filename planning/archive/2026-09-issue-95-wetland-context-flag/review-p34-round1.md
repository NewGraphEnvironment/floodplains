## Findings

- **[severity: bug]** scripts/floodplain_lcc/fire_tag.R:57 (`tr <- sf::st_read(gpkg, layer = tlyr, quiet = TRUE)`) — the re-tag DOES rewrite the published geometry, contrary to the header ("The geometry is never rewritten") and the comment at :59-64. `sf::st_read()` defaults to `promote_to_multi = TRUE`, and step 3 writes the transition layer as a mixed POLYGON/MULTIPOLYGON layer declared `GEOMETRY`. So `tr` arrives as all-MULTIPOLYGON, and `st_geometry(tagged) <- st_geometry(tr)` then writes every POLYGON back as a MULTIPOLYGON and re-declares the layer. Measured against the pre-re-tag copies in the scratchpad (`backup_{necr,bulk}_floodplain_landcover.gpkg`):
  - NECR: 3,947 POLYGON + 1,745 MULTIPOLYGON, declared GEOMETRY → now 5,692 MULTIPOLYGON, declared MULTIPOLYGON.
  - BULK: 5,024 POLYGON + 2,137 MULTIPOLYGON, declared GEOMETRY → now 7,161 MULTIPOLYGON, declared MULTIPOLYGON.
  - Areas that have not been re-tagged (KOTL, MORR) are still mixed and declared GEOMETRY, so the published areas now disagree on geometry type, and 8,971 published geometries changed their WKB.

  Fix: `st_read(..., promote_to_multi = FALSE)`. Probed on a copy of the NECR backup: it reads `sfc_GEOMETRY` (3947/1745), a write/read round trip keeps 3947/1745 with declared type `GEOMETRY`, and the WKB is identical.

  **Written data outlives the fix.** `data/necr` and `data/bulk` already hold the promoted layers (mtime Sep 28 23:23). Re-running the fixed script over them would read them *unpromoted*, find they are already MULTIPOLYGON, and write them back unchanged. They have to be restored from the pre-re-tag geometry and then re-tagged. The only pre-promotion copies I found are the two `backup_*.gpkg` files in this session's scratchpad, which is ephemeral.

- **[severity: bug]** scripts/floodplain_lcc/disturbance-check.R:222 (`read_layer`, `x <- sf::st_read(gpkg, lyr, quiet = TRUE)`) — the WKB guard cannot catch the defect above, because it reads its own output. Both the snapshot and the post-re-tag read go through the same default `promote_to_multi = TRUE`, so both sides are all-MULTIPOLYGON. Probed: WKB from a default read of the original is `identical()` to WKB from a default read of the promoted layer (TRUE). That is why "geometry is byte-identical to the snapshot (WKB)" passed live on NECR and BULK while every POLYGON had been rewritten. Use `promote_to_multi = FALSE` here too. Add an arm that must go red: a snapshot with mixed types compared against a promoted layer, or a check of `gpkg_geometry_columns.geometry_type_name` and the per-type counts. The live-pass evidence recorded for this phase (findings.md) should be corrected.

Checked and found OK (lens: name lookups and keys):
- `(name_basin, patch_id)` is unique on the live NECR and BULK layers (5692/5692, 7161/7161). The tagger keeps row order and row count, so the geometry reattach by position is sound.
- Field schema is unchanged by the re-tag apart from the added `in_wetland` and `waterbody_poly_id`. `patch_id` stays Integer and `in_*` stays Integer(Boolean).
- `append = TRUE, delete_layer = TRUE` replaces the layer rather than appending rows (probed: row count 5692 after the rewrite).
- `fp_same_values`: a NULL (absent) column fails on length, so it is reported as moved, the safe direction. Keys are exact-matched with `[[`. `$` on the config lists hits exact keys only.
