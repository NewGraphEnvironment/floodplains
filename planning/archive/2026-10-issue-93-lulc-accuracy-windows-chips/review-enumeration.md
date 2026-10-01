# /code-check enumeration (terminal) — #93 windows + chips, phase 1

Round 3 named the mechanism: each stage reads what the previous one wrote, and the file does not
record the fact the reader needs, so the reader infers it from how the value looks. Round 3's
finding sat inside round 2's fix: the log-grep did not cover `derive` or the cache. That means an
enumeration, not a quiet round, ends the loop. The candidate set is every drift call and every
file read in the changed code, found by grep (`clear_count(`, `dft_stac_composite(`, `read.csv`,
`read_yaml`, `rast(`).

| # | site | fact the reader needs | source of truth | handled |
|---|---|---|---|---|
| 1 | `window_count-clear.R:126` validate (a) res 100 | read complete | its own log (`> log 2>&1`) + `FORCE=1` | yes, by procedure (drift#87 upstream) |
| 2 | `:127` validate (a) res 20 | same | same | yes |
| 3 | `:152` validate (c), whole floodplain; fills the cache `run` reuses for 2021-07 | same | the **validate** log, named in the header as a cache-filling log | yes |
| 4 | `:188` derive direct 2017 counts, which decide a committed file | same | the derive log (header) | yes |
| 5 | `:217` run, 49 months | same | the run log | yes |
| 6 | `clear_count` integer guard | "this is a day count" | drift's cache key separates the count family (round 3 verified) + the integer check | yes |
| 7 | `clear_count` empty vs failed | "no scene" vs "error" | drift's warning text; any other text falls to `failed` (NA) | yes |
| 8 | derive reading `windows_clear_obs.csv` | month type, failed rows, completeness | `grepl` + `as.integer`; `fp_acc_window_pass` refuses NA, missing and duplicate rows | yes (arms in `accuracy-check.R`) |
| 9 | non-2017 span, per-month union | "each month passes ⇒ the window passes" | count over a union ≥ each month's count (monotone) | yes, sound |
| 10 | 2017 span / widened windows | union coverage | a direct count, span first | yes |
| 11 | `chip_build-composite.R` reading `windows.csv` | `months` is a string | `colClasses = c(months = "character")` | yes |
| 12 | `chip_build-composite.R` `dft_stac_composite()` per chip | chip read complete | the chip-build log. The phase 3 procedure greps it too; a holed chip is also visible to the reviewer as NA | yes, by procedure |
| 13 | `review_build-qgis.R` reading `chips/*.vrt` | which window-years exist | the filenames `derive` → chip builder produced | yes |

Outside this diff and left as-is (round 3 noted them as low):
- The chips pass no `cloud_cover_max`, so they rest on drift's default staying 20, the value
  the counts pass explicitly.
- `windows_clear_obs.csv` records no drift version.
- `YEARS`, `CHIP_YEARS` and the 2017 literal are NECR-specific. That is correct for the only
  area this runs on.

Nothing in the set sits above its source of truth. The loop ends here: 3 rounds plus this
enumeration.
