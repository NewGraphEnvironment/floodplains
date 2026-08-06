## Outcome

After a run produces publishable outputs, `run_area.R` / `run_region.R` now print the
`stac_floodplains_bc` release sequence, so the final publish step is discoverable instead of tribal
knowledge borrowed from the infrastructure repo (the old `scp` + `ssh root@geopro ...
stac_register-pypgstac.sh` incantation, replaced repo-side by stac_floodplains_bc#14).

The decisive scoping finding: floodplains#32 and stac#14 carry near-identical bodies (copy-paste), so
#32 *reads* like the whole catalogue system — but stac#14 states plainly that "the producer side
(floodplains#32) then simply calls this repo's release step." The floodplains-side work is its title
only. #32 also appeared blocked on stac#14 until the user confirmed it was built (verified on branch
`14-adopt-the-converged-stac-catalog-system`, not yet merged to stac main — the documented commands
land when it does).

**The hook is deliberately advisory** (user decision): floodplains prints the next command rather
than shelling out. Making the driver invoke the publish layer would point the dependency arrow both
ways — stac already reads `$FLOODPLAINS_DATA` — and break CLAUDE.md's layering. Both README and
CLAUDE.md record that rationale explicitly so a future session doesn't "helpfully" wire them together
in pursuit of a true one-command publish.

**Two details that mattered more than the code:** (1) the stac release is *two* steps and the order
is load-bearing — `run_pipeline.sh` rebuilds `data/stac`, `catalogue_release.sh` publishes whatever
was last built — so naming only the release in the advisory would have silently shipped a stale
catalogue; both are named, in order. (2) `run_region.R` invokes `run_area.R` as a subprocess, so an
unguarded hint would repeat once per WSG (8× on Fraser); children inherit `FP_NO_PUBLISH_HINT=1` and
the batch prints once.

Verified: all four helper branches unit-checked (prints on steps 2/3, silent on step-1-only, silent
when suppressed, multi-area batch), and confirmed in situ after a real `run_area.R morr 3` (0 errors).
floodplains retains no executable dependency on stac — the hook is a message, nothing more.

Closed by: PR #34
