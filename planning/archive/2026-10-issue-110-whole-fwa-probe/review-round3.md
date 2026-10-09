# Review round 3 — #110 whole-FWA probe (branch diff dc77486...HEAD)

Probed on copies in a scratch dir (`mktemp -d` under the session scratchpad); nothing in the repo
or `data/morr/` written except this file. DB probes were read-only (`fresh.log`,
`fresh.log_recompute`, and a VALUES CTE).

## Mechanism

Every finding in rounds 1–2 has one shape: **a report figure is trusted because a file or row with
the right NAME exists now, not because something the producing run wrote binds it to that run.**
Each fix so far closed it for one input by adding a tie, and the ties themselves are mostly
*proxies read from a mutable store at report time* (a count, an mtime, "the newest row"). Round 3
audits those ties: the ones that bind by content hold; the ones that read "now" from a store that
can move independently — `fresh.log`, `provenance.json`, `config/` — still fail toward pass, and
two inputs (the anchor's verdict and toolchain, and the scenario each mode ran) were never in the
enumeration at all.

## Enumeration audit

| input read by `fp_wf_report()` / the modes | tie | holds? |
|---|---|---|
| `logs/<mode>.log` RSS | `PROBE_DONE <mode>` in that log AND log mtime ≥ mode json | **holds**. All 10 logs carry one `PROBE_DONE`; 5.log 02:22:06.57 > arm5_timing 02:22:06.49. Max RSS 9.30 GiB (5.log), so "≤ 9.3 GiB in every stage" is right |
| `arm<k>_timing.json` ↔ `arm<k>_floodplain.tif` | content digest | **holds** |
| `arm<k>_waterbody.tif`, `arm<k>_by_blk.gpkg` | mtime order + by_blk rows = `attr_rows` | holds (proxy, but a partial re-run breaks the order) |
| `dem.json` ↔ `dem_common.tif` ↔ every arm | digest | **holds** |
| arm segment counts / `seg$n_groups` vs `dem.json` | count | holds as a count |
| `reach.json` ↔ arm floodplains | `valley_cells` count only | holds on this data: probed, every coho-reach cell of all 5 arms lies inside that arm's floodplain (0 outside), and arm 5's re-run reproduced 385,021 cells. Still a count, not a digest |
| `arm<k>_coho_reach.gpkg` ↔ `reach.json` | rasterized cell count | holds |
| `anchor.json` ↔ `anchor_floodplain.tif` | digest | holds |
| **`anchor.json` verdict** (`network_match`, `*_match_replay`) | **none — printed, never gated** | **FAILS toward pass** (finding 2) |
| **anchor's toolchain** | **not in `vsig`** (anchor.json has no `sf` key) | **missed** (finding 2) |
| **network re-read per mode** (`reach` has no count) | newest `fresh.log` MORR `run_uid` = provenance.json's | **FAILS toward pass** three ways (finding 1) |
| **scenario / VCA parameters per mode** | **none** — `tm[[k]]$scenario` recorded, never read | **missed** (finding 3) |
| `fresh.streams_vw_bcfp` (habitat), `net` for panels | live at report time | accepted (stated) |
| `provenance.json` (uid_rec) | read "now" | part of finding 1 |

## Findings

- **[bug — fails toward pass]** scripts/floodplain_lcc/floodplain_probe-report.R:86-99 — the
  `run_uid` tie that round 2 made the sole guard for the `reach` mode's network (and the window
  between modes) has three holes:
  1. `ORDER BY date_end DESC NULLS LAST`. link inserts the `fresh.log` row at START with
     `date_end` NULL and leaves it NULL on failure (`link/R/lnk_log.R:881-886`; one such row exists
     today, FRCN). So a MORR rebuild that is in flight, or that died after rewriting
     `fresh.streams`, sorts LAST, and the old completed row is picked → MATCH. Probed with a VALUES
     CTE of exactly those two rows: the query returns the old `run_uid`. Order by `date_start`.
  2. `lnk_access` recompute surgically UPDATEs `fresh.streams_access` (`link/R/lnk_access.R:199-240`)
     and logs to **`fresh.log_recompute`**, not `fresh.log` (MORR has one, 2026-09-02 01:45). A
     recompute during the probe changes `access_co` — i.e. arm 5 and the `reach` mode's coho seeds,
     the whole supersession measure — with no `fresh.log` row. The segment-count ties catch it only
     between `dem` and an arm mode; `reach` has no count.
  3. `uid_rec` is read from `provenance.json` NOW. If step 1 re-runs on MORR after a rebuild during
     the probe, provenance and `fresh.log` move together and match, while the arms read the old
     network. The anchor should record the `run_uid` it validated in anchor.json, and the report
     compare against that, not the mutable record.
  Cheapest content fix that closes all three: record `fp_table_content_sha256(s5, KEY, VAL)` in
  reach.json (and each arm json), and require it to equal `anc$network`.

- **[bug — fails toward pass]** floodplain_probe-report.R:46, 52-56, 354-358 /
  floodplain_probe-whole-fwa.R:202-219 — the report never gates on the anchor's verdict. The
  anchor mode writes anchor.json (with `floodplain_match_replay = FALSE`) BEFORE its final `stop()`,
  and the report only digests `anchor_floodplain.tif` against `anc$floodplain` and prints
  `yn(...)`. A failed anchor followed by modes run individually (how arm 5 was re-run, and how the
  runner accepts a mode list) produces a full rule table with "floodplain: DIFFERS" in one line.
  Separately, anchor.json carries `flooded/terra/terra_gdal/sf_gdal` but no `sf`, so it is excluded
  from the `vsig` toolchain check: an anchor run before a flooded/terra upgrade "proves" arms run
  after it. (Today's values match, and `delineate()`/the SQL are unchanged since 08cc056, which the
  anchor ran on — verified by diff, not by anything the report checks.) Fix: `stop()` unless
  `network_match && dem_match_replay && floodplain_match_replay`, and add `vers()` to anchor.json and
  its signature to `sigs`.

- **[fragile — missed input]** floodplain_probe-report.R (no reference) /
  floodplain_probe-whole-fwa.R:60-63, 302 — the scenario each mode ran is never tied. Every arm
  json records `scenario`; the report never reads it, and dem/reach/seg record none. `reach` and
  `seg` take `max_width`/`cost_threshold` from the scenario row at THEIR run time, and a
  `flood_scenarios.csv` edit between modes is recorded nowhere. `Rscript … morr 3 co_ff06` (args[3]
  is supported) overwrites arm 3 with an ff06 delineation; every existing tie still passes (same
  DEM, own digest, same segment count; `reach` re-run records whatever valley it sees) and the report
  titles it `co_ff04`. Fix: compare every `tm[[k]]$scenario` to `scen_id`, and record the scenario
  row's parameters in every json.

- **[bug — verdict does not follow from the registered rule]** research/whole_fwa_floodplain.md:57-59
  vs :143-145, :170-186 — criterion 3 as pre-registered reads "in the hillshade review of
  **order-1 additions**, the majority of panels are read as valley floor", for any candidate floor.
  The registered evidence is `panel_1..6`, and the preliminary read of those is "majority do
  **not** read as valley floor". The Recommendation then (a) states "Floor: order ≥ 2" flatly and
  (b) redirects criterion 3 to "the user's read of `panel_order2_*`" — panels the file itself says
  were "drawn as evidence outside the registered criterion". Under the text as registered, the
  preliminary outcome is: no floor below 3 passes, the recommended floor is order ≥ 3, and its
  moved share is **1.6% ≤ 2%, i.e. NOT superseded** — the opposite of "Existing items are
  superseded, not extended … #104 must plan a republish" (:183-186), which is stated
  unconditionally. Even on the charitable reading (criterion 3 means "the floor's own additions"),
  the rule says a floor is recommended "only if all three hold"; with 3 pending, both the floor and
  the supersession verdict are pending, and the table's "pending" for order ≥ 2 vs "pending;
  preliminary no" for order ≥ 1 should be stated as conditional in the Recommendation. Either
  state both verdicts as conditional on criterion 3, or record (dated, as the Method correction
  was) that criterion 3 is being read per floor — a change to a registered rule after its results
  were read.

- **[minor — number not in any artifact]** research/whole_fwa_floodplain.md:90-91 — "825 s with the
  fallback" comes from the superseded arm-5 run (round 1), whose 5.log was overwritten by the re-run.
  No committed or on-disk artifact carries it; the current figures are 829.9 s (arm 5, 340 groups,
  `complete = TRUE`) and 5.0 s (reach.json arm 5, one group, `complete = FALSE`). Cite those.

- **[minor — range]** research/whole_fwa_floodplain.md:113-114 — "a minority of each floor's added
  area (12–27%)". Over the three floors (1_vs_2, 2_vs_3, 4_vs_3) the waterbody share of added area is
  13.8 / 19.7 / 12.0%, so 12–20%; 27% (26.5%) is 3_vs_5, order ≥ 3 over the coho network, which is
  not a floor.

Checked and sound: every other number in Results and Recommendation against the committed
`20261009_*.md` (cost table, fit, seg rate, area pairs, supersession table, habitat shares 308.4 /
1,224.8 km, rule and grain tables, 36 vs 20 min, 33 → ~20 min); review.gpkg patch stats re-derived
from a copy (6,621 order-1 patches, 4,301 < 1 ha holding 7.9%, 72.7% in ≥ 5 ha, top two 233.0 and
229.7 ha); FP_WF_RULE thresholds and comparison operators match the registered text. Post-run
commits: the panel loop rewrite reproduces the old order-1 draw sequence under `set.seed(110)`
(order 1 sampled first, same `sample()` calls), `bbx()` fixes the `c(name = x)` trap, and the
relabel (5d3fa4f) is label/comment only and was committed before arm 5's re-run started (02:06:53
vs 02:06:56). No bugs found in them.

## Disposition (main session)

Mechanism (reviewer's): ties that read "now" from a mutable store pass when both sides move
together; ties by content hold. Every "now" read in the enumeration was replaced or gated:

| finding | disposition |
|---|---|
| `run_uid` tie: in-flight/failed run sorts last; recompute logs elsewhere; provenance.json read now | replaced by a window check: no `<schema>.log` or `<schema>.log_recompute` row for the group with `date_start >= t0 OR date_end >= t0 OR date_end IS NULL`, t0 = earliest driver start stamp of a mode the report reads. Predicate tested on a VALUES CTE (old completed run passes; in-flight, old-open, recent, ended-inside all refuse). Fails closed on a missing table |
| anchor verdict never gated; anchor toolchain not compared | gated: all three replay matches must be TRUE; anchor's flooded/terra/terra_gdal/sf_gdal must equal the `dem` mode's. Restore-the-bug: flipping `floodplain_match_replay` in a backed-up anchor.json made the report stop with the anchor message; file restored byte-identical |
| scenario per mode untied | `flood_scenarios.csv` must predate t0 (it is 2026-08-28); every recorded scenario (anchor, arms) must equal the report's |
| verdict does not follow from the registered rule (criterion 3 names order-1 panels) | accepted. Research and #104 now state both readings: per-floor → order ≥ 2, superseded (16.6%); literal → order ≥ 3 without access filter, extended (1.6%). The user decides; the ambiguity was the drafting |
| "825 s" not in any surviving artifact | research now cites 829.9 s (arm5_timing.json, 340 groups, fallback on) and 5.0 s (reach.json, one group, fallback off); the 825 s single-group figure is labelled as planning-log-only |
| "12–27%" includes a non-floor pair | corrected to 12–20% over the three floors |

Not gated, stated: the code version the anchor ran on (the reviewer diffed `delineate()` and the
SQL unchanged since the anchor's commit); the live habitat/panel reads.
