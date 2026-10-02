# Code-check round 3: #103 lookback overlays (staged diff)

Reviewer: subagent, 2026-10-02. Scope: the staged diff only. The unstaged `scripts/landcover_accuracy/`
changes were ignored except where noted as reach outside the diff.

Offline `Rscript scripts/floodplain_lcc/disturbance-check.R`, run on a `git checkout-index` copy of
the INDEX (not the worktree): **ALL PASS**.

## The mechanism behind rounds 1 and 2

`lookback:` was added by **concatenation** into code paths written for `sources:` and `context:`:
- `FP_DST_LISTS` in the validator loop;
- `c(disturbance, context_overlays, lookback_overlays)` in 03;
- `c(sources, context, lookback)` in fire_tag;
- `c(dst$context, dst$lookback)` in the live check.

Each rule it joined was correct because of a property of the **population** it was written for, not
because of the rule's own logic. That property was never written down, so nothing re-derived it for
the new kind of entry:

- **Round 1.** A source's window is a pair of literal config years, so formatting it with `%d`
  needed no finiteness check. A lookback window is **arithmetic on an unbounded user number**.
- **Round 2.** Context overlays are ubiquitous, so "tagged nothing" meant "the fetch failed". A
  lookback is **sparse**.

So the shared assumption is: "a lookback entry is a source (dated) or a context entry (not a cause),
so whatever held for that list holds for it." A lookback differs from both on four axes:
- its window is **derived**;
- it is **sparse**;
- its carries are **aliased**, so the source-side and patch-side names differ;
- its values depend on a **tunable** number (`lookback:`) and on a table that was hand-appended.

Every site below was checked against those four axes.

## Reach in the staged diff, site by site

| # | Site | Inherited assumption | Holds for lookback? |
|---|------|----------------------|---------------------|
| 1 | `fp_disturbance_validate` generic loop: name/table/geom_col, `.dst_carry_shape`, `.dst_core_clash`, case-folded name dupes, owned-column dupes | structural, per entry | **Holds.** Owned and core checks run on PATCH-side names (`unlist(carry)`), which is what makes same-table aliasing safe. There is an arm for this (`lb_unaliased`). |
| 2 | `.dst_query` `%d` window formatting | the window is finite integer years | **Holds** after round 1 (finite, whole, 1–200). A grep shows `.dst_window` is the only reader of `src$window`; nothing else reads a source's window directly and would get the change interval for a lookback. |
| 3 | `.dst_query` `year_col` vs carry names | `year_col` names a column the fetch returns, which is true when the year is carried unaliased | **Holds in the diff.** The WHERE uses the source-side `year_col`, which is correct. No staged code reads `poly[[year_col]]` from a fetch. **Reach outside the diff:** `reference_omission-disturbance.R:49-53` does `p[[QUAL[[nm]]$year_col]]`. It is sources-only today, but a lookback passed there would make `p[[yc]]` NULL, and the per-year loop would silently emit no rows. That is not a defect now. |
| 4 | `fp_disturbance_tag`: typed-NA init (`poly[[a]][NA]`), `lost` check, dominant carry | the carry name is the fetched column name | **Holds.** SQL `AS alias` returns patch-side names, and the stub mirrors that. A zero-hit area still types its carries from the bbox rows (round 2: every zero-hit area returned 10–51 polygons). |
| 5 | Live: "in_X tagged something" | the overlay is ubiquitous | Fixed in round 2 (INFO for lookback). |
| 6 | Live: "carry set exactly where in_X is TRUE" | the dominant feature's carried attributes are never NULL | **Holds today** as a data property (round 1: 0 NULL `fire_year`/`fire_number` pre-2017). It holds because the carries are a key and a year, which is the same reason it holds for `waterbody_poly_id`. |
| 7 | Live: "typed, not Boolean" | the zero-match tag is still typed | **Holds** (see 4). |
| 8 | Live: "every context and lookback column is present" | presence follows any re-tag | **Holds; forward-only by design.** Every area not re-tagged since #103 now FAILs this arm, **necr and bulk included**, though both pass today. Expected (Phase 3), the same as #95. Don't read it as a regression. |
| 9 | `fire_tag.R` compare-before-write (`cause_cols` = sources only) and the live snapshot `keep <- setdiff(..., ctx_cols)` | "context columns are free to change; adding them is the point" | **Weakest site. See the finding below.** |
| 10 | `fp_disturbance_report`: lookback refused as a source; `absent` check; residual-share line | a list is identified by key presence (`year_col`, `lookback`) | **Holds.** The validator confines `lookback` to the lookback list, so key presence and list membership agree. The share is computed over `!any_in`, so there is no double count, even against a source whose `window` override reaches back. |
| 11 | 03 / fire_tag entry order and log lines | none | Holds. Column order is sources, context, lookback, then item keys last, on both paths. |
| 12 | `run_area.R` `cfg$lookback_overlays` and the prefix sweep | `$` partial matching | Holds (the sweep passes). |
| 13 | README figure / `fp_readme_sources` | reads `sources:` only | Holds (the offline arm covers lookback names). |

## Findings

- **[low / design, not a crash]** `scripts/floodplain_lcc/fire_tag.R:13,43,71` and
  `scripts/floodplain_lcc/disturbance-check.R:333,382` exempt lookback columns from every
  must-not-move guard, inheriting context's exemption.
  - **Why the exemption existed.** At #95 the exemption was justified as "adding them is the point",
    which describes the *first* tag, when none of those columns were published yet.
  - **Why it does not carry over.** After the Phase-3 re-tag, `in_fire_prior`, `fire_prior_year` and
    `fire_prior_number` are published values. Nothing refuses or reports a later change to them,
    whether it comes from:
    - editing `lookback: 15` (the number #93 is expected to revisit);
    - the documented `DELETE ... WHERE fire_year < 2017` and reload in `fire_load-prior.sh`;
    - a change-interval edit picked up on re-run.
  - **What the guards miss.** `fire_tag.R` writes over the published layer silently. The snapshot
    comparison in `disturbance-check.R` also skips these columns, so a before/after run passes with
    the prior-fire share moved.
  - **Why it is sharper than for context.** Context carries the same exposure in principle. But a
    wetland table is rarely reloaded, while `lookback:` is a tunable parameter whose value is still
    an open question.
  - **Options.** Either name lookback columns in fire_tag's REFUSED/FORCE report when they already
    exist and would move: compare only the columns present in `tr`, so the first tag still passes.
    Or keep the exemption and state in the fire_tag header that published lookback values move
    without a guard. This is a policy call. The code does what its comment says.

No other site in the staged diff inherits an assumption that fails for a lookback entry. There are
no new bugs in validation, SQL, tagging, the report or the plumbing.
