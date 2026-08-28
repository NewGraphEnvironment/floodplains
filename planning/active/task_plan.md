# Task: Attribute floodplains per watercourse/reach (#40)

A delineation currently answers only "where is the floodplain of this watershed group's network?"
and cannot answer "where is the floodplain of **this river**?". This blocked Morice fieldwork —
sampling within the Morice River floodplain and upstream of it needs a boundary that does not
exist in the output. `flooded` 0.4.0 shipped `fl_valley_attribute()`; this is the driver half.

Decisions at plan time (user): **capability + the Morice layer** (not capability alone);
**`primary_scenario` only** (attribution costs a cost-distance pass per group per scenario).

## Phase 1 — Measure at watershed-group scale (closes flooded#44)
- [x] Install `flooded` 0.4.0; confirm `fl_valley_attribute` is available (we are on 0.3.2)
- [x] Time on **MORR / `co_ff04`** at `group = "gnis_name"` (k≈33) vs `fl_valley_confine()` for the
      same AOI; derive `slope` once and pass it rather than re-deriving per call
- [x] Then `group = "blue_line_key"` (k=340) — the one at real risk. Intractable is a finding, not
      a failure: `gnis_name` becomes the documented default
- [x] Record what #44 asks: wall time, peak memory, per-group crop area as a fraction of the AOI,
      and `attr(x, "fl_fallback_cells")`
- [x] Post numbers to flooded#44; post the #41 probe result to flooded#41

## Phase 2 — Wire attribution into step 2
- [x] Optional `attribute_by:` in `area.yml` — absent ⇒ nothing runs, output byte-identical
- [x] Carry region → area via the pass-through added in #36 (`run_region.R` rewrites `area.yml`)
- [x] Call `fl_valley_attribute()` after `fl_valley_confine()` for the **primary scenario only**,
      passing `sc$max_width` / `sc$cost_threshold` so thresholds match the delineation
- [x] New layer `<scenario_id>_by_<group>` with the item key (#30) + the group column; the existing
      `<scenario_id>` layer untouched
- [x] Fail early by area name if `attribute_by` is not a network column
- [x] Log the fallback-cell count as a QA signal

## Phase 3 — The Morice deliverable
- [x] Run MORR with attribution; isolate `gnis_name == "Morice River"`
- [x] Locate the upstream terminus so "within" vs "upstream of" is well defined
- [x] Confirm overlap is represented at confluences (Nanika, Gosnell, Thautil), not resolved away
- [x] Hand over the layer with a note on what the two categories mean

## Phase 4 — Docs + close
- [ ] `README.md` + `CLAUDE.md`: grouping key as the fourth member of the item key; `attribute_by`
- [ ] Note in #40 that `subset` (blk+drm) is the degenerate one-group case — do NOT refactor here
- [ ] `/planning-archive`, `/gh-pr-push`

## Validation
- [x] No `attribute_by` ⇒ `floodplain.gpkg` byte-identical (the regression that matters)
- [x] Attributed rows union to the unattributed `co_ff04` polygon (the `complete = TRUE` contract —
      assert it rather than assume it)
- [ ] `/code-check` clean per commit
- [ ] `/planning-archive` on completion
