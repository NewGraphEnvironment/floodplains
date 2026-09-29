# Review round 1 — staged diff for #95 (context overlays)

Scope: `git diff --cached` (config/disturbance.yml, 03_lulc_classify.R, fp_disturbance.R, run_area.R,
task_plan.md). The offline `disturbance-check.R` was run against the tree (working tree = staged code +
an unstaged findings.md edit only): **ALL PASS**. Nothing new in the diff itself is broken; the two
findings below are pre-existing mechanisms that this diff now routes wetlands through, and the first
one gets materially more likely to fire because wetlands hit far more patches than fire/harvest do.

## Findings

- **[severity: bug]** scripts/floodplain_lcc/fp_disturbance.R:~131-144 (`fp_disturbance_tag`, carry
  block: `group_by(patch_id)` ... `m <- match(patches$patch_id, dom$patch_id)`) — the carried
  attributes are joined back by `patch_id` alone, but step 3 hands this function a layer whose
  `patch_id` is **per-sub-basin** (03_lulc_classify.R:280 documents it: neexdzii has 2032 rows, 1973
  distinct ids — measured just now, 59 duplicated ids in the current layer). Two consequences, both
  silent: (a) `keep <- !is.na(m)` is computed over ALL patches, not just the intersecting `idx`, so a
  patch in basin B that touches no wetland receives the `waterbody_poly_id` of the same-numbered patch
  in basin A that does; (b) `group_by(patch_id)` + `slice_max` pools two different patches' overlaps,
  so a patch can be given the dominant feature of the *other* patch. Probe (two patches, `patch_id` 1
  in basins A and B, one wetland touching only A):
  ```
    patch_id name_basin in_wetland waterbody_poly_id
  1        1          A       TRUE                77
  2        1          B      FALSE                77
  ```
  `in_<name>` itself is correct (row-wise `st_intersects`); only the carried columns are wrong. The
  function's own header states the precondition ("an sf with a unique `patch_id`") and step 3 violates
  it for every multi-sub-basin area — neexdzii, the parity fixture. The current neexdzii layer shows
  0 mis-carried fire/harvest rows (few hits happened to coincide), so this has been latent; wetlands
  are the overlay most likely to expose it. `disturbance-check.R` cannot see it: its synthetic patches
  have unique ids and the live section compares against a snapshot produced by the same code. Fix is
  to key on `(name_basin, patch_id)` (the same `patch_key` the bridge block builds at
  03_lulc_classify.R:287) or on row position, and restrict `keep` to `idx`.

- **[severity: fragile]** scripts/floodplain_lcc/fp_disturbance.R:101-104 (`.dst_fetch`) + the
  `ST_Transform(ST_MakeEnvelope(...))` in `.dst_query` — pre-existing, moved not introduced. The AOI
  bbox is round-tripped 3005 -> 4326 -> 3005 through 4-vertex rectangles, so the server-side envelope
  does not contain the patches' own bbox (code-check-spatial: "reproject the polygon ... never
  transform the projected bbox corners"). Measured on a 200 x 150 km BC-Albers bbox: 14.7 km² of the
  AOI rim, up to ~74 m deep, falls outside the fetch envelope, so a source/context polygon lying only
  in that rim is never fetched and the edge patch reads `in_<name> = FALSE`. Small, but it now applies
  to wetlands too. Transforming the patches' bbox polygon (densified) or padding the envelope closes it.

No other issues found. Checked and cleared: validator ordering (fp_disturbance.R is sourced before
`fp_read_config()` runs, and `fp_read_config` has no other caller); empty/absent disturbance.yml
(`read_yaml` -> NULL -> validate returns NULL -> `cfg$disturbance` NULL, no crash); the empty-carry
case (`SELECT , geom` in the old builder is now fixed); `change_interval` is defaulted in
`fp_read_config` so `window` is never NULL; context query plan against live fwapg (seq scan, ~1.1 s
over 375,178 rows for a BULK-sized bbox — acceptable); `waterbody_poly_id` and `geom` exist in
`whse_basemapping.fwa_wetlands_poly` (SRID 3005); no downstream consumer (README figure,
stac_floodplains_bc) treats every `in_*` column as a cause — `fp_readme_sources()` reads `sources:` only.
