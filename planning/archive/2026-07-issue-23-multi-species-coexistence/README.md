## Outcome

Made per-area pipeline outputs coexist across species in the same `data/<area>/` gpkgs, so a second
species (MORR chinook) can be modelled alongside the first (MORR coho) without destroying it. Three
root causes were fixed: (1) hardcoded coho layer names (`streams_co3`) → species+order-keyed
(`streams_<sp><min_order>`, backward-compatible for coho-3) in 01 (write), 02 (read), and
`run_region.R:131`; (2) whole-gpkg `file.remove()` wipes each run in **all three** steps (01, 02, and
— caught by the Plan-agent review — 03, which the first design wrongly called "already safe") →
per-layer `append=file.exists + delete_layer=TRUE`; (3) step-2 scenario selection not filtered by
species → filter on `cfg$species`. Runtime species selection is via `FP_SPECIES` +
`FP_PRIMARY_SCENARIO` env overrides (chosen over a CLI arg because `run_region.R` invokes `run_area`
positionally and env propagates for free), with a guard that the resolved `primary_scenario` belongs
to the selected species. MORR gained `ch_ff01..12` scenario rows.

**Verified:** neexdzii coho parity reproduces exactly on a clean cold-path run (678.2 km / 171.0 km² /
943.13 ha). MORR chinook (`FP_SPECIES=ch FP_PRIMARY_SCENARIO=ch_ff06`) lands `streams_ch3` +
`ch_ff02/04/06` + `ch_ff06` land cover alongside the coho layers; coho outputs exactly preserved
(411.1 km² / 433.8 ha). Idempotent both directions. Fire attribution (the existing `fire_tag.R`
one-off, #19 prototype) applied to both MORR scenarios — ~6% of tree loss inside a 2017–2023 fire
perimeter, consistent with BULK; these upper-Skeena/Bulkley groups are conversion-driven, not
fire-driven. ch_ff06 (valley bottom): 432.4 km², 482.4 ha loss.

**Scope boundary (deliberate):** coexistence is at the data layer (steps 01/02/03 + driver). Zones
(04) and prioritization (05) remain coho-hardwired. Fire pipeline-wiring stays as separate #19 /
stac_floodplains_bc#6.

**Learned:** the adversarial Plan-agent review before baseline caught the 03 wipe blocker and the
`run_region.R` hardcoded read that the first design missed — both would have destroyed data or
silently failed chinook batch groups. Worth the ~5 min every time. The `append=file.exists +
delete_layer=TRUE` idiom is the safe cross-species coexistence pattern for sf character-dsn gpkg
writes (guard against both-flags only fires on the DBI branch).

Closed by: PR #24 (commits aa793a5 → ad79e00 on branch 23-support-multiple-species-per-area-coexis)
