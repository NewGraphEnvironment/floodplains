# Plan review — #77

A `Plan` subagent reviewed the draft plan against the issue body and this checkout on
2026-09-04. It has no Write tool, so the review is transcribed here. Every finding was verified
in this checkout before being acted on; the disposition column says what happened.

## Blockers

| # | finding | disposition |
|---|---|---|
| B1 | `CLAUDE.md:468` is `<!-- BEGIN SOUL CONVENTIONS — DO NOT EDIT BELOW THIS LINE -->` with **no closing marker**, so lines 468–2729 of 2,729 are machine-managed. The boundary rule written below it is erased on the next `/claude-md-propagate`. | **Accepted.** Verified. Rule lands above 468. |
| B2 | `.nojekyll` yes, `CNAME` no. The org user site `newgraphenvironment.github.io` owns `www.newgraphenvironment.com` (`https_enforced: true`) and every project page inherits it — which is why the sibling reports `cname: null` yet serves at the custom domain. Without `.nojekyll`, Pages runs Jekyll/Liquid over all **84** tracked `.md` files and one future planning doc quoting Liquid breaks the build while Pages keeps serving the last good commit. | **Accepted.** Verified; the earlier draft had `.nojekyll` but had not established the CNAME question. |
| B3 | The link guard fails toward pass: `https://www.newgraphenvironment.com/floodplains/` returns **404** with `url_effective` equal to the request, so the issue's criterion as written is satisfied by a 404. | **Accepted.** Guard asserts code **and** URL. |

## Ordering

| # | finding | disposition |
|---|---|---|
| O1 | Phase 1 set `homepage` before Phase 2 made it exist — advertising a 404. Correct order: description → branch → merge → `POST /pages` → poll `built` → **then** `homepage` → then the link check. | **Accepted.** Phase 1 is description-only. |
| O2 | Pages enabled before `index.html` is on `main` serves a **Jekyll-rendered `README.md`**, not a 404 — worse, because it looks like it worked. | **Accepted.** |
| O3 | CDN caching makes the served-bytes check racy; gate on `pages/builds/latest --jq .status == "built"`, and pre-check `%{size_download}` against `stat -f%z index.html` before hashing. | **Accepted.** |
| O4 | Preflight `gh auth status` — a 403 at the `POST /pages` step strands a merged commit with no site. | **Accepted.** |

Verified-and-do-not-re-litigate: serving byte-identity is already true on the sibling —
`shasum -a 256 index.html` equals `curl -sL <site> | shasum -a 256`. Pages serves the file
verbatim once `.nojekyll` is present.

## Design findings that changed the plan

- **The figure's dominant nondeterminism is knitr, and the fix is architectural, not a seed.**
  Write every figure to `fig/` from a gated builder and `knitr::include_graphics()` it in both
  targets. A plotting chunk lands the `.md`'s image in the ignored `README_files/` (404s for
  everyone but the author) and re-encodes the PNG each render.
- **Drop the elevation cross-section.** Not mainly for its `fl_dem_aoi()` dependency: `ff0N` is
  not a stage height, and the boundary at any transect is set as much by the slope/cost/max-width
  gates as by depth (`02_floodplain_model.R:194-206`). Three clean lines on a section would be a
  simplification that reads as the method — #77's own failure mode aimed at a figure.
  **Replace with the `flood_scenarios.csv` table**, which is committed, needs no gate, carries
  each scenario's ecological meaning and citations, and surfaces that only `02`/`04`/`06` run.
- **Build the figures from `data/bulk/`, not `data/neexdzii/`.** neexdzii is deliberately in no
  region roster, so a figure of it shows ground that is not in the catalogue.
- **The roster must not carry a total.** Four sets do not coincide — configured (22 + neexdzii),
  published (22), re-runnable (21), provenance-carrying (20, the two missing being MCGR and PINE,
  exactly #76). "22 groups" collapses them, and counting YAML entries would let a group claim to
  be modelled before a cell is delineated.
- **floodplains cites the VCA method nowhere at all**, while `flood_scenarios.csv` already carries
  five citation keys per scenario that nothing renders. That, not the sibling's already-fixed
  URL, is the real gap behind the issue's bullet.

## Acceptance gaps

| # | gap | disposition |
|---|---|---|
| G1 | Link check must run over the **rendered** targets, not the `.Rmd` — a link inside an `rmd_on` branch exists in only one output. | Accepted. |
| G2 | Anchors are unchecked by curl, and `github_document` and pandoc's `html_document` do not share a slug algorithm. They agree on today's two anchors by luck. | Accepted — checked per target. |
| G3 | "No catalogue count, extent or version stated anywhere" has no mechanical guard, so it decays exactly the way "20 items" did. The failure mode is **recurrence**. | Accepted — grep guard over both targets. |
| G5 | A sha compare alone passes while `README.md` points at an image that 404s on github.com. | Accepted — plus `git status --porcelain`, and render twice. |
| G6 | `.gitignore` has no render-byproduct entries, so G5 cannot distinguish the mistake from known noise. | Accepted. |
| G7 | The sibling's restatement of the BULK/KOTL percentages is an edit in the other repo; the AC only mandates the rule in both `CLAUDE.md`s. Decide explicitly or it goes silently undone. | Accepted — decided in the PR body. |
| G8 | No `LICENSE` in floodplains; a public landing page invites the question. | Flagged, out of scope. |
| G9 | Issue item 3 bullet 2 is misattributed — confirmed independently. | Accepted; recorded in `findings.md`. |

## Assumptions made explicit

- The figures are only **rebuildable** on a machine that has run the pipeline. Committed PNG plus
  a default-FALSE gate handles it — and the render must **fail loudly on a missing PNG** rather
  than produce a page with holes in it.
- `params$rmd_on` earns its keep only if the targets actually differ; badges alone justify it.
- Adding `title:` makes `README.md` open with a setext heading rather than `# floodplains`.
  Cosmetic; expect it, do not debug it.
- `gh api -f 'source[branch]=main'` bracket syntax is valid (gh 2.92.0).
