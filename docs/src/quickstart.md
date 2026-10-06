# Quickstart

## Gaussian regression

With Julia 1.12 and the package dependencies already available, run from the package
root. A fresh environment may require dependency installation first.

```sh
julia --startup-file=no --project=. test/runtests.jl
```

```julia
using GroundTruth
s = Scenario("lm-n100"; n=100, alpha=1.0, beta=0.7, sigma=1.2)
a = Adapter("OLS", ols; metadata=(
    likelihood="Gaussian identity", target="alpha,beta", prior="none",
    inference="OLS with t intervals", interval_level=0.95))
study = runstudy([s], [a]; reps=10, seed=20261004)
foreach(println, summarize(study))
data = replay(s, 1; seed=20261004)
```

Ten replications illustrate the interface, not calibration. Every attempt is retained
in `study.ledger`. Exceptions, nonconvergence and missing/nonfinite coefficient targets
are failures. Point summaries use accepted estimates; coverage uses finite ordered
intervals. Read `successful`, `failed`, `usable_intervals` and `covered_per_attempt`
together. A finite estimate without an interval can remain a point success. All-failed
cells have missing summaries, and a singleton does not yield a reliable Monte Carlo
standard error. Zero plug-in coverage uncertainty at 0% or 100% is a boundary artifact;
inspect the Wilson Monte Carlo interval.


## Inspect the denominators

Read `attempted`, `successful`, `failed`, `usable_intervals` and `unusable_intervals`
together. Point summaries use accepted estimates; coverage uses usable intervals.
Keep the attempt ledger with the summary. Ten replications demonstrate the interface,
not calibration. [Check the current limits](capabilities.md).
