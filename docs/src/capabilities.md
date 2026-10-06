# Capabilities and limits

## What works today

| Model or feature | Current support | Limit |
|---|---|---|
| Gaussian linear regression | Independent generator; OLS coefficients and t intervals | Targets alpha and beta |
| Logistic regression | Independent Bernoulli generator; bounded Newton MLE and Wald intervals | Conditional log-odds; separation/instability can fail |
| Gaussian random intercept oracle | Independent grouped generator; known-covariance GLS | Sigma and tau are supplied, not estimated |
| Recovery | Bias, RMSE, Monte Carlo standard errors, coverage and Wilson uncertainty | Report accepted and usable-interval denominators |
| Reproducibility | Replay, named data/adapter streams, copied paired data, provenance | Record Julia/RNG versions; no cross-version draw guarantee |
| R exchange | CSV and optional identical-data R checks | No live R bridge |
| Stan/TMB | Explicit Gaussian templates with conformance receipts | Export does not run or validate a fit |

The repository status records 95 passing tests and independent R/TMB checks for the
prototype. Those are saved verification results, not a new run performed while writing
this page. Stan sampling was not rerun in this package. Small saved recovery runs are
smoke evidence and do not establish general calibration or speed gains.


## Gaussian random-intercept model

```math
y_i = \alpha + \beta x_i + u_{g(i)} + \sigma\epsilon_i,\qquad
u_j\sim N(0,\tau^2),\quad\epsilon_i\sim N(0,1).
```

The current random-intercept example supplies the generating `sigma` and `tau` to a
known-covariance GLS oracle. It demonstrates recovery when the covariance is known;
it does not estimate variance components.

## What the intervals mean

OLS uses coefficient t intervals. Logistic MLE uses normal Wald intervals, with
separation and instability treated as failure conditions.

## Reproducibility and scope

Replay and named random-number streams support repeatable studies within the
recorded environment. No cross-version draw guarantee is claimed. No fitted GLMM,
general translator or large calibration campaign has been completed.
[Inspect validation](validation.md) before extending an example.

## API reference

```@autodocs
Modules = [GroundTruth]
Order = [:module, :type, :function]
```
