# Task: Producer publish handoff — point at the stac release after a run (#32)

Publishing used to end in a manual server-side incantation borrowed from the infrastructure repo
(`scp` + `ssh root@geopro ... stac_register-pypgstac.sh`) — tribal knowledge outside both repos.
stac_floodplains_bc#14 replaced that with a repo-owned release. This is the **producer side**: after
floodplains generates products, the operator should know exactly what to run next.

**Decision:** keep the **pull** coupling; the hook is **advisory**. floodplains prints the next
command rather than shelling out — preserving the one-way dependency and CLAUDE.md's layering.

## Phase 1 — Advisory publish hint
- [x] `scripts/publish_hint.R` — `fp_publish_hint(areas, steps)`; suppressed by `FP_NO_PUBLISH_HINT=1`;
      silent unless steps include 2 or 3 (only those write published assets).
- [x] `run_area.R`: source + call after the final "Done:" message.
- [x] `run_region.R`: sets `FP_NO_PUBLISH_HINT=1` for its subprocess children, unsets and prints
      **once** after the batch (would otherwise repeat per-WSG, 8x on Fraser).
- [x] Verified: unit-checked all four branches; confirmed in situ after a real `run_area.R morr 3`.

## Phase 2 — Document the publish handoff
- [x] `README.md` "Publishing" section — two-step sequence, order matters, idempotent, retraction.
- [x] `CLAUDE.md` — same, plus the explicit **do not wire this repo to call the publish layer**
      rationale so a future session doesn't "helpfully" make the dependency circular.

## Validation
- [x] steps 2/3 print; step-1-only silent; `FP_NO_PUBLISH_HINT=1` silent; multi-area batch works
- [x] Hint appears after a real run (`run_area.R morr 3`, 0 errors)
- [x] floodplains has no executable dependency on stac — the hint is a message, nothing more
- [ ] `/planning-archive` on completion
