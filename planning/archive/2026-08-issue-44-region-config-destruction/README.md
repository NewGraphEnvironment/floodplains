## Outcome

`run_region.R` regenerated `config/<wsg>/area.yml` and `flood_scenarios.csv` wholesale on every
invocation and deleted `break_points.csv`, silently destroying the second species' scenario rows
(undoing #23), every citation, and the break points — **under `DRY=1` as well**, so the safe-looking
preview was exactly as destructive as a real run. That is how it surfaced: a dry run to preview an
unrelated one-line region change came back with 50 deletions.

The audit came before the fix and shaped it. Exposure was precisely **BULK and MORR**, both via
`skeena.yml`; the other 17 groups are fully generated, so regenerating them was a no-op, which is
why this survived so long. The parity fixture was never at risk — `skeena.yml` excludes NEEXDZII
deliberately. And the loss was silent for a specific reason: step 2 reads none of `citations`,
`ecological_process`, `min_order` or `anchor_order`, so the destroyed columns were **documentation
that no machine checks**. `break_points.csv` was the exception — its presence decides which
sub-basin branch step 2 takes, so deleting it was a model change, not just a lost file.

`FP_REGION_OWNED` now draws the ownership line in one place. Region-owned keys are **stripped and
re-applied** rather than merged: a `modifyList` would leave `network_source: fresh_default` stale in
`area.yml` after someone removed it from the region file, and the group would keep GRABbing when it
was meant to BUILD — a new silent divergence introduced by the fix for a silent loss. That case has
its own regression check. `flood_scenarios.csv` is created when absent and appended to when the
resolved species has no rows; existing rows are never rewritten.

Making config resolution a **pure function** was the load-bearing move. `run_region.R` holds a
Postgres connection for its species pre-pass, so none of this was testable before; separating the
planner from the writer is what lets `DRY` report instead of act *and* lets the acceptance criteria
be asserted without a database. The two goals turned out to be the same refactor.

The fix nearly reintroduced the bug it was fixing. Running it for real produced a correct *data*
diff and a bad *file* diff: `yaml::write_yaml` round-trips the data and discards every comment — 8
lines of rationale in `bulk/area.yml`, the publish-targets explanation and an open question in
`morr/area.yml`. The writer now edits only the lines it owns, keeping trailing comments, key order,
`null` vs `~`, and blank lines. A real `run_region.R skeena` went from **50 deletions** to **2
insertions**.

`region_config-check.R` asserts all of it with no database — 27 checks covering the create path, the
append path, idempotence, comment preservation and the stale-key regression. Replaying the *old*
behaviour against the same assertions fails all four acceptance checks, so the guard demonstrably
catches the bug it was written for rather than passing for unrelated reasons.

Filed rather than decided: **#48** — `config/morr/break_points.csv` and `CLAUDE.md` disagree about
whether MORR is whole-WSG (the two paths differ by 0.07%, which is why it never looked wrong). The
#44 fix is correct either way, and that is the point: if MORR should be whole-WSG, deleting that
file belongs in a commit with a message, not as a side effect of a preview command.

Closed by: PR #49
