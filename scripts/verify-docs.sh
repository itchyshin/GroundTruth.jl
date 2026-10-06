#!/usr/bin/env bash
set -euo pipefail

# Use the retained Julia 1.12.6 binary and cached source packages. Never resolve or
# install dependencies. These are the authorized shared-machine launch caps.
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
julia_bin="/Users/z3437171/.julia/juliaup/julia-1.12.6+0.aarch64.apple.darwin14/Julia-1.12.app/Contents/Resources/julia/bin/julia"
version="$("$julia_bin" --version)"
[[ "$version" == "julia version 1.12.6" ]]
export JULIA_DEPOT_PATH="/private/tmp/logistic-twins-julia-depot:/Users/z3437171/.julia"
export JULIA_LOAD_PATH="$root:/private/tmp/logistic-twins-cached-packages:@stdlib"
export JULIA_NUM_THREADS=1
export JULIA_NUM_PRECOMPILE_TASKS=1
export OPENBLAS_NUM_THREADS=1
export GITHUB_ACTIONS=false
evidence="$root/.unlazy/logistic-twins/evidence/docs-package"
mkdir -p "$evidence"

if ! "$julia_bin" --startup-file=no --compiled-modules=no --threads=1 --project="$root" -e '
using Documenter
using GroundTruth
@assert :logistic_mle in names(GroundTruth)
@assert :Scenario in names(GroundTruth)
include(joinpath(pwd(), "docs", "make.jl"))
' > "$evidence/documenter.log" 2>&1; then
  cat "$evidence/documenter.log" >&2
  exit 1
fi

python3 - "$root/docs/src" "$root/docs/build" <<'PY'
from pathlib import Path
import re, sys
src, build = map(Path, sys.argv[1:])
files = list(src.rglob("*.md"))
assert files, "no Markdown documentation sources found"
rendered = build
for page in files:
    text = page.read_text()
    for target in re.findall(r"\[[^\]]*\]\(([^)]+)\)", text):
        if target.startswith(("http://", "https://", "mailto:", "#")):
            continue
        path, _, anchor = target.partition("#")
        resolved = (page.parent / path).resolve() if path else page.resolve()
        assert resolved.exists(), f"broken local documentation link: {page}: {target}"
        if anchor:
            rendered_page = build / (resolved.relative_to(src).with_suffix(".html"))
            assert rendered_page.is_file(), f"linked page was not rendered: {page}: {target}"
            body = rendered_page.read_text(errors="replace")
            assert re.search(r"id=[\"']" + re.escape(anchor) + r"[\"']|<a[^>]+name=[\"']" + re.escape(anchor) + r"[\"']", body), f"missing rendered anchor: {page}: {target}"
assert (build / "index.html").is_file(), "Documenter did not produce docs/build/index.html"
all_html = "\n".join(p.read_text(errors="replace") for p in build.rglob("*.html"))
for url in ("https://github.com/itchyshin/GroundTruth.jl", "https://itchyshin.github.io/groundtruth/"):
    assert url in all_html, f"expected GitHub/sister-site URL missing from rendered site: {url}"
print("LOGISTIC_DOCS_PACKAGE_OK")
PY
