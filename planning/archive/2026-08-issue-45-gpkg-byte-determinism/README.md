## Outcome

`sf::st_write()` to GeoPackage was not byte-deterministic — GDAL stamps `gpkg_contents.last_change`
with wall-clock time at write, so every rebuild produced a new file even when nothing changed, and
`file:checksum` on the published assets would have churned per build across the 72% of the bucket
that is GeoPackage. Fixed by pinning `OGR_CURRENT_DATE` to a fixed epoch (`scripts/fp_gpkg.R`) at
the four entry points that write a published gpkg. A determinism probe run *before* planning is
what shaped the fix: the env-var route works, so this is one line per entry point rather than edits
to all 13 `st_write` call sites — and per-call arguments would have gone silently incomplete the
moment someone added the 14th. `packages.R` alone was not enough; `gpkg_backfill-wsg.R` and
`fire_tag.R` are standalone CLIs that do not source it.

The more useful finding is the **limit**. A full rebuild into an absent file is byte-identical
(verified on 7 layers / 7.5 MB and 18 layers / 79 MB, with a cold-path run proving the guard fails
without the pin). Rewriting one layer into an *existing* gpkg is not, and `VACUUM` does not close
it — after vacuuming, the difference is exactly 3 SQLite header bytes (file change counter, schema
cookie, version-valid-for) with identical page count and identical content. Those are write-history
counters and cannot be normalized to a content-derived value, so `VACUUM` was measured and rejected
rather than adopted on intuition. The conclusion worth carrying forward: **byte equality answers
"same build?", not "same content?"** — and a partial rerun is exactly where the two come apart.
That gap was filed as #46 (content hash per feature) rather than half-built here.

Reviewing `bcgov/FIT_changedetector` at the user's prompt did not change the fix — no semantic diff
makes a byte checksum stable — but it supplied the shape of #46 and exposed a real gap in
`code-check.md`: its cache-key guidance says to hash WKB rather than the sfc, and says nothing about
canonicalizing geometry first, so two identical polygons with different ring order hash differently
(soul#95). Both that issue and #46 state the same unresolved blocker instead of guessing past it —
`sf::st_normalize()` rescales to the unit bbox and is **not** GEOS `normalize`, so neither
recommends a function that was not verified.

#41 shipped alongside as the same defect class — the published catalogue described in terms that do
not hold. Its README half is fixed (`stac-floodplains-bc`, hyphenated; the underscore form is the
repo name and returns a `NotFoundError` that reads like "not published"). Its unrelated asset-split
half moved to `stac_floodplains_bc#23` with its measurements carried over, and #41's body records
the split so the close is honest.

Parity verified through the real runner with the pin live: neexdzii `co_ff04` still 171.0 km².

Closed by: PR #47
