# Progress — Producer publish handoff (#32)

## Session 2026-08-06

- Planning surfaced that #32 appeared blocked on stac#14 (the `catalogue_release.sh` it calls);
  user confirmed stac#14 is now built — verified on branch `14-adopt-...` (not yet merged to main).
- User chose the **advisory** hook (keep pull coupling) over floodplains invoking stac.
- Phases 1–2 complete: `fp_publish_hint()` wired into both runners (once-per-batch in run_region),
  README + CLAUDE.md document the two-step handoff and the do-not-couple rationale.
- Verified: four-branch unit check + in-situ after a real `run_area.R morr 3` (0 errors).
- Next: `/planning-archive` + PR.
