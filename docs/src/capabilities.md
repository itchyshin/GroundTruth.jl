# Capabilities and limits

| Model or feature | Scope | Limit |
|---|---|---|
| Gaussian linear regression | Independent generator; OLS coefficients and Student t intervals | Targets intercept `alpha` and slope `beta` |
| Logistic fixed effects | Julia Bernoulli-logit generator and repaired MLE; native R GLM adapter in groundtruth | Conditional log odds; finite-MLE existence and convergence are checked |
| Gaussian random intercept | Optional Julia and R adapters; choose ML or REML variance fitting and normal or ML-profile coefficient intervals; four named targets | Profile intervals are ML-only; variance targets are point-only; no method is guaranteed calibrated |
| Random-intercept predictor level | Supports `x_level=:observation` (default) and `:group`; group values expand in canonical group order | Group-level x changes unconditional response correlation; ICC is conditional on x |
| Recovery | Bias, RMSE, Monte Carlo uncertainty, coverage and Wilson uncertainty | Report accepted and usable-interval denominators |
| Reproducibility | Replay, named streams, copied paired data and provenance | Julia and R streams are distinct; no cross-version draw guarantee |
| R exchange | CSV and optional identical-data R checks | No live R bridge |
| Stan/TMB | Explicit Gaussian templates with conformance receipts | Export does not run or validate an engine fit |

Julia and R provide fixed-effect logistic workflows. The retained frozen-fixture, package
and documentation checks cover those earlier workflows; see [validation](validation.md)
for versions and scope. The existing Gaussian random-intercept example is a known-covariance
oracle with supplied variance components. The optional adapter fits the Gaussian
random-intercept model by ML or REML; see the [model guide](random-intercept.md)
and [inference comparison guide](random-intercept-inference.md). The
[finite-design reliability map](random-intercept-reliability.md) reports failed fits,
few-group undercoverage and numerical discrepancies without a blanket calibration claim.

## Logistic model and interpretation

```math
Y_i \sim \operatorname{Bernoulli}(p_i), \qquad
\operatorname{logit}(p_i)=\alpha+\beta x_i.
```

The coefficients are conditional log odds. The Julia implementation standardizes the
predictor for fitting and transforms estimates and the full covariance back to the
original coefficient scale. With default `tol=1e-9`, convergence requires a maximum
absolute standardized mean score and maximum absolute standardized Newton correction
to the linear predictor no greater than `tol`. Half the Newton decrement must be no
greater than `tol^2 / 2`.
Exact response-class support checks detect complete and quasi separation;
rounded probabilities are not a separation test. A finite-MLE data set can still fail
optimization, so finite-MLE existence and numerical convergence are separate questions.

Julia and R use normal Wald coefficient intervals at 90% and 95%. Gaussian OLS retains
Student t intervals. Logistic levels are requested as separate fits or studies. An
interval-only failure can leave valid point estimates in the summaries.

## Known-covariance Gaussian random-intercept oracle

The public example supplies the generating `sigma` and `tau` to known-covariance GLS.
It demonstrates recovery when covariance is known. It does not estimate variance
components or fit a GLMM.

## Scope

The random-intercept adapters report point estimates for `alpha`, `beta`, `sigma2`, and
`tau2`. The default normal method provides approximate plug-in intervals at 90% and 95%
for the two coefficients under either ML or REML. ML can also request fixed-effect
profile intervals with asymptotic likelihood-ratio cutoffs. These choices are not
calibration guarantees. Variance-component uncertainty is not represented by intervals,
so variance coverage is unavailable. A converged boundary fit with `tau2 = 0` is valid.

A bounded numerical match on specified fixtures supports only those fixtures, quantities
and tolerances. It does not establish calibration, mixed-model accuracy or
package-wide Julia/R parity. The two languages draw independent streams; comparisons use
shared frozen CSV inputs. No broad calibration, speed advantage or general model
translation is claimed.

## API reference

```@autodocs
Modules = [GroundTruth]
Order = [:module, :type, :function]
```
