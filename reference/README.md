# Reference-model conformance

All templates use exported `x,y` unchanged and map `alpha` to intercept, `beta` to slope.
The independent generator lives in `src/GroundTruth.jl`, never in these fitting templates.

| Path | Likelihood | Priors | Inference |
|---|---|---|---|
| Julia OLS / R lm | Gaussian identity | none | OLS coefficients, unbiased variance, exact t intervals |
| TMB linear.cpp | Same normalized Gaussian likelihood | none | ML via optim BFGS; ML residual variance |
| Stan linear.stan | Same Gaussian likelihood | alpha N(0,5), beta N(0,2), log_sigma N(0,0.5) | Bayesian posterior; optional NUTS |

Stan samples `log_sigma` directly, implying a lognormal prior on sigma. No sigma-coordinate
Jacobian belongs in the current log_sigma parameterization. The prior and posterior
summary are not equivalent to the OLS frequentist interval procedure.

`linear.stan` was copied byte-for-byte from the explicit matched benchmark at
the previous day's task-6 `scripts/linear.stan`, previously fitted there. This prototype has not rerun Stan sampling. TMB's new small template is checked
locally against independent R normalized log likelihood at a fixed parameter point and
against OLS coefficients. Fitting with BFGS replaced an unsuccessful strict-tolerance
nlminb attempt; convergence code and score are both checked. TMB intervals are not
claimed to equal OLS intervals: ML variance divides by N while OLS divides by N-2.

From the package root, optional checks:

```sh
Rscript --vanilla reference/check_lm.R
Rscript --vanilla reference/check_tmb.R
Rscript --vanilla reference/check_extensions.R
```

TMB requires installed TMB and a C++ toolchain. Its build is confined to
`results/linear/tmb-build`; source templates are not compiled in place. These scripts
install nothing. `check_extensions.R` checks logistic coefficients via R glm and
recomputes information at the final probabilities for interval comparison (glm's cached
IRLS covariance can use the preceding iteration weights). Its random-intercept check
is an independent known-covariance GLS calculation, not a fitted GLMM.

An optional Stan run after installing/configuring CmdStan separately:

```r
library(cmdstanr)
d <- read.csv("results/linear/rep1-data.csv")
m <- cmdstan_model("reference/linear.stan")
f <- m$sample(data=list(N=nrow(d), x=d$x, y=d$y),
               chains=2, parallel_chains=1, seed=20261005,
               iter_warmup=500, iter_sampling=500, refresh=0)
f$summary(c("alpha", "beta", "log_sigma"))
f$diagnostic_summary()
```

This illustrative run is NOT part of verified core tests. Before accepting a Bayesian
adapter, check convergence, effective sample size, divergences, parameter mapping,
interval levels and diagnostics, and return rejected fits to the ledger. Exporting a
matching likelihood does not verify the inference engine. StanBlocks.jl and RTMB may
help later; translation or shared likelihood code must not become the generator oracle.
