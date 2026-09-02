# Task: Verify #33's provenance block against a live database (link log row + neexdzii parity A/B) (#63)

## Problem

#33 shipped the per-area provenance block (PR #62) with every offline assertion exercised against
input built to break it — but one half of its first acceptance criterion has never run: the
**end-to-end neexdzii A/B against a live fwapg**. #63 was itself filed on a false premise
("postgres is down" — a bad probe, not an outage); connecting properly closed most of it and found
a real bug (`pq__text`, fixed in 2406548). What remains is the run.

This is a **verification** issue. The expected code delta is near zero; the deliverables are
measurements, a committed evidence log, and answers written back into the issue body.

## Pre-flight measured before planning (read-only, 2026-09-02)

| fact | value |
|---|---|
| `fresh-db` | up 7 weeks, healthy, `0.0.0.0:5432`, `pg_isready -h localhost` OK |
| province rebuild (the stated blocker) | **finished** — last `fresh.log` write 01:25Z, no R processes; BULK done 00:27Z |
| BULK log row | `run_uid 20260901_234743-6628379d`, link 0.50.0, sha `689146867a…`, dirty false |
| freshness guard | grab 2205.70 km vs bcfp 2205.57 km = **0.006% dev** (tol 2%) — will pass |
| network stability across the rebuild | **all 1915** on-disk `streams_co3` segments present in rebuilt `fresh`, `length_metre` diff 0 |
| parity numbers off current outputs | **673.5 km / 142.8 km² / 770.0 ha** — reproduce exactly |
| `provenance.json` | **absent from every `data/<area>/`** — the A/B creates it from scratch |
| this machine | m1. m4 reachable, has the checkout, and can reach m1's postgres |

Measurement method: `sum(st_length(streams_co3))/1000`; `sum(st_area(co_ff04))/1e6`;
`sum(area_ha[from_class == "Trees"])` on `transition_co_ff04_2017_2023`.

## Deliberately out of scope

- **No flooded/drift upgrade.** m1 has flooded 0.5.0 / drift 0.8.0 installed with checkouts at
  0.6.0 / 0.10.0. Upgrading flooded moves the delineation and breaks the 142.8 km² contract.
  Phase 3 reinstalls **link only**.
- **No writing to the publish layer.** The coupling stays one-way.

## Phase 1: Baseline capture and pre-flight

- [ ] Back up `data/neexdzii/` to the scratchpad so a moved number is diffable, not just reported
- [ ] Record pre-run state to `findings.md`: parity numbers, `fresh.log` BULK row, installed vs
      checkout versions/SHAs for link/flooded/drift/fresh on m1
- [ ] `Rscript scripts/floodplain_lcc/provenance-check.R` green offline (no area arg) before any run
- [ ] Confirm no other session is writing `data/neexdzii/` (the writer is read-modify-write over one file)

## Phase 2: m1 end-to-end A/B (the core deliverable)

Two full `run_area.R neexdzii 1,2,3` passes under `caffeinate -s`, logged to the gitignored
`scripts/floodplain_lcc/logs/runs/`. **Gate on the in-band error count and the output mtime, never
the wrapper's exit code** — a crash before the write makes the A/B compare a stale file against
itself and pass.

- [ ] Pass 1: assert `grep -c 'Execution halted\|^Error' == 0`; snapshot `provenance.json` to scratch
- [ ] Pass 2: assert 0 errors **and** `provenance.json -nt` the snapshot
- [ ] `inputs_hash` **identical** across passes for all three sections, compared per section key —
      not by whole-file diff
- [ ] `run.datetime_utc` **differs** in all three sections
- [ ] `Rscript scripts/floodplain_lcc/provenance-check.R neexdzii` exits 0
- [ ] Parity unmoved: **673.5 km / 142.8 km² / 770.0 ha**
- [ ] `link_log` non-null; `config_hash` matches `fresh.log` for BULK; `run_uid` populated;
      `link_log$link_sha` populated (written by link at pipeline time — distinct from
      `fp_pkg_stamp("link")`, which the issue body conflated with it)

If parity moves: that is an **upstream network change, not a provenance defect** — record it with
the provenance block as the artifact that explains it, and do not silently re-baseline.

## Phase 3: link 0.50.0 reinstall, step-1-only pass

- [ ] Install link 0.50.0 from `~/Projects/repo/link` (clean at 2b5a435), matching the version that
      built tonight's `fresh`
- [ ] `Rscript scripts/run_area.R neexdzii 1` (GRAB — fast)
- [ ] `fp_pkg_stamp("link")` now resolves: `sha` populated, `sha_source` naming the git-walk tier,
      `dirty` FALSE — where it previously read `unresolved (checkout … is 0.50.0, installed is 0.47.3)`
- [ ] Network `inputs_hash` **changed** (correct — different code is a different input) while
      `floodplain` and `landcover` are untouched, confirming the forward-only per-section merge

## Phase 4: m4 cross-machine leg

m4 points at **m1's database over tailscale** — sharing the DB isolates the machine variable
instead of confounding it with a different restore. m4 is currently far behind: floodplains at
f0d6fb3 (pre-#33), link 0.40.2, flooded 0.3.0, drift 0.6.0, no `PG*` in `~/.Renviron`.

- [ ] Bring m4's floodplains to `main`; mirror the four package checkouts to m1's SHAs
      (link 2b5a435, flooded 1eaaaa0, drift b61f002, fresh dc48ca4)
- [ ] Install to match m1's **installed** set: link 0.50.0 (from checkout), flooded 0.5.0, drift 0.8.0
- [ ] Point m4 at m1's postgres. Copy `PG*` **through a pipe that never prints the value** —
      reading a secret clamps the rest of a session, so this phase is sequenced last and verified
      only by a connection test
- [ ] Full `run_area.R neexdzii 1,2,3` on m4, same error/mtime gating
- [ ] Compare `inputs_hash` per section against m1's post-Phase-3 file, and **classify** every
      divergence: (a) genuine code difference, (b) install-route / checkout-state artifact,
      (c) real determinism bug

**Predicted before running, so it is not mistaken for a bug:** `fp_pkg_stamp`'s tiers make
`inputs_hash` sensitive to the *developer's checkout state*, not only to the code that ran — an
`unresolved (checkout … is X, installed is Y)` string enters the hash. Mirroring the checkouts is
what makes this leg an equality test rather than a guaranteed mismatch. If it holds, it is a real
(b)-class limitation of #33's design and becomes a follow-up issue.

## Phase 5: Record, and close

- [ ] Committed evidence log `scripts/floodplain_lcc/logs/20260902_provenance_live-verify_neexdzii.md`
      (curated evidence lives directly under `logs/`; `logs/runs/` is gitignored bulk)
- [ ] **Edit the #63 body** so it reads correctly top to bottom with every checkbox answered —
      including the `link_sha` conflation, which the body currently states wrongly
- [ ] CLAUDE.md only if a durable, generalisable lesson lands (a (b)/(c) finding)
- [ ] File a follow-up issue for anything genuinely unrunnable — but establish it is really blocked
      first; #63 is the cautionary example of an issue filed on a false premise
- [ ] `/planning-archive` with **Measurement** and **Evidence** sections; `/gh-pr-push`

## Validation

- [ ] Every long run gated on in-band error count + output mtime, never exit code
- [ ] `provenance-check.R neexdzii` exits 0
- [ ] `/code-check` clean on each commit
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion
