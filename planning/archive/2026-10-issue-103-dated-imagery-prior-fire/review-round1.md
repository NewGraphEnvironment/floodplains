# Code-check round 1: #103 lookback overlays (staged diff)

Reviewer: subagent, 2026-10-02. Scope: config/disturbance.yml, fp_disturbance.R, disturbance-check.R,
fire_tag.R, 03_lulc_classify.R (tagging block), run_area.R (fp_read_config), fire_load-prior.sh.

## Verified

- `Rscript scripts/floodplain_lcc/disturbance-check.R` (offline): **ALL PASS**.
- Live, read-only probe against fwapg, on a scratch **copy** of `data/necr/floodplain_landcover.gpkg`.
  It ran `fp_disturbance_tag(sources + context + lookback)` and `fp_disturbance_report(lookback =)`
  on `transition_ch_ff04_2017_2023`, and the aliased SQL works on real Postgres:
  - `in_fire_prior` is TRUE on 314 of 5,692 patches.
  - `fire_prior_year` falls in 2010–2015, inside the 2002–2016 window.
  - `fire_year` is unchanged against the published layer.
  - The report prints "of which in_fire_prior: 242.8 ha (27% of residual)", which matches the 27%
    quoted in the yml and fp_disturbance.R comments.
  - The residual is unchanged at 886.3 ha.
- DB: neither side of 2017 has a NULL `fire_year` or `fire_number` (pre-2017: 21,186 rows; in-window:
  3,565 rows). So the live check "carry set exactly where in_fire_prior is TRUE" will not false-fail
  on a NULL `fire_number`.
- These carry shapes are refused or handled:
  - yml `[a, b]` (character vector) and `{a: b}` (named list) both reach `unlist()` correctly.
  - A null value, a nested map, a half-named list and a duplicate YAML key are all refused. The
    duplicate key is refused by the yaml parser itself.
  - The owned-column duplicate check runs on patch-side (alias) names, case-folded, so
    `{fire_year: fire_year}` on the fire table is refused.
- Other readers of `disturbance.yml` (readme_functions `fp_readme_sources`, accuracy_estimate,
  sample_draw-pilot, reference_*) read `$sources` / `$context` by name or validate. None of them
  enumerates the top-level lists or builds SQL from `carry` itself, so neither the `lookback:` key
  nor the map-form carry breaks them.
- `fire_tag.R`: lookback columns stay out of `cause_cols`, so a re-tag can add them without being
  refused. Item keys remain last. Lookback columns are reported via `lookback =`.
- No credentials or private endpoints in the staged diff (planning files included).

## Findings

- **[severity: fragile, low]** `scripts/floodplain_lcc/fp_disturbance.R:137`: the `lookback:`
  validator accepts `Inf` (YAML `.inf`). `Inf >= 1` and `Inf == round(Inf)` both hold, so it passes.
  Then `.dst_window()` gives `as.integer(Inf)` = `NA` with a coercion warning, and `.dst_query()`
  emits `fire_year BETWEEN NA AND 2016`. Postgres rejects that as `column "na" does not exist`, and it
  does so in step 3 **after** the STAC fetch. That is exactly the "fail at load, not after the fetch"
  class the validator exists for. A huge finite value (e.g. `1e10`) takes the same path.
  - Reproduced: `d$lookback[[1]]$lookback <- Inf; fp_disturbance_validate(d)` is accepted, and the
    query text contains `BETWEEN NA AND 2016`.
  - Fix: add `!is.finite(lb)` to the condition. Optionally also bound it, e.g. `lb > 200`.
  - Implausible as a typo, so this is low priority, but it is a one-token gap in a guard.

## Pre-existing, not introduced by this diff (noted only)

- `03_lulc_classify.R:226` passes `cfg$change_interval` unsorted to `fp_disturbance_tag()`, while
  line 55 sorts its own copy to "guard a reversed config". With a reversed `change_interval`, a
  source's predicate becomes `BETWEEN 2023 AND 2017`, which matches nothing in Postgres, so every
  cause comes back FALSE with no error. The new lookback path uses `min(window)` and is immune.
  Sources are not. Out of scope for #103.

## Verdict

No bugs in the diff. One low-severity validator gap (Inf / non-finite `lookback:`).
