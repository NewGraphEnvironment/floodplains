## Outcome

#125's per-region acceptance, run read-only on the Fraser (13 groups), Peace (3) and Columbia (4)
whole-network runs of 2026-10-14/15, and recorded beside Skeena's. Two committed scripts derive
every table: `scripts/floodplain_lcc/region_checks-run.sh <region>` runs the per-group checks, and
`scripts/floodplain_lcc/region_acceptance-report.R <region>|all` (no database) derives the results
and the outlier screen from disk. Each group is tied to its `provenance.json` records by digest,
record order and time window before anything is printed, and the logs name the columns that cannot
be tied. Both scripts reproduced the Skeena log first. The habitat join then ran on all 20 groups.
Every new FAIL has its own issue (#138 waterbody spill, #139 bridge proxy, #140 accuracy scenario),
and the imagery look is #141. #125 closes on merge, as do #58, #59, #73 and #76, which the
whole-network runs supersede.

Rounds 2-4 each found a defect inside the previous fix, all one mechanism: a value trusted for
where it was found, not tied to the run that produced it. Round 4 ended the loop by enumerating
all 49 inputs, verdict paths and claims of the two scripts (`findings.md`). A fifth round covered the docs
added after GitHub came back. It found 3 bugs there, among them a wrong build date for DUNC and a
claim that the checks ran on flooded 0.7.0. Every claim in its fixes was then checked against its source.

## Measurement

- **Checks, 23 groups (20 new plus the Skeena control):** `provenance-check.R` PASS 23/23,
  `dem_cache-check.R` PASS, the `all_ff04` section of `disturbance-check.R` PASS 23/23.
  `composition-check.R`'s 1% bound fails everywhere, as expected: inside-polygon change cells equal
  the patch totals within 0.12 ha (the #53 edge, +1.1% to +7.8%; PCEA +225% from the reservoir).
  Classified coverage of the floodplain is 0.9991-1.0001.
- **Outlier screen, written down before the new numbers were read** (1.5 x IQR over 23 groups):
  km² per km has median 0.1113 (IQR 0.0837-0.1532), nothing flagged. Floodplain outside the group
  polygon has median 1.73% (IQR 1.12-2.42%); **PCEA is flagged at 41.7%**, 83.6% of it reservoir or
  large lake (Williston, spilling into PARA and FINA). That became #138.
- **Bridge union coverage:** the check's unweighted max proxy reads 0.889-0.898 on LARL, SLOC and
  PCEA. The true union reads 0.936-0.961. Area-weighting alone is not the fix: FRAN fails it at
  0.8994, with a true union of 0.9235 (#139).
- **Habitat join, 20 groups, flooded 0.8.2:** every floodplain cell is attributed. Every habitat
  row matches in Fraser, Peace and DUNC. KOTL, LARL and SLOC have 21 / 35 / 10 unmatched rows per
  species, because link 0.66.0 rebuilt `fresh_default` on 2026-10-17 after step 1 snapshotted
  `habitat_link`. That changed what #123 has to do.
- **Peak RSS was not sampled** for these three runs, and the logs say so.

Wrong turns kept in `findings.md`:
- The bridge mechanism was first put down to "multiple blue lines", until a weighting measurement
  refuted it. "Area-weighting fixes it" was refuted next, by FRAN.
- The checks were believed to run on flooded 0.7.0 before the install. 0.8.2 had in fact been in
  place since 11:00 UTC; the verdicts were unaffected.
- The Skeena log's "patches >= 1 ha" counts rows, which are 8-connected single-code patches;
  8,058 of BULK's 9,210 are under 1 ha. It is corrected in place.

## Evidence

- `scripts/floodplain_lcc/logs/20261017_whole_network_*` (one per region, plus the correction appended to `20261014_whole_network_skeena.md`)
- `scripts/floodplain_lcc/logs/20261018_habitat_join-query_*`
- Check outputs: `data/logs/region_checks_<region>_20261017_*` (gitignored). The report CSV is `data/logs/region_acceptance_*`.

Closed by: the PR from branch `125-region-acceptance-fraser-peace-columbia` (Closes #125, #58, #59, #73, #76).
