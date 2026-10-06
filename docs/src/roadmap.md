# Roadmap

1. Audit the existing logistic fit against independent reference engines and decide
   whether a bounded repair is warranted.
2. Plan a fitted Bernoulli random-intercept GLMM as a separate arc, with explicit
   conditional targets, approximation settings and same-data validation.
3. Run the existing explicit Stan LM reference with its declared priors and sampling
   diagnostics. Posterior intervals need not match OLS intervals.
4. Demonstrate a named-schema CSV round trip with R; audit existing transports if
   file exchange becomes limiting.
5. Add a small symbolic DGP table or diagram linking each independent draw, parameter,
   truth value and fit extractor. No general model compiler is planned.
6. Validate variance-component interval procedures and design a calibration study with
   explicit Monte Carlo precision, failure accounting and an approved compute target.

BayesDRM/BayesGLLVM remain paused. DRM/GLLVM integration, resumable scheduling,
arbitrary estimands and a general translator are later decisions. There is no blanket
Julia speed claim.


## Development boundaries

GroundTruth.jl is a research prototype. New fitted-model integrations need explicit
estimands, independent generators, same-data references and failure contracts. Small
saved examples do not establish general calibration or speed advantages.

## Reference sources

- [Documenter guide](https://documenter.juliadocs.org/stable/man/guide/): local documentation builds.
