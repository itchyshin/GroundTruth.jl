# Validation

## Saved checks

The repository status records the following checks on the current prototype:

| Check | Saved result |
|---|---|
| Core Julia tests | 95 assertions passed |
| Base R `lm()` reference | Coefficients and t interval endpoints matched within 5.0e-16 |
| R `glm()` reference | Coefficients and final-information Wald endpoints matched within 3.6e-13 |
| Known-covariance GLS reference | Estimates matched within 1.2e-15 |
| Gaussian smoke example | 100 fits produced finite coefficients and usable intervals |

These are saved results from the repository status record, not a fresh test run made
while preparing this site. The smoke examples are small and do not establish general
calibration or speed gains.

## Failure accounting

Every attempted adapter fit remains in the ledger, including exceptions,
nonconvergence and invalid estimates. Point summaries use accepted finite estimates;
coverage uses intervals that are finite and ordered. A successful point estimate can
remain useful when its interval is unavailable. Read attempted, successful, failed,
and usable-interval counts together.

## Limits

The known-covariance random-intercept GLS example is an oracle: it receives the true
variance components and does not fit them. The saved checks do not establish fitted
GLMM support, broad interval calibration, Stan posterior sampling, or performance
advantages. See [capabilities and limits](capabilities.md) for the implemented scope.
