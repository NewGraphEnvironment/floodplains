## Outcome

The composite windows were the one accuracy-module output with no scenario (#140 left them to #148). Now
`window_count-clear.R run` stamps `scenario` into `windows_clear_obs.csv`, and `derive` refuses counts with
no scenario or another one before it writes `windows.csv` with its own. Two readers in `fp_accuracy.R`,
`fp_acc_windows_read()` and `fp_acc_window_obs_read()`, are the only way in, and every consumer reads
through them, including the chip build's `WINDOWS=` override. With that guard in place, NECR's accuracy
sample was redrawn on `all_ff04`, the published floodplain, at the user's choice (2026-10-23). The catalogue
had retired the species items, and nobody had labelled in either review project. Every reference input
was regenerated on the new draw:
- windows, wetland composition and omission reference;
- dated-imagery and Wayback indexes;
- 1,920 Sentinel-2 chips;
- review projects A and B;
- contact sheets.

The blind model labeller then ran again. The first draw's model labels were discarded unread, and a
dated amendment in the research file records why.

The criterion-4 verdict did not move (0.148 on `all_ff04`, 0.2549 on `ch_ff04`; the bar is 0.30), and
the measured windows were the same months on both floodplains. Two things were learned beyond the issue:
- A printed criterion had been rounded twice: 0.1475 printed as 0.147.
- gdalcubes' warnings are block-buffered, so a `repoprted` line cannot be tied to a point by where it
  sits in the log, and the grep cannot see a log's last block at all (#150).

## Measurement

- **Redraw:**
  - `FORCE=1 sample_draw-pilot.R necr all_ff04` took 7.0 min and was byte-identical on a second run.
  - 16 strata and 480 points, on a footprint of 8,078,287 cells (80,782.9 ha).
  - 1,019,347 change cells after the 1 ha sieve and 204,033 sieved, so the sieve removes 17% of IO's
    change (18% on `ch_ff04`).
- **Windows:**
  - Unchanged: 2017 `8-9`; 2018, 2020 and 2023 `8`. The 2017 Aug–Sep direct count is 0.999.
  - `run` lost 2022-08 and 2022-09 to the transient STAC error "content type 'text/plain'", and
    `derive` lost its 2017 count the same way. A plain re-run fixed both. `repoprted` count 0 in all
    five logs (a check with the blind spot in #150).
- **Wetland and omission:**
  - 2,646 FWA wetland polygons, 12,809.04 ha. `composition-check.R necr` (5) passes at 12,809.04
    vs 12,809.04.
  - Criterion 4 is 0.1475 (7,103 / 48,146 cells) over 481.46 ha and 223 polygons. It used to print
    0.147 because the print rounded an already-rounded value; it now prints `%.4f`.
- **Imagery:**
  - Orthophoto 2021 covers 136 of 480 points (204 on the first draw).
  - Wayback: 89,814 captures over 55 dates. The 2017 capture is within ±1 year at 67% of points,
    the 2023 capture at 49%.
- **Chips:**
  - One process ran at about 73 s a chip (31.5 s on 2026-09-30), so the build was re-run as four
    one-window processes, which took 175 / 208 / 175 / 560 min.
  - Three transient failures came back on the full pass: 1,920 chips, 0 missing.
  - The one `repoprted` line was first credited to `32_00004` by its position. That chip was refetched
    and was identical (0 of 3,969 cells). Round 5 placed the line with `19_00001`, which drift
    refused: 648 `##` lines (~324 cubes) precede it, and the blocks double from 1 to 445 lines.
  - Each window log holds 895 `##` lines for 473 cubes, so ~25 cubes per log left no line.
- **Model labeller:**
  - Contact sheets: 480 in 5.9 min. A Plan canary was clean.
  - 12 Plan batches, 3 at a time, from 08:31:28Z to 08:48:20Z. Each was accepted on the first try,
    with 40 rows, 41 reads and 0 violations. The batches took 175–262 s and 109–118k tokens each.
  - 476 labelled and 4 `cannot_label`; hash `084dafcd3563…`.
- **Checks:** `accuracy-check.R` passes in full. Removing the windows guard turns 4 arms red, and
  removing derive's guard turns 2 red.
- **Review:** `/code-check branch` ran 5 rounds.
  - The code was clean in every round. Each finding was a prose number copied from nearby text or
    left on the first draw.
  - Rounds 1–4 ended on an enumeration of 87 values, none rounded twice.
  - Round 5 ended on re-deriving its fix's eight new numbers from the logs.
- **Subagents:** 19 in all: 1 plan review, 5 rounds, 1 canary and 12 labellers. The plan approved
  the labellers; that is past the usual bound of 5.

## Evidence

- `scripts/landcover_accuracy/logs/20261023_*_necr*` holds the redraw, windows, free reference and
  imagery logs.
- `scripts/landcover_accuracy/logs/20261024_*_necr.md` holds the chip build and the model labels.
- `research/landcover_accuracy.md` holds the restated sections and the dated amendment under "Model
  labeller".

## Owed

- Sync both review projects to Mergin before labeller B starts: the server still serves the first draw.
  This is the user's call.
- #150: decide how the `repoprted` grep's blind spot is stated, or whether the grep is dropped.

Closed by: PR (stacked on #149)
