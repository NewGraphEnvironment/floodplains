# Round 3 review — #77 README guards

Scope: `scripts/readme_content-check.py`, `scripts/readme_determinism-check.sh`,
`scripts/readme_functions.R`, and the `scenarios` / `scenarios-run` / `citekeys` / `roster` /
`figs` chunks of `README.Rmd`. Everything below was run (R 4.5.2, python3, `data/` present).

Verdict: **the class is NOT closed.** Seven instances, one of them a live wrong return value.

---

## The mechanism

Rounds 1 and 2 each fixed an instance by **replacing a literal with a value derived from one
artifact, and introducing a new literal that must agree with a second artifact nothing reads.**

| round | literal removed | literal introduced | must agree with | asserted? |
|---|---|---|---|---|
| 1 | one empty-set guard over the union | a per-target loop over `TARGETS` | the render's two outputs | no (3 copies) |
| 2 | `"Three are modelled by default"` | `c("Zero", …, "Six")` — 7 words | max rows in the CSV + 1 (today: 7) | **no** |
| 2 | one shared regex flag set | a per-pattern flag decision | nothing external | n/a — fine |
| pre-existing | — | `BYPRODUCTS` (3 names) | `.gitignore`'s byproduct block (5) | **no, and already disagrees** |
| pre-existing | — | `lv <- c("fire","harvest",…)` | `config/disturbance.yml` `sources` | **no** |
| pre-existing | — | `scen <- c("ff02","ff04","ff06")` | the CSV's `run == TRUE` set | **no** |
| pre-existing | — | `named` (3 citekeys) + `"Those three"` | the 3 prose bullets above it | **no, one-directional** |

So the invariant that keeps producing instances is not "a hardcoded number goes stale". It is:

> **Every literal in this pipeline is one half of an equality whose other half lives in a file the
> code never opens.** The fix each round applied — derive from the artifact — was applied to the
> half that was *visible in the diff*, and the new half was written as a comment asserting the
> agreement instead of a line checking it.

Three of those comments make claims that measurement contradicts (`nzchar`'s docstring,
`.gitignore` "lists exactly these paths", and the figure subtitle "fire and harvest are what
config/disturbance.yml lists today"). A comment is where an unenforced invariant goes to look
enforced.

**What would close it**, and it is enumerable rather than a feeling: for each literal, name the
artifact it must equal, and either read it from there or `stop()` on disagreement. I enumerated
**22** literals across the three files and the five chunks (table in §"Literal enumeration"); **5**
are on the wrong side. That set is small and finite, which is what makes "closed" checkable next
round rather than a claim.

---

## Findings

- **[bug]** `scripts/readme_functions.R:100` — `k[nzchar(k)]` does not filter the input its own
  comment says it is load-bearing for, because **`nzchar(NA)` is `TRUE`** and an all-empty
  `citations` column parses as **logical `NA`**, not `""`. Measured against the committed tree:

  ```
  fp_readme_citekeys("kotl", "bt")  ->  "NA"      (1 key)
  fp_readme_citekeys("ufra", "ch")  ->  "NA"      (1 key)
  ```

  20 of the 23 `config/*/flood_scenarios.csv` are in that state (`citations` NA on all 6 rows;
  only bulk, morr, neexdzii carry keys — that half of the comment is correct). The comment's
  stated mechanism ("an empty `citations` cell becomes `""`") is wrong, so the `""` case it
  demonstrates is not the case the data contains.

  The silent-wrong-number path is reachable without changing `FIG_AREA`: a single literal `NA`
  cell in an otherwise-populated column. Measured on a copy of `config/bulk/flood_scenarios.csv`:

  | mutation | `class(citations)` | keys | bogus key counted? |
  |---|---|---|---|
  | baseline | character | 12 | no |
  | one row's field blanked | character | 12 | no |
  | **one row's field set to `NA`** | character | **13** | **yes** |

  13 is what the README would publish ("Those three and **10** more"), and `named %in% keys`
  passes because all three named keys are still present. That is exactly the wrong derived number
  #77 exists to prevent.

  `paste()` stringifies NA before the filter sees it, so `is.na(k)` is useless downstream — the
  NA has to go before the `paste`. Verified fix (bulk 12→12, morr 12→12, kotl 1→**0**, ufra 1→**0**,
  and 0 then trips `named %in% keys` loudly, which is the correct outcome):

  ```r
  cit <- s$citations
  cit <- cit[!is.na(cit)]
  k <- unique(unlist(strsplit(paste(cit, collapse = ";"), ";")))
  k[nzchar(k)]
  ```

  Correct the comment to what was measured, not to what was reasoned.

- **[fragile]** `README.Rmd:341` — `cat("Those three and ", length(setdiff(keys, named)), " more…")`
  hardcodes `length(named)` as the word **"three"**. This is round 2's fix #3 (`"Three are modelled
  by default"`) reappearing 138 lines further down the same file, in the chunk whose own comment
  explains why `n - 3` would be one fact derived twice — the `n - 3` was removed and the `3` in
  the prose was left. Measured, adding a fourth paper to the Method bullets and to `named`:

  ```
  3 papers written out ->  "Those three and 9 more"   guard stops? FALSE
  4 papers written out ->  "Those three and 8 more"   guard stops? FALSE
  ```

  The count updates; the word does not; nothing fires. Fix: drive the word from `length(named)`
  (subject to the next finding).

- **[fragile]** `README.Rmd:207` — `c("Zero","One","Two","Three","Four","Five","Six")` has exactly
  **7** entries and `config/bulk/flood_scenarios.csv` has exactly **6** rows. Two lists that merely
  happen to agree, introduced by round 2's fix. Measured:

  ```
  n_run = 3 -> "Three of these are modelled by default"
  n_run = 6 -> "Six   of these are modelled by default"
  n_run = 7 -> "NA    of these are modelled by default"     <- no error
  ```

  A seventh scenario row turned on renders `NA` into the published page. `sum()` is also not
  `na.rm`, so one NA `run` cell reaches the same place by a different route. Guard the index
  (`stopifnot(n_run + 1L <= length(w))`) or format the number.

- **[fragile]** `scripts/readme_determinism-check.sh:43` — `BYPRODUCTS=(README_files index_files
  README.html)` names **3** paths; `.gitignore`'s README-byproduct block lists **5**
  (`README.html`, `README_files/`, `index_files/`, `*.knit.md`, `*.utf8.md`). The script's comment
  at line 18 asserts *"`.gitignore` lists exactly these paths"* — false in the tree as committed,
  which is the unenforced invariant stating itself as documentation.

  Arm 2 covers a hardcoded subset of the ignored set; arm 3 (`git status --porcelain`) covers the
  complement of the ignored set. A byproduct that is ignored **and** unnamed escapes both.
  Measured, with a plotted-figure byproduct and a knit intermediate on disk:

  | on disk | arm 2 (by name) | arm 3 (`--porcelain`) | `--porcelain --ignored` |
  |---|---|---|---|
  | `README_files/figure-gfm/plot-1.png` | caught | silent | caught |
  | `README.utf8.md` | **silent** | **silent** | caught |

  Complement fix, one word, and it makes arm 2 redundant rather than adding a fourth name to
  maintain: capture `git status --porcelain --ignored` for `before_status`/`after_status`.
  Measured stable — the ignored listing is byte-identical across the script's four renders, so it
  does not introduce noise (`data/` does not move during a render).

- **[fragile]** `scripts/readme_functions.R:205-206, 243` — `lv <- c("fire","harvest","not yet
  attributed")` and `tl$in_fire` / `tl$in_harvest` enumerate the overlays that
  `config/disturbance.yml` happens to list, while the figure's own subtitle claims to be
  *describing that file* ("fire and harvest are what config/disturbance.yml lists today — it takes
  any layer"). `disturbance.yml` carries a commented-out third source (`pest`, explicitly
  deferred), i.e. the addition is planned. Enabling it adds `in_pest` to the transition layer,
  `fire`/`harvest` still resolve, and every pest-attributed patch is silently folded into **"not
  yet attributed"** — publishing an under-count of attribution and an over-count of the residual
  in the one place those numbers exist. No error, no stale prose to notice.

  Fix: `lv <- c(vapply(yaml::read_yaml("config/disturbance.yml")$sources, `[[`, "", "name"),
  "not yet attributed")`, build the `in_*` lookup from it, and `stop()` if a named source has no
  `in_<name>` column in the layer. `PAL_CAUSE` needs the same treatment or a palette function.

- **[fragile]** `scripts/readme_functions.R:144` — `scen <- c("ff02","ff04","ff06")`, `PAL_FF`
  (3 colours) and the hardcoded subtitle **"one window, three scenarios"** must agree with the
  CSV's `run == TRUE` set. They do today (bulk/co: ff02, ff04, ff06). The README invites exactly
  the edit that breaks it — *"Turning one on is a `run` column edit, not a code change"* — after
  which the table says "Four", the figure still shows three, and its subtitle still says three.
  Derive `scen` from `fp_readme_scenarios()[run == TRUE, ]` and the subtitle from `length(scen)`.

- **[fragile]** `scripts/readme_functions.R:79` + `README.Rmd:186` — one area's scenario table is
  presented as universal. `fp_readme_scenarios()` reads `config/bulk/` for species `co` only,
  under prose that says *"the parameters live in `config/<area>/flood_scenarios.csv` — so this
  table is read from the file the model runs on"*. Measured across all 23 areas: the rendered
  columns agree everywhere — 18 distinct `(scenario_id, flood_factor, run, description)`
  signatures, exactly one per species × ff-level, each holding for every area carrying that
  species. So the table **is** representative today, by agreement, not by construction, and
  nothing asserts it. Turning `bt_ff08` on in `config/kotl/` makes "Three of these are modelled by
  default" false for kotl with no guard — #77's recurrence class moved from the time axis to the
  area axis.

  Cheap fix, same shape as the `named %in% keys` guard: read every
  `config/*/flood_scenarios.csv`, and `stop()` if the `(flood_factor, run, description)` triple
  disagrees across areas for any ff-level. Or name the area in the prose and drop the `<area>`
  placeholder.

---

## Answers to the specific questions

### 1. Literal enumeration and its (a)/(b) partition

(a) = a contract this repo chose, which must be hardcoded or the guard cannot fail.
(b) = a fact about a third party's behaviour, which should be read from the artifact.

| # | literal | file | class | verdict |
|---|---|---|---|---|
| 1 | `TARGETS` | content-check:44 | a | right — but the same pair is restated in `FILES` (determinism:37) and the `build` chunk; 3 copies |
| 2 | `CATALOGUE_FACTS` — 8 patterns | content-check:56 | a | right; these are the rules this repo chose |
| 3 | …the substring `stac-floodplains-bc` inside pattern 5 | content-check:61 | **b** | **wrong side, unavoidably.** A collection rename upstream disarms that arm silently. It cannot be read from an artifact here (restating the id is the forbidden thing), so it needs a source + date stamp, per code-check.md's vendored-witness rule |
| 4 | `re.I` present/absent per pattern | content-check:56-64 | a | right — round 2's fix; the one pattern without it is the one whose char class collides with a unit |
| 5 | `INBOUND_ANCHORS` | content-check:74 | **b** | **verified accurate today**: exactly one inbound anchor exists, `stac_floodplains_bc/README.md:29` → `…/floodplains#reading-the-outputs-experimental`, and no `github.io`/custom-domain deep link. Still a third-party fact with no drift signal — stamp it with the source path and the date it was checked |
| 6 | `gh_slug` + `GITHUB_PUNCT` | content-check:79-88 | b | right, and measured sound: all 11 README.md heading slugs are present verbatim in `index.html`'s pandoc ids (`have_md - have_html` is empty), so the "they agree by luck" caveat is currently true rather than aspirational |
| 7 | `SCRIPT_OR_STYLE` | content-check:97 | b | right |
| 8 | `DOI_PREFIX`, `CROSSREF` | content-check:76-77 | b | right — endpoints, no artifact to read them from |
| 9 | timeout 30 s, UA string | content-check:195-197 | a | fine |
| 10 | `FILES` | determinism:37 | a | right; duplicate of #1 |
| 11 | `BYPRODUCTS` | determinism:43 | **b** | **wrong side** — knitr/rmarkdown's byproduct names; must equal `.gitignore`'s block and does not. See finding 4 |
| 12 | the two `render()` calls + params | determinism:57-61 | a | right; duplicate of the `build` chunk in README.Rmd |
| 13 | `FIG_AREA`, `FIG_SPECIES` | functions:23-24 | a | right, documented |
| 14 | `FIG_INSET` | functions:29 | a | right, documented (a heuristic would churn the figure) |
| 15 | `PAL_FF`, `PAL_CAUSE` | functions:31-32 | a | right — except their **lengths**, which are #17 and #18 |
| 16 | `scen` + "three scenarios" subtitle | functions:144, 189 | **b** | **wrong side** — the CSV's `run` column owns it. Finding 6 |
| 17 | `lv`, `in_fire`, `in_harvest` | functions:205-206 | **b** | **wrong side** — `config/disturbance.yml` owns it. Finding 5 |
| 18 | `"transition_…_2017_2023"` | functions:202 | b | tolerable: a changed `change_interval` renames the layer and `fp_fig_read()` stops loudly |
| 19 | `paste0("streams_", FIG_SPECIES, "3")` — min_order 3 | functions:152 | b | tolerable, same reason (missing layer ⇒ stop) |
| 20 | number-word vector | README.Rmd:207 | **b** | **wrong side** — its length must equal max CSV rows + 1. Finding 3 |
| 21 | `named` + `"Those three"` | README.Rmd:338-341 | **b** | **wrong side** — the Method bullet list owns it. Finding 2 |
| 22 | parity numbers, 43.6%, 0.7% | README.Rmd prose | a | right — floodplains-owned, accepted |

Five on the wrong side: **#11, #16, #17, #20, #21**, plus #3 and #5 as unavoidable-(b) that need a
provenance stamp rather than a code change.

### 2. `blank_code` vs `strip_code` — fork, not divergence

Measured on the committed `index.html`: identical extraction, three ways.

```
strip==blank content?      False   (only whitespace differs: 572 vs 2106 newlines)
href="#…"   same set?      True
id="…"      same set?      True
https?://…  same set?      True
CATALOGUE_FACTS hits       []  under both
```

Both call the same `SCRIPT_OR_STYLE` regex, so the *removed* span is identical by construction and
the only difference is line preservation. **The divergence is not load-bearing and cannot become
load-bearing while both delegate to one regex** — so no arm's stripping can differ from another's
in a way that matters today.

It is a fork waiting to drift in the weaker sense: `blank_code` strictly dominates (line-preserving
*and* content-identical), so `strip_code` is redundant. Collapse to one function; the risk is not
the two behaviours, it is that a future edit to the removal rule has two places to land.

### 3. "Which targets, stripped how" is restated three times, in three shapes

- `check_anchors` — dispatches `t.endswith(".md")` → `anchors_md` / `anchors_html`, stripping
  hidden *inside* `anchors_html`.
- `check_catalogue_facts` — dispatches `not t.endswith(".md")` → `blank_code`, inline.
- `check_links` — dispatches `t.endswith(".md")` → `strip_code`, inline, in the argument position.

Three arms, three spellings of one rule ("HTML needs script/style removed; markdown does not"), and
each opens the file itself. A fourth arm has three examples to copy and no shared thing to reuse —
and the one property none of them share is the empty-set guard's wording, which is already
duplicated per arm.

Not a bug today. The one-line removal of the whole class: a `def source(t)` returning the
already-prepared text (`open(t).read()`, blanked when not `.md`), with each arm consuming it. That
also deletes the `strip_code`/`blank_code` fork from §2 and leaves exactly one place that knows
what a target is and how it is prepared.

### 4. One area's scenario table as universal — measured, and it agrees today

See finding 7. All 23 areas agree on every rendered column; the table is representative by
coincidence with nothing asserting it. Related: `fp_readme_citekeys()` inherits the same
`FIG_AREA`/`FIG_SPECIES` defaults, so the "9 more" is bulk-coho's 12 keys — which happens to be
every citekey in the repo (13 distinct repo-wide, and the 13th is the bogus `"NA"` from finding 1;
the true repo-wide set is 12 and identical to bulk's).

### 5. `named %in% keys` — reachable, fails toward stop, blind in one direction

Proven by mutation on a copy of the config (`opperman` deleted from every row):

```
[baseline]           renders: Those three and 9 more
[opperman removed]   STOP fired: opperman_etal2010EcologicallyFunctional
```

So the direction it guards — *prose cites something the config dropped* — works and stops the
render. The other direction — *prose cites something `named` does not list* — is unguarded, which
is the half that finding 2 is about: it is a one-directional set comparison written as if it were
a set equality. Closing it fully needs the Method bullets to be data rather than prose; the cheap
partial is finding 2's `length(named)` plus a count of the reference bullets in the rendered
Method section.

---

## Ran clean (no finding)

- `python3 scripts/readme_content-check.py` → OK anchors, OK catalogue facts.
- `CHECK_LINKS=1` → 9 of 10 URLs 200-and-self-resolving; the only failure is the accepted
  `https://www.newgraphenvironment.com/floodplains/` 404 (Pages enabled after merge). **No false
  refusals** — round 2's mirror defect (a guard rejecting correct content) does not recur here.
- `bash scripts/readme_determinism-check.sh` → all three arms OK, rc=0.
- The committed figures are **current**, measured against `data/bulk/`: `ff02/ff04/ff06` =
  345/387/415 km², and fire 66.1 ha 4.2% / harvest 473.5 ha 30.3% / residual 1025.4 ha 65.5%,
  matching `fig/attribution.png` exactly. Worth noting as a *fragility* rather than a finding:
  nothing regenerates or checks those numbers unless someone renders with `update_figs = TRUE` on
  a machine with `data/`, so #77's "true when it was typed" failure has been moved out of prose and
  into a binary where it is harder to see. The gate is a person remembering.

## Convergence

Not converged. The seven findings are one class, and the enumeration in §1 is what says so rather
than a feeling: 22 literals, 5 on the wrong side of the (a)/(b) partition, and the two that round 2
introduced (#20 the word vector, and the surviving `"Those three"`) are on the wrong side too — the
fix carried the defect forward one axis, twice, exactly as rounds 1→2 did.

Round 4 has a checkable stopping condition rather than a judgement call: re-derive the table in §1
and show that every (b) row either reads its value from the artifact or `stop()`s on disagreement,
with the two unavoidable-(b) rows (#3, #5) carrying a source-and-date stamp.
