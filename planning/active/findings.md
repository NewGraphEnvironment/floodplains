# Findings — run_region.R destroys hand-maintained area config (#44)

## Measured blast radius (2026-08-28)

Audited all 20 area configs against the five region files:

| area | scenario rows | citations | break_points | in a region file? |
|---|---|---|---|---|
| **morr** | 12 (`ch`:6 + `co`:6) | 12 | **yes** | **yes — `skeena.yml`** |
| **bulk** | 6 (`co`) | 6 | no | **yes — `skeena.yml`** |
| neexdzii | 6 (`co`) | 6 | yes | **no** — deliberately excluded |
| the other 17 | 6, single species | 0 | no | yes |

Exposure today is precisely **BULK and MORR**, both via `skeena.yml`. The other 17 are fully
generated, so regenerating them is currently a no-op — which is why this went unnoticed for so long.
The parity fixture is safe: `skeena.yml` excludes NEEXDZII with a comment saying so.

## Why the loss is silent

Step 2 consumes only `scenario_id`, `species`, `run`, `flood_factor`, `slope_threshold`,
`max_width`, `cost_threshold`, `size_threshold`, `hole_threshold`, `description`
(`02_floodplain_model.R:117-157`).

`citations`, `ecological_process`, `min_order` and `anchor_order` are **documentation columns that
nothing reads**. Destroying them fails no run and throws no error — `git status` is the only signal.
That is the whole reason this class of bug survives: the damage is to the part of the config a
machine never checks.

## `break_points.csv` is not just a file — deleting it changes model behaviour

`02_floodplain_model.R:54-58` branches on its presence:

- present ⇒ `fresh::frs_watershed_split(conn, cfg$break_points)` — interior sub-basins
- absent ⇒ `fp_wsg_subbasin(conn, wsg, name)` — the FWA group polygon

MORR's single row documents the outlet split as verified at **4382.2 km²** against the **4379.1 km²**
group polygon, capturing 4877/4877 coho order-3+ segments. Near-equivalent, not identical, and it
feeds the per-sub-basin summaries in step 3.

### An inconsistency this audit surfaced (not for this PR to settle)

`CLAUDE.md` describes MORR as whole-WSG and says whole-WSG areas need no `break_points.csv` — yet
MORR has one, and `CLAUDE.md` separately warns that the single-outlet break point "does NOT
generalize". Config and docs disagree about MORR.

The fix here is the same either way: **stop deleting it**. If MORR should be whole-WSG, that
deletion belongs in a commit with a message, not as a side effect of a preview command. Filed
separately.

## Design note: why the planner has to be pure

`run_region.R` opens a Postgres connection for its species pre-pass, so nothing in it is testable as
it stands — which is part of why this shipped. Moving config resolution into a pure function makes
#44's acceptance criteria checkable without a database, and gives `DRY` something to *report* rather
than something to *do*. The two goals turn out to be the same refactor.

## The way to get this wrong

A merge that preserves too much. Leaving a stale region-owned key in `area.yml` after the region
file drops it would silently keep a group GRABbing from `fresh_default` after someone deliberately
switched it back to BUILD — a new silent-divergence bug introduced by the fix for a silent-loss bug.
Hence strip-then-apply rather than `modifyList`, with its own regression check.
