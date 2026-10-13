# Plan review (#126) — Plan agent, 2026-10-13

Findings in the reviewer's own categories, summarised; dispositions in task_plan.md / progress.md.

- **B1 (Blocker)** Re-stamping through fp_prov_set() moves inputs_hash on every live landcover and
  floodplain entry: read_json(simplifyVector = FALSE) turns `I(c(2017L, 2023L))` into a list, which
  fp_prov_hash(auto_unbox = FALSE) serialises `[[2017],[2023]]`. Measured read-only on necr, kotl,
  lnth, bulk. -> helper edits `run` in place and writes via fp_prov_write (already so).
- **G1** Transition digest is `outputs.transition_content_sha256` (null with `transition_raster`
  when 0 patches); classified are `inputs.classified_content_sha256[<yr>]`. Refuse a late file with
  no recorded digest; never treat NA as a match.
- **G2** Reconcile in top-level script code has no tests -> factor into fp_provenance.R, cover in 5g.
- **G3** State-keyed re-stamp cannot tell a strip from a `touch` / mtime-losing copy -> forward
  path stamps only files repaired by this invocation; backfill needs zero stray tags + explicit opt-in.
- **G4** Helper's in-memory before/after compare is near-circular -> re-read after write, compare
  parsed JSON minus run against the pre-write parse; restore bytes on mismatch.
- **O1** Reconcile must run before the script's `quit(status = 1)`.
- **O2** DRY on a dirty area under-reports (mtimes not moved) -> report "would re-stamp after repair".
- **O3** stac check needs PROV_FIELDS defined and cwd = stac root; call as 01_stage.R:260-264.
- **A1** Text diff is not the acceptance check (re-serialisation re-flows lines); compare parsed.
- **A2** Floor the stamp explicitly (necr 22:44:28.047 -> 22:44:28Z; kotl 22:47:07.600 -> 22:47:07Z).
- **A3** cfg: `area` from CLI, `watershed_group` from area.yml, assert non-empty (a NULL deletes the key).
- **A4** Backfill toolchain is today's, not the repair's -> record toolchain only in the forward path.
- **A5** `files` as a list of basenames.
- **S1** Scan of all 23 landcover entries: only necr ch_ff04 and kotl bt_ff04 have late rasters (7 each).
- **AC1** No-op second run checked by md5. **AC2** Capture the live FAIL before the backfill.
- Checked fine: no reader refuses `run.repairs`; nothing breaks when landcover's stamp moves later.
