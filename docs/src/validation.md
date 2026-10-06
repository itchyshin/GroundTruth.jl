# Validation scope

## Historical Gaussian and logistic checks

The saved Julia status records 95 passing assertions for its earlier prototype, along
with the Gaussian OLS and TMB checks. It also records an earlier same-data R `glm()`
comparison on a logistic fixture: coefficients and final-information Wald endpoints
differed by 3.566036e-13. A separate 20-replication logistic extension had intercept
coverage 1.00 with Wilson interval [0.839, 1.00]. These are historical checks of the
public baseline, not a fresh run of this candidate or broad calibration evidence.

## Local repair and R addition

The local candidate repairs the existing Julia fixed-effect logistic MLE and adds a
native R family/adapter. On Julia 1.12.6 with Distributions 0.25.131, the frozen-fixture
numerical gate checked 14 accepted fits across seven paired fixtures and five
rejected-design fixtures. Maximum paired absolute differences were 6.87e-11 for
coefficients, 7.12e-12 for standard errors, 8.28e-11 for interval endpoints and
9.99e-16 for mean negative log likelihood. The core Julia tests passed 393 assertions
across 16 suites.

R 4.6.0 checked package version 0.0.0.9000: 346 assertions passed, with `Status: OK`
and no NOTE. The local pkgdown 2.2.0 preview rendered successfully. Documenter 1.19.0
built the Julia documentation, and the local page, link and anchor checks passed. These
are local checks; the candidate changes remain uncommitted and publication is not
approved.

The comparison reused identical frozen CSV bytes because Julia and R use distinct random
streams. Its scope is one-predictor Bernoulli models with unit weights; references were
reused, not newly refit. Agreement is bounded to the named fixtures, quantities and
tolerances. It does not establish interval calibration, GLMM behavior, broad performance
or package-wide parity. The earlier R `glm()` comparison above is historical evidence on
a separate logistic reference check.

## Failure accounting

Finite-MLE existence and convergence are distinct. Complete and quasi separation prevent
a finite unique logistic MLE under the declared one-predictor model. Data with a finite
MLE can still encounter an optimization or information failure. Conversely, a
converged point estimate can remain accepted when only an interval fails. Reports should
keep point acceptance, interval usability and native-engine diagnostics separate.

## Historical and current limits

The known-covariance Gaussian random-intercept GLS example is an oracle with supplied
variance components, not a fitted GLMM. No broad interval-calibration campaign, fitted
mixed model, Stan posterior sampling result, speed advantage or general cross-language
parity follows from the small saved examples or the bounded logistic comparison.
