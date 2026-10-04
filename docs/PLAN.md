# Bounded prototype acceptance gates

1. Complete Gaussian slice: independent DGP, scalar estimands, OLS t intervals,
   stable data/adapter RNG streams, paired data, attempt ledger, conditional
   coverage denominator and covered-per-attempt fraction, bias/RMSE/MCSE.
2. Test scalar OLS formulas, replay/order invariance, adapter mutation isolation,
   exceptions/nonconvergence/nonfinite values, missing/invalid intervals,
   singleton/all-failed summaries, modest recovery smoke.
3. Compare identical exported Gaussian data against independent R lm code.
4. Provide explicit whitelist of reference templates; distinguish common
   likelihood/data/target from priors and inference. No automatic translator.
5. Only after Gaussian passes: bounded logistic MLE and known-covariance GLS
   random-intercept examples. Do not claim fitted variance-component GLMM support.
6. README aimed at R users; retained commands/results/status and provenance.

Reuse review supplied by parent task (4 October 2026): SimDesign, simEngine,
simChef, simsalapar, simFrame, DeclareDesign, simstudy, simcausal and simsem already
cover substantial R simulation work. Julia candidates include TARGENE/Simulations.jl,
CausalTables.jl, NeuralEstimators.jl and SimulationBasedCalibration.jl. GroundTruth
focuses on explicit statistical conformance and failure accounting; this prototype
uses a small serial loop, no new scheduler/plotting framework/compiler. Audit
specific APIs before adopting any backend. RCall/JuliaCall/JuliaConnectoR are future
transport choices; CSV is sufficient for this bounded reference comparison.

BayesDRM/BayesGLLVM work is paused by user instruction. No integration into existing
DRM/GLLVM environments; no campaign, pushing, deployment or new credentials.
