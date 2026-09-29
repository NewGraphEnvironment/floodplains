# Plan review (Plan agent, read-only, returned as reply text; written here by the parent)

Findings, and what was done with each. The agent's evidence was probed before acting (see findings.md).

1. Gap (high), CONFIRMED: an empty match leaves carried columns logical, and GDAL writes Boolean. Live in tabr (`fire_year`) and thom (`harvest_start_year_calendar`). Fix: initialise carried columns from the fetched frame's typed column. Offline arm added.
2. Gap, CONFIRMED: carried values are joined on `patch_id`, which is unique only per sub-basin (neexdzii: 2032 rows, 1973 ids). Fix: join on a row index. Offline arm with a duplicate id across basins. Code-check round 1 found this independently.
3. Acceptance: the live check passes if the wetland fetch returns nothing. Fix: assert `sum(in_wetland) > 0` and `!is.na(carry) == in_<name>` per row.
4. Gap: the offline "residual unchanged" arm could not fail (it hands the report the sources itself). Fix: `fp_disturbance_report()` refuses an undated entry. Arm added.
5. fire_tag.R: loop over every transition layer (not `[1]`), take the window from the layer suffix, validate, report sources only, and compare-before-write (refuse to overwrite if cause columns would move, unless FORCE=1).
6. Carry guard: apply the core check at tag time too (fire_tag bypasses fp_read_config), and reserve `geom`/`geometry`. Suggestion (ii) (refuse carry ∩ names(patches) − owned) was not taken: carry ⊂ owned by definition, so that set is always empty.
7. Live check: the checker owns the snapshot format (a `snapshot` mode), compares geometry WKB, and iterates over layers.
8. Scope: `in_wetland` sits on CHANGED patches only (`changes_only = TRUE`), so #93's "stable land inside wetlands" and per-year composition need their own overlay. Recorded in #93.
9. Forward-only means "never" for cached region groups. Stated in CLAUDE.md and the stac#6 comment.
10. Docs: `scripts/floodplain_lcc/README.md` and `gpkg_prune-legacy.R:6` still describe the old fire_tag behaviour.
11. Provenance does not record disturbance.yml, and a fire_tag re-tag now changes a published layer without provenance. Filed as a follow-up issue rather than widening scope.
12. What the offline check cannot reach: covered by the live section.
13. Minor: the report with empty sources printed residual 0 (Reduce over an empty list); the validator's `nzchar()` on a length>1 field raised a plain error. Both fixed.
