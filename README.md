# GroundTruth.jl

Generate independently. Fit anywhere. Compare against declared truth.

This small Julia package checks statistical results against known generating values.
Its public workflow targets the intercept `alpha` and slope `beta` in Gaussian and
logistic regression, plus a known-covariance Gaussian random-intercept oracle. This
version repairs the Julia logistic MLE; the R twin provides a native logistic workflow.
The retained local checks passed 393 Julia assertions across 16 suites, frozen-fixture
numerical checks and both documentation builds. Across seven paired, one-predictor
Bernoulli fixtures with unit weights, seven accepted data fits per engine were checked,
or 14 engine-by-fixture fits total, along with five rejected designs per engine. Maximum paired differences were 6.87e-11 for
coefficients, 7.12e-12 for standard errors, 8.28e-11 for interval endpoints and
9.99e-16 for mean negative log likelihood. The Julia checks used Julia 1.12.6 and
Distributions 0.25.131. The R package check passed with 346 assertions under R 4.6.0;
its pkgdown preview rendered under pkgdown 2.2.0. These fixed-fixture comparisons
do not establish calibration, fitted GLMM behavior or package-wide parity.
The package remains a research prototype with a serial runner, no new scheduling
infrastructure and no automatic model translation or speed claim.

## Start here if you use R

A `Scenario` is like a row in an R simulation design table. `generate` is your data
simulation function. An `Adapter` is your fitting function. `FitResult` provides named
estimates and intervals. `runstudy` repeats them; `summarize` evaluates recovery.

With Julia 1.12 and Distributions 0.25 available, from this directory:

```sh
julia --project=. test/runtests.jl
julia --project=. examples/linear.jl
```

```julia
using GroundTruth
s = Scenario("lm-n100"; n=100, alpha=1., beta=.7, sigma=1.2)
a = Adapter("OLS", ols; metadata=(likelihood="Gaussian identity",
    target="alpha,beta", prior="none", inference="OLS with t intervals",
    interval_level=.95))
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

## Logistic regression

The Bernoulli-logit model is

```math
Y_i \sim \operatorname{Bernoulli}(p_i), \qquad
\operatorname{logit}(p_i)=\alpha+\beta x_i.
```

Here `alpha` and `beta` are conditional log-odds coefficients. The public Julia API
fits them by bounded Newton maximum likelihood. The repaired
fitter reports normal Wald intervals from final observed information.

```julia
using GroundTruth
scenario = Scenario("logistic-n200"; family=:logistic, n=200,
                    alpha=-0.4, beta=0.8)
make_adapter(level) = Adapter("fixed-effect-logit-$level",
    (data, rng) -> logistic_mle(data, rng; level=level); metadata=(
        likelihood="Bernoulli logit", target="alpha,beta", prior="none",
        inference="maximum likelihood; normal Wald intervals", interval_level=level))
adapter95 = make_adapter(0.95)
study95 = runstudy([scenario], [adapter95]; reps=10, seed=20261006)
summarize(study95)
# Fit the other declared level in a separate study.
adapter90 = make_adapter(0.90)
study90 = runstudy([scenario], [adapter90]; reps=10, seed=20261006)
summarize(study90)
```

Complete and quasi separation, nonfinite coefficient transformations, and failure to
meet the numerical convergence checks reject the point fit. If only an interval cannot
be represented, an accepted point estimate remains available without that interval.
The default tolerance is `1e-9`. Convergence requires the maximum absolute
standardized mean score and the maximum absolute standardized Newton correction to
the linear predictor to be at most `tol`; half the Newton decrement must be at most
`tol^2 / 2`. These bounds are checked after recomputing the fit state. The score and
correction bounds use standardized quantities.

The R package adds a separate native `stats::glm()` binomial-logit adapter selected
with `gt_glm_adapter()`. R and Julia use distinct random streams. Cross-language numerical
comparisons therefore use the same frozen CSV bytes; equal seed labels do not imply
equal draws. Agreement on the bounded fixed-effect fixtures is not calibration evidence,
GLMM evidence, or a claim of package-wide parity.

## What is being tested?

Gaussian: `x ~ N(0,1)` and `y = alpha + beta*x + sigma*epsilon`, with independent
standard-normal errors. OLS estimates both coefficients, estimates residual variance
with `n-2` degrees of freedom, and uses exact Student t intervals under this DGP.

Logistic: `y ~ Bernoulli(logistic(alpha + beta*x))`. The coefficient targets are
conditional log odds, not marginal probabilities or causal effects. The candidate
uses normal Wald intervals at 0.90 and 0.95; request each level in a separate fit.
Finite-MLE existence and numerical convergence are distinct checks.

The symbol-to-code contract in [docs/ALIGNMENT.md](docs/ALIGNMENT.md) specifies the
generating terms and recovery mapping. The generator never calls fitted-model code or uses fitted priors.
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
| covered_per_attempt | Covered / all attempted fits |

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
hashes and complete scenario/adapter metadata in the example provenance files. Keep
scenario IDs meaningful and change them when changing the design. Timing is
informational; it is not a speed benchmark.

A custom adapter follows this contract:

```julia
myfit = Adapter("my-method", (data, rng) -> begin
    FitResult(Dict(:alpha=>1.1, :beta=>0.6);
              intervals=Dict(:alpha=>(0.8,1.4), :beta=>(0.3,0.9)),
              converged=true)
end; metadata=(likelihood="state it", target="alpha,beta",
               prior="state it", inference="state it", interval_level=.95))
```

The numbers above illustrate the return format; they are not an estimator. Exceptions,
nonconvergence, missing targets and nonfinite estimates are retained in `study.ledger`.
No automatic retries or parallel scheduler are provided.

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
and failure accounting. The local work repairs the existing Julia fixed-effect logistic
MLE and adds a native R Bernoulli-logit workflow. The Gaussian random-intercept example
remains an oracle with known covariance, not a fitted GLMM. Before growing the package, audit and
reuse an existing scheduler, plotting system or transport. DRM/GLLVM integrations, arbitrary estimands, Stan posterior comparison,
resumable campaigns and translation of arbitrary models are future work. BayesDRM and
BayesGLLVM are paused. See [actual verification status](STATUS.md).
