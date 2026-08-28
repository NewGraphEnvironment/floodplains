# Progress — Attribute floodplains per watercourse/reach (#40)

## Session 2026-08-27

- Filed #40 off Morice fieldwork; `flooded` 0.4.0 then landed `fl_valley_attribute()` upstream
- Plan-mode exploration; phases approved (capability + Morice layer; primary_scenario only)
- Cleared flooded#41 by measurement before planning around it (0 exact-zero slope cells over
  Kootenay Lake) — it does not affect us or the Columbia outputs
- Created branch `40-delineate-and-attribute-floodplains-per-`
- Next: Phase 1 — install flooded 0.4.0 and measure on MORR
- Phase 1 done: measured on MORR; both prior cost hypotheses wrong (85% of cost is k-independent,
  blue_line_key affordable). Posted to flooded#44; posted the #41 exposure check.
- Phase 2 done: wired, and the regression passed in the strong form (co_ff04 byte-identical WITH
  attribution on; chinook layers untouched).
- Phase 3 done: morice_floodplain_sampling.gpkg delivered — 55.98 km2 Morice floodplain
  (24.92 exclusive / 31.07 shared), upstream terminus at route measure 91.75 km.
- Next: Phase 4 docs + PR.
