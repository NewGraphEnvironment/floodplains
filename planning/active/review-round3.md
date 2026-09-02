# Round 3 code-check — branch `64-nge-landcover-key-hashes-the-geotiff-con`

Reviewed: `scripts/floodplain_lcc/{fp_provenance.R, provenance-check.R, 02_floodplain_model.R,
03_lulc_classify.R}` and the `CLAUDE.md` hunk, against `main`.

Everything below was measured, not read. Baseline: the suite is green on HEAD
(`Rscript scripts/floodplain_lcc/provenance-check.R` → PASS, exit 0; with `neexdzii` → PASS).
R 4.5.2, terra 1.9.34, GDAL 3.8.5.

---

## Findings

- **[severity: bug]** `provenance-check.R:63` — `KEYS_TOOLCHAIN` is a literal that nothing pins to
  `fp_toolchain()`, so a member can be **renamed or dropped from the producer with the entire
  offline suite still green**. This is round 2's own finding, one axis over: round 2 pinned the
  sibling literal on the very next line (`SECTIONS_WITH_RASTERS`, line 64) via
  `prov_sections_writing_toolchain()`, and left line 63 matched to its producer by coincidence.

  Measured — two mutations of `fp_provenance.R:559`, each run through the full script:

  | mutation to `fp_toolchain()` | offline suite |
  |---|---|
  | `gdal = pick("GDAL")` → `gdal_version = pick("GDAL")` | **PASS** |
  | `gdal = pick("GDAL")` deleted entirely | **PASS** |

  Why it matters rather than being tidiness: `viol_split()`'s "toolchain missing: …" arm only fires
  against a *parsed provenance.json*, i.e. §7, which is opt-in on an area argument and only sees the
  loss **after** a real area has been re-run under the broken code — after the record has already
  been written without it. GDAL is the field the whole #64 cross-machine investigation turned on, and
  the guard's own comment (lines 57–62) calls the toolchain "the ONLY provenance field with no drift
  protection". Round 2 closed *whether a producer writes the block*; nothing closes *what the block
  contains*.

  One offline line, no database, no raster, verified in both directions (HEAD `TRUE`; both mutants
  `FALSE`):

  ```r
  check(setequal(names(fp_toolchain()), KEYS_TOOLCHAIN),
        "KEYS_TOOLCHAIN matches what fp_toolchain() actually returns")
  ```

- **[severity: bug]** `provenance-check.R:185-187` — `viol_coverage()`'s digest arm is
  `all(is.na(unlist(inp[["classified_content_sha256"]] %||% NA)))`, which cannot see a **single**
  year whose digest is missing. Two mechanisms compound, and the second is the one that is not
  obvious: `all()` requires every year to be absent, *and* `unlist()` **drops** a JSON `null`
  outright. `fp_prov_write()` serializes `NA` as `null` (`na = "null"`), so on a real file the
  missing year is not even a counted `NA`.

  Measured round trip through `toJSON(na = "null")` → `fromJSON(simplifyVector = FALSE)`:

  ```
  {"2017":"sha256:11","2020":null,"2023":"sha256:22"}
  unlist(d)                      -> "sha256:11" "sha256:22"   (length 2, not 3)
  all(is.na(unlist(d)))          -> FALSE        # not reported
  any(is.na(unlist(d)))          -> FALSE        # also not reported — the null is gone
  ```

  This is reachable: `fp_raster_content_sha256()` returns `NA_character_` whenever the file is
  absent or 0 bytes, which is precisely the "the writer produced nothing and the record says it did"
  case the guard exists for. The §5 must-fail fixture (`nh`, line 373) sets *all* years to `NA`, so
  it cannot distinguish `all` from `any` — the fixture-cannot-reach-the-failure-mode shape.

  Contrast the `item_ids` arm four lines below (188–190), which iterates `names(ids)` and reports a
  named year. The digest arm — described in its own message as "the only field that can move" —
  should do the same:

  ```r
  d <- inp[["classified_content_sha256"]]
  unlist(lapply(names(d), function(y)
    if (is.null(d[[y]]) || all(is.na(unlist(d[[y]]))))
      sprintf("landcover[%s] year %s has no classified raster digest", e$key, y)))
  ```

  Related and uncovered by any check: nothing asserts that the digest year set equals the
  `years` / `item_ids` year set, so 2 digests recorded for a 3-year run passes.

- **[severity: fragile]** `provenance-check.R:605-617, 642-648` — the comment claims
  `prov_sections_writing_toolchain()` reads the raster-writing set "off the producers rather than
  listed by hand … A literal set here would match the producers by coincidence and stop covering a
  section added later". Its **argument is a hand-written literal** of (file → section) pairs, so the
  scope is still a coincidence — moved one level, not removed.

  Measured (defect restored in a scratch copy): adding `toolchain = fp_toolchain()` to
  `01_network_extract.R:299`'s run block leaves §6 green at
  `every raster-writing producer still records run$toolchain (found: floodplain, landcover)`. A
  section that becomes raster-writing is invisible to §6 *and* to `viol_split()`, which gates on
  `SECTIONS_WITH_RASTERS`.

  The residual is small and nameable, which is what should be said rather than claiming derivation:
  `fp_prov_set()`'s `stopifnot` closes the section set to {network, floodplain, landcover}, so the
  only uncovered case is **the network section (01) becoming raster-writing**. The opposite
  direction is safe — adding `"network"` to `SECTIONS_WITH_RASTERS` without adding it to the
  candidate list makes `setequal` go red.

  Either enumerate the candidates instead of listing them —
  `list.files(dir, pattern = "^[0-9]{2}_.*\\.R$")` crossed with the closed section set — or replace
  the claim in the comment with the residual.

  The construct itself is **correct** — I checked each part the review brief asked about:
  `vapply(names(x), step, "")` returns `character(1)` full paths (`step()` is
  `file.path(dirname(--file=), f)`); `setNames(as.list(unname(x)), …)` maps path → section as
  intended, and `names<-` discards the names `vapply` attaches; `|>` and `\(x)` are R ≥ 4.1 and the
  native pipe is already used in `scripts/packages.R`, `01/02/03_*.R` and `fp_disturbance.R`, so
  they add no new floor. A plainer equivalent exists
  (`setNames(list("floodplain","landcover"), c(step("02_…"), step("03_…")))`) but that is style.

- **[severity: fragile]** `provenance-check.R:310-312` — the "network is not required to carry a
  toolchain" check is a **no-op mutation**. `good_prov()` gives `network$co3$run` as
  `list(datetime_utc = …)` with no `toolchain`, so `b9$network$co3$run$toolchain <- NULL` leaves
  `b9` `identical()` to `g` (measured). The assertion therefore restates line 273's clean-fixture
  check rather than independently exercising the exemption. It is not harmful — it does go red if
  `"network"` is ever added to `SECTIONS_WITH_RASTERS` — but it does not test what its message says,
  and the surrounding block's whole discipline is that each arm is shown able to fail.

- **[severity: fragile]** `fp_provenance.R:241-242` — a measured claim that does not measure.
  "What IS independently provable is the second line, and §5d fails three checks without it."
  Measured, by deleting each line from `fp_norm_block()` and running the suite:

  | mutation | §5d failures |
  |---|---|
  | `v[is.na(v)] <- NA_real_` deleted | **2** |
  | `as.double(v)` deleted | 0 (as documented — subsumed) |
  | both deleted | 3 |

  Three is the both-deleted number, not the second-line number. Trivial in isolation; flagged only
  because the file's persuasiveness rests on its figures being checkable, and this one is.

---

## Verified correct (round 2's two fixes, and what I probed around them)

Both round-2 fixes go red under a restored defect — I did not take the author's word for it:

| restored defect | result |
|---|---|
| `serializeVersion = 2L` stripped from `fp_raster_content_sha256()` | §5c **FAIL** "the digest is pinned to serializeVersion 2" |
| `toolchain = fp_toolchain()` removed from **both** 02 and 03 | §6 **FAIL** "(found: NONE)" |
| removed from **03 only** | §6 **FAIL** "(found: floodplain)" |

- **§5c option handling is sound.** `options()` is restored at line 513, *before* the `check()` at
  514; `a` is written at 457 and `unlink(d)` is at 517, so the file is still on disk. A throw inside
  `fp_raster_content_sha256()` under `serializeVersion = 3L` halts the Rscript (`Execution halted`,
  exit 1) rather than leaking a poisoned option into later sections. Moving the pin into the
  `requireNamespace(terra)` block does **not** create a silent skip: the `else` branch calls `bad()`.
- **`prov_keys(part = "run")` is safe.** Measured: `[[` on a `call` with a character index does
  **exact** matching — `quote(list(inputs=…, run_note="x"))[["run"]]` is `NULL`, so the `$`
  partial-match trap this file documents does not reappear here. An absent `run` yields `NULL` →
  `character(0)` → the section drops out of `writers` → `setequal` red. Right direction.
- **No double-count between `find_calls(target,"list")` and `find_calls(target,"fp_prov_run")`.**
  For `part = "run"` the target is `fp_prov_run(toolchain = fp_toolchain())` — no nested `list` call,
  so the first returns empty. For `part = "inputs"` in 03 the target is `c(list(…), lc_items)` and
  only the one `list` call is found. §6's three `drift1` checks are green at 9/20/19 keys, which is
  the positive control for that.
- **The core #64 property holds end to end, not just on the fixture.** The three digests recorded in
  `data/neexdzii/provenance.json` reproduce **exactly** from the on-disk rasters — with the
  `.aux.xml` sidecars now present (they were not when the run wrote them), with the sidecar removed,
  and under both `GDAL_PAM_ENABLED=YES` and `=NO`. That is the storage-type axis
  (`double`+`NaN` vs `integer`+`NA_integer_`) the normalization exists for, exercised against real
  data rather than a fixture.
- **`as.double()` really is subsumed** (accepted tradeoff, not re-flagged): measured,
  `v <- c(1L,2L,3L); v[is.na(v)] <- NA_real_` promotes to double even though the index selects
  nothing, so the documented reasoning is accurate.
- **CLAUDE.md's factual claims check out.** `stac_floodplains_bc/scripts/fp_provenance.R:50` does map
  `landcover_key = c("inputs", "item_hash")`; §5c does pass with both normalization lines deleted
  (measured — 3 failures, all in §5d), which is the stated reason §5d exists. Minor: the prose says
  "`terra`, `sf` and GDAL are now recorded" where the code also records GEOS and PROJ.
