## Outcome

`fig/attribution.png` now reads for a site visitor. Both in-plot subtitles are gone: the bar's
"fire and harvest are the causes config/disturbance.yml lists today — it takes any layer" and
the map's "…what it can be attributed to today". The residual category "not yet attributed" is
now "no mapped cause", in the legend, the bar, the README alt text and the three places prose
quoted it. The relabel widened #136 mid-run. Code-check round 4 found the company site's issue for
this figure (newgraphenvironment.github.io#66, from its #65 review) pointing at #136 for both
problems. A comment on #136 that the plan had not read asked for the relabel and suggested the
words. The site's copy rules rule out "not yet" wording. What was learned: the figure's real
consumer is outside this repo, and the issue body stated only half of what that consumer
needed. Rounds 3 to 5 all found that consumer's expectations, not code defects.

## Measurement

The bar is unchanged by both rebuilds: fire 66 ha 4%, harvest 474 ha 30%, no mapped cause 1025 ha
66% (1,565 ha of BULK `co_ff04` tree loss 2017–2023). The README's "about a third" still holds.
The rebuilt PNG is 1500×1500 px and 339 KB, within the site's 1600 px / 750 KB limits. The figure
was built on m4 from m1's three BULK gpkgs, which matched by sha256 and were removed after.
`index.html` moved only in the embedded PNG and the alt text, checked by diffing with the payloads
masked. `readme_determinism-check.sh` and `readme_content-check.py` (links included) pass.

## Owed

- The company site holds its own copy of the old PNG
      (`content/project/open_source_software/floodplains_attribution.png` in
      newgraphenvironment.github.io, byte-identical to main's old figure, found by code-check
      round 3). Swapping it is newgraphenvironment.github.io#66, which waits on this merge.

Closed by: PR for #136 (branch `136-fig-attribution-png-the-subtitle-is-writ`)
