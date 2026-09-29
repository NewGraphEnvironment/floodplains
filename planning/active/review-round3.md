# Code review, round 3: #95 staged diff

Scope: `git diff --cached -- scripts config` (fp_disturbance.R, disturbance-check.R, run_area.R
`fp_read_config`, 03_lulc_classify.R 213-230, config/disturbance.yml). fire_tag.R read for context only.
Offline check run on the staged tree: ALL PASS.

## Mechanism

Every earlier defect comes from one assumption: **a lookup by name returns the thing the author
meant, and a name that is absent reads as a value.** R answers a lookup with something plausible
where most languages would raise. `$` returns a longer sibling key. `[[` on an absent column returns
NULL, and NULL then does one of three things: assigning it drops a column, `%in%` turns it into
`logical(0)`, and in an elementwise op that zero-length vector wipes out the other operand. A
`patch_id` that looked like a key is really a per-basin counter. Postgres folds identifiers to
lower case, and GPKG compares field names without regard to case, so two names R keeps apart can
be one name on disk. In each case the code keeps running and hands back a wrong value where it
should have failed. The fixes in rounds 1 and 2 closed individual lookups. The instances below are
the lookups those fixes did not reach: an absent **patch column** read by the report, an absent
**entry key** read by the validator and query builder, and a **case-variant name** in the two
duplicate checks the round-2 case-fold did not cover.

## Enumeration

Every name- or key-based lookup in the staged code:

- `fp_read_config`: `dst[["sources"]]` and `dst[["context"]]`. **Handled** (exact `[[`).
- `fp_read_config`: `cfg$disturbance <-` and `cfg$context_overlays <-`. **Handled** (`$<-` is exact;
  assigning NULL removes the key cleanly).
- 03: `cfg[["disturbance"]]` and `cfg[["context_overlays"]]`. **Handled** (exact `[[`). No `cfg$disturbance`
  read remains anywhere in `scripts/` (grep). No area.yml or region yml key starts with either name
  (grep over all 28 area configs and 5 region files).
- 03: `nms()` uses `s$name`. **Handled** (the validator guarantees `name` is present, so `$` matches exactly).
- 03: `cfg$change_interval`. **Handled** (defaulted in `fp_read_config`, so it is always present).
- validate: `dst$sources` and `dst$context` use `$`. **Handled**, because of ordering: the unknown-key refusal
  runs first, so `contexts:` or `sources_x:` is refused before `$` could partial-match it.
- validate: `s[[f]]` for name, table and geom_col. **Handled** (type plus length plus nzchar).
- validate: `s[["year_col"]]` and `s[["window"]]`. **Handled** for these two keys.
- validate: other per-entry keys (`carry`, `filter`, `window` on a source). **NOT handled.** A misspelled
  key reads as absent and is dropped without a message (probe: `filtr:` and `cary:` are both ACCEPTED,
  and the query comes out with no filter predicate and no carried column). See Finding 2.
- validate: `s$.list`. **NOT handled (theoretical).** It is an internal tag injected into user data, so an
  entry that itself carries `.list: context` shadows it (`c()` appends, and both `$` and `[[` return the
  first match). Probe: an undated **source** carrying `.list: context` is ACCEPTED. Finding 2's fix
  covers this too, as long as it runs on the raw entry.
- validate: `.dst_core_clash` against FP_PATCH_CORE and geometry. **Handled**, case-folded (fixed in round 2).
- validate: `anyDuplicated(nm)` and `anyDuplicated(owned)`. **NOT handled, but loud.** Both comparisons are
  case-sensitive, while GPKG field names are case-insensitive. Probe: `name: fire` (source) together with
  `name: Fire` (context) is ACCEPTED, and `st_write` of `in_fire` plus `in_Fire` then fails with
  *"Field count reached: duplicate names present?"*. That failure comes at step 3's write, after the
  STAC fetch. Carry-vs-carry case variants are caught at tag time by the `lost` refusal, because Postgres
  folds names to lower case. See Finding 3.
- `.dst_query`: `src[["window"]]`, `src[["year_col"]]`, `src[["filter"]]`, `src[["carry"]]`, `src[["geom_col"]]`.
  **Handled** for the keys that are present. An absent `filter` is indistinguishable from a
  misspelled one (Finding 2).
- tag: `poly[[a]]` for a carry. **Handled.** The `lost` refusal runs before the typed-NA line.
  Verified live: a zero-row `st_read` keeps `waterbody_poly_id` as int and `fire_year` as num. Note that
  `fire_year` and `harvest_start_year_calendar` are Postgres `numeric`, so they arrive as double and
  are written as Real. They are consistent across areas now, but they are Real, not Integer.
- tag: `patches[[a]][dom$._row] <- dom[[a]]`. **Handled.** Rows are joined back by position.
  `hit` is built from `patches` after `st_make_valid`, which does not drop rows. The only
  non-geometry column in `hit` is `._row`, so `st_intersection` cannot rename a carry column with a
  `.1` suffix.
- tag: `dplyr::slice_max(._ov, with_ties = FALSE)`. **NOT handled, pre-existing and out of scope.**
  Ties on overlap area resolve by the row order of an SQL query with no ORDER BY. Duplicate geometries
  in consolidated cutblocks would make the carried year arbitrary. The line is unchanged in this diff.
- tag: `in_col` from `src[["name"]]`. **Handled** (exact).
- report: `s[["year_col"]]` and `s[["name"]]`. **Handled** (exact). An undated entry is refused.
- report: `loss[[ic]]`. **NOT handled.** An absent `in_<source>` column produces NULL, then `logical(0)`, and the
  new `Reduce(..., rep(FALSE, n))` init is wiped out by `rep(FALSE, n) | logical(0)` = `logical(0)`.
  See Finding 1.
- disturbance-check.R: the prefix sweep. **Handled for this pair**, but only because every read uses `[[`.
  The sweep collects keys from script accesses (`cfg$x`, `cfg[["x"]]`) and never from the keys the
  YAML actually supplies. Partial matching needs a longer key to be present, so a future
  `cfg$disturbance` read beside an area.yml key such as `disturbance_note` would not be swept. No
  finding today.
- disturbance-check.R live section: it orders by the non-unique `patch_id` and compares the sorted
  multiset. It is correct only because `order()` is stable and the re-tag preserves row order.
  Accepted (Phase 4 rework).
- readme_functions.R `fp_readme_sources` uses `y$sources`, unvalidated. It is not staged. Given the
  committed file it resolves exactly.

## Findings

- **[Medium]** scripts/floodplain_lcc/fp_disturbance.R:188-198. `fp_disturbance_report()` reports a
  **0 ha / 0% residual** ("everything explained") when it is given a cause whose `in_<name>` column the
  patches do not carry. Probe: total loss 3.0 ha with `in_fire` 1.0 ha and `in_harvest` absent printed
  `in_harvest: 0.0 ha`, `residual (noise): 0.0 ha (0%)`. With fire alone, the same data gives 2.0 ha (67%).
  The cause is `loss[[ic]]` returning NULL, `NULL %in% TRUE` giving `logical(0)`, and
  `rep(FALSE, n) | logical(0)` giving `logical(0)`, which makes `resid = sum(area[logical(0)]) = 0`.
  The guard fails toward pass on the exact number #95 protects. It is latent today, because
  fire_tag.R tags with the same list immediately before reporting. It becomes reachable as soon as
  the report runs against a layer written before a source was added, which is the direction Phase 3
  (a fire_tag.R rewrite) and any "report without re-tag" path would take. Fix: refuse when
  `setdiff(in_cols, names(patches))` is non-empty, with a must-fail arm in the check.
  *Inside a previous fix?* **Yes.** The `Reduce` init added in this diff for the empty-sources case
  does not cover a missing column.

- **[Low]** scripts/floodplain_lcc/fp_disturbance.R:60-89. The validator refuses unknown **top-level**
  keys but not unknown **per-entry** keys. On a source, `filtr:` for `filter:` silently removes the
  SQL predicate, so the source over-attributes and the residual shrinks. `cary:` for `carry:` silently
  drops the carried columns, and the live "every context column is present" check reads the same
  config, so it passes. `windw:` silently falls back to the default interval. The probe accepted all of
  them. The validator's own header states the principle ("a typo like `contxt:` would drop every
  entry"), but it is applied one level up only. Fix: refuse any entry key outside
  `c("name","table","geom_col","year_col","carry","filter","window","confidence")`, checked on the raw
  entry **before** `.list` is injected. Doing it there also closes the theoretical `.list` shadow above.
  *Inside a previous fix?* No (new validator, same mechanism).

- **[Low]** scripts/floodplain_lcc/fp_disturbance.R:84-89. The duplicate-name and duplicate-column checks
  are case-sensitive, while GPKG field names are case-insensitive. `fire` together with `Fire` passes the
  validator and aborts step 3 at `st_write` ("Field count reached: duplicate names present?"), after the
  STAC fetch rather than at config load, which is where the validator's promise puts it. The failure is
  loud, but it comes after a long, expensive fetch. Fix: apply `tolower()` inside both `anyDuplicated`
  calls, the same fold round 2 added to `.dst_core_clash`.
  *Inside a previous fix?* **Yes** (a sibling). The round-2 case-fold covered the core clash but not these two
  checks.

/Users/airvine/Projects/repo/floodplains/planning/active/review-round3.md
