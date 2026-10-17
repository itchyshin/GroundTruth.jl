# Gaussian random-intercept model

The random-intercept workflow generates grouped Gaussian data and fits a marginal
maximum-likelihood model with one fixed predictor and a random intercept:

```math
 y_{ij} = \alpha + \beta x_{ij} + u_j + \epsilon_{ij},
 \qquad u_j \sim N(0,\tau^2),
 \qquad \epsilon_{ij} \sim N(0,\sigma^2).
```

The predictor, group effects and residual errors are generated independently. The
predictor level is explicit: `x_level=:observation` (the default) draws one independent
standard Normal value per observation; `x_level=:group` draws one value per group and
expands it to that group's observations in canonical group order. This expansion is
defined by the scenario's group sizes, including unequal sizes. Both modes use the same
conditional response model, and predictor draws remain independent of group effects
and residual errors. The scenario records the true intercept, slope, residual variance
`sigma2 = sigma^2`, and group-intercept variance `tau2 = tau^2`. The generator does not
call the fitter. Julia
adapters receive `x`, `y`, and `group` with the existing `family=:random_intercept`
tag. An R custom fitter receives exactly `x`, `y`, and `group` in its data frame.

## Julia

The mixed-model adapter is an optional source module. Use an environment that has
`GroundTruth` and `MixedModels` available, then load the adapter explicitly:

```julia
using GroundTruth
include("adapters/lmm/lmm_ml.jl")
using .GroundTruthLMM: lmm_ml

scenario = ri_scenario("grouped-example"; group_sizes=fill(6, 20),
                       alpha=1.0, beta=0.7, sigma=1.0, tau=0.5,
                       x_level=:observation)
group_scenario = ri_scenario("group-x-example"; group_sizes=fill(6, 20),
                             alpha=1.0, beta=0.7, sigma=1.0, tau=0.5,
                             x_level=:group)
adapter = Adapter("Gaussian-ML", lmm_ml; metadata=(
    likelihood="Gaussian random-intercept ML", target="alpha,beta,sigma2,tau2",
    prior="none", inference="ML; approximate normal coefficient intervals",
    interval_level=0.95))
study = runstudy([scenario], [adapter]; reps=2, seed=20261006)
foreach(println, summarize(study))
```

The adapter fits `y ~ 1 + x + (1 | group)` by maximum likelihood (`REML=false`). The
optional module keeps the mixed-model dependency out of the ordinary package path.
`ri_scenario` accepts a vector of positive group sizes with at least two groups and at
least one group containing multiple observations. Its total sample size is the sum of
the group sizes. The general `Scenario(...; family=:random_intercept, x_level=...)`
constructor accepts the same `:observation` and `:group` levels. Other families retain
observation-level predictors.

The random-intercept generator revision is `random-intercept-v2`. Provenance records
scenario settings and the revision so data can be replayed from the recorded seed under
the package's RNG contract. Julia and R use different RNG algorithms; equal seed labels
do not produce cross-language identical draws. The predictor-level option does not
change the estimand or fitter.

The supported constructors retain their API defaults. Julia object serialization
across older struct layouts is outside the compatibility contract; record the scenario
and seed through the package provenance/replay workflow instead.

The conditional residual ICC, given `x`, is
`tau^2 / (tau^2 + sigma^2)`. For `x_level=:group`, the shared predictor also contributes
to unconditional same-group response correlation. Thus a conditional ICC of 0.2 is
not an unconditional ICC of 0.2.

The adapter returns named point estimates for all four targets. It reports approximate
90% and 95% normal plug-in intervals for `alpha` and `beta`, based on the fitted marginal
covariance from one model fit. They are not exact finite-sample intervals. Variance
targets `sigma2` and `tau2` are point estimates only; their interval coverage is marked
unavailable. The runner records coefficient results at both levels and one point-only
result per variance target. Fit failures remain in the attempt ledger. A valid boundary
estimate `tau2 = 0` is accepted and flagged in diagnostics. If a coefficient covariance
or interval is unavailable, the fit can retain its valid point estimates.

## R

The [separate R twin package](https://github.com/itchyshin/groundtruth) exposes the same
scenario through `gt_ri_scenario()` and an optional `lme4` adapter through
`gt_lmm_adapter()`:

```r
library(groundtruth)

scenario <- gt_ri_scenario("grouped-example", n_groups = 20L,
                           group_sizes = 6L, alpha = 1, beta = 0.7,
                           sigma = 1, tau = 0.5,
                           x_level = "observation")
group_scenario <- gt_ri_scenario("group-x-example", n_groups = 20L,
                                 group_sizes = 6L, alpha = 1, beta = 0.7,
                                 sigma = 1, tau = 0.5,
                                 x_level = "group")
study <- gt_runstudy(scenario, adapters = gt_lmm_adapter(),
                     reps = 2L, seed = "20261006")
gt_summarize(study)
```

Install `lme4` separately to use this adapter. If it is unavailable, the adapter gives
an actionable message. It fits the same Gaussian random-intercept model by ML. Scenario
construction, four-target scoring, coefficient interval levels, point-only variance
summaries, and failure accounting follow the same contract as the Julia workflow.
Legacy R scenarios and studies without `x_level` normalize to `"observation"` on replay.
Random-intercept exports use schema v4 and include `x_level`; existing v3 artifacts are
preserved. R's RNG algorithm remains separately named from Julia's.

These two-repetition examples explain the interface; they do not measure
calibration. The separate [finite-design reliability map](random-intercept-reliability.md)
retains all 60,000 attempts across 15 scenarios. It records few-group undercoverage
and numerical tolerance exceedances. The earlier fixed-effect evidence has its own scope.
