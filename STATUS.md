# Factual status: 6 October 2026

## Implemented workflow

The Julia package and R twin support Gaussian and one-predictor Bernoulli-logit
studies. Julia uses the repaired fixed-effect logistic MLE; R provides a logistic
family and native GLM adapter. Julia also retains the known-covariance Gaussian
random-intercept GLS oracle. The checked numerical and failure contracts are
described below.

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

## Retained local validation

The frozen-fixture numerical gate passed under Julia 1.12.6 and Distributions 0.25.131.
It checked seven accepted data fits per engine, or 14 engine-by-fixture fits total,
and five rejected designs per engine. The largest paired absolute differences were 6.87e-11 for coefficients,
7.12e-12 for standard errors, 8.28e-11 for interval endpoints and 9.99e-16 for mean
negative log likelihood. The core Julia suite passed 393 assertions across 16 suites.

The R package check passed with 346 assertions under R 4.6.0 for development version
0.0.0.9000, with `Status: OK` and no NOTE. The pkgdown 2.2.0 site preview rendered and
its link and reference checks passed. The Julia Documenter 1.19.0 site build and local
link checks also passed. Package and documentation gates passed.

Julia and R streams are distinct; paired comparisons use identical frozen CSV bytes.
The evidence covers one-predictor Bernoulli models with unit weights and reused
references that were not newly refit. It supports bounded numerical agreement only. It
does not establish interval calibration, a fitted GLMM, broad performance or
package-wide cross-language parity.

## Scope limits

No fitted GLMM, broad calibration campaign, Stan posterior sampling result, speed
advantage or general cross-language parity is claimed. Gaussian OLS continues to use
Student t intervals; logistic MLE uses normal Wald intervals at separately requested
90% and 95% levels.
