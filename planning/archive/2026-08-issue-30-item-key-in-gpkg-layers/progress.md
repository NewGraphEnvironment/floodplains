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

- **Phases 1–4 complete.** Item key written at generation time (02+03); 16 areas backfilled (131
  layers, 0 failures, strict validation); KISP (Kispiox) chinook modelled from scratch and carries
  the keys **natively**; stac smoke test PASS.
- Two silent-wrong-value bugs caught by verification in the backfill parser: (1) year-strip ran
  before span-strip → `bt_ff04_2017`; (2) suffix enumeration missed `_patches`. Replaced
  suffix-stripping with **extraction** (`^[a-z]{2,4}_ff[0-9]+`) — one rule covers every suffix,
  present and future. Made the script idempotent **by value** so re-runs repair bad values.
- Self-inflicted 429: ran KISP and MORR concurrently, both hit the Planetary Computer STAC API.
  Wrapper still exited 0 — only the in-band error + mtime gate caught it. Serialized and retried.
- KISP headline: floodplain ch_ff04 246.7 km², tree loss 267.9 ha (fire 3.5, harvest 13.2);
  smoke test item `kisp_ch_ff04` valid.
- Next: `/planning-archive` + PR.
