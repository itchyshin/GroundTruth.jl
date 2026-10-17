# Compare random-intercept inference choices

The optional Gaussian random-intercept adapter lets you choose how it fits the
variance components and how it forms fixed-effect intervals. `criterion` accepts
`:ML` or `:REML`; `interval_method` accepts `:normal` or `:profile`. The profile
method is available only with ML. The adapter still returns the four point targets
`alpha`, `beta`, `sigma2` and `tau2`; only `alpha` and `beta` receive intervals,
at both 0.90 and 0.95 from one accepted fit.

## Put the methods in one paired study

Create three adapters with distinct IDs, then pass them to one `runstudy`. The
runner gives each adapter the same generated data for each replication. This short
example shows the interface; four replications are far too few to assess calibration.
The code is not run while building the documentation.

```julia
using GroundTruth
include("adapters/lmm/lmm_ml.jl")
using .GroundTruthLMM: lmm_ml

scenario = ri_scenario("inference-example"; group_sizes=fill(6, 20),
                       alpha=1.0, beta=0.7, sigma=1.0, tau=0.5)
adapter(id, criterion, method) = Adapter(id,
    (data, rng) -> lmm_ml(data, rng; criterion, interval_method=method,
                          profile_timeout=60.0);
    metadata=(likelihood="Gaussian random-intercept", target="alpha,beta,sigma2,tau2",
              prior="none", inference="$criterion with $method coefficient intervals",
              interval_level=0.95))

study = runstudy([scenario],
    [adapter("ml-normal", :ML, :normal),
     adapter("reml-normal", :REML, :normal),
     adapter("ml-profile", :ML, :profile)];
    reps=4, seed=20261017)

ml_vs_reml = compare_inference(study;
    baseline="ml-normal", comparison="reml-normal")
ml_vs_profile = compare_inference(study;
    baseline="ml-normal", comparison="ml-profile")
details = inference_details(study)
```

`compare_inference` returns separate rows for scenario, fixed-effect target and
nominal level. Differences are comparison minus baseline. The comparison uses
the study's scheduled attempts and checks that the replication keys match; matching
replication numbers from separate studies would not establish paired data. Inspect
`schedule_verified` before interpreting a comparison.

## Read the comparison denominators

`baseline_coverage` and `comparison_coverage` are conditional on a finite usable
interval for that method. `baseline_finite_yield` and `comparison_finite_yield`
are the fractions of all scheduled attempts
that produced a finite interval containing the truth. The paired yield difference
counts attempts without usable finite intervals as zero contribution, including
failed fits and missing, nonfinite, unbounded or incomplete intervals. An absent
companion leaves its diagnostic state unknown; legacy intervals still contribute
when their usable-interval flag is true. An unknown diagnostic state does not imply
an unbounded set or a missing finite interval. These quantities answer different questions:
conditional coverage can be high when many attempts have no usable interval, while
finite covered-interval yield retains that loss in its denominator.

`coverage_difference_mcse` is a paired first-order ratio/delta-method Monte Carlo
standard error. `finite_yield_difference_mcse` is the sample standard deviation of
paired covered-per-attempt indicators divided by the square root of the attempt count.
These are asymptotic descriptions of simulation uncertainty, not finite-sample
calibration guarantees. A missing conditional coverage or MCSE means its denominator
or sample size is insufficient; it is not zero coverage. `joint_width_difference`
uses only attempts with usable intervals under both methods and is a descriptive
width comparison.

The companion detail rows returned by `inference_details(study)` identify each
coefficient interval as `:finite`, `:unbounded`, `:incomplete`, `:error`, `:timeout`
or `:invalid`, with criterion, interval method, endpoints and profile diagnostics
where available, including root-LR residual, endpoint distance, elapsed time and
message. A missing detail row has state `:unknown`; it does not mean that an
interval is unbounded. Only finite, ordered endpoints enter the legacy usable-interval
denominator. Failed profiles preserve accepted point estimates, and a timeout or
search failure is not evidence of an unbounded confidence set.

## What the intervals mean

With `interval_method=:normal`, the adapter uses the fitted ML or REML variance
components to reconstruct the fixed-effect covariance
`(X' * V^-1 * X)^-1`, then uses normal quantiles at 0.90 and 0.95. These are
approximate plug-in intervals with normal rather than Student t quantiles; they do
not receive an additional residual-scale multiplier. The two levels use the same
covariance from one fit.

With `criterion=:ML, interval_method=:profile`, only the two fixed effects are
profiled. The endpoints use asymptotic likelihood-ratio cutoffs. ML normal and ML
profile use the same point-estimation procedure; their paired comparison concerns
interval construction, not two independent estimators. This method choice does not
establish small-sample coverage or guarantee that a profile is finite; inspect the typed
states and diagnostics. `:REML` with `:profile` is rejected. ML and REML optimize
different objective functions, so their objective magnitudes are not directly
comparable.

Fit diagnostics record the objective convention. The REML negative log likelihood
includes `log|X' V^-1 X|` in addition to the covariance determinant and residual
quadratic, under the documented explicit Gaussian convention. Its magnitude therefore
cannot be ranked against the ML objective.

The adapter and its profile-helper base refit use internal objective stopping
controls `ftol_rel=1e-12` and `ftol_abs=1e-12`. For the MixedModels 4.36
backend, the relative control matches its native default; the absolute control is
tighter than its native `1e-8` default. This can require more objective evaluations.
The optimizer family, other controls and caller's `maxfeval` limit (default 10000)
are preserved. The policy applies uniformly to ML and REML and does not change the
interval formulas or nominal levels. Actual controls and native status are recorded
in fit diagnostics; a stopping status alone does not establish numerical accuracy.

The hard profile deadline covers profiling after the accepted base fit. It requires
POSIX process support; on unsupported platforms profiling returns error states while
preserving the point estimates. The deadline does not limit time spent in the base fit.

The design can also limit what a variance component identifies. With two groups and
a predictor constant within each group, the REML likelihood is flat in `tau2` at fixed
`sigma2`. In that design, the reported `tau2` and its plug-in fixed-effect covariance
depend on the arbitrary fitted value; do not read it as variance recovery or demand
agreement between engines. This information limit is distinct from a singular
`tau2 = 0` fit and from residual-variance collapse. More generally, two groups,
replication within groups and a full-rank fixed-effect design do not by themselves
prove that both variance components are identifiable.

The [finite-design reliability map](random-intercept-reliability.md) reports the
earlier ML normal-interval study. It does not evaluate REML or profile intervals.
Neither the comparison helper nor a successful profile status certifies a method as
calibrated. Calibration requires a design-specific study with enough independent
replications and complete failure accounting.
