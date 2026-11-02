# Plan review — #136 (Plan agent, 2026-11-02)

Findings, with dispositions.

- **Blocker (disproved):** `data/bulk/floodplain_landcover.gpkg` at 21 MB looked like a partial scp.
  It was the scp in flight; after it finished, all three gpkgs match m1 by sha256.
- **Gap (taken):** the cleanup line should name the three files exactly.
- **Gap (taken):** Phase 3 names only the `rmd_on = TRUE` render; README.md is the other target.
  The determinism check renders both twice, and its first arm also asserts the committed targets
  match README.Rmd, so render first, then run it.
- **Gap (taken):** the comment at the top of `fp_fig_attribution()` says `src` comes from the config
  "which is what the caption claims to describe". `src` still sets the cause levels and the
  missing-column stop; reword it to drop the caption claim.
- **Assumption (kept as gate):** the committed PNG predates #53's backfill, so the 66/474/1025 ha
  check is real. README says "about a third"/"roughly a third".
- **Acceptance (taken):** the read-back also checks the bar panel's layout once the subtitle row is
  gone (`heights = c(4.3, 1)`).
- **Acceptance (taken):** `python3 scripts/readme_content-check.py`; run the determinism check after
  the gpkgs are removed and with no render byproducts on disk.
- Scope: fine as written.
