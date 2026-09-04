# Progress — Modernize the README, publish via Pages, set description + homepage (#77)

## Session 2026-09-04

- Plan-mode exploration; a Plan subagent reviewed the draft against the issue and the codebase and
  returned 3 blockers, 4 ordering findings and 9 acceptance gaps. Its review is in
  `planning/active/review-77.md`; every finding was verified in this checkout before being folded
  in, and two changed the design outright (drop the elevation cross-section; build the figures
  from `data/bulk/` rather than the unrostered `neexdzii`).
- Phases approved by the user, with two content steers: tighten the prose to plain language, and
  reframe the disturbance section around the attribution framework being layer-agnostic — fire and
  harvest are what `config/disturbance.yml` lists today, not the limit of what it takes.
- Created branch `77-modernize-the-readme-publish-it-via-gith` off main; scaffolded the PWF
  baseline (`a555f0a`).
- **Phase 1** — repo description set via `gh api -X PATCH` (343 chars; the cap is 350 and the
  first four drafts were over). No count in it. `homepage` deliberately held back to Phase 5.
- **Phases 2–4** — `README.Rmd` as the single source rendering `README.md` + `index.html`;
  `scripts/readme_functions.R` with the config readers and two gated figure builders;
  `fig/floodplain.png` and `fig/attribution.png` built from `data/bulk/`; `.nojekyll`;
  `.gitignore` entries for render byproducts; README rewritten. 290 lines → 254, with the
  catalogue counts gone and the roster, the scenario table and the attribution percentages all
  regenerated rather than typed.
- **Phase 5 (partial)** — the boundary rule and the render arrangement written into `CLAUDE.md`
  above the soul marker; `scripts/readme_determinism-check.sh` and
  `scripts/readme_content-check.py` written, and **every arm of both proven against a restored
  bug** before being trusted. Pages itself waits until `index.html` is on `main`.
- **Code check** — four rounds, 27 findings, all fixed and each fix proven against a restored
  bug: 7, then 4 (two of them round 1's own class one axis over), then 7 plus the mechanism
  behind all of it, then 9 running that mechanism as a stop condition — including one live bug
  where a derived scenario set left `FIG_PRIMARY` unchecked and the overview panel would have
  drawn no floodplain, silently. Reviews are in `planning/active/review-round[1-4].md`; the
  mechanism is written up in `findings.md`.
- Next: commit, PR, then enable Pages and set `homepage` after merge.
