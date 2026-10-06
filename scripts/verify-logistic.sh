#!/bin/sh
# Reviewed fixed language modes; callers supply timeouts and shared numerical budget.
set -eu
cd "$(dirname "$0")/.."
JULIA_NUM_THREADS=1
JULIA_NUM_PRECOMPILE_TASKS=1
OPENBLAS_NUM_THREADS=1
JULIA_DEPOT_PATH=/private/tmp/logistic-twins-julia-depot:/Users/z3437171/.julia
export JULIA_NUM_THREADS JULIA_NUM_PRECOMPILE_TASKS OPENBLAS_NUM_THREADS JULIA_DEPOT_PATH
julia=/Users/z3437171/.julia/juliaup/julia-1.12.6+0.aarch64.apple.darwin14/Julia-1.12.app/Contents/Resources/julia/bin/julia
case "${1:-}" in
    logistic)
        "$julia" --startup-file=no --project=. -e 'include("test/logistic_contract.jl"); include("scripts/export_logistic.jl"); println("LOGISTIC_LANGUAGE_OK")'
        ;;
    core)
        "$julia" --startup-file=no --project=. -e 'include("test/runtests.jl"); println("LOGISTIC_CORE_OK")'
        ;;
    controls)
        "$julia" --startup-file=no --project=. -e 'include("test/logistic_controls.jl"); println("LOGISTIC_CONTROLS_OK")'
        ;;
    *) printf '%s\n' 'usage: sh scripts/verify-logistic.sh logistic|core|controls' >&2; exit 2 ;;
esac
