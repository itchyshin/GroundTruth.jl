# GroundTruth.jl — first working prototype

Generate independently. Fit anywhere. Compare against declared truth.

This small Julia package checks statistical results against known generating values.
It currently targets the intercept `alpha` and slope `beta` in Gaussian and logistic
regressions, plus a Gaussian random-intercept **oracle** with known variance components.
It is a prototype, with a serial runner and no claim of new scheduling infrastructure,
automatic model translation, established calibration, or automatic speed gains.

## Start here if you use R

A `Scenario` is like a row in an R simulation design table. `generate` is your data
simulation function. An `Adapter` is your fitting function. `FitResult` provides named
estimates and intervals. `runstudy` repeats them; `summarize` evaluates recovery.

With Julia 1.12 and Distributions 0.25 available, from this directory:

```sh
julia --project=. -e 'using Pkg; Pkg.instantiate()'
julia --project=. test/runtests.jl
julia --project=. examples/linear.jl
```

`instantiate()` may need network access on a new machine. The verified local run used
cached dependencies and an isolated writable depot; it did not change another project.
The core needs neither R nor Turing, Stan, TMB, credentials or remote compute.

```julia
using GroundTruth
s = Scenario("lm-n100"; n=100, alpha=1., beta=.7, sigma=1.2)
a = Adapter("OLS", ols; metadata=(
    likelihood="Gaussian identity", target="alpha,beta", prior="none",
    inference="OLS with t intervals", interval_level=.95))
study = runstudy([s], [a]; reps=100, seed=20261004)
summary = summarize(study)
foreach(println, summary)
# The exact simulated data from replication 7:
data = replay(s, 7; seed=20261004)
export_data("rep7.csv", data)
```

`examples/linear.jl` saves CSVs in `results/linear`. R reads them with
`read.csv("results/linear/summary.csv")`. Run `Rscript --vanilla reference/check_lm.R`
for an independent base-R `lm()` coefficient and interval comparison on replication 1.

## What is being tested?

Gaussian: `x ~ N(0,1)` and `y = alpha + beta*x + sigma*epsilon`, with independent
standard-normal errors. OLS estimates both coefficients, estimates residual variance
with `n-2` degrees of freedom, and uses exact Student t intervals under this DGP.

Logistic: `y ~ Bernoulli(logistic(alpha + beta*x))`. The coefficient targets are
conditional log odds, not marginal probabilities or causal effects. Newton MLE uses
normal Wald intervals; separation/unstable coefficients and nonconvergence are failures.

Random intercept: `y_ij = alpha + beta*x_ij + u_j + sigma*epsilon_ij`,
`u_j ~ N(0,tau^2)`. The example supplies known `sigma,tau` to GLS. This is an oracle
baseline; estimated variance components and general GLMMs remain future work.
Run the two small examples with `julia --project=. examples/extensions.jl` and optionally
check identical data with `Rscript --vanilla reference/check_extensions.R`.

[The symbol-to-code contract](docs/ALIGNMENT.md) specifies the generating terms and
recovery mapping. The generator never calls fitted-model code or uses fitted priors.
Adapters receive data and their own RNG, without scenario truth. Each receives its own
copy of the shared replication data so one adapter cannot contaminate another.

## Read the denominators before interpreting a result

Every adapter attempt has a ledger record: scenario, replication, adapter, data and fit
seeds, status, error message and elapsed time. Failed fits remain in the attempt count.
Point summaries use successful finite estimates; coverage uses **usable intervals**.
An interval is usable only if both endpoints are finite and ordered. Converged estimates
without usable intervals remain point-estimate successes. The runner rejects a fit
missing either declared coefficient target. It does not independently certify an
adapter's convergence claim or whether an interval has the advertised nominal level.

| Output | Meaning |
|---|---|
| attempted, successful, failed | Total fits, accepted coefficient fits, rejected fits |
| usable_intervals, unusable_intervals | Target-specific interval denominators |
| bias | Mean estimate minus truth among accepted fits |
| bias_mcse | Sample SD of errors divided by sqrt(successful) |
| rmse | Square root of mean squared error among accepted fits |
| rmse_mcse | Delta-method MCSE: SD(squared errors)/sqrt(successful)/(2*RMSE) |
| coverage | Covered / usable intervals; conditional on usability |
| coverage_mcse | Plug-in binomial MCSE, sqrt(p*(1-p)/usable) |
| coverage_mc_lower/upper | 95% Wilson interval for Monte Carlo coverage uncertainty |
| covered_per_attempt | Covered / all attempted fits; failures and missing intervals counted as not covered |

MCSE means Monte Carlo standard error: uncertainty from a finite number of replications,
not the estimator's own standard error. All-failed estimates/coverage are `missing`,
not zero; MCSE is `missing` with fewer than two observations. Zero plug-in coverage
MCSE at 0% or 100% is a boundary artifact: inspect the Wilson interval. Bias/RMSE and
coverage conditional on successful fits can hide selective failures, so always report
the ledger and denominator columns. RMSE MCSE is an approximation, especially near zero.
Replications are intended to be independent pseudorandom streams; summaries assume
independent replications and do not account for dependence from a custom adapter.

## Reproducibility and adapters

Scenario and adapter IDs must be unique within a study. SHA-256 of a length-prefixed
key `(base seed, scenario id, replication, stream)` supplies 64-bit Xoshiro seeds.
Data and each adapter have distinct streams; reordering adapters does not change the
results. These are stable stream keys, not a proof of mathematical independence or
identical draws across Julia versions. Preserve Julia version, the manifest, code/data
hashes and complete scenario/adapter metadata in the example provenance files.
Keep scenario IDs meaningful and change them when changing the design. Timing is
informational; it is not a speed benchmark.

A custom adapter follows this contract:

```julia
myfit = Adapter("my-method", (data, rng) -> begin
    # Fit with an existing Julia engine, or a guarded external comparison.
    # Extract names explicitly; never silently align parameters by position.
    FitResult(Dict(:alpha=>1.1, :beta=>0.6);
              intervals=Dict(:alpha=>(0.8,1.4), :beta=>(0.3,0.9)),
              converged=true)
end; metadata=(likelihood="state it", target="alpha,beta",
               prior="state it", inference="state it", interval_level=.95))
```

The numbers above illustrate the return format; they are not an estimator.
Exceptions, nonconvergence, missing targets and nonfinite estimates are retained in
`study.ledger`. No automatic retries or parallel scheduler are provided.

## Explicit Stan/TMB reference path

```julia
d = replay(s, 1)
reference_bundle("my-stan-reference", d; engine=:stan)
reference_bundle("my-tmb-reference", d; engine=:tmb)
```

This emits a reviewed Gaussian template, shared CSV/JSON data and a conformance receipt.
Only this explicit LM template is supported; unsupported families/engines error.
Choose a fresh output directory. Export does not execute or validate an engine fit.
See [reference instructions](reference/README.md). Stan has explicit Bayesian priors;
TMB fits the likelihood by maximum likelihood. Common likelihood/data/coefficient
targets do not imply common priors, inference, variance estimators or intervals.

## Scope and reuse

Existing R simulation tools and Julia projects already implement much of the wider
workflow. [The bounded plan](docs/PLAN.md) records the supplied reuse review. This package
concentrates on independent truth, explicit statistical conformance, parameter mapping
and failure accounting. Before growing it, audit and reuse an existing scheduler,
plotting system or transport. DRM/GLLVM integrations, fitted GLMMs, arbitrary estimands,
Stan posterior comparison, resumable campaigns and translation of arbitrary models are
future work. BayesDRM/BayesGLLVM are paused. See [actual verification status](STATUS.md).
