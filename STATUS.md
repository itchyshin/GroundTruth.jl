# Factual status: 6 October 2026

## Publication boundary

The public Julia package and documentation already include a logistic MLE example and
a known-covariance Gaussian random-intercept GLS oracle. The public R site covers the
established Gaussian workflow. This local candidate repairs the Julia fixed-effect
logistic MLE and adds an R logistic family and native adapter. The R logistic addition
and the repaired Julia candidate remain local and unpublished. The changes are
uncommitted; review and publication approval have not been completed.

## Historical verification retained from the 4 October status

The saved Julia prototype status recorded Julia 1.12.6 and Distributions 0.25.131, with
95 passing assertions across seven test sets. Those tests covered independent scalar
OLS formulas, replay/order invariance, mutation isolation, failure accounting,
reference-template selection, logistic score/separation, the known-covariance oracle,
and a 100-replication Gaussian smoke run. The saved Gaussian example attempted 100
fits, all with finite coefficients and usable intervals. Its intercept bias was
-0.005713 (MCSE 0.010965), slope bias -0.000566 (MCSE 0.013361), and coverage was 0.97
(MCSE 0.017059) and 0.94 (MCSE 0.023749). These small-run results do not establish
broad calibration.

Saved same-data references included a base R `lm()` coefficient and exact t-endpoint
discrepancy of 4.996004e-16 and a TMB 1.9.21 Gaussian template coefficient discrepancy
of 9.182877e-11. The earlier native R `glm()` comparison was on the logistic reference
fixture: coefficients and final-information Wald endpoints differed by 3.566036e-13.
That is earlier reference evidence, distinct from the candidate paired-fixture
cross-language check below.

A saved 20-replication logistic extension had intercept coverage 1.00 with Wilson
Monte Carlo interval [0.839, 1.00]. This illustrates uncertainty with a small sample;
it is not calibration evidence. The known-covariance Gaussian random-intercept example
is an oracle with supplied `sigma` and `tau`, not an estimated variance-component model
or fitted GLMM. Its saved checks do not establish mixed-model support.

## Local candidate checks

The frozen-fixture numerical gate passed under Julia 1.12.6 and Distributions 0.25.131.
It checked 14 accepted fits across seven paired fixtures and five rejected-design
fixtures. The largest paired absolute differences were 6.87e-11 for coefficients,
7.12e-12 for standard errors, 8.28e-11 for interval endpoints and 9.99e-16 for mean
negative log likelihood. The core Julia suite passed 393 assertions across 16 suites.

The R package check passed with 346 assertions under R 4.6.0 for development version
0.0.0.9000, with `Status: OK` and no NOTE. The pkgdown 2.2.0 site preview rendered and
its link and reference checks passed. The Julia Documenter 1.19.0 site build and local
link checks also passed. The local candidate passed package and documentation gates. These results do not
approve publication.

Julia and R streams are distinct; paired comparisons use identical frozen CSV bytes.
The evidence covers one-predictor Bernoulli models with unit weights and reused
references that were not newly refit. It supports bounded numerical agreement only. It
does not establish interval calibration, a fitted GLMM, broad performance or
package-wide cross-language parity.

## Scope limits

No fitted GLMM, broad calibration campaign, Stan posterior sampling result, speed
advantage or general cross-language parity is claimed. Gaussian OLS continues to use
Student t intervals; logistic MLE uses normal Wald intervals at separately requested
90% and 95% levels. The candidate remains local and uncommitted. Final review and
publication approval have not been completed.
