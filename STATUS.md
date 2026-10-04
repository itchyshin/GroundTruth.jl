# Factual status — 4 October 2026

## Completed locally

- Gaussian linear-model vertical slice: independent data generator; explicit coefficient
  truth; OLS t intervals; deterministic data/adapter stream keys; exception,
  nonconvergence and invalid-estimate ledger; usable-interval and attempt denominators.
- Bias/RMSE with Monte Carlo standard errors; conditional coverage with plug-in MCSE
  and Wilson Monte Carlo intervals; covered-per-attempt fraction. Missing summaries
  for all-failed cells and unknown MCSE for singleton cells.
- Bounded logistic MLE and known-covariance Gaussian random-intercept GLS example.
  The latter is an oracle, NOT a fitted GLMM or estimated variance-component model.
- R-user README, symbolic alignment, explicit Gaussian Stan/TMB template exporter,
  optional R reference scripts and synthetic outputs with provenance.

## Verified evidence

Julia 1.12.6, Distributions 0.25.131: **95 tests passed**, 0 failed/errors across
seven test sets (`test/runtests.jl`). Tests cover independent scalar OLS formulas,
replay/order invariance, mutation isolation, failures, mixed interval denominators,
MCSE formulas/boundaries, reference template selection, logistic score/separation,
known-covariance GLS, and a 100-replication Gaussian smoke test.

The saved `examples/linear.jl` run attempted 100 fits; all 100 yielded finite
coefficients and usable intervals. Intercept bias -0.005713 (MCSE 0.010965), slope
bias -0.000566 (MCSE 0.013361). Coverage 0.97 (MCSE 0.017059) and 0.94
(MCSE 0.023749), respectively. These are smoke results, not broad calibration evidence.

Independent reference checks on identical exported replication-1 data:

- Base R lm coefficients and exact t endpoints: maximum discrepancy 4.996004e-16.
- TMB 1.9.21 template compiled; BFGS convergence code 0, maximum score below 1e-4;
  coefficient discrepancy 9.182877e-11. Normalized log likelihood checked at a fixed
  parameter point to 1e-9. TMB intervals were not compared with OLS intervals.
- R glm coefficients and final-information Wald endpoints: discrepancy 3.566036e-13.
- Independent R known-covariance random-intercept GLS: discrepancy 1.110223e-15.

Extension examples each attempted 20 fits, all usable. The random-intercept intercept
coverage was 0.80 with Wilson Monte Carlo interval [0.584, 0.919]; slope coverage
was 0.90 [0.699, 0.972]. These small runs do not establish calibration. Logistic
intercept coverage was 1.00 [0.839, 1.00], illustrating why zero plug-in MCSE does
not establish certainty. Full summaries and ledgers are retained in `results/`.

## Corrected during verification

A test syntax error was corrected. A real adapter-input mutation bug was reproduced
by a failing test and fixed by providing each adapter a copy of paired data. Test
comparison of missing-valued rows now uses `isequal`. A strict-tolerance TMB nlminb
attempt failed its convergence gate; an independently verified BFGS run replaced it.
An R glm cached-covariance comparison differed by 1.4e-7 because the cached IRLS
weights came from the preceding iteration; final-information comparison is explicit.
These initial failures are not relabeled as passes.

## Not run / future

No Stan posterior sampling in this prototype. The exact explicit Gaussian Stan model
was reused from yesterday's verified matched benchmark; exporting it is not a new
posterior-validation result. No Turing adapter, arbitrary model translator, fitted
GLMM/variance components, DRM/GLLVM integration, general target DSL, scheduler,
checkpoint/resume, plotting infrastructure, campaign or speed claim. BayesDRM and
BayesGLLVM remain paused. R/Stan/TMB remain optional; Julia core runs alone.

No existing project environments were modified. Dependency resolution used cached
packages in an isolated task depot; no new credentials or remote compute. No GitHub
repository was created and nothing was pushed/deployed. Repository publication awaits
separate scoped approval of exact owner and tracked payload.

Scientific/factual gates: claims above are scoped to the saved local checks. Reference
gate: copied Stan template and local R/TMB checks have explicit provenance; the wider
framework review is parent-supplied context, not a new comprehensive audit here.
Writing-naturalness assessment: NOTASSESSED under the hub's formal protocol.
