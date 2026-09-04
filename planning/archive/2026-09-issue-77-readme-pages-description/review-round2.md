# Review round 2 — #77 (README.Rmd + three guards)

Target: the round-1 **fixes**. Everything below was reproduced on this machine (R 4.5.2,
python3, `data/` present, `fresh-db` up). Working tree restored after every mutation —
`README.md` / `index.html` / `README.Rmd` hash the same as before this review.

## Findings

- **[fragile] `scripts/readme_content-check.py`:58 (and :146) — the widened catalogue-fact
  pattern refuses correct floodplains-owned content.** `(r"\b\d{1,3}\.\d+\s*°?\s*[NS]\b", "a
  collection extent (latitude)")` is matched with `re.IGNORECASE` in `check_catalogue_facts`,
  so `[NS]` also matches lowercase `s` — i.e. **seconds**. Any decimal timing this repo writes
  is refused as a latitude. Proven end-to-end by appending one sentence lifted verbatim from
  `CLAUDE.md`'s own #40 note to `README.md`:

  ```
  FAIL: catalogue facts
    README.md:258: a collection extent (latitude) — '0.39 s'. This repo links to the
    catalogue; it does not restate it.
  ```

  Also matched: `"the run took 47.5 s"`, `"delivered in 2.5 s"`. This is the mirror defect
  `code-check.md` names under "A guard that fails toward pass" (stac_floodplains_bc#46): an
  assertion about the *data* where an *artifact* property was meant, refusing correct content
  and pointing the operator at the wrong rule.

  It is close to firing on the artifact, not just on future prose. `check_catalogue_facts` is
  the **only** one of the three checks that does not call `strip_code()`, so the whole embedded
  bootstrap/jQuery payload of `index.html` is in scope. Measured on the committed page: **30**
  CSS durations (`.15s`, `.2s`) sit one leading digit away from matching — `0` in front of any
  of them (a bootstrap or pandoc bump) fails the guard on a page that is fine.

  Fix: compile that one pattern case-sensitively (per-pattern flags, or `(?-i:[NS])`), and/or
  run `strip_code()` on HTML targets here as the other two checks already do.

- **[fragile] `scripts/readme_content-check.py`:154–164 — round 1's empty-set guard is over the
  UNION of both targets; `check_anchors()` guards per target.** Same defect class as round-1
  finding #1, one axis over. Measured today: `README.md` yields 10 URLs, `index.html` yields 7.
  Simulating a broken HTML extraction path (`strip_code` over-matching) gives:

  ```
    README.md: 10 urls
    index.html: 0 urls
  union: 10 -> empty-set guard fires? False
  ```

  So `index.html` can contribute nothing and the sweep still prints `OK: links`. That matters
  because the module docstring makes per-target difference the whole point of checking the
  rendered targets ("a link inside an `if (params$rmd_on)` branch exists in only one of the two
  outputs"), and because this is the opt-in arm — a silent pass gets no second chance. Fix:
  build the URL set per target and guard each, as `check_anchors()` does.

- **[fragile] `README.Rmd`:203 — "Three are modelled by default" is a hardcoded count sitting
  directly under the table that regenerates it.** The table comes from
  `config/bulk/flood_scenarios.csv` via `fp_readme_scenarios()`; the sentence does not. Three is
  correct today (`co_ff02`, `co_ff04`, `co_ff06` are `run=TRUE`; ff01/ff08/ff12 are FALSE), but
  a fourth `run=TRUE` row moves the table and leaves the sentence wrong with nothing to notice
  — the exact recurrence shape #77 exists to remove, reintroduced inside the change that removes
  it. One-line fix: `sum(s$run == "TRUE" | s$run == TRUE)` in the chunk, or drop the count.
  (The neighbouring "about a third of the tree loss" is the same shape but hedged and
  corroborated — measured 34.5% — so it is fine as written.)

- **[minor] `scripts/readme_content-check.py`:21 — the docstring still cites `drift >= 0.8.0`**,
  the exact wrong floor round-1 fix 6 corrected. `scripts/packages.R:22` and
  `scripts/floodplain_lcc/03_lulc_classify.R:33` both enforce **0.6.0**, and `README.Rmd`:267 now
  says 0.6.0. Nothing executes the docstring, but it is where the wrong number gets copied back
  from.

## Answers to the two questions round 1 left open

**Is the third arm of `readme_determinism-check.sh` reachable single-fault?** Yes — proven, not
argued. `git status --porcelain` reports status codes and paths, so it covers everything
non-ignored that the render can touch, of which `README.md`/`index.html` content is only a
subset. Single-fault construction: a chunk that writes a file which is neither a rendered target
nor a listed byproduct nor gitignored. Injected `writeLines('x', 'roster_cache.txt')` as an
`echo=FALSE, include=FALSE` chunk (so both rendered outputs stay byte-identical) and ran the real
script:

```
OK: README.md and index.html are byte-identical across two re-renders.
OK: rendering left no byproducts on disk.
FAIL: rendering changed what git sees:
15a16
> ?? roster_cache.txt
RC=1
```

Arms 1 and 2 green, arm 3 alone red. It is a guard, not decoration. (Baseline first: the
unmodified script is green on all three arms, 3.9 s, 4 renders.) Arm 1 also has its own
uniqueness — `porcelain` prints only `M README.md`, not its content, so a target that is
*already dirty* before the run and rendered to different-but-still-dirty bytes moves the sha and
not the status string.

**Are the arms mutually shadowing?** No. Both scripts **accumulate** rather than dispatch —
`readme_content-check.py:196-218` runs anchors, then catalogue facts, then links, each printing
its own `OK:`/`FAIL:` label and OR-ing into `rc`; `readme_determinism-check.sh:70-108` does the
same with three `if` blocks and one `rc`. That is the structure `code-check.md` prescribes, and
no arm can short-circuit another.

The residual caveat is the one `code-check.md` warns about and it is real here: a *single* fault
can fire *two* arms (mutating `README.md` fires sha + porcelain together), so `rc=1` alone never
identifies which arm fired. Every proof above was read off the printed label, never off the exit
code.

## Checked and clean (no action)

- **Fix 2, `k[nzchar(k)]`.** Verified against every config CSV. Two distinct empty shapes exist
  and both are handled: a *partially* empty `citations` column reads as `""` (filtered, the case
  the fix was written for), and an *all-empty* column — 20 of the 23 files — reads as an all-`NA`
  logical column, so `paste(collapse=";")` yields the single key `"NA"`, which then fails loudly
  at the `named %in% keys` guard in `README.Rmd`:327 exactly as the comment claims. Count is
  right: 12 keys, 3 named, README says "9 more". bulk, morr and neexdzii carry the identical
  12-key set, so the count is not an artifact of `FIG_AREA`.
- **Fix 3, false positives.** Swept the full rendered `README.md` and `index.html` — the only
  false positive is the seconds one above. `\bgroups\s+publish\b` / `\b\d+\s+(?:\w+\s+){0,2}items\b`
  matched nothing this repo legitimately writes; parity numbers, `flooded 0.5.0`, `drift 0.6.0`,
  `terra >= 1.8-10`, `43.6%`, `0.7% province-wide` all pass.
- **Fix 4, `INBOUND_ANCHORS`.** Grounded, not speculative:
  `stac_floodplains_bc/README.md:29` links
  `https://github.com/NewGraphEnvironment/floodplains#reading-the-outputs-experimental`. The slug
  `gh_slug()` derives from `## Reading the outputs (experimental)` matches it.
- **Fix 5, roster.** Renders 5 rows; `skeena` correctly appears twice (co: BULK, MORR / ch: KISP)
  rather than being merged. `list.files(pattern = "\\.yml$")` matches `run_region.R`:43, which
  also only ever builds a `.yml` path — no region file can be silently skipped.
- **CLAUDE.md's new BULK attribution numbers.** Recomputed from
  `data/bulk/floodplain_landcover.gpkg`, `transition_co_ff04_2017_2023`: 2,101 `Trees ->` patches,
  1,565.07 ha, fire **4.2%** / harvest **30.3%** / not yet attributed **65.5%**. Matches to the
  decimal, and the components sum to the total (no `NA` cause leaking out of
  `fp_fig_attribution`'s `ifelse`).
- **"coho and chinook networks are *identical* wherever both are modelled"** (`README.Rmd`:162) —
  a universal claim generalised from MORR, so I measured it. Province-wide over
  `fresh.streams_vw_bcfp` at `stream_order >= 3`, every watershed group where both species are
  modelled has **0** segments where `access_co > 0` differs from `access_ch > 0`. Claim holds.
- **Determinism.** `README.md` and `index.html` are byte-identical across two fresh re-renders on
  this machine, and identical to the committed bytes.
- **Links.** `CHECK_LINKS=1` returns exactly one failure, the accepted Pages 404. The two DOIs
  resolve at Crossref; the seven remaining URLs are 200 and self-final.
- **`fp_fig_floodplain()`'s `["geom"]`** — `data/bulk/floodplain.gpkg` really does name its
  geometry column `geom`, so the gated builder will not fail on that.
