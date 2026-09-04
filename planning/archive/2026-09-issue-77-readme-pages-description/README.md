# #77 — README rebuilt from README.Rmd, published via Pages, repo described

Closed by PR #78 (merge `5786053`). The repo now has a description, a homepage and a site at
<https://www.newgraphenvironment.com/floodplains/>, and `README.md` and `index.html` are both
rendered from one `README.Rmd`.

The rule the whole change turns on — **each repo states only what it owns, and neither restates
the other's numbers** — is in `CLAUDE.md` above the soul marker, and mirrored in
`stac_floodplains_bc`. Its downstream half is `stac_floodplains_bc#58`.

## Measurement

- The three claims the issue was filed over, all **true when they were typed**: "20 items live"
  against a collection serving **23**; "19 groups publish as 20 items" against **22 groups**; a
  Fraser roster of 10 against `config/regions/fraser.yml` listing **13**.
- A fourth nobody had noticed: the README's own BULK attribution percentages, 5 / 36 / 62 against
  a measured **4.2 / 30.3 / 65.5** over 1,565.1 ha of tree loss on the 2026-09-02 output. Fixed in
  `CLAUDE.md` and removed from prose — the numbers now exist only inside the figure that computes
  them.
- Four sets that a single "22 groups" would have collapsed: **configured** (22 + neexdzii),
  **published** (22), **re-runnable at flooded ≥ 0.5.0** (21), **provenance-carrying** (20 — the
  two missing are MCGR and PINE, exactly #76). Hence a roster of codes with no total.
- Attribution is concentrated in large patches: by count 1,984 of 2,101 tree-loss patches are
  unattributed (94%), by area 66%. The figure plots every centroid sized by area rather than
  dropping the small ones, which would show attribution as commoner than it is.
- `config/disturbance.yml`'s list order is precedence for single-cause reporting. Only 2 BULK
  patches carry both tags and reversing it still moves **36.31 ha** between fire and harvest.
- The served page hashes identical to the committed `index.html`
  (`649271503da62bef…`), and both render targets are byte-identical across re-renders.
- README 290 → 254 lines, gaining two figures, a Method section and a flood-scenario table it
  never had.

## Two premises in the issue that measurement disproved

- **The dead USDA VCA Toolbox URL is not in this repo.** `grep -rn 'usda|valley_confinement'`
  returns nothing; `README.md` carried five links, all `github.com/NewGraphEnvironment/*`. It
  lives in the sibling, already fixed. The real gap was the opposite: floodplains cited the
  valley confinement method *nowhere*, while `flood_scenarios.csv` already carried five citation
  keys per scenario that nothing rendered.
- **The acceptance criterion "every link resolves to itself, redirects followed" is satisfied by a
  404.** Measured before Pages existed: the homepage-to-be returned 404 with `url_effective`
  equal to the request. And a DOI needs the *opposite* treatment — it redirects by design, and
  both Wiley landing pages 403 even a browser user-agent, so DOIs are verified at Crossref.

Both were reconciled into the issue body before the merge rather than left contradicting it.

## The mechanism four review rounds converged on

Rounds found 7, 4, 7 and 9. Round 3 named what produced them:

> Each round replaced a literal with a value derived from one artifact **and introduced a new
> literal whose other half lives in a file the code never opens** — then wrote a comment asserting
> the agreement instead of a line checking it.

Three of those comments were measurably false: `BYPRODUCTS` claimed to be `.gitignore`'s list and
was missing two entries; the figure caption claimed to describe `config/disturbance.yml` while the
cause list was hardcoded; and `nzchar()` claimed to filter empty citation cells when `nzchar(NA)`
is TRUE and an all-empty column is a logical NA column, so `paste` produced the literal key `"NA"`.

Round 4 ran that as an **enumerated stop condition** rather than a judgement. It re-counted from
scratch — 29 artifact-dependent literals where round 3 had curated 22 — and found the axis the
earlier partition had missed: **literals inside strings that get *printed*** (figure titles,
subtitles, `fig.alt`) rather than inside values that get used. Two of its nine findings had been
introduced by round 3's own fixes.

One was a live bug. With the scenario set derived from config, `FIG_PRIMARY` had to be a *member*
of it and nothing checked; `ff[[primary]]` is `NULL`, and `geom_sf(data = NULL)` draws a
**zero-row layer with no error and no warning**. Reproduced end-to-end: the figure wrote
successfully at 373,719 bytes with the entire floodplain ribbon gone, under a subtitle still
naming a scenario. Reachable by moving `primary_scenario` in `area.yml`, or by flipping a `run`
column off — which the README itself describes as "a `run` column edit, not a code change".

Both figures rebuilt **byte-identical** through every round of that refactoring, which is the
evidence that the derivations reproduce exactly what the literals did.

## Wrong turns worth keeping

- **A `for` loop adding one `geom_sf` per scenario with `aes(fill = lab[i])` captures `i` lazily.**
  All three layers were labelled with the last scenario, so the detail panel rendered as one solid
  colour with a one-entry legend — twice, in two different colours depending on draw order. It
  looks exactly like a z-order bug.
- **`git status --porcelain` could not see the byproduct it was written to catch.** `.gitignore`
  lists `README_files/` five lines from the guard that was supposed to notice it. The check is by
  name now, with `--ignored` as the complement for anything nobody named.
- **The first widened catalogue-fact regex refused correct content.** Under `re.IGNORECASE`,
  `[NS]` in the latitude pattern matches lowercase `s` — seconds — so `0.39 s`, a figure from this
  repo's own notes, was rejected as a collection extent. Flags are per pattern now.
- **The elevation cross-section was designed, then dropped.** Not for its DEM fetch: `ff0N` is not
  a stage height, and at any transect the boundary is set as much by the slope and cost gates as
  by depth. Three clean lines would have been a simplification that *reads as the method* — this
  issue's own failure mode, aimed at a figure instead of a number. The `flood_scenarios.csv` table
  answers the same question from a file that moves when the model moves.

## Evidence

`planning/archive/2026-09-issue-77-readme-pages-description/review-*.md` — one plan review and
four code-check rounds, each with a disposition against every finding. `findings.md` carries the
measurements and the errors ledger.
