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

## Phase 1 measurement — MORR, 16,478,040 cells (closes flooded#44)

`slope` supplied, derived exactly as the package does internally. AOI is the real `co_ff04`
delineation (the issue estimated ~27M cells; the actual raster is 16.5M).

| | k | wall time | vs delineation | peak R mem |
|---|---|---|---|---|
| `fl_valley_confine()` | — | **64.3 s** | 1× | ~381 Mb |
| `fl_valley_attribute()` by `gnis_name` | 33 | **769.6 s** | **12.0×** | ~518 Mb |
| `fl_valley_attribute()` by `blue_line_key` | 340 | **890.7 s** | **13.9×** | ~522 Mb |

`fl_fallback_cells` 14,094 / 14,105 = **3.17%** of 443,975 valley cells (~13.05 km² of 411.13).

### k is nearly free — and both prior hypotheses were wrong

```
marginal cost per extra group:     0.39 s
implied k-independent fixed cost:  757 s  (85% of the k=340 run)
10.3x the groups -> 1.16x the time
```

flooded#44 predicted hours at k=340 because per-group crops would stop paying off for a long
sinuous mainstem. Measured, the opposite happens: at WSG scale the AOI dwarfs any one watercourse,
so the worst-case crop is **0.201** of the grid (`gnis_name`) / **0.332** (`blue_line_key`) against
0.39–0.74 on the bundled tile, and all crops sum to **0.7× / 1.3×** a full-grid pass against ~2.76×.
Crop efficiency *improved* at scale and runtime got worse anyway.

My own first reading — that per-group fixed overhead dominates — is also wrong: 10.3× the groups
buys only 1.16× the time. **85% of the cost is k-independent.** So `blue_line_key` at k=340 is
affordable (14.8 min), and the optimisation target upstream is the full-extent setup, not
`crop_margin` or per-group overhead.

### Which grouping to use

| grouping | rows | NA group |
|---|---|---|
| `gnis_name` | 33 | **320.6 km² — 54% of summed area** (the 721 km of unnamed streams, pooled) |
| `blue_line_key` | 340 | **0.0 km²** — every watercourse resolved |

`blue_line_key` is strictly more informative and costs 16% more, so it is the better default for
completeness. `gnis_name` earns its place when a human-readable name is the point — which is
exactly the Morice deliverable, where you select `"Morice River"`. Documented as a tradeoff rather
than hard-defaulted, since the key is opt-in config either way.

## Attribution result on MORR (`co_ff04`, by `gnis_name`)

**The `complete = TRUE` coverage contract holds exactly** — asserted, not assumed:

```
union of attributed rows: 411.13 km2
unattributed co_ff04:     411.13 km2      ratio 1.0000
sum of row areas:         590.27 km2
=> overlap:               179.14 km2 (43.6%)
```

**43.6% of the floodplain is claimed by more than one watercourse.** A hard partition would have
mis-assigned nearly half the ground — which is the empirical case for the overlapping-rows design.

Morice River: **55.98 km²** floodplain over 91.7 km of mainstem (route measure 0.1–91.75 km).
Splitting it against the union of every other watercourse:

| part | km² | share |
|---|---|---|
| exclusive — only the Morice claims it | **24.92** | 45% |
| shared — a tributary floodplain also claims it | **31.07** | 55% |

(The two reconcile to 55.99 ≈ the whole. An earlier per-tributary sum gave 36.5 km²; that
double-counts ground where two tributaries overlap the same Morice floodplain, so 31.07 is the
correct shared figure.) Largest individual sharers: unnamed streams 22.47 km², Lamprey 2.60,
Thautil 2.27, Gosnell 1.97, Owen 1.59, Peacock 1.23.

Material to the sampling design: **a "within the Morice floodplain" sample is mostly also a
tributary sample** unless restricted to the exclusive 24.92 km².

## Phase 2 regression — the strong form

Re-ran MORR step 2 **with attribution on** and compared the pre-existing `co_ff04` layer:

```
BEFORE: rows=1 area_m2=411131287.230639637 wkb_md5=c385ce7c556dca3fc8375d1b99917ffc
AFTER : rows=1 area_m2=411131287.230639637 wkb_md5=c385ce7c556dca3fc8375d1b99917ffc
```

Byte-identical WKB. This is stronger than the planned "no `attribute_by` ⇒ unchanged" check,
because it proves the existing layer is untouched **while attribution runs**, not merely when the
feature is switched off. It also re-confirms the delineation is deterministic (same DEM + params
reproduce the same geometry) and that the #23 per-layer write still holds — `ch_ff02/04/06`
survived a coho run untouched.

The wired path reproduced the standalone measurement exactly: `co_ff04_by_gnis_name`, 33 groups,
14,094 fallback cells.
