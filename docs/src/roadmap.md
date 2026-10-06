# Roadmap

1. Local frozen-fixture, package and documentation checks for the Julia logistic MLE
   repair and R logistic workflow are complete. Final bundle review and publication
   approval remain separate decisions.
2. Keep fitted Bernoulli random-intercept GLMM work as a separate proposal with explicit
   estimands, approximation settings and same-data validation.
3. Run the explicit Stan Gaussian reference with its declared priors and sampling
   diagnostics if posterior sampling is needed. Posterior intervals need not match OLS.
4. Audit named-schema data transport only if file exchange becomes a practical limit.
5. Add a symbolic DGP view when it improves inspection of draws, parameters, truth and
   fit extraction.
6. Design any calibration study with explicit Monte Carlo precision, failure
   accounting and an approved compute target.

BayesDRM/BayesGLLVM remain paused. DRM/GLLVM integration, resumable scheduling, arbitrary
estimands and a general model translator require separate decisions. No blanket Julia
speed or Julia/R parity claim is planned.

## Development boundary

GroundTruth.jl is a research prototype. Each new fitted-model integration needs explicit
estimands, independent generators, same-data references and a failure contract. Small
saved examples do not establish general calibration or performance advantages.
