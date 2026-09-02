# Progress — nge:landcover_key hashes the GeoTIFF container, not the landcover (#64)

## Session 2026-09-02

- Plan-mode exploration — phases approved by user
- Established #64's premise is wrong: `classified_sha256` is not published; `landcover_key` maps to
  `item_hash`. Scope adjusted — fix here, file the switch in the publish layer
- Root-caused the divergence below tag 42112 to double/NaN vs integer/NA from `readValues()`, and
  measured a working block-streaming content digest (1.16 s / 28.3M cells) that agrees across
  machines while still moving on a single changed cell
- Created branch `64-nge-landcover-key-hashes-the-geotiff-con` off main
- Scaffolded PWF baseline with approved phases
- Next: Phase 1 (correct the issue body), then the digest

## Session 2026-09-02 (cont.)

- Phase 1: #64's body corrected — the premise (`classified_sha256` is published) was wrong, and the
  root cause (tag 42112) was the symptom rather than the mechanism.
- Phase 2–4: `fp_raster_content_sha256()` replaces `fp_file_sha256()`; field renamed; guard §5c added.
  The declared-key drift check went red on the rename before anything else noticed — as designed.
- Phase 5: verified against m4's actual rasters — all three years agree where the file hash does not.
  Step 3 and step 2 both re-run clean; **the three floodplain `inputs_hash` values are byte-identical
  before and after**, proving the toolchain landed in `run` and not in the hashed half.
- Phase 6: filed stac_floodplains_bc#40 to point `nge:landcover_key` at the raster digest; CLAUDE.md
  corrected.
- Caught in my own guard: an `on.exit()` at a script's top level never fires, so the §5c fixture
  directory leaked. CLAUDE.md documents this exact trap. Replaced with an explicit `unlink()` plus an
  assertion that the cleanup happened.
