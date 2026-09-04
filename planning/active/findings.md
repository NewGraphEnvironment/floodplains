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
the check also asserts no byproduct directory was left behind, and re-renders **twice** (a first
render that creates state and a second that reads it are different code paths). It checks by
NAME, not with `git status` — see "Measured while building" below for why the porcelain form
could not see it.

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
| Detail panel rendered as one solid colour with a one-entry legend | `aes(fill = lab[i])` inside a `for` loop captures `i` lazily — every layer got the last scenario's label. Bind the scenarios into one frame with a factor whose level order is the draw order |
| Byproduct guard reported OK with `README_files/` on disk | `.gitignore` lists that exact path, so `git status --porcelain` is silent on it. Check the byproducts **by name** |
| `there is no package called 'patchwork'` (nor cowplot, gridExtra, ggspatial) | Lay the panels out with base `grid` viewports — a figure that only builds on the author's machine is what the gate exists to avoid |
| Both Wiley DOI landing pages return `403`, browser user-agent included | Not a dead link — bot protection. Verify the DOI at `api.crossref.org/works/<doi>` instead, which answers "is this identifier registered" |
| Description rejected at 353 characters | GitHub's cap is 350. Measure with `wc -c` before the PATCH; four trims to land it |
| Catalogue-fact guard refused `0.39 s`, a figure from this repo's own notes | Under `re.IGNORECASE`, `[NS]` in the latitude pattern matches lowercase `s` — seconds. Compile flags **per pattern**; that one case-sensitive |
| An empty-set guard added in round 1 was reproduced one axis over in round 2 | It guarded the UNION of both targets, so one target's extractor could go to zero silently. Guard per target, the way the sibling arm already did |

## Measured while building, not planned for

- **The README's BULK attribution percentages were themselves stale.** It stated fire 5% /
  harvest 36% / residual 62%. Recomputed from the current `data/bulk/` output (the 2026-09-02
  re-run under #65): **fire 4.2% / harvest 30.3% / not yet attributed 65.5%**, over 1,565.1 ha of
  tree loss. Only the 1,565.1 ha reconciles with `CLAUDE.md`; the three percentages there are
  stale by the same mechanism the README's were. So the fix is not to
  correct the number in prose: the number now lives **only in `fig/attribution.png`**, computed at
  figure-build time, and the prose says "about a third". One copy, regenerated with the figure.
- **Attribution is concentrated in large patches.** By count, 1,984 of 2,101 tree-loss patches are
  unattributed (94%); by area that is 66%. A map that dropped small patches would show attribution
  as commoner than it is, which is why the figure plots every centroid sized by area.
- **`git status --porcelain` cannot see the byproduct it is asked to catch.** Restoring a plotting
  chunk made `README_files/` appear on disk while porcelain still reported OK — `.gitignore` lists
  that exact path, five lines from the guard that was supposed to notice it. The check is by name
  now. This is "A guard's escape hatches are where it goes to die" with the escape hatch added in
  the same commit as the guard.
- **A `for` loop adding one `geom_sf` per scenario with `aes(fill = lab[i])` captures `i` lazily**,
  so all three layers were labelled with the LAST scenario: the detail panel rendered as one solid
  colour with a one-entry legend, twice, in two different colours depending on draw order. It looks
  like a z-order bug and is not. Fixed by binding the three into one frame with a factor whose
  level order **is** the draw order.
- **Both Wiley DOIs return 403 to a browser user-agent**, not just to a bot one, so fetching the
  landing page cannot verify them. Crossref answers the actual question — is this identifier
  registered — with a 200. A DOI also redirects by design, so "resolves to itself" is the wrong
  property for that one class.

## The mechanism behind three rounds of review findings

Rounds 1, 2 and 3 found 7, 4 and 7 issues. Round 3 named what produced them, and it is worth
more than any individual finding:

> Each round replaced a literal with a value derived from one artifact **and introduced a new
> literal whose other half lives in a file the code never opens** — then wrote a comment
> asserting the agreement instead of a line checking it.

Three of those comments were measurably false when checked:

| the comment said | the artifact said |
|---|---|
| `BYPRODUCTS` are the paths `.gitignore` names | `.gitignore` listed 5, the array listed 3, and `README.utf8.md` escaped **both** arms — unnamed by one, gitignored from the other |
| the figure shows what `config/disturbance.yml` lists | the cause list was a hardcoded `fire`/`harvest`; `pest` sits commented out in that file, and enabling it would have folded pest patches into "not yet attributed" under a caption claiming otherwise |
| `nzchar()` filters the empty `citations` cells | `nzchar(NA)` is TRUE, and an all-empty column is a **logical NA column**, not `""`. `paste` turns it into the literal key `"NA"` — `fp_readme_citekeys("kotl", "bt")` returned it |

The pattern is exactly the failure #77 exists to remove, reappearing inside the fix for it: a
number stated in one place and maintained in another. It is also why round 2's own two new
literals were both on the wrong side — a `"Three are modelled by default"` sentence under a table
that generates itself, and a seven-entry number-word vector indexed by a count from a six-row
CSV, one added scenario away from rendering `"NA of these are modelled by default"` with no error.

**The stop condition is an enumeration, not a judgement.** Every literal in the three files and
five chunks is partitioned: a **contract this repo chose** must be hardcoded, or the guard could
never fail — it would agree with whatever the artifact happens to say today; a **fact about a
third party** must be read from its artifact. Two are genuinely unavoidable — the collection id
`stac-floodplains-bc` (it lives in the sibling repo, and reading it from there would make the
guard depend on the thing it guards against) and `INBOUND_ANCHORS` (nothing in this repo can tell
you another repo's link has gone stale) — and both now carry a source-and-date stamp naming the
file that makes them true.

**Round 4 ran that enumeration as a stop condition, and it did not hold.** It re-enumerated from
scratch rather than trusting round 3's count, found **29** artifact-dependent literals where round
3 had curated 22, and named the axis round 3's partition had missed: *literals inside strings that
get **printed** — figure titles, subtitles, `fig.alt` — rather than inside values that get used.*
Nine were on the wrong side and **two had been introduced by round 3's own fixes**. One was a live
bug rather than a latent one:

> `FIG_PRIMARY` has to be a *member* of the scenario set round 3 made derived, and nothing checked
> it. `ff[[primary]]` is `NULL` when it is not, and `geom_sf(data = NULL)` inherits the plot's
> empty data and draws a **zero-row layer with no error and no warning** — the overview panel
> loses its entire floodplain under a subtitle still naming one. Reproduced end-to-end: the figure
> wrote successfully, 373,719 bytes, silent.

Reachable two ways, and the README invites the second: `primary_scenario` moving in `area.yml`
(a file `readme_functions.R` never opens), or the `run` column being flipped off — which this
README describes in its own words as *"a `run` column edit, not a code change"*.

The fixes derive `scen` from the CSV's own `scenario_id` rather than rebuilding it from
`flood_factor`, assert `FIG_PRIMARY` is in the run set, read the disturbance sources and the
colour words from one table, and key the display labels by area code so pointing `FIG_AREA` at
another group **stops** rather than titling MORR's figures "Bulkley". Every figure rebuilt
**byte-identical** through all of it, which is the evidence the derivations reproduce the literals
they replaced.

`config/disturbance.yml` gained one line it needed independently: **its list order is precedence**
for any single-cause reporting. Additive tagging means a patch can be both; the figure has to pick
one. Measured on BULK — only 2 patches carry both tags, and reversing the order still moves
**36.31 ha** between fire and harvest.

