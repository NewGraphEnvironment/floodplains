# Code review, round 1 (#93 windows + chips, staged diff)

## Findings

- **[severity: bug]** scripts/landcover_accuracy/window_count-clear.R:185-188 with
  scripts/landcover_accuracy/chip_build-composite.R:37,57-60. The file `derive` writes cannot always
  be read back in the shape the reader needs. When the span is one month and 2017 is not widened
  (for example, all four chip years get `"7"`), `windows.csv` holds only digits. `read.csv`
  type-converts that column to integer, and the conversion ignores `quote = FALSE`: quoted digits
  are converted too. Then `months_of()` calls `strsplit()` on an integer and aborts with
  `non-character argument` on the first point. Reproduced:

  ```
  write.csv(data.frame(window="same_season", year=c(2017L,2018L,2020L,2023L), months="7"), quote=FALSE)
  read.csv(...)$months   # int 7 7 7 7
  months_of(7L)          # Error: non-character argument
  ```

  A mixed file such as `"5-8"` alongside `"7"` stays character and works, so only the all-single-month
  case fails. The failure is loud, not silent, but it is a real crash on a legitimate `derive`
  output. Fix it on the read side: `read.csv(win_file, colClasses = c(months = "character"))`, or
  `as.character(s)` inside `months_of()`.

## Checked and found correct

- **Types in `derive`.** `run` writes `month` as character through `count_stats`
  (`fp_acc_months_str`) and as integer in the empty/failed rows. `rbind` makes the column
  character, and `read.csv` converts it back to integer. The `grepl("^[0-9]+$")` filter and
  `as.integer()` then work.
- **Failed rows.** A failed row's `share_ge1` is written as `""` (`na = ""`) and read back as
  numeric `NA`, because blank fields in a numeric column are NA. `fp_acc_window_pass` refuses it.
- **Empty rows** are a measured 0 and fail the bar.
- **Missing and duplicate month-years** are refused. Rows outside the wanted years and months are
  ignored.
- **`fp_acc_window_span`.**
  - It keeps maximal runs correctly: only a prefix directly followed by its extension is dropped.
  - Tie-break is `order(-len, -minv, first)`, matching the prose.
  - The minimum is taken over the years passed in, so when 2017 is excluded the tie-break is
    computed over the other six years.
- **The 2017 deviation** fires only when the all-years span is empty and a span exists without
  2017, as the prose says.
  - A failed direct count stops the run before anything is written.
  - An empty direct count reads as 0 and widening continues.
  - When no candidate passes, the script stops with the HLS fallback.
- **The drift 0.20.0 count** (source read): 0 becomes NA through `count_zero_na`, and a failed
  chunk read is also NA. `count_stats` maps NA to 0 inside the AOI, so a partly failed read lowers
  the share. That errs toward failing a month, never toward passing one.
- **The empty/failed split** still holds under 0.20.0. drift's `composite_skip` warning text
  matches the regex. With one year per call, the empty case aborts "No year produced a composite",
  and that abort is caught as `empty`.
- **Validate (b).** The bound changed from items to distinct dates, which is correct for day
  counting because drift reads at `P1D`. The bbox query is a superset of drift's `intersects`, so
  the bound stays an upper bound.
- **Validate (c).** A failed call stops. An empty result is reported, not scored. The cache key
  includes the AOI, so `run` reuses the result.
- **Early/late `vapply(..., integer(2))`**: `min` and `max` of an integer vector are integer, and
  the empty case is `NA_integer_`. This is type-safe.

## Notes (not bugs; for the author's judgement)

- **Widening tie-break.** `fp_acc_window_widen` breaks a tie between the two neighbours by taking
  the earlier month (`accuracy-check.R` pins this). The pre-registered prose in
  `research/landcover_accuracy.md` does not state this tie-break. Either add a clause to the prose
  before the counts land, or accept it as unregistered.
- **The unwidened span is never counted directly for 2017.** The prose's own argument ("a union of
  months cannot be read off per-month shares") applies to the unwidened span as well. Every span
  month can fail for 2017 on its own while their union clears 95%. The rule, and the code, go
  straight to span+1, so 2017 can end up with a wider window than it needed. Both the prose and the
  code are consistent with each other. This is a rule-design gap to decide before results exist,
  not an implementation defect.
