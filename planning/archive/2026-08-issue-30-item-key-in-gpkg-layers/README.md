## Outcome

Every published gpkg layer now carries the **full item key** — `wsg`, `species`, `scenario` —
written at generation time (`02_floodplain_model.R` for the scenario delineation layers,
`03_lulc_classify.R` for classified + transition). The issue asked for `wsg` alone; planning widened
it on two counts: (1) `floodplain.gpkg` was brought into scope alongside `floodplain_landcover.gpkg`
— it is also a published asset and is the *worse* merge case, since its layer names (`co_ff04`,
`ch_ff04`) are identical across all 16 areas with only a `valley` column; (2) the key widened from
`wsg` to the full triple, because MORR publishes two items sharing one `wsg` (coho `co_ff04`,
chinook `ch_ff06`) with overlapping geometry and different extents — `wsg` alone leaves them
indistinguishable after a merge.

The governing principle: **the same key must exist as a STAC *property* (to select items) and as a
gpkg *column* (to separate rows once merged)**; they were asymmetric (item id `morr_ch_ff06` vs rows
carrying nothing). Layer names stay producer-keyed — generic names inside a per-area gpkg would
collide across species and undo #23's clean per-layer replace — so flattening to generic layers
(`classified_2017` = all areas appended) is a **downstream merge-time** concern. Net effect: adding
an area or species never touches a QGIS project again.

**Verified:** MORR re-run writes the keys natively with headline numbers unchanged (411.1 km² /
433.8 ha exactly); in-place gpkg layer replace proven safe on a *copy* before touching real data; all
16 existing areas backfilled via `gpkg_backfill-wsg.R` — **131 layers, 0 failures** under strict
validation (scenario matches `<species>_ff<NN>`, species agrees with scenario, wsg matches config,
feature counts unchanged). **KISP (Kispiox) chinook** was modelled from scratch as the end-to-end
test and carries the keys natively with no backfill (floodplain ch_ff04 246.7 km², tree loss 267.9 ha,
coverage 107%); the stac smoke test **PASSED** against a WSG the catalog had never seen
(`kisp_ch_ff04`, 4 COGs, valid item).

**Learned:** (1) Two silent-wrong-value bugs in the backfill's layer-name parser — a year-strip that
ran before the span-strip (`bt_ff04_2017_2023` → `bt_ff04_2017`), then a suffix enumeration that
missed `_patches`. Both were the same class: *stripping* suffixes means enumerating them, and any
unlisted one yields a plausible-but-wrong value. Replaced with **extraction**
(`^[a-z]{2,4}_ff[0-9]+`) — one rule covers year, span, `_disturbance`, `_fire`, `_patches`, and
anything added later. (2) Making the backfill idempotent **by value rather than presence** is what
let a re-run *repair* the bad values instead of skipping them as "already keyed" — presence-checks
make a migration un-fixable in place. (3) A region file carries one species preference and
`run_region.R` **writes** each group's `area.yml` from it, so a group of a different species needs
its own region file (`skeena_ch.yml`) — listing KISP under skeena's `[co]` would have clobbered its
chinook config. (4) Running two pipelines concurrently tripped a Planetary Computer 429; the wrapper
still exited 0 and only the in-band-error + output-mtime gate caught it.

Downstream republish (published items carrying the keys) is tracked in `stac_floodplains_bc#5`.

Closed by: PR #31
