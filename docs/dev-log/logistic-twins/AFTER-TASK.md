# Logistic twins after-task report, 6 October 2026

## 1. Goal

Build the approved one-predictor Bernoulli-logit twins and deliver a local, uncommitted review bundle. This report concerns `GroundTruth.jl` on `codex/logistic-twins`, based at `9f0dd012f522b083a45ec03af7fad9bdbc9eb8e3`. Commit, push, merge and publication are outside this authorization.

## 2. Implemented

The Julia MLE now checks exact class-support overlap, centers and scales the predictor, uses stable Bernoulli identities and factored Newton steps with Armijo backtracking, and rebuilds final information. It transforms the full covariance and computes slope SE before scaling twice, preserving representable extreme-scale intervals. The public signature, iteration/tolerance defaults and FitResult fields are unchanged. Accepted-fit messages now remain visible in the study ledger.

Both languages fit the same 12 frozen synthetic datasets. Seven have finite MLEs; five exercise separation, one-class outcomes or a constant predictor. Documentation explains log-odds targets, normal logistic intervals at 90% and 95%, retained Student t Gaussian intervals, and point versus interval failure.

## 3a. Decisions and Rejected Alternatives

Keep the shared fixed-effect contract, numeric 0/1 responses, unit weights and named alpha/beta targets. Use exact support comparisons rather than a magnitude cutoff or jitter. Standardize for fitting and transform back. Do not polish the native R GLM with Julia. Do not widen tolerances to make a check pass. GLM.jl and earlier R reference evidence were reused with their hashes; those engines were not freshly refit for this arc. The old native GLM interval discrepancies stay visible.

## 4. Files Touched

Production source, focused tests and frozen fixtures, reviewed verification scripts, reader documentation, generated R help/exports, and this evidence bundle. R's pkgdown change adds only the new API to its reference index. See `SOURCE-MANIFEST.json` for exact paths and hashes and `candidate.patch` for the review diff. Generated previews and raw run logs remain ignored local artifacts.

## 5. Checks Run

Parent-run language/core/control gates pass in both roots. Julia core: 393 assertions across 16 groups. R CMD check: Status OK, 346 passing assertions, no errors, warnings or notes. Both local documentation builds and link checks pass with Julia 1.12.6, Distributions 0.25.131, Documenter 1.19.0, R 4.6.0 and pkgdown 2.2.0. The documentation wrapper verifies the private R candidate identity used by article rendering. Final runnable commands are retained in `evidence/gates/` and raw outputs under `.unlazy/logistic-twins/evidence/`.

The independent scalar comparison checks seven accepted data fits per engine, or 14 engine-by-fixture fits total. Each engine has 14 accepted coefficient-target rows and five rejected design cases. Maximum paired absolute differences: coefficients 6.87e-11, SEs 7.12e-12, endpoints 8.28e-11, mean negative log likelihood 9.99e-16. The frozen acceptance tolerances are unchanged. Public main SHAs were rechecked and match the approved bases. Preservation checks cover 500 original paths plus HEAD, status, staged and unstaged diff hashes in all three protected roots.

## 6. Tests of the Tests

The original Julia rescaling defect failed before repair. The science panel's large-scale interval probe also failed before repair: beta's 95% interval collapsed to (0,0) instead of representable endpoints of about +/-3.20e-200. Regressions now cover both levels at scales 1e200 and 1e-160, genuine interval overflow at 1e-310, and nonrepresentable point transformations.

Controls reject sign errors, swapped/missing/duplicate targets, initial-information intervals, normal Gaussian intervals, SSE/n, and changed fixture bytes. Named-row permutations pass the mathematical checker. The retained transport's byte gate separately rejects altered candidate CSV bytes on a disposable copy. Four-attempt accounting recovers three accepted points, two usable intervals, conditional coverage 1/2 and covered-per-attempt 1/4.

## 7a. Issue Ledger

Resolved: unit-dependent Julia rejection; extreme-scale interval underflow; quoted fixture parsing; test oracle/path/denominator/name mistakes; R tail residual and target-specific interval handling; cached-tool API differences; source tarball Git-pointer inclusion; missing pkgdown topic; article subprocess library resolution; case-sensitive Documenter anchor. Fresh science and implementation reviews examine the repairs. Rose reviews usability, claim limits and closure evidence; saved verdicts and gate receipts govern final acceptance.

## 8. Consistency Audit

Reviewed source, tests, README, Julia status and site pages, R help and article, reference index, source identities, and export metadata together. Historical Gaussian and logistic results are labeled separately from this arc. Julia's pre-existing known-covariance random-intercept example remains an oracle, not a fitted mixed model. Canonical handover, dirty canonical files, R branding and the old isolated Gaussian/LMM/audit work are preserved.

## 9. What Did Not Go Smoothly

The CLI account rejected the requested Luna model. Available producer and panel receipts record requested native model/effort settings; strict CLI enforcement is not claimed. Rose's exact dispatch inputs were not retained, so her model and effort are unverified. Direct worktrees replaced the auto-committing launcher to respect the no-commit boundary. A generated Graft cache was retained outside the repository. Julia cached-source Documenter precompilation overflowed; loading without compiled modules succeeded. Wrapper API/logging and candidate-library repairs preceded successful builds. One diagnostic log-path error retained its budget charge and was rerun with a safe filename.

Core numerical commands share one lock and cumulative 900-second allowance. A first documentation attempt may have overlapped Julia repair checks outside that wrapper; global serialization of every earlier documentation example is not claimed. Final verification is sequential. Automated visual browser inspection was blocked by the local-file URL policy; rendered-file, link and executed-example checks passed, but visual layout is not certified.

## 10. Known Residuals

The bundle is local and uncommitted. No remote write, dependency installation, campaign, CRAN submission or deployment occurred. Cached reference-engine results were reused, not refit. The ordinary-fixture scalar oracle does not prove optimizer robustness at arbitrary extreme logits; separate fixed-point identities and predictor-scale regressions cover their stated cases. Protected R branding is outside these fresh baseline patches and needs reconciliation before any future deployment. Remote CI and publication remain untested for this candidate.

## 11. Team Learning

Memory receipt: vault/project searches supplied no relevant current GroundTruth record; the repository contract and retained audit supplied technical grounding. The original approved plan, exact roots, ownership and dispatch changes remain on disk. No vault edits were performed.

Golden Set: a broader model collection is outside this arc; existing Gaussian fixtures and compatibility controls were rerun. Useful practices were independent scalar checks, identical hashed CSVs, tests before repair, fresh review of extreme units, and preserving failed receipts. Numerical agreement and artifact identity require separate checks.

## 12. Cross-Product Coverage

Covers Gaussian compatibility plus one-predictor Bernoulli fixed effects across generation, fit dispatch, point extraction, normal coefficient intervals, failure denominators, replay/export and reader documentation. Logistic family mismatches, both interval levels, shifted/reflected predictors and partial interval failures are exercised.

This arc does NOT cover fitted LMM/GLMM integration, weighted or multivariable logistic regression, interval calibration campaigns, Bayesian twins, JuliaCall, CRAN, arbitrary cross-language parity, remote CI or publication. It does not replace or land the retained old LMM checkout.
