# GroundTruth.jl

```@raw html
<section class="gt-hero">
<div class="gt-hero-copy"><span class="gt-eyebrow">STATISTICAL SIMULATION · JULIA</span>
<h2>How well does your estimator recover the truth?</h2>
<p>Generate data from a known process. Fit the same data with your chosen engine. Measure recovery, including failures and missing intervals.</p>
<div class="gt-actions"><a class="gt-button" href="quickstart.html">Run your first study</a><a class="gt-button gt-secondary" href="validation.html">See the validation</a></div>
<span class="gt-prototype">Research prototype · Gaussian and logistic examples</span></div>
<img class="gt-hero-logo" src="assets/logo.png" alt="GroundTruth.jl hex logo: noisy estimates compared with a known reference" width="240" height="240">
</section>
<div class="gt-cards">
<div class="gt-card"><span class="gt-dot gt-green"></span><h3>Generate independently</h3><p>The data generator is separate from the fitting engine. Truth comes from the scenario.</p></div>
<div class="gt-card"><span class="gt-dot gt-purple"></span><h3>Compare named targets</h3><p>Track coefficient estimates against explicit generating values.</p></div>
<div class="gt-card"><span class="gt-dot gt-blue"></span><h3>Keep failures visible</h3><p>Inspect every attempt. Distinguish accepted estimates from usable intervals.</p></div>
</div>
```

## Why GroundTruth?

A simulation should make its statistical contract easy to inspect: what generated
the data, which parameters were fitted, what an interval means, and which attempts
failed. GroundTruth brings these pieces together in a small Julia workflow.

Established tools already provide simulation, recovery summaries and R interfaces.
GroundTruth reuses fitting engines and makes no novelty claim for those features.

## Start with a complete example

- [Gaussian regression](quickstart.md): independent draws, OLS estimates and t intervals.
- [Capabilities and limits](capabilities.md): distinguish the fitted regressions from the known-covariance oracle.
- [Validation](validation.md): inspect the saved regression and reference checks.

## From scenario to recovery

```text
Scenario → independent generator → shared replication data
                                     ↓ copied per adapter
                           fitting engine → named FitResult
                                     ↓
                    declared truth + attempt ledger → summary
```

An adapter receives data and its own random-number stream, without scenario truth.
Bias, RMSE and coverage summaries retain their relevant denominators and Monte Carlo
uncertainty. A finite point estimate can remain useful when its interval is unavailable.

## Current verification

The saved core check has 95 passing assertions. Gaussian and logistic reference checks
are recorded in the repository status file. These checks support specific examples;
they do not establish broad calibration or speed gains. [Read the evidence](validation.md).

## Where it goes next

Further work should begin with a bounded audit of the logistic estimator. Explicit
Stan sampling and a small symbolic DGP view remain separate future steps.
[See the roadmap](roadmap.md).
