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

## A second silent loss the fix itself would have caused

Wiring the merge in and running `run_region.R skeena` for real produced a *correct* data diff — and
a bad file diff. `yaml::write_yaml` round-trips the **data** and discards everything else: BULK lost
8 lines of rationale ("dedicated persist schema — never shared `fresh.*`, never neexdzii"), MORR lost
its publish-targets explanation and an open question, and `subset: null` churned to `subset: ~`.

That is the same class of damage #44 is about, so shipping it would have half-fixed the issue while
introducing the other half. The writer now edits **only the lines it owns**
(`fp_area_yml_edit`): a changed region-owned value is rewritten in place with its trailing comment
kept, a new key is appended past any block it must not land inside, a dropped key's line is deleted,
and every other byte — comments, key order, `null` vs `~`, blank lines — is left as found. A nested
value under a region-owned key is refused rather than mangled.

Before and after, on a real `run_region.R skeena`:

| | config diff |
|---|---|
| old behaviour | **50 deletions** across `config/{bulk,morr}/` |
| this fix | **2 insertions** — one `attribute_by: gnis_name` per group, which the region legitimately owns |

## Acceptance criteria, run for real

- `DRY=1 Rscript scripts/run_region.R skeena` → `git status` **clean**, twice
- A real `run_region.R skeena` → MORR keeps 12 rows across two species, all 12 citations, and
  `break_points.csv`; `config/tabr/` (generated-only) byte-identical
- `FP_SPECIES=ch FP_PRIMARY_SCENARIO=ch_ff06 … morr` resolves: `ch_ff06`, 12 rows, 1 break point
- `region_config-check.R`: 27 checks green, no database
- Replaying the OLD behaviour against the same assertions fails all four — the guard catches the bug
  it was written for, rather than passing for unrelated reasons

The `DRY` preview is now useful rather than merely harmless: it reports per group what would change
(`area.yml: update: attribute_by | flood_scenarios.csv: unchanged (12 rows, ch+co) |
break_points.csv: present, kept (1 point(s) => interior sub-basins)`).

## Filed, not decided: #48 (MORR break_points.csv)

`config/morr/break_points.csv` and `CLAUDE.md` disagree about whether MORR is whole-WSG. The file's
presence sends step 2 down the `frs_watershed_split` branch; the docs say MORR uses the group polygon
and that whole-WSG areas need no break points — while separately warning that the single-outlet
construct "does NOT generalize". The two paths differ by 0.07% for MORR (4382.2 vs 4379.1 km²),
which is why nothing ever looked wrong.

`morr/area.yml` still says its `break_points.csv` was "copied from Neexdzii as a starting template"
and still carries an unresolved "OPEN QUESTION … does MORR run as the WHOLE watershed group" — a
question the docs answered and the config never did. Filed as #48 rather than guessed at: it changes
which code path a published area takes.

The #44 fix is correct either way, and that is the point — **if MORR should be whole-WSG, deleting
that file belongs in a commit with a message, not as a side effect of a preview command.**
