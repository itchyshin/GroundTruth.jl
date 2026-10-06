# Quickstart

## Gaussian regression

This established example fits ordinary least squares and uses Student t intervals.
With Julia and the package dependencies available, run from the package root:

```sh
julia --startup-file=no --project=. test/runtests.jl
```

```julia
using GroundTruth
scenario = Scenario("linear-n100"; n=100, alpha=1.0, beta=0.7, sigma=1.2)
adapter = Adapter("OLS", ols; metadata=(
    likelihood="Gaussian identity", target="alpha,beta", prior="none",
    inference="OLS with Student t intervals", interval_level=0.95))
study = runstudy([scenario], [adapter]; reps=10, seed=20261004)
foreach(println, summarize(study))
```

Ten repetitions demonstrate the interface, not calibration. Every attempt remains in
the ledger. Point summaries use accepted estimates, while coverage uses finite,
ordered intervals. Read successful, failed and usable-interval counts together.

## Logistic regression

For a Bernoulli-logit model, `alpha` and `beta` are conditional log-odds coefficients:

```math
Y_i \sim \operatorname{Bernoulli}(p_i),\qquad
\operatorname{logit}(p_i)=\alpha+\beta x_i.
```

The public Julia fitter accepts the logistic family. This candidate repairs its bounded
Newton MLE; intervals use final observed information and normal Wald quantiles.

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
foreach(println, summarize(study95))
# Evaluate the same replications at the other interval level; each level is a separate fit.
adapter90 = make_adapter(0.90)
study90 = runstudy([scenario], [adapter90]; reps=10, seed=20261006)
foreach(println, summarize(study90))
```

The example runs separate studies at `level=0.90` and `level=0.95`. Each level uses a
separate fit, with the same replication data generated from the scenario. The default
fitter level remains 0.95. Exact class-support checks reject complete and quasi separation. Nonconvergence or
invalid point estimates reject a fit. If an interval cannot be represented for an
accepted estimate, the estimate remains available and only that interval is omitted. With the default `tol=1e-9`, convergence
requires the maximum absolute standardized mean score and maximum absolute standardized
Newton correction to the linear predictor to be at most `tol`; half the Newton
decrement must be at most `tol^2 / 2`. The score and correction criteria use
standardized quantities.

A matching R study uses `gt_scenario(..., family="logistic")` and
`gt_glm_adapter()`. The R adapter uses native `stats::glm()` with binomial logit link,
then checks native GLM convergence, a maximum absolute standardized score of at most
`1e-9`, and a maximum absolute standardized Newton correction to the linear predictor
of at most `1e-9`. R and Julia
have distinct RNG streams. To compare numerical results, both fit the same frozen CSV
bytes; identical seed labels do not produce identical cross-language draws.

Agreement on the specified fixed-effect fixtures is a bounded numerical check. It is
not an interval-calibration result, fitted-GLMM result or package-wide parity claim. The
R package and both documentation builds passed local checks.

## Keep denominators visible

An exception, nonconvergence or invalid required coefficient is a failed fit. An
unusable interval does not erase an accepted point. Conditional coverage divides by
usable intervals; `covered_per_attempt` divides by every attempt. Small replication
counts show accounting behavior, not repeated-sampling calibration.
