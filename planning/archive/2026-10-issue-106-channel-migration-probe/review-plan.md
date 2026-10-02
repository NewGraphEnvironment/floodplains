# Plan review — #106 (Plan agent, 2026-10-02)

The reviewer read the committed rule (943c0ec), not the plan draft, and ran one read-only
population count: NECR unsieved Water-involving 509.7 ha / 8,228 patches (3,763 single-cell),
sieved 230.5 ha; BULK 696.1 / 390.4 ha; NECR total unsieved change 5,779 ha. It computed no
candidacy and applied no rule.

| # | kind | finding | disposition |
|---|---|---|---|
| 1 | Blocker | C counts Trees→Water / Water→Trees opposite-bank pairs, which is drift's misregistration signature; a 2-px rigid shift passes width and C | Rule v2 adds D: displacement-direction dispersion over paired patches (a rigid shift points one way). Exact-reverse share reported. Fixture: rigid 2-px shift must fail |
| 2 | Blocker | Meanders put opposite-role patches on the same side within 300 m, so the same-side null fills with real migration | Pairs must overlap in along-stream station (FWA `downstream_route_measure`). Fixture: alternating bends |
| 3 | Blocker | 2023 is the drought endpoint (landcover_accuracy.md); a cell exposed only in 2023 scores as a clean single switch | Persistence redefined: onset ≤ 2021 |
| 4 | Gap | single_switch fails succession (Water→Bare→Rangeland→Trees) and counts Snow/Ice/Clouds/NA years as switches | `sustained`: left the from-class once, never returned, onset ≤ 2021; codes 9/10 and NA treated as missing |
| 5 | Acceptance | B can pass from the width filter alone (non-candidates include all slivers) | B compares against width-matched non-candidates (`width_px` ≥ 1.5) |
| 6 | Gap | Patches of one transition value split a strip eroding through mixed classes | Patches built per ROLE (erosion/deposition/other) with `terra::patches()`; `dft_transition_artifact()` kept for the misregistration report on transition-level patches |
| 7 | Gap | MRR elongation understates crescents | Elongation = equivalent-rectangle L/W from area and a 1-cell-simplified perimeter (bend-invariant, staircase removed); MRR reported |
| 8 | Assumption | io_adjacent near tautological; OR with FWA loosens; lake drawdown strips | channel_adjacent = io_adjacent AND FWA ≤ 50 m AND not within 50 m of `fwa_lakes_poly` |
| 9 | Gap | FWA side unreliable at half-width ≈ offset; centroid; digitising direction; confluences | Opposite bank = FWA sides differ AND the line between the two patches crosses IO stable Water; digitising direction asserted against `downstream_route_measure` |
| 10 | Acceptance | Outcomes missing (sieved-only, NECR fails / BULK passes) | Full outcome table pre-registered |
| 11 | Acceptance | Anchor is a trivial lower bound; plan's version wrong | Two exact anchors: re-sieving at 1 ha reproduces `transition.tif` cell for cell; unsieved total change = Σ change + sieved strata area (5,779.45 ha) |
| 12 | Assumption | `dft_transition_artifact()` feasible on both sets | Confirmed; `io_adjacent` read from the classified endpoints for both sets |
| 13 | Scope | task_plan stale against the committed rule | Research file declared the single authority in task_plan |
| 14 | Acceptance | C has no margin | C needs opposite ≥ same + 10 points; a patch paired both ways counts in both |
| 15 | Gap | Fixtures miss the two real failure modes | Added: rigid shift, alternating bends |
