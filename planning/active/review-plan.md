# Plan review (Plan agent, spawned 2026-10-14T12:31:49Z) — findings and disposition

| id | finding | disposition |
|---|---|---|
| B1 | stac stages from the floodplains WORKING TREE (`01_stage.R:27-28`); `fp_prov_read()` stops on any provenance key not `^[a-z]{2}_ff[0-9]{2}$` (`fp_provenance.R:251-259`), so all_* keys in a rostered group abort staging | Verified. The freeze is set by the run writing all_* keys into data/<wsg>/provenance.json (data/ is not in git), and was implied by #125's order (stac#75 is its publish step). Kept DUNC in columbia.yml (user decision); documented in PR, comments on stac#75/#76 |
| O1 | b4414eb converts area.yml without the all rows (broken intermediate) | Accepted as history; the run's reconciled csvs land in the next commit |
| O2 | run MORR before BULK | Moot: BULK's DEM fetched in 35.8 s (NRCan fast on 10-14) |
| O3 | fixtures frozen before config edits | Verified clean by the reviewer |
| G1 | config/dunc/area.yml contradicts itself on network_source | Fixed |
| G2 | cache ignores region-owned key changes (DUNC fresh -> fresh_default) | Fixed: a plan that sets/removes a region-owned key invalidates the cache |
| G3 | stale-grid check also applies in species mode | Intended (a pre-pin grid is stale whatever the mode); plan text corrected |
| G4 | no peak-RSS capture | RSS sampler (sum of R processes, 30 s) wraps the run |
| G5 | publish hint points at a release that cannot work until stac#75 | Noted in run log + PR |
| G6 | appended all rows carry empty citations | Fixed: fp_region_plan carries the existing rows' citations at the same flood factor when they agree; check arm + mutation M8 |
| G7 | fp_readme_roster tests the mode itself | Fixed: calls fp_region_mode() |
| A1 | BULK memory (64 GB host, annual LULC) | Watched via the RSS sampler |
| A2 | whole min_order not floored | Fixed: fp_region_mode refuses < 2; arm + mutation M9 |
| AC1 | no arm isolates fp_region_plan's validate call | Already fixed before the review landed (hand-built list); gnis_name arm added; M5 red |
| AC2 | live DRY exercises no area.yml conversion | Accepted: hand conversion was chosen to fix comments; the fixture arm covers fp_area_yml_edit's conversion |
| AC3 | provenance-check baseline before the run | MORR + KISP PASS pre-run (from a worktree at 4995867); BULK's run had already started |
| AC4 | bridge-check, disturbance-check, habitat_link, coverage CSV status | Added to the post-run checks |
| S1 | pointers on #59/#73 | Added to Phase 6 |
| S2 | stac stage_years-check.R hardcodes ufra/ch_ff04 | Noted for the Fraser step on #125 |
