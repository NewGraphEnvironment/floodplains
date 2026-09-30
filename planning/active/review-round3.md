# Code review, round 3 (#93 windows + chips, staged diff): the mechanism

## The mechanism behind rounds 1 and 2

Each stage reads something the stage before it produced. The artifact does not record the fact the
reader needs, so the reader works it out from what the artifact looks like. That works most of the
time, because the proxy usually agrees with the fact. All three earlier findings are this:

| round | artifact | fact the reader needed | proxy it used instead |
|---|---|---|---|
| 1 | `windows.csv` | `months` is a string | the cells look like numbers, so `read.csv` made them integers |
| 1 | per-month stats | whether a multi-month window is clear | whether each month in it is clear |
| 2 | `clear_count()` result | whether the count is complete | `status == "ok"`, meaning no R error was raised |

The general form: **when nothing went wrong, the value is taken to mean the thing.** Below is
every place in this diff where that happens, and whether each is handled.

## Findings

- **[severity: fragile]** `scripts/landcover_accuracy/window_count-clear.R:24-29` (the documented
  remedy) against `:177-196` (the direct counts in `derive`).
  - **The problem.** The drift#87 check tells you to grep **`run`'s** stderr before running
    `derive`. But `derive` makes its own `clear_count()` calls (the 2017 span, then each wider
    window), and it writes `reference/<area>/windows.csv` in the same process, a few lines later.
    Nothing tells anyone to capture or grep `derive`'s stderr, and nothing could happen between the
    count and the write anyway.
  - **Why it matters.** A failed chunk read in a direct count lowers that window's share. The
    window is rejected, and 2017 gets a wider window than it needed. That wider window goes into a
    committed reference input, and no error is raised.
  - **The header also understates the failure.** It says a failed read comes back "`ok` with a
    LOWER share". That is the partial case. If every chunk of a window fails, every cell is NA.
    drift then emits "Skipping … no clear pixels", and `clear_count()` records `empty`: a measured
    zero (`share = 0`). The run log shows the gdalcubes warning next to an `empty` row, so a reader
    checking only for low `ok` shares would not connect the two. Either way the month fails the
    bar and never passes it, but the span moves. `fp_accuracy.R:373-374` says that must not
    happen.
  - **The fix is a procedure change, not local detection.** Extend the documented step to
    `derive`: run it with `2>&1` into a log, grep that log, and treat a hit as invalidating the
    `windows.csv` it just wrote.

- **[severity: fragile]** `window_count-clear.R:24-29`, together with drift's cache
  (`dft_stac_composite.R:245-251`).
  - **The problem.** A cache hit prints only `"  count <label>: cached"`. No gdalcubes read
    happens, so no chunk warning can appear. The grep therefore only sees failures from the
    process that first computed each month. Any month computed earlier and served from cache
    carries its evidence in an older log, or in none. That covers three cases:
    - `validate (c)`'s 2021-07, logged to `window_validate_*.log`;
    - any aborted or earlier `run`;
    - the re-run that `task_plan.md` prescribes for `failed` rows ("a cached month is free").
  - **Why it matters.** "Grep the `run` log" reads as covering all 49 month-years. After any
    re-run it covers only the months that re-run actually fetched.
  - **Current state, measured.** It holds for NECR right now, by circumstance:
    - `~/Library/Caches/drift/v2/sentinel-2-l2a/count_*.tif` holds only files written from
      11:00:27 today, by the validate run and this run.
    - `grep -c chunks` finds 0 in both `window_validate_20260930.log` and
      `window_run_20260930.log`.
  - **The fix.** State that the grep covers every log that populated the cache for these keys:
    validate, every `run` and every `derive`. It is not just the last `run`.

- **[severity: fragile]** `window_count-clear.R:27-28` against `:80-87` (`clear_count`).
  - **The problem.** The remedy says to re-run a hit "with drift's `force = TRUE`", but
    `clear_count()` has no `force` argument and no environment variable passes one through. So
    the remedy can only be done by hand, calling `drift::dft_stac_composite()` outside the script.
  - **Why it matters.** That hand call must reproduce every part of the cache key:
    - the same AOI geometry, `res = 100`, `crs = crs_grid` and `clip = TRUE`;
    - `bands = "red"`, `aggregation = "count"` and `cloud_cover_max = 20`;
    - the same months and year.

    Any difference writes a **different** key. The script then keeps serving the bad file, and the
    operator believes it was refreshed. The script prints no cache path or key, so deleting the
    right `count_<key>.tif` by hand is not practical either.
  - **The fix.** A `FORCE=1` passthrough to `clear_count()`'s drift call makes the documented
    remedy reachable from the script. This is the recovery path, not local failure detection, so
    it does not work around drift#87.

## Every place the mechanism reaches in this diff

| where | proxy | status |
|---|---|---|
| `chip_build-composite.R:38`, `months` read-back | shape gives the type | **handled** (`colClasses`) |
| `window_count-clear.R:155-157`, `derive` reading `windows_clear_obs.csv` | `month` type; blank means NA | **handled**: `grepl` plus `as.integer`. `na = ""` reads back as NA and `fp_acc_window_pass` refuses it. Missing or duplicate rows are refused. |
| span for the non-widened chip years | a union of passing months is taken as passing | **handled, and sound**: the count over a union is at least the count in each month, so each month ≥ 0.95 gives union ≥ 0.95 |
| span for 2017 | per-month shares taken as the union's share | **handled** (round-2 fix, span counted directly first) |
| widening order (`fp_acc_window_widen`) | per-month share used to rank neighbours | **accepted design**: pre-registered, and acceptance is always a direct count |
| `run`: `ok` taken as complete | no R error means a full read | **accepted** (drift#87, documented grep) |
| `derive` direct counts: `ok` taken as complete | same | **not handled**: finding 1 |
| total read failure recorded as `empty` | "no clear pixels" taken as a measured zero | **not documented**: finding 1. It fails the bar, never passes it. |
| cache hit taken as evidence already seen | the latest log taken to hold every month's evidence | **not handled**: finding 2 |
| documented `force = TRUE` remedy | "re-run" taken as refreshed | **not reachable**: finding 3 |
| `clear_count:105` integer test as "this drift counts days" | whole numbers taken as day counts | **handled upstream**. drift's key separates the `count` family, the `P1D` read step and `mask_values` (snow). A 0.18–0.19 reflectance cache, or a pre-snow-mask count, cannot be hit (`dft_stac_composite.R:525-529`). |
| `empty` recognised by drift's warning text | the text taken as the cause | **handled**: if the text changes, the month falls to `failed` |
| validate (b) bound | bbox items over distinct UTC dates as the day bound | **handled**: the bbox is a superset of drift's `intersects` query, so it is still an upper bound |
| chips described by the counts (`CC_MAX` comment, `:52`) | "drift's default" taken as 20 in both places | **not handled, not in this diff, low**: `chip_build-composite.R:69` passes no `cloud_cover_max`, so it follows drift's default. It equals 20 today (`dft_stac_composite.R:170`). If the default changes, the counts no longer describe the chips, and nothing notices. |
| `windows_clear_obs.csv` provenance | the file taken to describe the current floodplain and drift | **not handled, low**: it records no scenario, AOI or drift version. If `primary_scenario` changed between `run` and `derive`, `derive` would combine an old span with direct counts on the new floodplain. |
| `YEARS`, `CHIP_YEARS`, the literal `"2017"` | a literal taken to be the area's endpoints | **not handled, low**: `cfg$change_interval` is ignored. NECR uses the default, so this is correct today, but for an area with another interval `derive` would chip the wrong endpoint years. |

## Checked and found correct

- `accuracy-check.R` reports ALL PASS when re-run (read-only, sources `fp_accuracy.R` only).
- The frozen run copy differs from the staged script only in the header comment and the span-first
  line. `run` reaches neither, so the CSV the live run writes is the one `derive` expects.
- `vapply(months_by_year, …)` returns a named vector, so the data frame gets row names `2017` and
  so on. `write.csv(row.names = FALSE)` drops them, so this is harmless.
- The live run log shows `0 items returned` for 2017-04, 2017-05 and 2017-07 at cloud ≤ 20. These
  come from the STAC query, not from a read failure, so they are the real zeros the rule is meant
  to see, and `empty` is the correct status for them.
