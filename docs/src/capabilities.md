# Capabilities and limits

| Model or feature | Scope | Limit |
|---|---|---|
| Gaussian linear regression | Independent generator; OLS coefficients and Student t intervals | Targets intercept `alpha` and slope `beta` |
| Logistic fixed effects | Existing public Julia Bernoulli-logit generator and MLE; this candidate repairs the MLE and adds a native R GLM adapter | Conditional log odds; finite-MLE existence and convergence are checked |
| Recovery | Bias, RMSE, Monte Carlo uncertainty, coverage and Wilson uncertainty | Report accepted and usable-interval denominators |
| Reproducibility | Replay, named streams, copied paired data and provenance | Julia and R streams are distinct; no cross-version draw guarantee |
| R exchange | CSV and optional identical-data R checks | No live R bridge |
| Stan/TMB | Explicit Gaussian templates with conformance receipts | Export does not run or validate an engine fit |

The public Julia package already includes the fixed-effect logistic API. This local
candidate repairs its MLE and adds R support. The frozen-fixture numerical, package and
documentation checks passed; see [validation](validation.md) for versions and scope.
The candidates remain local and unpublished. The Gaussian random-intercept example is
a known-covariance oracle with supplied variance components, not a fitted GLMM.

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

## Gaussian random-intercept oracle

The public example supplies the generating `sigma` and `tau` to known-covariance GLS.
It demonstrates recovery when covariance is known. It does not estimate variance
components or fit a GLMM.

## Scope

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
