# Code check, round 2 (#136)

## Checklist read

- code-check-python.md: in full (7,237 bytes). No Python changed in this diff.
- code-check.md: the prose of every H3 under `## Mechanisms` (all 14), with tables and evidence
  blocks skipped. Of the 23 headings outside Mechanisms, none was read. None of them names a tool,
  shape or pattern this diff uses (an R plotting edit, a rebuilt PNG, a re-rendered HTML).
- code-check-r.md: 3 sections read in full: "ggplot2 legends and labels: a key for an unused
  factor level, and ggrepel labels that must avoid each other", "Inserting a helper between a
  roxygen block and its function rebinds `@export`" and "Regenerated binaries churn git even when
  nothing changed". The other 114 headings were not read.
- code-check-shell.md: index only, with 0 sections read. No shell changed.
- code-check-spatial.md: index only, with 0 sections read. No spatial code changed; `sf` reads
  in `fp_fig_attribution()` are untouched.

## Verification done

- `scripts/readme_functions.R` was read in full. Both `labs()` calls are complete, and `src` is
  still consumed (by `lv`, the missing-column stop and the cause loop), so nothing is orphaned.
  `fp_fig_theme()`'s `plot.subtitle` is still used by `fp_fig_floodplain()`. The new roxygen
  paragraph sits inside the existing block, which is still directly above `fp_fig_attribution`,
  so the binding is unchanged (and this repo has no NAMESPACE).
- `fig/attribution.png` (new) and `766d015:fig/attribution.png` (old) were both read. The new one
  has no subtitles, and the bar reads the same as the old one: fire 66 ha 4%, harvest 474 ha 30%,
  not yet attributed 1025 ha 66%. Nothing is clipped. The map panel grew into the freed row, and
  the legend and the bar are unaffected.
- `index.html`: decoded the one embedded attribution `data:image/png` payload. Its sha256
  (`039c667434e6d6a2…`) equals that of `fig/attribution.png` on disk, so the page carries the
  rebuilt figure, not a stale one. The alt text is unchanged, and it still holds, because the
  numbers did not move.
- Grep outside `planning/` for the removed strings ("it takes any layer", "what it can be
  attributed to") finds nothing. "lists today" hits only README.Rmd/README.md:172/53, which is
  the accepted pre-existing sentence (#128).

## Clean

No issues found.
