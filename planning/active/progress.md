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
