# Plan review (Plan agent, 2026-10-08) — summary and disposition

Full findings were returned in the agent's reply. Each one, with what is being done about it:

| Finding | Disposition |
|---|---|
| B1: chips overlap in one VRT (176/480 points have a neighbour within 300 m), so a point can show a neighbour's capture | Agreed and measured independently. Each chip is clipped to its point's Voronoi cell, and an acceptance check verifies that the pixel under each point comes from its own chip. |
| B2: recording a dated Wayback chip as `esri` conflicts with labelling key rule 5 (undated basemaps support `low` at most) | Confirmed by reading rule 5. This is a stored-data fork, so it goes to the user. |
| B3: rtj `accuracy_review-compose.R` builds the Mergin project; floodplains' review_build is a local preview | Agreed. Keep the floodplains layer/theme changes minimal. The rtj hand-off carries the globs, `IMAGE_EXT`, `FORBIDDEN += wayback.csv`, and the path (rtj#377 says `chips_wayback/`; we write `dated/wayback_<year>/`). |
| B4: rtj compose stops on non-image files under `dated/` | WMS XML and tile cache go outside the project, `GDAL_PAM_ENABLED=NO`, and the build asserts `dated/wayback_*` holds only .tif/.vrt. |
| Gap: stale kept chips | A manifest outside the project (`dir_acc/wayback/built.csv`) records review_id, endpoint, release, zoom and the cell hash; a chip is refetched on mismatch or if it is invalid. |
| Gap: where review_id comes from | `fp_acc_review_key_read` plus a design check; refuse if a sample point has no key. |
| Gap: B's dated tree never pruned | Prune B's `dated/wayback*` files that A no longer has. |
| Gap: one stale guard for all dated layers | Split per source, and the wayback guard uses `fp_acc_wayback_read` (design-checked). |
| Gap: orphan regex / `dated_name` | A separate wayback branch and orphan pattern. The coverage glob (line ~149) stays untouched, so `labels.gpkg` is never rewritten. |
| Gap: qml / alpha | Wayback layers are RGBA (alpha from the mask) with `dated_rgba.qml`. Measure that the VRT honours it. |
| Gap: capture columns invisible | `cells_outline.qml` gains a scale-limited label. `cells.gpkg` gets a `fp_acc_blind_leaks` read-back. |
| Gap: selection rule | The endpoint date is 1 July. Same capture at both endpoints is counted and reported (not refused; the other endpoint's chip is still the nearest evidence). Straddle: noted, not built. |
| Gap: don't touch the labelling key | Agreed. Only "Dated reference imagery" changes. |
| Assumption: placeholder tiles | A per-chip low-variance check flags them. |
| Assumption: Esri terms | Flagged to the user in the PR (fetch-into-project was the issue's decision). |
| Acceptance: cells arm offline | Pure `fp_acc_capture_columns(wayback, key)` tested in the check; read-back assertion in review_build. |
| Acceptance: point 1 numeric | The built manifest's release for review_id 1 at 2017 is 15045, with capture 2017-06-11. |
