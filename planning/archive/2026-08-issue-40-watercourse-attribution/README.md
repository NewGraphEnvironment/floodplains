## Outcome

Wired `flooded::fl_valley_attribute()` into step 2 behind an optional `attribute_by:` key, so a
delineation can answer *"where is the floodplain of **this river**?"* — and delivered the Morice
sampling frame that motivated it: **55.98 km²** of Morice River floodplain, split into the
**24.92 km²** only the Morice claims and the **31.07 km²** a tributary also claims, with the
mainstem's upstream terminus at route measure **91.75 km**. That terminus is the boundary the
original fieldwork question needed and could not previously be located anywhere in the outputs.

The upstream half arrived mid-issue: `flooded` 0.4.0 shipped `fl_valley_attribute()` while #40 was
still describing the problem, and it is a better mechanism than the issue sketched — it applies the
VCA's own criteria per group rather than nearest-neighbour, and never recomputes the delineation
(re-running the VCA on a subset would move the boundary, since the flood surface interpolates from
every seed). So the driver half was config surface, wiring, and the deliverable.

**Three measurements changed conclusions rather than confirming them.** (1) flooded#41 — the
cost-distance seeding bug — was cleared *before* planning around it: 0 exact-zero slope cells over
423 km² of Kootenay Lake, because `terra::terrain()` on a float DEM lands ~1e-13 rather than 0. It
never threatened us or the lake-dominated Columbia outputs. (2) flooded#44 predicted hours at
k=340 because bbox crops would stop paying off for a long sinuous mainstem; measured, crop
efficiency *improves* at watershed-group scale (worst-case group crop 0.201 of the grid vs 0.39–0.74
on the bundled tile) and runtime got worse anyway — 12.0× the delineation at k=33. (3) The obvious
follow-on reading, that per-group overhead dominates, is also wrong: 10.3× the groups cost only
1.16× the time, so **85% of the cost is k-independent**. `blue_line_key` at k=340 is therefore
affordable and resolves every watercourse, where `gnis_name` pools 54% of the area into one unnamed
group. Both findings posted to flooded#44/#41.

The design point that earned itself: **rows overlap**. On MORR, 43.6% of the floodplain is claimed
by more than one watercourse, and 55% of the Morice's own floodplain is shared with a tributary. A
hard partition would have mis-assigned nearly half the ground — silently, and worst at confluences,
which is exactly where a sampling design cares most.

Verified in the strong form: re-running MORR **with attribution on** left the pre-existing `co_ff04`
layer byte-identical (wkb md5 `c385ce7c`), chinook layers untouched.

Closed by: PR (branch `40-delineate-and-attribute-floodplains-per-`)
