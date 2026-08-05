# Progress — Item key in published gpkg layers (#30)

## Session 2026-08-05

- Plan-mode exploration — phases approved by user
- Scope widened during planning (user decision): `floodplain.gpkg` included alongside
  `floodplain_landcover.gpkg` — it's also a published asset and its layer names are identical across
  all 16 areas, making it the worse merge case.
- Key widened from `wsg` to the **full item key** (`wsg`, `species`, `scenario`) so a merged gpkg can
  separate MORR-coho from MORR-chinook; keeps STAC properties and gpkg columns symmetric.
- KISP (Kispiox) chinook adopted as the Phase-3 end-to-end test of a brand-new area; verified chinook
  is modelled there (4,458 access_ch segments at order ≥ 3).
- Created branch `30-write-watershed-group-identifier-wsg-int` off main
- Scaffolded PWF baseline from issue #30 with approved phases
- Next: Phase 1 (write the item key at generation time in 02 + 03)
