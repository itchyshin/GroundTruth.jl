#!/bin/sh
set -eu

script_dir=$(CDPATH= cd "$(dirname "$0")" && pwd)
root=$(CDPATH= cd "$script_dir/.." && pwd)
cd "$root"
project=${RI_JULIA_PROJECT:-$root}
[ -f "$project/Project.toml" ] || { echo "Julia project not found: $project/Project.toml" >&2; exit 2; }

julia_bin=${JULIA_BIN:-julia}
case "$julia_bin" in
  */*) [ -x "$julia_bin" ] || { echo "Julia executable not found or not executable: $julia_bin" >&2; exit 127; } ;;
  *) julia_bin=$(command -v "$julia_bin") || { echo "Julia executable not found: ${JULIA_BIN:-julia}" >&2; exit 127; } ;;
esac
python_bin=${PYTHON_BIN:-python3}
case "$python_bin" in
  */*) [ -x "$python_bin" ] || { echo "Python executable not found or not executable: $python_bin" >&2; exit 127; } ;;
  *) python_bin=$(command -v "$python_bin") || { echo "Python executable not found: ${PYTHON_BIN:-python3}" >&2; exit 127; } ;;
esac

required_version=${JULIA_REQUIRED_VERSION:-1.12.6}
version=$("$julia_bin" --version) || { echo "Could not read Julia version from $julia_bin" >&2; exit 1; }
[ "$version" = "julia version $required_version" ] || {
  echo "Julia version mismatch: expected $required_version, got $version (override with JULIA_REQUIRED_VERSION if appropriate)." >&2
  exit 1
}

export JULIA_PROJECT="$project"
if [ -z "${JULIA_LOAD_PATH:-}" ]; then
  export JULIA_LOAD_PATH="$project:@:@v#.#:@stdlib"
fi
export JULIA_NUM_THREADS=1 JULIA_NUM_PRECOMPILE_TASKS=1
export OPENBLAS_NUM_THREADS=1 OMP_NUM_THREADS=1 MKL_NUM_THREADS=1
export VECLIB_MAXIMUM_THREADS=1 BLIS_NUM_THREADS=1
export JULIA_PKG_OFFLINE=true JULIA_PKG_PRECOMPILE_AUTO=0
export GITHUB_ACTIONS=false
evidence=${RI_DOCS_EVIDENCE:-$root/.unlazy/ri-twins/evidence/docs-package}
mkdir -p "$evidence"

set +e
"$julia_bin" --startup-file=no --compiled-modules=no --threads=1 --project="$project" -e '
using Documenter
using GroundTruth
@assert :logistic_mle in names(GroundTruth)
@assert :Scenario in names(GroundTruth)
@assert :ri_scenario in names(GroundTruth)
include(joinpath(pwd(), "docs", "make.jl"))
' > "$evidence/documenter.log" 2>&1
julia_status=$?
set -e
if [ "$julia_status" -ne 0 ]; then
  cat "$evidence/documenter.log" >&2
  exit "$julia_status"
fi

"$python_bin" - "$root/docs/src" "$root/docs/build" <<'PY'
from pathlib import Path
import re, sys
src, build = map(Path, sys.argv[1:])
files = list(src.rglob("*.md"))
assert files, "no Markdown documentation sources found"
for page in files:
    text = page.read_text()
    for target in re.findall(r"\[[^\]]*\]\(([^)]+)\)", text):
        if target.startswith(("http://", "https://", "mailto:", "#")):
            continue
        path, _, anchor = target.partition("#")
        resolved = (page.parent / path).resolve() if path else page.resolve()
        assert resolved.exists(), f"broken local documentation link: {page}: {target}"
        if anchor:
            rendered_page = build / resolved.relative_to(src).with_suffix(".html")
            assert rendered_page.is_file(), f"linked page was not rendered: {page}: {target}"
            body = rendered_page.read_text(errors="replace")
            assert re.search(r"id=[\"']" + re.escape(anchor) + r"[\"']|<a[^>]+name=[\"']" + re.escape(anchor) + r"[\"']", body), f"missing rendered anchor: {page}: {target}"
assert (build / "index.html").is_file(), "Documenter did not produce docs/build/index.html"
all_html = "\n".join(p.read_text(errors="replace") for p in build.rglob("*.html"))
for url in ("https://github.com/itchyshin/GroundTruth.jl", "https://itchyshin.github.io/groundtruth/"):
    assert url in all_html, f"expected GitHub/sister-site URL missing from rendered site: {url}"
print("RI_JULIA_DOCS_PACKAGE_OK")
PY
