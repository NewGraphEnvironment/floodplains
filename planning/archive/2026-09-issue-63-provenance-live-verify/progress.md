# Progress — Verify #33's provenance block against a live database (#63)

## Session 2026-09-02

- Plan-mode exploration — phases approved by user
- Established the issue's stated blocker is **cleared**: the province-wide `link` rebuild finished
  (last `fresh.log` write 01:25Z), and pre-flight predicts the freshness guard passes at 0.006% dev
- Confirmed the parity measurement method reproduces 673.5 km / 142.8 km² / 770.0 ha off the
  pre-run outputs, and that all 1915 network segments survived the rebuild unchanged
- Established m4 is reachable, can reach m1's postgres, and is far behind on packages
- Created branch `63-verify-33-s-provenance-block-against-a-l` off main
- Scaffolded PWF baseline with approved phases
- Next: Phase 1 baseline capture, then the Phase 2 A/B

## Session 2026-09-02 (cont.)

- **Pass 1 aborted in step 3** — and the wrapper still exited 0, which is the exact trap the
  in-band gate exists for. `caffeinate` reported success over `Execution halted`.
- Diagnosed: `tapply(bridge$overlap_frac, pk, max)` — *arguments must have same length*. `pk` is
  built before the zero-area filter and used after it. Trigger measured: one 9.9e-5 m² sliver pair
  rounding to `0.0000` ha. Introduced by 36145d3, which landed **one minute after** the last
  neexdzii run, so it had never executed.
- Fixed; restored-bug reproduces the error, patched reproduces the prior 4311 rows exactly.
- The aborted run also proved the plan review's B1/B2: `provenance-check.R` exits 0 on the 3-of-5
  file it left, and step 2 had already bumped the mtime, so the `-nt` gate was satisfied by a run
  that never reached step 3. Added a config-derived inventory assertion to close both.
- Landed `provenance_ab-compare.R` so the A/B is re-derivable rather than a scratchpad artifact.
- Relaunched pass 1 from a clean state (partial `provenance.json` moved aside, not deleted).
- Next: pass 2, then Phase 3 (link reinstall), then Phase 4 (m4).

## Session 2026-09-02 (final)

- **Phase 2 PASS** — 5 of 5 entries, `inputs_hash` identical, `run.datetime_utc` moved, parity
  unmoved (673.5 / 142.8 / 770.0). First attempt aborted; the wrapper exited 0 and the mtime gate
  passed, so only the in-band error count caught it.
- **Phase 3** — link 0.50.0 installed; stamp resolves, network hash moves, floodplain/landcover
  blocks byte-identical, `link_log` unchanged at 30 columns across the version change.
- **Phase 4** — m4 ran the identical commit against m1's database. Science identical on both;
  `network[co3]` hash identical across machines; `classified_sha256` differs on 28.3M cells with
  **zero** differing values (TIFF tag 42112, terra 1.9.11 vs 1.9.34).
- Three code-check rounds, 4 + 3 + 5 findings, all fixed. Round 3 caught round 2's fix reproducing
  the class it fixed (`st_delete` returns TRUE for a failed delete) — verified independently before
  acting on it.
- Five follow-ups filed: #64–#68. #63 body rewritten to read correctly top to bottom.
- Evidence log committed at `scripts/floodplain_lcc/logs/20260902_provenance_live-verify_neexdzii.md`.
- Next: archive, PR.
