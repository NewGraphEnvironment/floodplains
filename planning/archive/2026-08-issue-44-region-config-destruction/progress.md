# Progress — run_region.R destroys hand-maintained area config (#44)

## Session 2026-08-28

- Plan-mode exploration: audited all 20 area configs against the 5 region files; exposure is
  exactly BULK and MORR via `skeena.yml`, and NEEXDZII is deliberately excluded
- Established that the destroyed columns are documentation-only, which is why the loss is silent
- Established that deleting `break_points.csv` changes which sub-basin branch step 2 takes
- Phases approved by user
- Created branch `44-run-region-destroys-area-config` off main
- Next: Phase 1 — factor config resolution into a pure function
