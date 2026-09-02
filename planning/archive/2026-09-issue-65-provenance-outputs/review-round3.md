# Review round 3 — #65, full branch diff (`main...HEAD` @ `c7a8c1b`)

**Target.** `git diff main...HEAD -- scripts/` at HEAD `c7a8c1b` ("#65 Round-2 review fixes"), plus
the full current contents of all six changed files. Nothing was modified; nothing under
`scripts/run_area.R` was run. A live pipeline run was writing `data/neexdzii/` throughout (files at
12:07 → 12:13), so every measurement below names the artefact and time it was taken against.

**Method.** The brief asked for the MECHANISM, not more instances. So this round is built around one
question asked of every value the branch publishes — *what independent source says what this should
be, and does the code compute that?* — followed by a mutation battery that measures what the guard
can actually see. Round-1 and round-2 findings already fixed are not repeated.

**Baselines, both green before anything was mutated:**

```
Rscript scripts/floodplain_lcc/provenance-check.R                   PASS  (0 FAILs)
Rscript scripts/floodplain_lcc/provenance-check.R neexdzii          PASS  (0 FAILs)
Rscript scripts/floodplain_lcc/provenance_ab-compare.R A B neexdzii PASS  (5 entries)
```

---

## Findings

### 1. **[bug]** `01_network_extract.R:174` — `NETWORK_DIGEST_VAL` omits `channel_width`, which `fl_valley_confine()` reads on every segment. Triple every width and the digest does not move; the floodplain gains at least 2.7 km².

```r
NETWORK_DIGEST_VAL <- c("length_metre", "stream_order", "upstream_area_ha", "map_upstream")
```

The comment two lines above states the contract:

> The VALUE columns are what step 2 actually consumes: `fl_valley_confine()` reads
> `upstream_area_ha` for the bankfull regression and `map_upstream` for precipitation. **A network
> with the same accessible segment set but different upstream areas produces a DIFFERENT floodplain
> and must not hash the same.**

The enumeration is incomplete, and the omitted column is not marginal. From `flooded` 0.5.0's own
body (`deparse(fl_valley_confine)`), measured:

```r
if (is.null(channel_buffer)) {
    channel_buffer <- inherits(streams, "sf") && "channel_width" %in% names(streams)   # -> TRUE
}
...
if (isTRUE(channel_buffer) && inherits(streams, "sf")) {
    has_width <- !is.na(streams$channel_width) & streams$channel_width > 0
    buffered  <- sf::st_buffer(streams_w, dist = streams_w$channel_width/2)            # burned in
}
```

`02_floodplain_model.R` passes no `channel_buffer`, so the auto-enable branch is taken on every run,
and `02:79-81` explicitly coerces `channel_width` to numeric before handing `streams` over — this
repo already knows the column is load-bearing. On neexdzii **all 1915 segments** carry a non-NA
`channel_width > 0` (range 0.8–66.89 m, median 5.35).

Measured on the written `streams_co3` layer, using the branch's own function:

```
baseline                 sha256:fa4d47ea8f03963f9f752acb6ed91abeb59119b6b644e38c10215b82b88469e5
channel_width x3         sha256:fa4d47ea8f03963f9f752acb6ed91abeb59119b6b644e38c10215b82b88469e5  <== UNCHANGED
waterbody_key all NA     sha256:fa4d47ea8f03963f9f752acb6ed91abeb59119b6b644e38c10215b82b88469e5  <== UNCHANGED
gradient +1              sha256:fa4d47ea8f03963f9f752acb6ed91abeb59119b6b644e38c10215b82b88469e5  <== UNCHANGED
upstream_area_ha +1e-6   sha256:d5650d64...                                                       (moves — correct)
```

The baseline is byte-identical to the published `network[co3].outputs.streams_content_sha256`, so
this is the shipped digest, not a re-implementation of it.

And the floodplain really does move. The channel buffer is unioned into the valley mask, so its
ground is guaranteed included:

```
floodplain co_ff04            142.82 km2
channel buffer @1x              6.60 km2   of which OUTSIDE the current floodplain: 0.921 km2
channel buffer @3x             19.71 km2   of which OUTSIDE the current floodplain: 3.636 km2
```

So tripling widths adds **≥ 2.7 km² (≈ +1.9%)** of delineated floodplain — a lower bound, since the
buffer also seeds the cost surface — while `network_content_sha256` **and**
`streams_content_sha256` stay byte-identical. That is precisely the failure the field was added to
end, quoted from the same file:

> Rebuild `fresh` with a different config, a different link, or different data and the recorded hash
> did not move.

`channel_width` is a modelled link/fresh column, so a link rebuild changing its regression is the
realistic trigger, not an exotic one.

**`waterbody_key` is the same hole, one step further out.** `wb_keys` (01:228) selects the
waterbodies layer, and `fl_valley_confine(waterbodies = )` rasterizes it straight into the mask
(`fl_valley_confine` body line 71-74). neexdzii has 202 distinct keys. Neither the column nor the
`waterbodies_<sp><order>` layer appears anywhere in `inputs` or `outputs` — step 1 writes two layers
and `outputs` digests one.

**Fix.** Add `channel_width` to `NETWORK_DIGEST_VAL`; decide `waterbody_key` deliberately (adding it
to the value set covers *which* waterbodies were selected, but not the waterbody geometry itself —
that is the second layer, and #72 territory). Both columns are `is.numeric()` TRUE as read
(`channel_width` double, `waterbody_key` integer, 1074 NAs which `fmt` renders explicitly), so
neither trips the new non-numeric refusal. This changes every recorded network digest, which is
forward-only and free right now: the only two records that exist (`neexdzii`, `bulk`) were both
written today.

---

### 2. **[fragile]** `03_lulc_classify.R:437` — a zero-transition run publishes `transition_raster = "transition.tif"` for a file it deleted four lines earlier

Round 2's finding 2 offered two fixes and called only the second complete; the second was taken:

```r
} else {
  if (file.exists(trans_tif)) unlink(trans_tif)     # 145
  transition_sha <- NA_character_                   # 146
}
...
outputs = list(
  transition_raster         = basename(trans_tif),  # 437 -> "transition.tif", always
  transition_content_sha256 = transition_sha,       #        NA
  transition_patches        = n_transition_patches) #        0
```

The record then says: *there is a file called `transition.tif`, I have no digest for it, and it
holds zero patches* — while `rasters/<scenario>/transition.tif` does not exist. It is the same
internal contradiction round 2 reported (a populated hash beside a zero count), with the two halves
swapped: the digest is now honest and the filename is not. `02`'s parallel field
(`floodplain_raster`) cannot have this problem because that raster is always written.

Bounded honestly: nothing consumes `outputs` yet (it lands with this branch), and `transition_sha =
NA` is the load-bearing signal, so this is not currently a wrong number anyone will act on. It is a
field that names a non-existent artefact, in the block `stac_floodplains_bc` (#17) is being built to
publish, and it is one line: `transition_raster = if (is.na(transition_sha)) NA_character_ else
basename(trans_tif)`.

The zero-transition path is reachable without anything exotic (narrow `change_interval`, raise
`patch_area_min`, small AOI) and it is *not* covered by the wider #68 mismatch the file already
names — #68 is about stale gpkg layers, this is about a name inside the record.

---

### 3. **[fragile]** `provenance-check.R:922-926` — the assertion that licenses digesting the DEM as an object is exercised only on an **INT1U** fixture, and is FALSE for a float raster

```r
robj <- terra::rast(a); terra::values(robj) <- terra::values(robj)
check(terra::inMemory(robj)[1] && !terra::inMemory(terra::rast(a))[1],
      "premise: one fixture is in memory and the other is file-backed (two real code paths)")
check(identical(fp_raster_content_sha256(a), fp_raster_content_sha256(robj)),
      "the SpatRaster form AGREES with the path form (the #65 property)")
```

`a` is written at `provenance-check.R:855` as `datatype = "INT1U"` with values `sample(c(1:5, NA))`.
Integers round-trip exactly through INT1U and `fp_norm_block()` casts both sides to double, so the
two forms **cannot** disagree on this fixture. The property it names is the whole justification for
`02:157` digesting the DEM — a **float** raster — as an object rather than a path, and for the claim
at `fp_provenance.R:314-315`:

> Measured: path, file-backed object and forced-in-memory object all produce the SAME digest

Measured, same fixture geometry, only the datatype changed:

```
SHIPPED FIXTURE (INT1U): object == path : TRUE
FLOAT  FIXTURE (FLT4S) : object == path : FALSE
  path  : sha256:1770f2e90ad599d90e4
  object: sha256:82490ddfd536412e1e1
```

So the sentence in `fp_provenance.R` is true of the raster it was measured on and false as the
general statement it is written as. The mechanism is that a float64 in-memory raster and its FLT4S
on-disk form hold different values, and `fp_norm_block()` deliberately does not quantize.

**The consequence is a machine axis, and it is the one question 3 asked for.** terra spills to
`FLT4S` (measured: `datatype()` on a spilled `SpatRaster` is `FLT4S`), and whether it spills depends
on free memory:

```
r*1, values float64, in memory   -> sha256:420b4650dc0f90fe8d3
r*1, same, terraOptions(todisk)  -> sha256:83d548305c77071652a     DIFFERENT, same data
```

**Today's pipeline is safe, and only by accident.** `fl_dem_aoi()` is `crop()` then
`project(r_clip, target_crs$wkt)`, and I measured that terra's `project()` output digests identically
in memory and spilled — its values are already Float32-representable:

```
project() output, todisk=FALSE -> sha256:55e44f8251c44f02760   inMemory TRUE
project() output, todisk=TRUE  -> sha256:55e44f8251c44f02760   inMemory FALSE, FLT4S
```

That is a property of terra's projection internals, not of anything this code asserts. The fix is a
second §5c fixture at `datatype = "FLT4S"` with float64 in-memory values — which would go **red**
today, so it is a decision (quantize in `fp_norm_block`, or narrow the claim to "for the rasters this
pipeline produces, measured") rather than a one-line patch. At minimum the sentence at
`fp_provenance.R:314-315` should say which raster it was measured on, the same way §5c's own
`block_rows` comment already refuses to let a 40-row fixture stand for a 512-row default.

---

## 2. The mechanism, and a structural fix

### The mechanism, measured

Every property in `provenance-check.R` is about a **key set, a shape, or a closed vocabulary**.
Nothing reads a value and compares it to anything outside the file. The fixtures make this explicit:
`good_prov()` builds all three `outputs` blocks as
`setNames(as.list(rep(NA, length(KEYS_*_OUTPUTS))), KEYS_*_OUTPUTS)` — every published value is `NA`
in the only input the guard is ever exercised against.

So it is not that a value slipped past. **No value can be seen at all.** I mutated each published
value in a copy of the real `data/neexdzii/provenance.json` and re-ran `provenance-check.R neexdzii`:

| mutation to the real record | result |
|---|---|
| `landcover.outputs.transition_patches` → 999999 | **0 FAILs, PASS** |
| `floodplain[co_ff04].outputs.valley_cells` → 1 | **0 FAILs, PASS** |
| `network.outputs.n_segments` → 1 | **0 FAILs, PASS** |
| `floodplain[co_ff04].outputs.floodplain_content_sha256` → `sha256:deadbeef` | **0 FAILs, PASS** |
| `landcover.outputs.transition_raster` → `does_not_exist.tif` | **0 FAILs, PASS** |
| `floodplain[co_ff04].outputs.floodplain_raster` → `floodplain_ch_ff99.tif` | **0 FAILs, PASS** |
| `network.outputs.streams_layer` → `streams_ch9` | **0 FAILs, PASS** |
| `network.inputs.network_content_sha256` → `sha256:0` | **0 FAILs, PASS** |

Eight for eight. And the same blindness at the producer end — mutating the step scripts on a mirror
and running the offline suite:

| mutation to a producer | offline suite |
|---|---|
| `n_transition_patches <- nrow(trans_all$summary)` (round-2 bug #1, restored) | **0 FAILs** |
| `valley_cells = terra::ncell(valleys)` (every cell, not the valley cells) | **0 FAILs** |
| `n_segments = nrow(streams) + 1L` | **0 FAILs** |
| remove `unlink(trans_tif)` (round-2 bug #2, restored) | **0 FAILs** |
| `LNK_BUILD_CONFIG <- "bcfishpass"` | 1 FAIL ✓ |
| `hdr <- ""` / drop `cols=` in the table digest | 1 FAIL ✓ (round-1 finding 7 is genuinely closed) |

**Neither of round 2's two bugs can be caught by any guard on this branch, before or after the fix.**
That is the class, stated as a measurement rather than an impression.

### The structural fix: one guard, `§7c RECONCILE`

One shape covers the whole class: **for a named area, every value in `outputs` either names an
artefact on disk or counts one — so open the artefact and re-derive it.** §7 already resolves
`data/<area>/` and already parses the config; it just never opens a file.

I prototyped it (~50 lines, `sf` + `terra` + the branch's own two digest functions) and ran it
against the live record:

```
  ok    network[co3] streams_layer 'streams_co3' is a layer of the gpkg
  ok    network[co3] n_segments 1915 == layer feature count 1915
  ok    network[co3] streams_content_sha256 re-derives from the written layer
  ok    floodplain[co_ff02] floodplain_content_sha256 re-derives
  ok    floodplain[co_ff02] valley_cells 141504 == cells==1 in the raster
  ok    floodplain[co_ff04] valley_cells 153836 == cells==1 in the raster
  ok    floodplain[co_ff06] valley_cells 161555 == cells==1 in the raster
  ok    landcover[co_ff04] transition_content_sha256 re-derives
  ok    landcover[co_ff04] transition_patches 2032 == transition_co_ff04_2017_2023 feature count 2032

RECONCILE PASS
```

...and it goes red on every one of the mutations in the table above (each mutation → `RECONCILE FAIL
- 1`). So it can be shown able to fail, which is the bar this repo sets.

Three things about the shape, because the honest version is more useful than the flattering one:

- **The count arms are genuinely independent.** `n_segments` vs an OGR feature count, `valley_cells`
  vs `sum(values(r) == 1)`, `transition_patches` vs the transition layer's feature count. These come
  from the artefact, not from the producer's arithmetic. They are the arms that would have caught
  round-2's 48-vs-2032.
- **The digest arms are only semi-independent** — they re-run `fp_raster_content_sha256` /
  `fp_table_content_sha256`, so they verify *"the record describes THIS file"*, not *"the digest
  function is right"*. That is still exactly the property round-2 finding 2 broke (a digest of a
  previous run's raster), so it is worth having; do not oversell it as a check of the digest itself.
- **The name arms are trivial and were the cheapest catch:** `file.exists()` on
  `floodplain_raster` / `transition_raster`, `layer %in% st_layers()` on `streams_layer`. Finding 2
  above falls straight out of one of them.

Two implementation notes from writing it, both of which bit:

- `identical(as.numeric(o$valley_cells), sum(values(r) == 1, na.rm = TRUE))` reports **3 of 3
  mismatches** on a correct record — `sum()` of a logical returns **integer**, the JSON value parses
  as double, and `identical()` is type-strict. This is the `code-check.md` "a probe reporting that
  EVERYTHING is broken" case; coerce both sides.
- A mutated `streams_layer` makes `st_read()` **error** rather than fail the check. Guard the read
  and report, or the guard aborts instead of reporting.

If §7c is judged too heavy for the offline path, note it is naturally gated the same way §7 already
is — it only runs when an area is named, which is exactly when the artefacts exist.

---

## 3. Machine / session dependence — what I checked

| axis | result |
|---|---|
| **float64 object vs FLT4S file/spill** | **REAL, finding 3.** Different digests, same data. Not reachable through today's `fl_dem_aoi()` path (measured), unasserted either way. |
| projected DEM losing its EPSG authority code → `WKT:` fallback | **Clean.** `terra::crs(project(r, st_crs(streams)$wkt), describe=TRUE)$code` is `3005`. The 1554-char PROJ-rendered WKT branch is not reached. The comment at `fp_provenance.R:344-347` claimed this measured on classified rasters only (EPSG:32609); it now also holds for the DEM's BC Albers path. |
| `sort(method = "radix")` C-collation in the table digest | Clean, and its premise is asserted. |
| `serializeVersion` pin | Clean, exercised both ways in §5c. |
| `options(scipen)` | Clean, exercised both ways in §5e. |
| `LC_NUMERIC` reaching `sprintf("%.6f")` / `sprintf("%.9f")` | **Still open** — round-1 finding 4, not fixed on this branch. R forces `"C"` at startup so it is not env-reachable, but it is `.Rprofile`-reachable, which is the same reachability argument the file uses to justify pinning `serializeVersion`. Not re-litigated here. |
| GDAL/PROJ-warped DEM inside hashed `inputs` | **Still open** — round-2 finding 3. `02:140-155` now argues the case in the code rather than closing it, and names the cross-machine measurement as filed rather than done. That reads as a deliberate decision, so no action asked here. |
| `jsonlite` number formatting reaching `inputs_hash` | Pre-existing (`fp_prov_hash`, not in this diff). `outputs` carries no floats — three integers and four strings — so `outputs_hash` does not add exposure. |
| terra spill of the DEM (memory-pressure dependence) | Clean for `project()` output, measured both ways. See finding 3. |

---

## 4. Assertions that cannot fail, or whose fixture cannot reach the property

- **`provenance-check.R:926`** — finding 3 above. The one real instance.
- **`fp_provenance.R:444`, `hdr` `n=` component** — deleting `n=` from the table digest header
  leaves the whole suite green (measured). Unlike the `cols=` half (which round 1 closed and which
  now goes red correctly), I could not construct *any* input where `n=` matters: an empty table
  already separates from a one-row table by the newline, and rows are never deduplicated. It is
  redundant rather than unguarded, so **not a finding** — but the comment at `:442-443` credits
  `n=` with the empty-table distinguishability it does not actually supply. Same "the label names a
  mechanism the predicate does not test" shape as round-1 finding 7, one clause over.
- **`provenance-check.R:1265`, `check(length(lit) == 0L, "no lnk_config() call site names a bundle
  literally")`** — passes when there are zero `lnk_config()` calls at all, and when a call site uses
  a *variable* other than `LNK_BUILD_CONFIG`. Paired with the `assign_lit` check it is adequate
  today; noted, not reported.

Everything else I tried to break, broke correctly. Positive evidence, so a clean line is not mistaken
for an unrun check: §1's four `outputs_hash` separation arms (routed through `fp_prov_set` and read
back off disk, so they can see a `fp_prov_hash(value)` mutant), §2's six new `outputs` arms, §2's
`SECTIONS_WITH_RASTERS` scope-moving mutant, §5c's `block_rows`-by-value pin and its in-memory
premise, §5e's duplicate-composite-key pair and the `same_vals` column-swap (round-1 finding 7's
fix — verified red with the header removed), and §6's `assign_lit`/`lit` pair.

---

## What I verified and found CORRECT (the value sweep, question 1)

The candidate set is closed and enumerable: it is `KEYS_NETWORK_OUTPUTS ∪ KEYS_FLOODPLAIN_OUTPUTS ∪
KEYS_LANDCOVER_OUTPUTS` plus the four fields the diff adds to `inputs`. All 16, each against a source
outside the code that wrote it:

| value | independent source | result |
|---|---|---|
| `n_segments` = 1915 | `ogrinfo streams_co3` → Feature Count 1915 | ✓ exact |
| `streams_content_sha256` | re-derived from the written gpkg layer | ✓ byte-identical |
| `streams_layer` | layer present in `aquatic_network.gpkg` | ✓ |
| `network_content_sha256` | **bulk vs neexdzii** — two independent step-1 runs, same WSG/species/order/schema, one subset and one not: `37edc39d…` **identical** in both, and identical to bulk's own post-subset `streams_content_sha256` while differing from neexdzii's. Exactly what the design predicts. | ✓ (scope gap = finding 1) |
| `link_config_name` = `bcfishpass` | `link_log.config_name` = `bcfishpass`; `lnk_log_read()` is `DISTINCT ON (watershed_group_code) … ORDER BY date_start DESC`, so `row[1,]` is the LATEST run, not an arbitrary one | ✓ |
| `link_config_name_source` = `link_log` | closed vocabulary, guarded, and correct for a GRAB | ✓ |
| `valley_cells` 141504 / 153836 / 161555 | `sum(values(tif) == 1)` → exact match on all three; 153836 × 928.4114 m² = **142.82 km²**, which is CLAUDE.md's re-baselined `co_ff04` contract of 142.8 km², and equals the polygon area to 2 dp | ✓ exact |
| `floodplain_content_sha256` ×3 | re-derived from each `floodplain_*.tif` | ✓ identical |
| `floodplain_raster` ×3 | files exist | ✓ |
| `transition_patches` = 2032 | `ogrinfo transition_co_ff04_2017_2023` → 2032, and `distinct(name_basin, patch_id)` = **2032** (so every row is a distinct patch under the composite key, not a multi-part duplicate — `distinct patch_id` alone is 1973, which is the per-sub-basin collision the bridge comment describes, not a patch-splitting artefact) | ✓ round-2 fix confirmed live |
| `transition_content_sha256` | re-derived from `rasters/co_ff04/transition.tif` | ✓ identical |
| `transition_raster` | file exists in the non-empty case | ✓ / finding 2 for the empty case |
| `dem_content_sha256` | **no independent source exists on one machine** — the DEM is never written and `fl_dem_aoi()` builds its URL internally. `dem_ncell` 6533563 and `dem_res_m` 30.469844 match the floodplain raster's grid exactly, so the geometry corroborates; the heights do not. This is round-2 finding 3 + the code's own OPEN note. | not closeable here |
| `dem_crs_epsg` / `dem_res_m` / `dem_ncell` | `rast(floodplain_co_ff04.tif)`: 3005 / 30.46984 / 6533563 | ✓ exact |
| `network_layer` = `streams_co3` | matches step 1's `streams_lyr` | ✓ |

Also checked clean and worth recording:

- **`streams` is reassigned by the subset** (`01:221-222`), so `outputs` really is post-subset and
  `n_segments` really is the written layer's count. The whole-WSG identity holds (`bulk`:
  `network_content_sha256 == streams_content_sha256`), which is a live proof of the comment at
  `01:386-389` rather than a restatement of it.
- **`n_transition_patches` is not inside a loop** and is initialised to `0L` before the vector branch,
  so the zero-transition path cannot reach the provenance write undefined.
- **`terra::writeRaster(datatype = "FLT4S")` pin** — the written `floodplain_co_ff04.tif` holds only
  `0` and `1` with **no NA cells**, so the nodata sentinel the pin protects is not exercised on this
  area and the pin costs nothing.
- **`provenance_ab-compare.R`** — `sect <- sub("\\[.*$", "", k)` matches `entries()`'s
  `paste0(s, "[", k, "]")` construction; `source(fp_provenance.R)` introduces no side effects beyond
  definitions; the two `FAILS <<- FAILS + 1L` silent increments are now `bad()` calls with messages
  (a real improvement — a silent count was an unreadable failure). Ran it end to end: 5 entries, both
  hashes reported per entry, PASS.

---

## 5. Convergence

**The value axis has converged. The guard axis has not, and I am not claiming it has.**

What I enumerated, so the claim is checkable rather than asserted: the candidate set for question 1
is *closed by construction* — it is the three `KEYS_*_OUTPUTS` constants (which `viol_keys` already
enforces as a two-way whitelist, so no fourth value can appear without failing §3) plus the four
fields the diff adds to `inputs`. Sixteen values. Each was checked against a source outside the code
that produced it; fourteen reconcile exactly, one is finding 2, and one (`dem_content_sha256`) has no
single-machine independent source and is already filed as round-2 finding 3 plus the code's own OPEN
note at `02:151-155`. There is no seventeenth value to find.

Findings 1 and 3 are a different axis and I can name what would terminate each:

- **Finding 1** is *scope*, not *count* — "does the digest cover everything the downstream step
  reads?" The terminating enumeration is the column list in `01`'s `SELECT` (11 attribute columns)
  crossed against what `flooded` actually reads. I did that cross: `channel_width` is consumed by
  `fl_valley_confine` and omitted; `waterbody_key` is consumed indirectly via the waterbodies layer
  and omitted; `gradient`, `gnis_name`, `id_segment` and `linear_feature_id` are **not** referenced in
  `fl_valley_confine`'s body (measured) and are correctly out. `upstream_area_ha` and `map_upstream`
  are in. So that enumeration is complete against `fl_valley_confine` — but it is **not** complete
  against `fl_valley_attribute` (#40's per-watercourse pass), which I did not read. That is the one
  named next place to look, and it is bounded.
- **Finding 3** is one instance of "the fixture's datatype decides which branch runs". The complete
  candidate set is the datatypes this pipeline digests: `INT1U` (classified), `INT4S` (transition),
  `FLT4S` (floodplain mask, DEM). §5c covers `INT1U` only. Two more fixtures close it and there is no
  level above that, since `fp_raster_content_sha256`'s only type-sensitive step is
  `fp_norm_block()`.

**Two prior "terminal" judgements in this repo were wrong**, so the useful framing is not a verdict
but a prediction: as long as no guard reads a value, the *next* defect in this family will look
exactly like round 2's two and land in `main` the same way — invisible to a green
`provenance-check.R <area>`, discovered by a human comparing a published number to an artefact.
§7c is what changes that, and it is the only item here I would call blocking-shaped. Findings 1 and
2 are one-line fixes; finding 3 is a decision that needs stating either way.

---

## Process notes

- The working tree was live throughout (`data/neexdzii/` written at 12:07 and 12:13). All guard runs
  were against a **mirror** in the scratchpad (`scripts/floodplain_lcc` copied whole, plus
  `config/neexdzii` and a copy of `provenance.json`), never against the repo. No repo file was
  modified; `restore()` re-copied from the repo before every mutation.
- The in-flight run re-ran step 3 mid-review, so `transition_patches` moved from **48** to **2032**
  under me. The 48 → 2032 transition is therefore confirmed live, not inferred. Note that
  `provenance-check.R neexdzii` **passed on both files** — before and after the 42× correction —
  which is the single cleanest statement of the mechanism in section 2.
