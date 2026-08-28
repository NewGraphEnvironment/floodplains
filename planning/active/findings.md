# Findings — Attribute floodplains per watercourse/reach (#40)

## The gap, measured

`data/morr/floodplain.gpkg` layer `co_ff04` is **1 row**, MULTIPOLYGON, columns
`valley`/`wsg`/`species`/`scenario`. The network that produced it (`streams_co3`) carries 4,877
segments across **340 distinct `blue_line_key`** and **32 named watercourses** — Morice River
91.7 km / 366 segments, Nanika 66.6, Gosnell 56.4, Houston Tommy 39.9, Thautil 37.0; **721 km
unnamed**. All that identity goes in and none survives.

The loss happens before vectorizing: `fl_valley_confine(dem, streams, ...)` consumes the whole
network and returns a **raster** of valley/not-valley cells, and `fl_valley_poly()` vectorizes
that. A valley cell has no memory of which stream made it one, so this was never a
"stop dissolving the output" fix.

## Upstream already solved it — better than #40 sketched

`flooded` 0.4.0 (installed: **0.3.2**, so an install is Phase 1 work) ships:

```r
fl_valley_attribute(valleys, streams, group, dem = NULL, slope = NULL,
                    max_width = 2000, cost_threshold = 2500,
                    crop_margin = max_width, complete = TRUE)
```

One row per group (`valley` + the group column). Three properties that matter here:

- **It applies the VCA's own criteria per group**, not nearest-neighbour:
  `valley(cell) AND distance(cell, streams_g) <= max_width/2 AND cost(cell, streams_g) < cost_threshold`.
- **The delineation is never recomputed.** Re-running the VCA on a subset would change it (the
  flood surface interpolates from every seed; distance/cost loosen as seeds are added). So
  "the floodplain of this river" stays independent of whatever else was in the run.
- **Rows overlap** near confluences, because ground there genuinely belongs to both floodplains.
  A hard partition would be a false answer exactly where a sampling design cares most.

`max_width` / `cost_threshold` **must match the delineation being attributed** — both are already
on the scenario row (`sc$max_width`, `sc$cost_threshold`), so this is a wiring detail, not a new
parameter surface.

`complete = TRUE` assigns cells that no group reached within thresholds to the nearest group (they
come from morphological closing, hole filling, the channel buffer, and waterbody polygons, which
get no spatial filter). The count is exposed as `attr(x, "fl_fallback_cells")` — a QA signal worth
logging, since it is the share of the delineation attribution could not reach on its own terms.

## flooded#41 checked and cleared — no exposure here

`fl_cost_distance()` seeds every cell whose friction is **exactly** 0, not just stream cells
(`costDist(target = 0)` matches all zeros). Real bug, wrong roxygen. It needs true zeros to bite.

Probed MRDEM-30 over the largest waterbody we have — Kootenay Lake, 423 km², 62,662 non-NA slope
cells in the AOI:

```
EXACT zeros:  0  (0.000%)
min non-zero: 9.54e-14
cells < 1e-9: 2
```

`terra::terrain()` derives slope from a 3×3 neighbourhood of floating-point elevations, so even a
423 km² flat water surface carries enough float noise to land ~1e-13 — the same pattern flooded
observed in its own test DEM (min 1.42e-14). Our path is always MRDEM-30 → `terrain()`, including
inside `fl_valley_confine(slope = NULL)`. Strong evidence rather than proof across all 19 groups,
but the mechanism generalizes. **Not a blocker, and it did not affect the Columbia outputs** —
which was the specific worry, since those floodplains are 61–74% open water.

## flooded#44 is the live gate, and we are the ones who can close it

It says explicitly: measure at watershed-group scale *before the driver relies on it*. Current
evidence is a 518,400-cell tile at k=5 — attribution 0.74 s vs 1.36 s for the delineation. MORR is
~27M cells at k=33 (`gnis_name`) or k=340 (`blue_line_key`).

Why the small-tile number may not extrapolate, per #44: the saving comes from cropping each
group's cost distance to its own bbox + `crop_margin`, and **a bbox is a poor proxy for a long
sinuous mainstem** — the Morice's bbox approaches its whole AOI, so the most important group gets
least benefit. On the bundled tile the per-group crops were already 39–74% of the full grid.

We hold the WSG data, the DEM fetch and the fwapg setup; flooded holds a test tile. So Phase 1 is
their measurement, and its result decides our config default rather than the other way round.
