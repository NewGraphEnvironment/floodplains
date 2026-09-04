#!/usr/bin/env python3
"""readme_content-check.py — the three README properties #77 asked for, checked mechanically.

Usage:
    python3 scripts/readme_content-check.py            # offline: anchors + catalogue facts
    CHECK_LINKS=1 python3 scripts/readme_content-check.py   # also resolve every external link

Three checks, over the RENDERED targets rather than README.Rmd. That distinction matters: a
link inside an `if (params$rmd_on)` branch exists in only one of the two outputs, so checking
the source would pass on a link that is broken in the page people actually read.

  A. ANCHORS — every `](#…)` resolves to a heading in the SAME file. `github_document` and
     pandoc's `html_document` do not share a slug algorithm; they agree on today's anchors, and
     that is luck rather than a property, so each target is checked against its own headings.

  B. CATALOGUE FACTS — no item count, collection extent or collection version anywhere. This is
     the rule #77 exists for, and its failure mode is RECURRENCE: "20 items live" was true when
     it was typed. A one-time read closes today and nothing else, so it is a grep that runs
     every time.

     Package versions (`drift >= 0.6.0`) are deliberately NOT matched. They are this repo's own
     facts about its own prerequisites; the rule is about the catalogue's numbers.

  C. LINKS — opt-in, because it needs the network. Asserts BOTH `200` AND that the final URL is
     the one requested. Either alone is satisfiable by a defect: the issue's own criterion
     ("resolves to itself, redirects followed") is TRUE of a 404, measured on this repo's own
     homepage-to-be before Pages existed.

     A DOI is the one class that property is wrong for, twice over. Redirecting IS what a DOI
     does, so "resolves to itself" would refuse every correct one; and both publisher landing
     pages here return **403 to any non-interactive client** — measured with a browser
     user-agent as well, so it is bot protection and not a dead link. Fetching the page cannot
     answer the question. Crossref can: `api.crossref.org/works/<doi>` returns 200 for a
     registered DOI. So DOIs are checked there instead, which is a stricter statement than a
     landing page loading — it says the identifier resolves, not that a server was reachable.
"""

import os
import re
import sys
import urllib.request
import urllib.error

TARGETS = ["README.md", "index.html"]

# Each pattern is a catalogue fact this repo must not state. The label is what gets printed, so
# it has to say which rule was broken, not just that one was.
# Deliberately wider than the wording #77 was filed over. `\d+\s+items` needs the digits
# ADJACENT to the noun, and an adjective is exactly what a rewrite adds — "serves 23 floodplain
# items" slipped straight through the first version. Measured: 5 of 12 candidate restatements
# were missed before these were widened, including a one-decimal latitude and "spans 48.9 N".
# Flags are PER PATTERN, and the latitude one is the reason. Under IGNORECASE, `[NS]` also
# matches a lowercase `s` — seconds — so `0.39 s`, a figure lifted straight from this repo's own
# notes, was refused as a collection extent. That is the mirror defect: a guard that rejects
# correct content, pointing the reader at a rule they have not broken.
CATALOGUE_FACTS = [
    (re.compile(r"\b\d+\s+(?:\w+\s+){0,2}items\b", re.I), "an item count"),
    (re.compile(r"\bitems\s+(?:are\s+)?(?:live|available|published)\b", re.I), "an item count"),
    (re.compile(r"\bgroups\s+publish\b", re.I), "a groups-to-items count"),
    (re.compile(r"\bitems\s+for\s+\d+\s+watershed", re.I), "a published-group count"),
    # The collection id is a literal this repo cannot derive: it lives in the sibling repo, and a
    # value read from there would make this guard depend on the thing it is guarding against.
    # SOURCE, verified 2026-09-04: `https://images.a11s.one/collections/stac-floodplains-bc`.
    (re.compile(r"stac-floodplains-bc[^\n]{0,40}\d", re.I), "the collection id next to a number"),
    (re.compile(r"\b\d{1,3}\.\d+\s*°?\s*[NS]\b"), "a collection extent (latitude)"),
    (re.compile(r"\bcollection[^\n]{0,30}\bversion\s+v?\d+\.\d+", re.I), "a collection version"),
    (re.compile(r"\bcollection\s+version\b", re.I), "a collection version"),
]

# Anchors that OTHER repos link into. Hardcoded on purpose: this is a contract this repo chose,
# so a set derived from the file could never fail — it would agree with whatever the headings
# happen to say today. Renaming one breaks a published page in another repo with nothing here to
# notice.
#
# Check A only sees anchors this README uses ITSELF. Today it happens to use this one, which is
# luck, not coverage.
#
# SOURCE, verified 2026-09-04: `stac_floodplains_bc/README.md:29` links
# `https://github.com/NewGraphEnvironment/floodplains#reading-the-outputs-experimental`.
# Re-check that file when adding or removing an entry here — it is the only thing that makes
# this list true, and nothing in this repo can tell you it has gone stale.
INBOUND_ANCHORS = {"README.md": ["reading-the-outputs-experimental"]}

DOI_PREFIX = "https://doi.org/"
CROSSREF = "https://api.crossref.org/works/"

GITHUB_PUNCT = re.compile(r"[^\w\- ]", re.UNICODE)


def gh_slug(text):
    """GitHub's heading slug: strip markup and punctuation, lowercase, spaces to hyphens."""
    t = re.sub(r"`([^`]*)`", r"\1", text)
    t = re.sub(r"\*\*?([^*]*)\*\*?", r"\1", t)
    t = t.strip().lower()
    t = GITHUB_PUNCT.sub("", t)
    return t.replace(" ", "-")


def anchors_md(src):
    used = set(re.findall(r"\]\(#([^)]+)\)", src))
    have = {gh_slug(m) for m in re.findall(r"(?m)^#{1,6}\s+(.*?)\s*$", src)}
    return used, have


SCRIPT_OR_STYLE = re.compile(r"<(script|style)\b.*?</\1>", re.DOTALL | re.IGNORECASE)


def strip_code(src):
    """Drop <script>/<style> bodies.

    self_contained pandoc embeds jQuery and bootstrap, whose source contains string literals
    like `'#' + $(elm).attr('id')`. Left in, those parse as internal links to anchors that
    cannot exist, and the check fails on a page that is perfectly fine.
    """
    return SCRIPT_OR_STYLE.sub("", src)


def anchors_html(src):
    src = strip_code(src)
    used = set(re.findall(r'href="#([^"]+)"', src))
    have = set(re.findall(r'id="([^"]+)"', src))
    # NOT full coverage, and the comment here used to claim it was. `toc_float: true` emits an
    # EMPTY `<div id="TOC">` and builds the list at runtime in jQuery, so after strip_code() the
    # only static `href="#…"` are the inline body links -- measured on the committed page, 2 used
    # against 15 ids. Nothing is falsely passed (tocify resolves ids in the DOM, so a slug
    # divergence cannot break that TOC), but the other 13 ids are unchecked here. INBOUND_ANCHORS
    # is what covers the one that matters.
    return used, have


def links(src):
    out = set(re.findall(r"https?://[^\s\"'<>)\]]+", src))
    return {u.rstrip(".,;") for u in out}


def check_anchors():
    bad = []
    for t in TARGETS:
        src = open(t, encoding="utf-8").read()
        used, have = anchors_md(src) if t.endswith(".md") else anchors_html(src)
        if not used:
            bad.append(f"{t}: no internal anchors found at all — the extractor is broken, "
                       f"not the file")
            continue
        for a in sorted(used - have):
            bad.append(f"{t}: `#{a}` matches no heading in that file")
        for a in INBOUND_ANCHORS.get(t, []):
            if a not in have:
                bad.append(f"{t}: `#{a}` is linked from another repo and no longer exists here")
    return bad


def blank_code(src):
    """`strip_code` but line-preserving, so reported line numbers still point at the file.

    This check is the only one that reports a LOCATION, and it is the only one that was reading
    the embedded bootstrap/jQuery payload of index.html. That payload carries 30 CSS durations
    (`.15s`, `.2s`) sitting one leading digit away from the latitude pattern, so a pandoc or
    bootstrap bump could fail the guard on a page that is fine.
    """
    return SCRIPT_OR_STYLE.sub(lambda m: "\n" * m.group(0).count("\n"), src)


def check_catalogue_facts():
    bad = []
    for t in TARGETS:
        src = open(t, encoding="utf-8").read()
        if not t.endswith(".md"):
            src = blank_code(src)
        for i, line in enumerate(src.split("\n"), 1):
            for pat, label in CATALOGUE_FACTS:
                m = pat.search(line)
                if m:
                    bad.append(f"{t}:{i}: {label} — {m.group(0).strip()!r}. "
                               f"This repo links to the catalogue; it does not restate it.")
    return bad


def check_links():
    bad = []
    urls = set()
    # PER TARGET, not over the union. An empty set sweeps nothing and prints OK, and this is the
    # opt-in arm, so a silent pass gets no second chance. Guarding the union is not enough: the
    # HTML extractor can go to zero while the markdown one still returns ten, and the union stays
    # non-empty — which would silently drop exactly the half the docstring says is worth checking
    # separately (a link inside an `rmd_on` branch exists in only one output).
    for t in TARGETS:
        src = open(t, encoding="utf-8").read()
        found = links(src if t.endswith(".md") else strip_code(src))
        if not found:
            bad.append(f"{t}: no external links found at all — the extractor is broken, "
                       f"not the file")
        urls |= found
    if bad:
        return bad
    for u in sorted(urls):
        if u.startswith(DOI_PREFIX):
            probe = CROSSREF + u[len(DOI_PREFIX):]
            self_resolving = False
        else:
            probe = u
            self_resolving = True
        req = urllib.request.Request(probe, headers={"User-Agent": "floodplains-readme-check"})
        try:
            with urllib.request.urlopen(req, timeout=30) as r:
                code, final = r.status, r.geturl()
        except urllib.error.HTTPError as e:
            code, final = e.code, e.geturl()
        except Exception as e:  # DNS, TLS, timeout — report, do not crash the sweep
            bad.append(f"{u} -> {type(e).__name__}: {e}")
            continue
        if code != 200:
            bad.append(f"{u} -> HTTP {code}" + ("" if self_resolving else f" (via {probe})"))
        elif self_resolving and final.rstrip("/") != u.rstrip("/"):
            bad.append(f"{u} -> 200 but redirected to {final}")
        else:
            print(f"  ok  {u}" + ("" if self_resolving else "  [DOI registered at Crossref]"))
    return bad


def main():
    missing = [t for t in TARGETS if not os.path.exists(t)]
    if missing:
        print("FAIL: render the targets first — missing " + ", ".join(missing))
        return 1

    rc = 0
    for name, fn in (("anchors", check_anchors), ("catalogue facts", check_catalogue_facts)):
        bad = fn()
        if bad:
            rc = 1
            print(f"FAIL: {name}")
            for b in bad:
                print("  " + b)
        else:
            print(f"OK: {name}")

    if os.environ.get("CHECK_LINKS") == "1":
        bad = check_links()
        if bad:
            rc = 1
            print("FAIL: links")
            for b in bad:
                print("  " + b)
        else:
            print("OK: links (every URL returns 200 and is its own final URL)")
    else:
        print("SKIP: links — set CHECK_LINKS=1 to resolve them (needs the network)")

    return rc


if __name__ == "__main__":
    sys.exit(main())
