# fp_network grab-from-schema + freshness guard — validation (#14)

**Date:** 2026-07-11 · **Stack:** link 0.44.2, drift 0.6.0 · **Change:** step 1 can GRAB the
accessible network from an existing schema (`cfg$network_source`, e.g. `fresh_default`) instead of
re-running `lnk_pipeline_run`, guarded by a bcfp-reference freshness check.

## Why

Step 1 re-ran the whole link pipeline every time. When a compatible default-config network is
already materialized (`fresh_default`), that is the same "recompute what's already there"
redundancy removed in Pass 2 (#11). But a shared schema is **not uniformly current per-WSG**, so a
blind grab is unsafe — hence the guard.

## Freshness anchor

A current default-config network sits within ~0.5% of the province bcfp reference
(`fresh.streams_vw_bcfp`); a stale one diverges. So the guard needs no expensive rebuild — compare
grabbed accessible-km to bcfp, `stop()` beyond tol (default 2%).

| WSG | bcfp ref | fresh build (0.44.2) | fresh_default |
|---|---|---|---|
| PCEA | 2,194 km | 2,200 (0.3%) | 2,281 (**4.0%**) |
| PARS | 2,310 km | 2,314 (0.2%) | 2,314 (0.2%) |

## Validation (`FP_NETWORK_SOURCE=fresh_default`, step 1)

| WSG | freshness check | exit | outcome |
|---|---|---|---|
| **PARS** | grabbed 2,314 vs bcfp 2,310 = 0.2% ≤ 2% | 0 | GRAB ok — 9,387 seg / 2,314 km, matches the built 9,386 / 2,314 (skips the link pipeline) |
| **PCEA** | grabbed 2,281 vs bcfp 2,194 = 4.0% > 2% | 1 | **refused** ("diverges from bcfp by 4.0% — likely stale"); `data/pcea` left untouched |

Verified by exit code + the freshness message + built-vs-grab km/segments + that the refused grab
did not overwrite `data/pcea/aquatic_network.gpkg`. PARS's built network was restored after the
grab test (functionally identical; keeps it matched to its already-built floodplain).

## Provenance stamp + guard override (lnk_stamp)

Step 1 now writes an `aquatic_network.stamp.md` sidecar (via `link::lnk_stamp`) next to every
network — build or grab. It records config identity (`default`), link/fresh versions + git SHAs,
a DB snapshot (`bcfishobs.observations` = the crossings/observations signal), per-file config
provenance (the crossings/barrier override CSVs + byte/shape drift), AOI, and a
"Floodplains network source" footer (source + freshness result). So a floodplain self-documents
what produced it, and any guard override is auditable.

`network_guard` (area.yml / `FP_NETWORK_GUARD`): **strict** (default, stop on divergence) |
**warn** (log + proceed) | **off** (proceed, override recorded in stamp). Set warn/off when a
divergence is expected and understood — updated crossings data (override CSV byte-drift) or a
deliberately different config.

Validated (`FP_NETWORK_SOURCE=fresh_default`, step 1):

| run | exit | outcome |
|---|---|---|
| PARS, strict | 0 | 0.2% dev → pass, stamp written |
| PCEA, strict | 1 | 4.0% dev → stop ("set network_guard: warn/off if intentional") |
| PCEA, **guard=off** | 0 | 4.0% dev → proceeds; stamp records `source: GRAB from fresh_default`, `freshness: 4.0% dev, guard=off`, config provenance (0 drift) + observations 372,690 |

`fresh_default` carries no in-DB stamp, so the stamp is generated at build/grab time (captures the
current config/version/DB state). Built networks were restored + grab-test sidecars removed after
the check (`data/` is gitignored).

## Scope

Validated at **step 1** (network read + guard). Steps 2–3 consume `aquatic_network.gpkg` agnostic
to how it was produced, so the grab network flows through unchanged. Grab is for default-config
(bt/grayling) sources; chinook/other configs need their own current source. Absent
`network_source` => BUILD (default) — unchanged for every existing area.
