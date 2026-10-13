# #117 branch review — round 1

Reviewer scope: `git diff main...HEAD` (index.html excluded), the changed files read in full, issue #117,
flooded#67 / flooded PR #77, flooded 0.7.0 NEWS, live `data/*/provenance.json`.

## Findings

- **[fragile] research/whole_fwa_floodplain.md:399-401 (diff hunk @@ -391) — the datum shift is stated with
  its sign reversed.** The new bullet says "PROJ 9.8.1 routes through WGS 84 (+1.13 m E, −0.61 m N near MORR,
  the grid move above)". flooded PR #77 defines that vector as **sf (PROJ 9.5.1) minus terra (PROJ 9.8.1)**
  ("sf (PROJ 9.5.1) minus terra (PROJ 9.8.1) is +1.13 m E, −0.61 m N, which matches the grid move the issue
  measured (+1.138, −0.612)"), i.e. old minus new. The same file, four lines up, says the 9.8.1 grid "sits
  ~1.1 m west and ~0.6 m north" of the old one, and the xmin pair it quotes confirms it
  (847157.099813 − 847158.237521 = −1.138 m). So what 9.8.1 did is −1.13 m E / +0.61 m N; the bullet
  attributes the opposite vector to it and calls it "the grid move above", which contradicts the sentence
  above it. Same reversal in the #117 issue body's Problem bullet ("PROJ 9.8.1 ... routes through WGS 84,
  about 1.3 m away: +1.13 m east, −0.61 m north"). Fix: say "sf minus terra: +1.13 m E, −0.61 m N" or
  "9.8.1 moves the grid 1.13 m W, 0.61 m N".

- **[fragile] CLAUDE.md:168 (#108 bullet, not touched by the diff) — a present-tense parity claim the
  re-baseline made false.** "neexdzii carries them from a full step 3, which reproduced parity: 770.0 ha,
  2,032 patches, and the transition `outputs_hash` byte-identical." This branch re-ran neexdzii step 3:
  `data/neexdzii` now holds 2,018 patches / 773.43 ha tree loss, transition digest
  `sha256:6d3df685…`, and a rebuilt composition. The branch updated the contract in CLAUDE.md:644,
  README.Rmd, run_area.R and area.yml but left this sentence, which still reads as describing what
  neexdzii carries. Either date it ("…from a full step 3 on 2026-10-02, which…") or point at the new contract.

- **[fragile] README.Rmd:337 and CLAUDE.md:739 (Prerequisites, not touched) — no flooded floor stated,
  while step 2 now hard-stops below 0.7.0.** Both list bare `flooded` (and `terra` ≥ 1.8-10, though flooded
  0.7.0 requires terra ≥ 1.9-25 per its NEWS and this branch's packages.R comment). `drift`'s correctness
  floor is spelled out in the same paragraph; flooded's new reproducibility floor is the one a machine set
  up from these docs will hit as an abort in step 2. (README.Rmd's line also still says `drift` ≥ 0.6.0,
  pre-existing.)

- **[fragile, minor] scripts/floodplain_lcc/fp_provenance.R:1006 — comment claims more than the code it
  cites.** "`gdal_terra` / `proj_terra`, the names the in-place repair record already uses": the repair
  record (`fp_prov_reconcile_late`, line ~457) carries `terra` and `gdal_terra` only, no `proj_terra`.

## Checked and clean

- `fp_toolchain()`: `terra::gdal(lib = "all")` on terra 1.9.50 returns a 1-row data.frame with
  `gdal`/`proj`/`geos`/`TBB`; `tg[[k]][1]` reads it correctly. Live neexdzii record carries
  `gdal_terra 3.13.0 / proj_terra 9.8.1` beside sf's `3.8.5 / 9.5.1`. NA → JSON `null` → `NULL` on
  `read_json(simplifyVector = FALSE)`, which the new NA arm handles.
- Restored the defect in a temp copy (`gdal_terra = pick("GDAL"), proj_terra = pick("PROJ")`): offline
  `provenance-check.R` goes FAIL on "fp_toolchain()'s gdal_terra/proj_terra are terra's (3.8.5 / 9.5.1)".
  Guard fires.
- Date gate: `prov_step_time()` mirrors `fp_prov_restamp()`'s own rule (`reps[[1]]$previous_datetime_utc`,
  always written by the writer at fp_provenance.R:360). All stamps use `FP_PROV_TS_FMT`
  (`%Y-%m-%dT%H:%M:%SZ`), so string comparison is order-correct. Scanned every `data/*/provenance.json`:
  the only floodplain/landcover entries with a step time ≥ 2026-10-13T22:00:00Z are neexdzii's four, all
  carrying both keys; necr/kotl (repaired 09-05) resolve to their 09-05 step time. No hole found. The
  composition sibling is not covered by `viol_split`, but it warps no raster.
- No other consumer pins the toolchain key set: `provenance_ab-compare.R` does not read it; the probe
  scripts build their own signatures; `stac_floodplains_bc` does not read `run.toolchain`.
- `attribute_tag.R` grid guard: evaluated on live rasters — neexdzii (res 30, origin %% 30 = 0) passes;
  morr (30.43, 18.24/4.21) and dunc (30.17, 21.79/17.16) are refused. `all.equal` against `c(0,0)` falls to
  absolute tolerance, fine for integer-valued Albers origins.
- 02 floor sits before any write (after `fp_whole_network_validate`).
- Rebaseline log numbers re-derived from `data/neexdzii`: 2,018 patches; Trees 788 patches / 773.43 ha;
  `co_ff04` 157,822 valley cells of 3,474,262 at 30 m (= 142.040 km²); `co_ff02`/`co_ff06` 144,228 /
  165,698; DEM digest `192ea21e380f…` shared by all three scenarios; network 1,915 segments, streams digest
  `1f88bf8b…` matching the 2026-10-02 log; old valley cells 141,504 / 161,555 match the 10-02 provenance-check
  log. Toolchain line (incl. sf GEOS 3.13.0) matches the record.
- Issue/PR numbers introduced resolve to on-topic titles: #53, #80, #110, #117, #120, #122, #125, #126,
  flooded#67, flooded#78, link#328 (closed 2026-10-13, title "Build DUNC into fresh_default"). flooded 0.7.0
  NEWS supports +0.17% (MORR) and −0.6% (Parsnip); flooded#67 supports 0.12 mm and 35,679.2 ha.
