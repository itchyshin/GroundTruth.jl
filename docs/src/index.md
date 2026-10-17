# GroundTruth.jl

```@raw html
<section class="gt-hero">
<div class="gt-hero-copy"><span class="gt-eyebrow">STATISTICAL SIMULATION · JULIA</span>
<h2>How well does your estimator recover the truth?</h2>
<p>Generate data from a known process. Fit the same data with your chosen engine. Measure recovery, including failures and missing intervals.</p>
<div class="gt-actions"><a class="gt-button" href="quickstart.html">Run your first study</a><a class="gt-button gt-secondary" href="validation.html">See the validation scope</a></div>
<span class="gt-prototype">Research prototype · Gaussian and logistic fixed effects, plus Gaussian random-intercept inference</span></div>
<img class="gt-hero-logo" src="assets/logo.png" alt="GroundTruth.jl hex logo: noisy estimates compared with a known reference" width="240" height="240">
</section>
<div class="gt-cards">
<div class="gt-card"><span class="gt-dot gt-green"></span><h3>Generate independently</h3><p>The data generator is separate from the fitting engine. Truth comes from the scenario.</p></div>
<div class="gt-card"><span class="gt-dot gt-purple"></span><h3>Compare named targets</h3><p>Track coefficient estimates against explicit generating values.</p></div>
<div class="gt-card"><span class="gt-dot gt-blue"></span><h3>Keep failures visible</h3><p>Inspect every attempt. Distinguish accepted estimates from usable intervals.</p></div>
</div>
```

## Why GroundTruth?

A simulation should make its statistical contract easy to inspect: what generated the
data, which parameters were fitted, what an interval means, and which attempts failed.
GroundTruth assembles these parts into a small Julia workflow. Existing tools already
provide simulation and recovery summaries; this package makes no novelty claim for
those features.

## Start with an example

- [Gaussian regression](quickstart.md): independent draws, OLS estimates and Student t intervals.
- [Logistic fixed effects](quickstart.md#Logistic-regression): Bernoulli-logit data and conditional log-odds targets.
- [Gaussian random-intercept model](random-intercept.md): use the optional adapter, choose observation- or group-level predictors, and read its inference limits.
- [Random-intercept inference comparison](random-intercept-inference.md): compare ML normal, REML normal and ML profile intervals on paired data.
- [Capabilities and limits](capabilities.md): review fixed-effect models, random-intercept ML/REML choices and the known-covariance oracle.
- [Validation scope](validation.md): inspect the separate fixed-effect checks and random-intercept reliability map.

## From scenario to recovery

```text
Scenario → independent generator → shared replication data
                                     ↓ copied per adapter
                           fitting engine → named FitResult
                                     ↓
                    declared truth + attempt ledger → summary
```

An adapter receives data and its own random-number stream, without scenario truth.
Bias, RMSE and coverage summaries retain their denominators. A finite point estimate can
remain useful when its interval is unavailable.

## Publication and validation status

Julia and the R twin provide Gaussian and logistic fixed-effect workflows and
Gaussian random-intercept ML and REML choices. The [reliability map](random-intercept-reliability.md)
retains 60,000 attempts across 15 scenarios, including failures, few-group undercoverage
and numerical tolerance exceedances. See [validation](validation.md) for the separate evidence scopes.
The R twin source is [GitHub: itchyshin/groundtruth](https://github.com/itchyshin/groundtruth),
and its established site is [groundtruth](https://itchyshin.github.io/groundtruth/).
