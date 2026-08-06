# Findings — Producer publish handoff (#32)

## Scope: the issue's body is not its title

floodplains#32 and stac_floodplains_bc#14 carry near-identical bodies (copy-paste of the system
description), so #32 *reads* like the whole catalogue system. It isn't — stac#14 says so directly:
"The producer side (floodplains#32) then simply calls this repo's release step." The floodplains-side
work is the title only.

## Verified

- floodplains had **zero** references to stac (one README mention) — the coupling really is one-way.
- **The stac release is TWO steps** (`catalogue_release.sh` header): `run_pipeline.sh` rebuilds
  `data/stac` from `$FLOODPLAINS_DATA`; `catalogue_release.sh` validates → syncs → registers →
  verifies, and explicitly "does NOT require `$FLOODPLAINS_DATA` — rebuild and publish are separate."
  Naming only the release in the advisory would silently publish a **stale build** — so both are
  named, in order.
- `catalogue_release.sh` is idempotent (sync skips unchanged, register upserts); flags
  `--allow-retract` / `--skip-sync`; `GEOSERV_HOST` overrides `root@geopro`.
- `run_region.R` calls `run_area.R` via `system2`, so a child hint would repeat per-WSG — the child
  inherits `FP_NO_PUBLISH_HINT=1` and the batch prints once.
- **Dependency:** stac#14 is complete but on branch `14-adopt-the-converged-stac-catalog-system`,
  not yet merged to stac main. The documented commands land when that PR merges.

## Design rationale (recorded so it isn't "fixed" later)

The obvious-looking improvement — have `run_area.R` shell out to `catalogue_release.sh` for a true
one-command publish — would point the dependency arrow both ways (stac already reads
`$FLOODPLAINS_DATA`) and break the layering in CLAUDE.md (a driver reaching into the publish layer).
The advisory hint keeps floodplains ignorant of stac while still removing the tribal knowledge, which
was the issue's actual complaint.
