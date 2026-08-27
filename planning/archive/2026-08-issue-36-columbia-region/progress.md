# Progress — Add a columbia region (KOTL/LARL/SLOC) (#36)

## Session 2026-08-27

- Plan-mode exploration; phases approved by user (bt only; scope runs through publish)
- Verified species resolution, disturbance coverage, and the publish path against the live DB
  before writing any config — see `findings.md`
- Mid-plan discovery: `fresh_default` gained KOTL/LARL/SLOC during exploration, turning the run
  from a BUILD into a GRAB and surfacing the freshness-guard calibration finding
- Created branch `36-add-a-columbia-region-kotl-larl-sloc-bul` off main
- Next: Phase 1 — `network_source`/`network_guard` pass-through, then `columbia.yml`
- Phase 1 done: `run_region.R` carries `network_source`/`network_guard` from the region file into
  the generated `area.yml`; `config/regions/columbia.yml` written. DRY run resolves **bt** for
  KOTL/LARL/SLOC with zero SKIPs. Regression: a DRY `peace` run regenerates its `area.yml`s
  byte-identically (no git diff) and still skips PINE, so the pass-through is backward-compatible.
- Next: Phase 2 — run the region under `caffeinate -s`.
- Phases 2-4 done. 3/3 groups modelled and gated (0 error markers, outputs fresh); classified
  coverage 101-104% so the large-AOI scaling class did not recur on KOTL (936,950 ha).
  SLOC's 98.7% residual verified real (only 4.6 ha of in-window cutblock inside its floodplain).
  Published: 20 items live, collection extent 52.71 N -> 48.99 N. Acceptance test passes — a
  Nelson-area bbox search returns larl_bt_ff04 + kotl_bt_ff04 where it previously returned nothing.
- Filed #37 (GRAB guard tolerance mis-calibrated) and #38 (treed-area denominator) from findings.
- Docs: README group/item counts corrected (17 was conflating groups with items AND dropping BOWR
  and MCGR from the Fraser roster) -> 19 groups / 20 items / four regions.
- Next: Phase 5 close-out — archive, PR.
