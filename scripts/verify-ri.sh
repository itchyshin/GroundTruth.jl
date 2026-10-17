#!/bin/sh
set -eu

script_dir=$(CDPATH= cd "$(dirname "$0")" && pwd)
root=$(CDPATH= cd "$script_dir/.." && pwd)
cd "$root"
project=${RI_JULIA_PROJECT:-$root}
adapter_project=${JULIA_ADAPTER_PROJECT:-$root/adapters/lmm}
[ -f "$project/Project.toml" ] || { echo "Julia project not found: $project/Project.toml" >&2; exit 2; }
[ -f "$adapter_project/Project.toml" ] || { echo "Julia adapter project not found: $adapter_project/Project.toml; set JULIA_ADAPTER_PROJECT to an existing cached adapter environment." >&2; exit 2; }

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
export JULIA_PKG_OFFLINE=true JULIA_PKG_PRECOMPILE_AUTO=0

case "${1:-}" in
  red) "$julia_bin" --startup-file=no --compiled-modules=existing --threads=1 --project="$project" -e 'include("test/ri_core.jl"); include("test/ri_adapter.jl")' ;;
  language) "$julia_bin" --startup-file=no --compiled-modules=existing --threads=1 --project="$project" -e 'include("test/ri_core.jl"); include("test/ri_adapter.jl"); include("scripts/ri-language.jl"); println("RI_JULIA_LANGUAGE_OK")' ;;
  core) "$julia_bin" --startup-file=no --compiled-modules=existing --threads=1 --project="$project" -e 'include("test/runtests.jl"); include("test/logistic_contract.jl"); include("test/logistic_controls.jl"); println("RI_JULIA_CORE_OK")' ;;
  *) echo 'mode red|language|core required' >&2; exit 2 ;;
esac
