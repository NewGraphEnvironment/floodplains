# Code check, round 1 (#136)

## Checklist read

- code-check-python.md: index only. No Python changed in this diff; `readme_content-check.py`
  was run, not edited.
- code-check.md: every H3 under `## Mechanisms` read as prose, tables skipped (A guard that fails
  toward pass; A fixture that cannot reach the failure mode; A proxy is not the property;
  Verification that reads its own output; A guard's scope, escape hatches, and remedies; A fix
  lands in one of two callers that share a harness; Restore the bug and prove the guard fires;
  the rest skimmed). Also read "Documentation Staleness". The other 20 headings are unread: they
  do not apply to an R plotting edit.
- code-check-r.md: index read, no section opened. The diff removes two `labs(subtitle = )`
  arguments and rewrites comments. No R construct the index names is added or changed (the
  `sprintf`/`paste` that went is deleted, not modified).
- code-check-shell.md and code-check-spatial.md: index read, no section opened. No shell or spatial
  code changed.

## Verification done

- `scripts/readme_functions.R`: `src` is still used, as `lv`, by the missing-column stop and by
  the cause loop, so removing the subtitle orphans nothing. The `labs()` calls are syntactically
  complete. `fp_fig_theme()`'s `plot.subtitle` element is still used by `fp_fig_floodplain()`.
  The new roxygen lines sit inside the existing block, directly above the function, so roxygen
  binds them to the right function.
- `fig/attribution.png` read back: no subtitles. The bar reads fire 66 ha 4%, harvest 474 ha 30%,
  not yet attributed 1025 ha 66%, the same as the committed figure the plan cites. The bar panel's
  title and labels are laid out in `heights = c(4.3, 1)` with no clipping.
- No script greps the removed subtitle text. A repo-wide grep for "lists today" and "it takes any
  layer" outside `planning/` finds nothing.
- `README.Rmd`'s `fig.alt` still derives the source list from `src`, so it does not depend on the
  removed subtitle.

## Clean

No issues found.

Not a finding, pre-existing and outside the diff: `README.Rmd` line 171 hard-codes "Fire and
harvest are the causes that file lists today". The removed bar subtitle derived that list from
`config/disturbance.yml`. With the subtitle gone, this prose line is the only place in the
rendered page that states the source set without deriving it. If `pest` is enabled, the figure
and alt text will update and this sentence will not. The sentence was already hard-coded before
this branch, so the change does not introduce it. It is now the last stated copy, which is worth
knowing for #128's README rewrite. The `fp_readme_sources()` roxygen ("while the caption still
claimed to describe that file") still refers to the deleted subtitle's claim. That is
documentation only.
