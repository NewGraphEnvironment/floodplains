#!/usr/bin/env bash
# readme_determinism-check.sh — a re-render of README.Rmd from unchanged inputs moves nothing.
#
# Usage: bash scripts/readme_determinism-check.sh
#
# Sibling of gpkg_determinism-check.R, and there for the same reason: index.html is a committed
# ~2 MB artifact, so anything that churns it per render makes every rebuild look like a change.
#
# TWO assertions, and neither is sufficient alone:
#
#   1. sha256 of README.md and index.html is unchanged across a re-render. This catches a
#      timestamp, an unseeded id, a re-encoded figure payload.
#   2. No render byproduct is left on disk, checked against the SAME five paths `.gitignore`
#      names. This catches the failure the sha CANNOT see: a chunk
#      that PLOTS instead of routing through fp_fig_*() writes its image into README_files/, and
#      README.md then points at an image that 404s for everyone but the author.
#
#      It is checked by NAME, not with `git status`. `.gitignore` lists exactly these paths, so
#      porcelain output is silent on precisely the artifacts this assertion exists to find --
#      measured: with a plotting chunk restored, README_files/ appeared on disk and the porcelain
#      form still reported OK. A guard defeated by the ignore rule written beside it.
#
# It renders TWICE, because a first render that creates state and a second that reads it are
# different code paths.
#
# A third property falls out of arm 1 and is worth naming: `before_sha` is taken BEFORE the first
# render, so the check also asserts that the committed README.md and index.html match the current
# README.Rmd -- i.e. that whoever last edited the source remembered to render it.
#
# It needs no `data/`, no database and no network: params$update_figs stays FALSE and the render
# reads the committed PNGs. That is what makes it runnable anywhere.
#
# STATED LIMIT: identity holds within one toolchain. A pandoc bump rewrites the embedded
# bootstrap payload of index.html and every byte after it, with nothing about the content
# changed. Same shape as the README's own "rewriting one layer into an existing GeoPackage is
# not byte-stable" caveat.

set -euo pipefail

cd "$(cd "$(dirname "$0")/.." && pwd)"

FILES=(README.md index.html)

for f in "${FILES[@]}"; do
  [ -f "$f" ] || { echo "FAIL: $f is missing — render it before checking it"; exit 1; }
done

# Every path the .gitignore byproduct block lists. It listed FIVE and this listed three, while
# the comment above asserted they were the same set: `README.utf8.md` escaped BOTH arms — it is
# not named here, and it IS gitignored, so `git status --porcelain` was silent on it too.
BYPRODUCTS=(README_files index_files README.html '*.knit.md' '*.utf8.md')

# Anything already present before the render is the caller's, not ours — say so and stop, rather
# than reporting it as a finding or deleting someone's file.
# `$pat` unquoted so the globs expand; an unmatched glob stays literal and fails `-e`.
present_byproducts() {
  local found="" pat f
  for pat in "${BYPRODUCTS[@]}"; do
    for f in $pat; do
      if [ -e "$f" ]; then found="$found $f"; fi
    done
  done
  printf '%s' "$found"
}

pre="$(present_byproducts)"
if [ -n "$pre" ]; then
  echo "FAIL: byproducts exist before the render:$pre — remove them, then re-run"; exit 1
fi

before_status="$(git status --porcelain --ignored)"
before_sha="$(shasum -a 256 "${FILES[@]}")"

render() {
  Rscript -e 'rmarkdown::render("README.Rmd", output_format = "github_document",
                                params = list(rmd_on = FALSE, update_figs = FALSE), quiet = TRUE)'
  Rscript -e 'rmarkdown::render("README.Rmd", output_format = "html_document",
                                output_file = "index.html",
                                params = list(rmd_on = TRUE, update_figs = FALSE), quiet = TRUE)'
}

echo "render 1 of 2 ..."; render
echo "render 2 of 2 ..."; render

after_sha="$(shasum -a 256 "${FILES[@]}")"
after_status="$(git status --porcelain --ignored)"

rc=0

if [ "$before_sha" != "$after_sha" ]; then
  echo "FAIL: a re-render changed the rendered bytes."
  diff <(printf '%s\n' "$before_sha") <(printf '%s\n' "$after_sha") || true
  echo "  If the toolchain moved (pandoc, rmarkdown, knitr, R), that is the expected cause and"
  echo "  the committed artifacts need regenerating. If it did not, something in README.Rmd is"
  echo "  not deterministic — an unseeded id, a date, or a figure re-encoded at render time."
  rc=1
else
  echo "OK: README.md and index.html are byte-identical across two re-renders."
fi

left="$(present_byproducts)"

if [ -n "$left" ]; then
  echo "FAIL: rendering left byproducts behind:$left"
  echo "  README_files/ or index_files/ means a chunk PLOTTED instead of calling"
  echo "  fp_fig_require() on a committed PNG. The rendered page then works locally and shows a"
  echo "  broken image everywhere else — and .gitignore hides it, so nothing else will say so."
  rc=1
else
  echo "OK: rendering left no byproducts on disk."
fi

# `--ignored` on purpose: arm 2 names the byproducts it knows about, and this arm is the
# COMPLEMENT — anything the render creates that nobody thought to name. Without it, a new
# gitignored artifact is invisible to both. The listing is directory-level for `data/` and stable
# across renders, so the comparison stays cheap.
if [ "$before_status" != "$after_status" ]; then
  echo "FAIL: rendering changed what git sees (ignored files included):"
  diff <(printf '%s\n' "$before_status") <(printf '%s\n' "$after_status") || true
  rc=1
else
  echo "OK: rendering changed nothing else git can see."
fi

exit "$rc"
