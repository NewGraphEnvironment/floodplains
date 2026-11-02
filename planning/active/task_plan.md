# Task: fig/attribution.png: the subtitle is written for the analyst, not the reader (#136)

`fig/attribution.png` carries the subtitle "fire and harvest are the causes config/disturbance.yml
lists today — it takes any layer". The company site shows this figure on its Open Source page, where
the caption already says what the figure is ("Floodplain tree loss 2017–2023 in the Bulkley
watershed group, by attributed cause"), so the in-plot subtitle reads as config notes to a visitor.

Suggest the figure carry a plain title only (or none) and leave the explanation to whatever text
sits beside it.

Builder: `fp_fig_attribution()` in `scripts/readme_functions.R`. No check greps the subtitle text
(`readme_content-check.py`, `readme_determinism-check.sh`). The README prose under the figure
already explains `config/disturbance.yml` and that any layer is one config line.

## Decided at the gate

Approved by the user at the plan gate, 2026-11-02.

- **Drop both subtitles in this figure, keep both titles.** The map's "…coloured by what it can be
  attributed to today" carries the same analyst voice ("today"), and its title plus legend already
  say it. The titles are plain and stay. `fig/floodplain.png` is out of scope.
- **Rebuild only `fp_fig_attribution()`**, not `fp_fig_build()`: that would also rebuild
  `floodplain.png` and `region_totals.csv` (the latter needs all 23 areas).
- **Build on m4 from a copy of m1's three BULK gpkgs** (`floodplain_landcover.gpkg`,
  `floodplain.gpkg`, `subbasins.gpkg`, ~170 MB, into gitignored `data/bulk/`), removed after the
  build so m4 does not keep a stale snapshot.

## Phase 1: Drop the subtitles
- [x] Remove `subtitle =` from the map `labs()` and the bar `labs()`, with the now-orphaned comment
- [x] Revise the roxygen to say the explanation lives in the README prose beside the figure
- [x] Reword the `src` comment, which claimed the caption describes the config (plan review)

## Phase 2: Rebuild fig/attribution.png
- [x] scp the three gpkgs from m1 `data/bulk/` into m4 `data/bulk/` (sha256 matches m1)
- [x] `Rscript -e 'source("scripts/readme_functions.R"); fp_fig_attribution()'`
- [x] Read the PNG: no subtitles; bar still reads fire 66 ha 4% / harvest 474 ha 30% /
      not yet attributed 1025 ha 66%. If the numbers moved, stop and report (the README's
      "about a third" and the alt text depend on them). Check the bar panel's layout too, now
      the subtitle row is gone (`heights = c(4.3, 1)`)
- [x] Remove `data/bulk/{floodplain_landcover,floodplain,subbasins}.gpkg`

## Phase 3: Re-render the README
- [x] Render both targets: `rmd_on = FALSE` (README.md) and `rmd_on = TRUE` (index.html, which
      embeds the PNG as base64), both with `update_figs = FALSE`
- [x] `bash scripts/readme_determinism-check.sh` (after the gpkgs are removed and with no render
      byproducts on disk) and `python3 scripts/readme_content-check.py` pass

## Phase 4: Relabel "not yet attributed" (scope widened by code-check round 4)

Site #66 (from site #65's review) names two problems with this figure and points at #136 for both;
the comment on #136 asks for the relabel and suggests "no mapped cause". The site's copy rules rule
out "not yet" wording. #136's body now records the widened scope.
- [x] `UNATTRIBUTED <- "no mapped cause"` and its two comment mentions; README.Rmd alt text
      "where there is no mapped cause"
- [x] Rebuild the PNG (gpkgs re-copied from m1, sha256-matched, removed after); bar unchanged
- [x] Re-render: README.md and index.html move only in the alt text and the PNG payload;
      determinism and content checks (links included) pass

## Owed at the end (reported, done after merge)

- [ ] The company site holds its own copy of the old PNG
      (`content/project/open_source_software/floodplains_attribution.png` in
      newgraphenvironment.github.io, byte-identical to main's old figure, found by code-check
      round 3). Swapping it is newgraphenvironment.github.io#66, which waits on this merge.

## Validation

- [x] Tests pass (the two README checks above)
- [x] `/code-check` clean (once over the branch with `/code-check branch`): 5 rounds, ended by enumeration
- [x] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

Verification is visual (the PNG read back) plus unchanged bar figures, plus the README checks.

## Noted, not in scope

- `FIG_PRIMARY` is still `co_ff04`, a retired species item; #131's prune would remove the layer
  this figure reads, and #128 rewrites the README. Neither is touched here.
- The site's copy of the figure: see Owed at the end.
