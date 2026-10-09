# Progress — Probe: cost and difference of a whole-FWA floodplain on MORR (#110)

## Session 2026-10-09

- `/planning-init 104` asked; #104 is gated on #110 (open, no work started), so the user chose to
  init #110 instead.
- Plan-mode exploration — phases approved by user; instruction: all phases to PR.
- Created branch `110-probe-cost-and-difference-of-a-whole-fwa` off main
- Scaffolded PWF baseline from issue #110 with approved phases
- Next: start Phase 1
- Phase 1: `fp_whole_fwa.R` + `floodplain_probe-check.R` (25 asserts). Arms are R predicates over ONE
  whole-group read rather than five SQL WHEREs, so nesting is checkable offline. Six planted defects
  (NA guard, arm-4 parent NA, grid check, species guard, seg-key format, arm check) each turn it red.
- Phase 2: runner `floodplain_probe-whole-fwa.R` (modes anchor / 1..5 / seg / report) and driver
  `floodplain_probe-run.sh` (per-mode process under `caffeinate -s /usr/bin/time -l`, gated on
  `PROBE_DONE <mode>` + an output newer than the mode's start stamp). `data/*` is gitignored
  (`.gitignore:3`), so `probe_whole_fwa/` never reaches git or the publish layer.
