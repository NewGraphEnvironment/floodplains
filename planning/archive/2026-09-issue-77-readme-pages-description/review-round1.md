# Code review — round 1 — staged diff for #77 (README.Rmd single source + three checks)

Reviewed the staged tree as of 2026-09-04 (13 staged paths, including `CLAUDE.md` and
`planning/*` which were staged part-way through this review). Everything below was verified by
running it; commands and measurements are inline.

---

## What I verified positively (so the findings are read against a known-good baseline)

- **The committed artifacts reproduce byte-identically.** Built an isolated sandbox containing
  only `README.Rmd`, `scripts/readme_functions.R`, and symlinks to `config/` and `fig/` — **no
  `data/`, no database, no network** — and ran both renders twice. `README.md` and `index.html`
  matched the staged blobs on sha256 after render 1 and again after render 2, and the directory
  was left with no `README_files/`, `index_files/`, `README.html`, `*.knit.md` or `*.utf8.md`.
  So the determinism check's central claim holds on this toolchain (rmarkdown 2.31, knitr 1.51,
  pandoc 3.9.0.2), and the "needs no data/DB/network" claim is demonstrated rather than asserted.
- **The gated figure cold path works and the committed PNGs are current.** Ran `fp_fig_build()`
  against `data/bulk/` with `FIG_DIR` redirected to scratch: both figures built in ~2 s and are
  **byte-identical** to the committed ones (`9097f0da…` attribution, `36362489…` floodplain).
  That is the one path a routine render never exercises, and it is not broken.
- **`fp_fig_read`'s implicit assumptions hold on the real data**: `co_ff02/04/06`,
  `subbasins`, `streams_co3`, `transition_co_ff04_2017_2023` all exist; the sf geometry column is
  named `geom`, so `clip(ff[[s]])["geom"]` resolves; `in_fire`/`in_harvest` are logical with
  **zero NAs** (7,161 rows), so the nested `ifelse()` cannot produce an `NA` cause that
  `aggregate()` would silently drop out of the percentage denominator.
- **The prose number is right.** "about a third of the tree loss" measures 34.5% (fire 4.2% /
  66.13 ha, harvest 30.3% / 473.54 ha, residual 65.5% / 1025.40 ha, total 1565.07 ha) — exactly
  the figures the `CLAUDE.md` hunk replaces 5/36/62 with.
- **`INBOUND_ANCHORS`' premise is real**, not assumed: `stac_floodplains_bc/README.md:29` does
  link `github.com/NewGraphEnvironment/floodplains#reading-the-outputs-experimental`.
- **Content check**: passes offline; with `CHECK_LINKS=1` the only failure is the accepted
  `https://www.newgraphenvironment.com/floodplains/` 404. The other 9 URLs resolve 200-and-self,
  and both DOIs come back registered at Crossref.
- **Shell hygiene in `readme_determinism-check.sh` is clean against the traps in
  `code-check-shell.md`**: `set -euo pipefail`; the explicit `if` in the byproduct loop rather
  than a bare top-level `&&` list (the comment naming that trap is correct); both arrays are
  non-empty literals so the bash-3.2 empty-array-under-`set -u` case cannot fire; no heredocs, so
  no code-span substitution; `cd "$(cd "$(dirname "$0")/.." && pwd)"` resolves to the repo root
  from any cwd; `diff <(…) <(…) || true` cannot take the script down.

### On the four proofs in the brief

- **sha arm** — sound, and I confirmed the direction your proof could not: it also passes on an
  unmutated tree, twice. One caveat worth recording: mutating `README.md` fires the sha arm *and*
  the `git status --porcelain` arm simultaneously (mutated tree is `M README.md` before, clean
  after). You quoted the sha arm's own message, which is the right discipline — but the run was
  not a single-fault proof, so the porcelain arm has not been separately exercised.
- **byproduct arm** — the strongest of the four, because it recorded the *discriminating*
  observation (porcelain said OK while `README_files/` sat on disk). That is what justifies
  checking by name.
- **catalogue-fact arm** — weak; see finding 3. The fixture sentence was written to match the
  patterns, so it shows the patterns fire, not that they cover the class.
- **anchor arm** — sound for detection, but see finding 4: on `index.html` it only ever
  exercises 2 of 15 ids.

---

## Findings

- **[bug] `scripts/readme_content-check.py:143–171` — `check_links()` has no empty-set guard, so a
  broken URL extractor prints `OK: links`.** `check_anchors()` has exactly this guard
  (`if not used: bad.append("…the extractor is broken, not the file")`); `check_links()` does not.
  Proven: with `links()` monkeypatched to return `set()`, `check_links()` returns `[]`, and
  `main()` then prints `OK: links (every URL returns 200 and is its own final URL)` with `rc = 0`.
  This is the checklist's *"An empty result set is not a pass — a loop over nothing exits 0"*, and
  it lands on the arm that is **opt-in and therefore run rarely**, so a silent pass has no second
  chance to be noticed. The extractor is also the fragile part — `r"https?://[^\s\"'<>)\]]+"`
  excludes six delimiters and is applied to `strip_code()`'d HTML — so "no URLs found" is a
  reachable state, not a theoretical one. One line fixes it:
  `if not urls: return ["no external links found at all — the extractor is broken, not the files"]`.

- **[bug] `scripts/readme_functions.R` `fp_readme_citekeys()` counts an empty `citations` cell as a
  citation key, silently inflating the README's derived count.**
  `unique(unlist(strsplit(paste(s$citations, collapse = ";"), ";")))` turns a blank cell into `""`,
  which survives `unique()`. Measured on `config/bulk/flood_scenarios.csv`: 12 keys today; blank
  **one** cell and it becomes 13 with `""` in the set. `README.Rmd`'s `citekeys` chunk then renders
  `Those three and 10 more` instead of `9` — no error, no warning, wrong number.
  This is not hypothetical: **20 of the 23 `config/*/flood_scenarios.csv` have all six `citations`
  cells empty** (only `bulk`, `morr`, `neexdzii` carry any), so blank cells are the norm in this
  repo and `FIG_AREA` happens to point at one of the three exceptions. It is the exact class #77
  exists to close — a number the README derives, and gets wrong. Fix: `k <- k[nzchar(k)]` before
  returning.
  (The *all*-empty case is safe — `keys` becomes `""`, `all(named %in% keys)` is FALSE and the
  render stops loudly. It is the *partially* empty case that is silent, which is the harder one.)

- **[fragile] `scripts/readme_content-check.py:48–55` — the catalogue-fact grep misses the
  phrasings most likely to recur.** Measured against 12 candidate sentences; **5 missed**:

  | sentence | result |
  |---|---|
  | `20 items live in the collection.` (the #77 wording) | CAUGHT |
  | `The catalogue currently serves 23 floodplain items.` | **MISSED** |
  | `23 STAC items are available for download.` | **MISSED** |
  | `Twenty-three items are live.` | **MISSED** |
  | `The collection holds items for 19 watershed groups.` | **MISSED** |
  | `The collection spans 48.9 N to 60.0 N.` | **MISSED** |
  | `The catalogue currently holds 23 items.` | CAUGHT |
  | `Extent: 48.99N to 60.00N.` | CAUGHT |

  `\b\d+\s+items\b` requires the digits **adjacent** to `items`, so one adjective defeats it — and
  an adjective is what a rewrite naturally adds. `\b\d{2}\.\d{2}…N\b` requires exactly two decimal
  places, so a one-decimal latitude passes. `\bcollection\s+version\b` matches the phrase, not the
  thing (`the collection is at version 1.4.0` passes). Since the guard's stated purpose is
  **recurrence** rather than today's wording, the gap is the point of the guard. Cheap widening
  that keeps the same shape: `\b\d+\s+(?:\w+\s+){0,2}items\b`, `\b\d{2}\.\d+\s*°?\s*[NS]\b`,
  `\bversion\s+\d+\.\d+\b` near a collection mention.

- **[fragile] `scripts/readme_content-check.py:104–105` — the comment in `anchors_html()` asserts
  coverage the artifact does not have.** It says *"A pandoc TOC links every section, so its own
  entries are in `used` too"*. Measured on the committed `index.html`: `toc_float: true` emits
  `<div id="TOC" class="tocify">` **empty** and builds the TOC at runtime in jQuery, so after
  `strip_code()` the only static `href="#…"` are the two body links. Instrumented:
  `index.html used: 2 have: 15` — the same two anchors the markdown arm checks. So the html arm
  covers 2 of 15 ids, and the docstring's rationale for checking each target separately
  (*"they agree on today's anchors, and that is luck rather than a property"*) is unreachable for
  the other 13. No false pass today, and functionally it is fine — tocify resolves ids at runtime,
  so a pandoc/GitHub slug divergence cannot break that TOC — but the comment is the thing the next
  person will read as coverage. Say what is actually true instead: the TOC is client-side, so only
  inline anchors are checkable, and `INBOUND_ANCHORS` is what covers the rest.

- **[fragile] `scripts/readme_functions.R` `fp_readme_roster()` — `y$species[[1]]` prints the
  region's first species *preference*, but the column is labelled "species".** `run_region.R`
  resolves per WSG (first listed species **modelled at ≥ `min_order`**), which is not necessarily
  the first listed. Today every group resolves to the first — `fraser.yml [ch, bt]` → `ch` for all
  13, `columbia.yml [bt, wct]` → `bt` for all 3 (that file explicitly documents `wct` as a
  fallback that never fires) — so the rendered table is correct. But the day a group falls through
  to the second preference, the README states the wrong species for it with nothing to notice,
  which is the same shape as the counts #77 was filed over. The function's docstring anticipates
  the *count* trap and not this one. Cheapest honest fix is the label: `species preference`, or
  one clause in the prose under the table.

- **[fragile] `README.Rmd:265` states `drift ≥ 0.8.0` while the file it cites as the source says
  `0.6.0`.** `scripts/packages.R:22` says `>= 0.6.0` and `scripts/floodplain_lcc/03_lulc_classify.R:33`
  enforces `< "0.6.0"` → stop. Three statements of one fact, two answers, in a sentence that ends
  `(see scripts/packages.R)`. Pre-existing — `git show HEAD:README.md:279` carries the same
  `0.8.0` — but it is being re-committed into the new single-source file, which is the moment to
  reconcile it. Nothing breaks today (installed drift is 0.8.0); the cost is a reader installing
  to the wrong floor, or the next person "fixing" `packages.R` upward.

- **[nit] `CLAUDE.md` (new README section) — "80-plus tracked `.md` files under `planning/`" is 75.**
  `git ls-files 'planning/**/*.md' | wc -l` → 75 (88 tracked `.md` repo-wide). Trivial, but the
  section it sits in is the one asserting that numbers must be derived rather than remembered.

---

## Explicitly checked and clean

- No secrets, no credentials, no shell injection surface. `check_links()` fetches URLs extracted
  from two committed files with a 30 s timeout and a fixed User-Agent; nothing is executed.
- No `.gitignore` entry hides a tracked artifact: `README.md`, `index.html`, `fig/*.png` and
  `.nojekyll` are all staged. `.nojekyll` is a legitimate empty file.
- `scripts/readme_content-check.py` and `readme_determinism-check.sh` are staged mode `100755`.
- `fp_fig_write()`'s `on.exit(dev.off(), add = TRUE)` closes the device on the error path; a
  builder failure propagates out of `fp_fig_build()` and aborts the render rather than leaving a
  half-written page.
- `ifelse(s$run == "TRUE" | s$run == TRUE, …)` in the `scenarios` chunk is correct for both the
  logical and the character forms `read.csv()` can return for that column.
- The determinism check's byproduct pre-check refuses rather than deleting a caller's file, and
  the post-check is by name — both correct, and the by-name choice is justified by measurement.
