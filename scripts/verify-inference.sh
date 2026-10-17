#!/bin/sh
set -eu

script_dir=$(CDPATH= cd "$(dirname "$0")" && pwd)
root=$(CDPATH= cd "$script_dir/.." && pwd)
cd "$root"
project=${INFERENCE_JULIA_PROJECT:-$root}
adapter_project=${JULIA_ADAPTER_PROJECT:-$root/adapters/lmm}
docs_project=${INFERENCE_DOCS_PROJECT:-}
capture=${INFERENCE_JULIA_CAPTURE:-$root/.unlazy/inference/evidence/julia-capture.csv}
validator=$root/audit/inference/validate_captures.py
controls=$root/audit/inference/check_capture_controls.py
receipts=$root/scripts/inference-receipts.py
[ -f "$project/Project.toml" ] || { echo "Julia project not found: $project/Project.toml" >&2; exit 2; }
[ -f "$adapter_project/Project.toml" ] || { echo "Julia adapter project not found: $adapter_project/Project.toml" >&2; exit 2; }
[ -f "$validator" ] || { echo "Independent native-capture validator is missing: $validator" >&2; exit 2; }

julia_bin=${JULIA_BIN:-julia}
case "$julia_bin" in
  */*) [ -x "$julia_bin" ] || { echo "Julia executable not found or not executable: $julia_bin" >&2; exit 127; } ;;
  *) julia_bin=$(command -v "$julia_bin") || { echo "Julia executable not found: ${JULIA_BIN:-julia}" >&2; exit 127; } ;;
esac

export JULIA_PROJECT="$project"
if [ -z "${JULIA_LOAD_PATH:-}" ]; then
  export JULIA_LOAD_PATH="$project:$adapter_project:@stdlib"
fi
export JULIA_NUM_THREADS=1 JULIA_NUM_PRECOMPILE_TASKS=1
export OPENBLAS_NUM_THREADS=1 OMP_NUM_THREADS=1 MKL_NUM_THREADS=1
export VECLIB_MAXIMUM_THREADS=1 BLIS_NUM_THREADS=1
export JULIA_PKG_OFFLINE=true JULIA_PKG_PRECOMPILE_AUTO=0 JULIA_SCRATCH_TRACK_ACCESS=0

run_julia() {
  "$julia_bin" --startup-file=no --compiled-modules=no --compile=min -O0 --threads=1 "$@"
}

audit_capture() {
  [ -f "$capture" ] || { echo "Native capture is missing: $capture" >&2; return 2; }
  python3 "$validator" "$capture"
}

case "${1:-}" in
  capture)
    python3 "$root/scripts/inference-julia-capture.py"
    ;;
  oracles)
    audit_capture
    printf '%s\n' INFERENCE_ORACLES_OK
    ;;
  methods)
    run_julia test/inference_profile_protocol.jl
    audit_capture
    printf '%s\n' INFERENCE_METHODS_OK
    ;;
  controls)
    audit_capture
    python3 "$controls"
    printf '%s\n' INFERENCE_CONTROLS_OK
    ;;
  accounting)
    run_julia --project="$project" test/inference_comparison.jl
    ;;
  compatibility)
    audit_capture
    python3 "$receipts" check package
    python3 "$receipts" check docs
    printf '%s\n' INFERENCE_COMPAT_OK
    ;;
  package)
    if ! python3 "$receipts" check package >/dev/null 2>&1; then
      run_julia --project="$project" test/runtests.jl
      python3 "$receipts" write package
    fi
    if ! python3 "$receipts" check docs >/dev/null 2>&1; then
      if [ -n "$docs_project" ]; then
        [ -f "$docs_project/Project.toml" ] || { echo "Docs overlay project not found: $docs_project/Project.toml" >&2; exit 2; }
        docs_julia_project=$docs_project
        docs_load_path=${JULIA_LOAD_PATH}
      else
        docs_load_path=${INFERENCE_DOCS_LOAD_PATH:-}
        [ -n "$docs_load_path" ] || { echo 'Set INFERENCE_DOCS_PROJECT or the explicit cached INFERENCE_DOCS_LOAD_PATH; no Pkg operation will be run.' >&2; exit 2; }
        docs_julia_project=$project
        case ":$docs_load_path:" in
          *":$project:"*) ;;
          *) docs_load_path="$project:$docs_load_path" ;;
        esac
        case ":$docs_load_path:" in
          *":$adapter_project:"*) ;;
          *) docs_load_path="$docs_load_path:$adapter_project" ;;
        esac
        docs_load_path="$docs_load_path:@stdlib"
      fi
      # This import is the non-mutating dependency check: it proves the selected
      # environment can resolve Documenter before make.jl starts the build.
      JULIA_LOAD_PATH="$docs_load_path" run_julia --project="$docs_julia_project" -e 'using Documenter; println("DOCUMENTER_RESOLVED ", Base.pkgversion(Documenter))'
      JULIA_LOAD_PATH="$docs_load_path" run_julia --project="$docs_julia_project" "$root/docs/make.jl"
      python3 "$receipts" write docs
    fi
    python3 "$receipts" check package
    python3 "$receipts" check docs
    printf '%s\n' INFERENCE_PACKAGE_DOCS_OK
    ;;
  *)
    echo 'mode capture|oracles|methods|controls|accounting|compatibility|package required' >&2
    exit 2
    ;;
esac
