# Task: Modernize the README, publish it via GitHub Pages, and set the repo description + homepage (#77)

`floodplains` produces every number in the published `stac-floodplains-bc` catalogue, and it is
the repo in the family that looks abandoned: no description, no homepage, no site. Its README is
the only place the model is documented, and it has drifted — "20 items live" against a collection
serving 23, a Fraser roster of 10 against a region file listing 13. Nothing regenerates those, so
they decay silently while reading as current.

The fix is the rule #77 proposes: **each repo states only what it owns, and neither restates the
other's numbers.** `floodplains` owns the model, its uncertainties, how to re-run it, provenance.
`stac_floodplains_bc` owns the item model, access, counts, extent, version, licence.

## Phase 1: Repo description

- [x] `gh auth status` preflight — a scope that can `POST /pages`, checked before anything merges
- [x] `gh api -X PATCH … -f description=…` — description only; `homepage` waits for Phase 5
- [x] No count in the description (nothing regenerates one, so a number in one is a future lie)

## Phase 2: `README.Rmd` as the single source

- [x] `README.Rmd` — `github_document` (`html_preview: false`, `--wrap=preserve`) + `html_document`
      (`self_contained`, `code_folding: hide`, toc). No `date:` field
- [x] `params$rmd_on` default FALSE; `params$update_figs` default FALSE
- [x] Never plot inline — every figure written to `fig/` by a gated builder, pulled in with
      `knitr::include_graphics()`; a missing PNG stops the render
- [x] Badges on the `.md` target only
- [x] `scripts/readme_functions.R` — roster reader, scenario-table reader, figure builders
- [x] `.gitignore`: `README.html`, `README_files/`, `index_files/`, `*.knit.md`, `*.utf8.md`
- [x] `.nojekyll` committed; no `CNAME`

## Phase 3: Figures and the scenario table

- [x] `fig/floodplain.png` — nested `co_ff02`/`co_ff04`/`co_ff06` over `streams_co3`, from `data/bulk/`
- [x] `fig/attribution.png` — 2017→2023 patches coloured fire / harvest / not yet attributed
- [x] The `ff0N` table rendered from `config/<area>/flood_scenarios.csv`, including which are `run`
- [x] Method credits rendered from the citation keys already in that CSV
- [x] `fig.alt` on both figures

## Phase 4: README content

- [x] Delete `Status` bullet 5 (count + collection name + extent) — link instead
- [x] Delete the arithmetic in `Status` bullet 1
- [x] Cut `Publishing` to the one-way dependency + `$FLOODPLAINS_DATA` + a link; keep the
      byte-reproducibility paragraph, drop "72% of the published bucket"
- [x] Cut the `Layout` ASCII tree
- [x] De-duplicate the item-key paragraph and the BULK/KOTL percentages
- [x] Move or link the `stac-floodplains-bc` hyphen gotcha
- [x] Roster generated from `config/regions/*.yml` — codes by region, no total, "configured to run"
- [x] Rebalance `Reading the outputs`: what the tool is for and has found, then attribution as a
      growing framework, then the open questions
- [x] Lede + figure above the fold + site link; preserve both internal anchors

## Phase 5: Pages, boundary rule, verification

- [ ] Merge Phases 2–4 to `main` first
- [ ] `POST …/pages`, poll `builds/latest` until `built`, **then** PATCH `homepage`
- [x] Boundary rule into `CLAUDE.md` **above the soul marker** (it has no closing line, so
      anything below is erased on the next propagate)
- [ ] Decide the sibling's BULK/KOTL restatement — file downstream or leave — and say so in the PR
- [x] `scripts/readme_determinism-check.sh` — sha both targets, re-render twice at default params,
      compare, and assert no byproduct is left. Checked **by name**, not with `git status`:
      `.gitignore` lists exactly those paths, so porcelain is blind to them (measured)
- [x] Link check asserting `200` **and** `url_effective` == request, per rendered target
      (`scripts/readme_content-check.py`, `CHECK_LINKS=1`); DOIs go to Crossref instead, since
      both Wiley landing pages 403 a browser UA and a DOI redirects by design
- [x] Anchor check per target (the two slug algorithms are not the same)
- [x] Mechanical grep for catalogue facts over both targets
- [ ] Served bytes hashed against the committed `index.html`, gated on `built`

## Validation

- [x] `/code-check` — four rounds; the fourth ran an enumerated stop condition rather than
      a judgement, and its findings are closed
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion
