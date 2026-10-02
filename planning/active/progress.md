# Progress — Dated orthophotos and air photos as review themes, and prior-fire regrowth attribution (#103)

## Session 2026-10-01

- Plan-mode exploration — phases approved by user (plus four plan-gate answers, see task_plan.md)
- Created branch `103-dated-orthophotos-and-air-photos-as-revi` off main
- Scaffolded PWF baseline from issue #103 with approved phases
- Next: start Phase 0
- Phase 0: rewrote #103 body (private ortho name/endpoint removed; measurements + decisions recorded; retitled "prior-fire attribution")
- Phase 1: `fire_load-prior.sh` appended 21,186 pre-2017 fires; in-window md5 unchanged
- Plan review (Plan agent) landed → `planning/active/review-plan.md` with a disposition per finding
- Phase 2: `lookback:` list (validator, aliased carry, `.dst_window`, report line, run_area/03/fire_tag plumbing, live-check tag set) + 29 offline arms; mutation-tested six guards (one fixture fixed: it was refused by a collision before reaching the rule)
- Phase 2 /code-check: 3 rounds. R1 `lookback: Inf` → `BETWEEN NA` (fixed, arms); R2 live "tagged something" arm wrong for sparse lookbacks, 9/23 areas (INFO for lookback); R3 enumerated the mechanism (lookback concatenated into code written for sources/context) across 13 sites — no bug, one policy gap: published lookback columns could move silently on a re-tag → fire_tag.R now NOTEs it. Loop ended by R3's enumeration.
- Phase 3: NECR re-tagged (314 patches in_fire_prior; live check ALL PASS vs pre-load snapshot); stac_floodplains_bc#6 body gained a lookback section
- Phase 4: stratum 19 + redraw (453.4 ha; unaffected strata identical; byte-reproducible); accuracy_estimate lookback guard (mutation-tested)
- Phase 5: imagery.csv — ortho 2021 229/480 points, air photo 2012 digital 480/480 (themed); film epochs indexed only
- Phase 6: dated layers built (ortho warped VRT 0.15 m; air photo 4.43 m thumbnails; fly#88 filed, then withdrawn as MY caller error (subset without roll neighbours, warning suppressed) — fixed: 250/250 frames, 480/480 points); themes Review + per-layer; re-chip running
- Filed floodplains#104 (user request): serve whole floodplains with habitat tags on blue_line_key polygons
- User: a lookback follow-up issue to be filed "once we understand" — drafted in findings.md, NOT filed
- Phase 4-6 committed (5ea92e7) after 3 code-check rounds + closing URL-egress enumeration; ortho coverage corrected to 204 (pixel-read)
- Phase 7: research/landcover_accuracy.md "Dated reference imagery" section; CLAUDE.md lookback + imagery rules; README.Rmd one sentence on in_fire_prior, both targets re-rendered (determinism OK)
