## Outcome

Generalized the one-off `fire_tag.R` into a config-driven, layer-agnostic disturbance-attribution
step wired into `fp_lulc`. `scripts/floodplain_lcc/fp_disturbance.R` (`fp_disturbance_tag`) tags each
transition (change) patch with, per source declared in the shared `config/disturbance.yml`, `in_<name>`
+ the dominant overlapping feature's carried attributes, windowed to `cfg$change_interval` (default
2017–2023, hoisted so the transition years and the attribution window share one value). Attribution is
additive (a patch may match several sources; salvage = fire AND harvest); the residual (matches none)
is the classification-noise floor. Sources are province-wide DataBC layers loaded into fwapg via
`bc2pg`, and the routine pushes the AOI bbox into the SQL server-side so a huge layer (121,836
cutblocks) never streams into R. Opt-in by file presence: no `config/disturbance.yml` ⇒ step 3 runs
unchanged (no DB conn, no columns). `fire_tag.R` refit as a thin CLI wrapper (re-tag an existing gpkg
without the ~30-min STAC fetch) that doubled as the parity harness.

**Verified:** fire-only parity exact (wrapper: BULK 103.2 / MORR-co 27.1 / MORR-ch 29.4) and
essentially exact wired in-pipeline (BULK 103.22, MORR 27.07 — within ±0.5). Multi-source payoff (fire
+ harvest): harvest explains **~30–36%** of floodplain tree loss previously buried in the "95% noise"
bucket (BULK: fire 5% / harvest 36% / residual 62%), and the residual dropped 95%→62–65%. Per-source
shares sum >100% by ~3% = burned-and-logged salvage, correctly excluded from the residual.

**Scope (deliberate):** fire + harvest wired; **pest/forest-health deferred** (weaker evidence; the
config contract already supports it via `filter:` + `confidence:`). The transition layer now carries N
disturbance attributes → the STAC publish schema must too (stac_floodplains_bc#6, already filed).

**Learned:** (1) the Plan-agent design review caught the harvest-layer bbox-prefilter blocker (a
province-wide layer without a server-side spatial filter OOMs), the in-memory-vs-re-read parity risk
(a non-issue in practice — 0.02 ha), and the missing DB conn / hardcoded change interval — all before
any code. (2) A reversed `change_interval` foot-gun (loss/gain silently swapped) was caught in
code-check and fixed with `sort()`. (3) **A parallel Claude session switched the shared git working
tree mid-Phase-1**, floating my uncommitted work on their branch — recovered by backing up + checking
out branch 19; the durable fix is separate worktrees per session. Commit + push early.

Closed by: PR #26 (commits ffc77a7 → 7f19294 on branch 19-config-driven-layer-agnostic-disturbance)
