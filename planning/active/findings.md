# Findings — Modernize the README, publish via Pages, set description + homepage (#77)

## Measured before any code was written (2026-09-04)

| claim | measured |
|---|---|
| README "20 items live" (line 212) | live API serves **23 items** |
| README "19 groups publish as 20 items" (line 199) | **22 groups**, 23 items |
| README Fraser roster of 10 groups | `config/regions/fraser.yml` lists **13** |
| union of `config/regions/*.yml` | **22** codes — the same 22 the collection publishes, today |
| `find data -maxdepth 2 -name provenance.json` | **21**, of which neexdzii is one → **20 of 22** rostered groups carry provenance. The two missing are **MCGR and PINE**, exactly #76 |

Four sets that "22 groups" collapses, and they do not coincide: **configured** (22 + neexdzii),
**published** (22), **re-runnable at `flooded` ≥ 0.5.0** (21), **provenance-carrying** (20).
Counting YAML entries would let a group claim to be modelled before a cell is delineated — #77's
own failure mode, reintroduced by the fix. So: codes by region, no total, "configured to run".

## Two corrections to the issue

- **The dead USDA VCA Toolbox URL is not in this repo.** `grep -rn 'usda|valley_confinement'`
  over `floodplains` returns nothing; `README.md` carries exactly 5 URLs, all
  `github.com/NewGraphEnvironment/*`. The URL lives in `stac_floodplains_bc/ATTRIBUTION.md`, where
  it is already fixed to `https://research.fs.usda.gov/rmrs`. The real gap is that floodplains
  cites the VCA method **nowhere at all**, while `config/*/flood_scenarios.csv` already carries
  five citation keys per scenario that nothing renders.
- **The link acceptance criterion as written is satisfied by a 404.** Measured:
  `https://www.newgraphenvironment.com/floodplains/` → `404`, `url_effective` equal to the
  request. "Resolves to itself with redirects followed" is true of it. The guard has to assert
  `http_code == 200` **and** `url_effective == requested`.

## Pages

- The org **user site** `NewGraphEnvironment/newgraphenvironment.github.io` owns
  `www.newgraphenvironment.com` (`https_enforced: true`), and every project page inherits it.
  That is why `stac_floodplains_bc/pages` reports `cname: null` yet serves at
  `www.newgraphenvironment.com/stac_floodplains_bc/`. **No `CNAME` file.**
- Verified: `/stac_floodplains_bc/` and `/flooded/` both 200; `/floodplains/` 404s today.
- The sibling commits a 0-byte `.nojekyll` and no `CNAME`. Not cargo cult here — floodplains
  tracks **84** `.md` files, almost all `planning/archive/**`. Without `.nojekyll` every push runs
  Jekyll/Liquid over all of them; none contains `{{` or `{%` today, but one future planning doc
  quoting Liquid breaks the build, and Pages then keeps serving the **last good commit** — a
  silent stale-site failure a byte check on the wrong commit cannot see.
- **Enabling Pages before `index.html` is on `main` serves a Jekyll-rendered `README.md`**, not a
  404. Worse, because it looks like it worked.
- Byte-identical serving is already proven on the sibling: `shasum -a 256 index.html` equals
  `curl -sL <site> | shasum -a 256`. Pages serves the file verbatim once `.nojekyll` is present.

## Render determinism

The dominant source of churn is **knitr figures, and the fix is architectural, not a seed**. The
sibling never plots inline: a gated builder writes `fig/*.png` and both targets
`knitr::include_graphics()` it. A plotting chunk instead (a) lands the `.md`'s image in the
ignored `README_files/`, which 404s for everyone but the author, and (b) re-encodes the PNG each
render, so `index.html`'s base64 blob is only as stable as the graphics device.

Remaining sources: no `date:` field in either target (checked the sibling's rendered head — no
pandoc version, no `<meta name="date">`); `dpi`/`out.width` only affect `<img>` attributes and are
pinned; widgets/`sample()` are N/A with no htmlwidget but both seeds stay as a guard against a
future map. **The real limit is the toolchain** — identity holds within pandoc 3.9.0.2 /
rmarkdown 2.31 / knitr 1.51 / R 4.5.2; a pandoc bump rewrites the embedded bootstrap payload.

A sha compare alone **passes while `README.md` points at an image that 404s on github.com**, so
the check also asserts `git status --porcelain` is clean, and re-renders **twice** (a first render
that creates state and a second that reads it are different code paths).

## Why the elevation cross-section was dropped

Not mainly the `fl_dem_aoi()` fetch. `ff0N` is not a stage height: `fl_flood_depth`
IDW-interpolates a flood surface from stream-cell elevations and `fl_valley_confine` then
thresholds on `slope_threshold = 9`, `cost_threshold = 2500`, `max_width = 2000`
(`scripts/floodplain_lcc/02_floodplain_model.R:194-206`). At any transect the boundary is set as
much by the slope and cost gates as by depth, so three clean lines on a section would be a
simplification that **reads as the method** — #77's own failure mode aimed at a figure instead of
a number.

`config/<area>/flood_scenarios.csv` answers the same question better and needs no gate, no data
and no network: bankfull channel / flood-prone width / functional floodplain / valley bottom /
extended valley / channel migration zone, each with citations — and it surfaces a fact the README
states nowhere, that only `02`/`04`/`06` carry `run: TRUE`.

## Figures come from `data/bulk/`, not `data/neexdzii/`

`neexdzii` is deliberately excluded from every region roster
(`config/regions/skeena.yml`: *"NEEXDZII (subset of BULK) intentionally excluded"*), so a figure
of it shows ground that is not in the published catalogue. `data/bulk/` is the whole Bulkley
group, published as `bulk_co_ff04`, and it is the ground the field knowledge is about. Verified
present: `floodplain.gpkg` layers `co_ff02`/`co_ff04`/`co_ff06`, `aquatic_network.gpkg` layer
`streams_co3` (1,915 features in the neexdzii subset), and
`floodplain_landcover.gpkg` layer `transition_co_ff04_2017_2023` — **7,161 rows** carrying
`in_fire`, `fire_year`, `in_harvest`, `harvest_start_year_calendar`.

## `CLAUDE.md` has no closing soul marker

`CLAUDE.md:468` is `<!-- BEGIN SOUL CONVENTIONS — DO NOT EDIT BELOW THIS LINE -->` and there is
no closing line: lines 468–2729 of 2,729 are machine-managed by `/claude-md-init` and
`/claude-md-propagate`. The boundary rule must land **above** 468 or the next sync erases it.

## Errors Encountered

| Error | Resolution |
|-------|------------|
| | |
