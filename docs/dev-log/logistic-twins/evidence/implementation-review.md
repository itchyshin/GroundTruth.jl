# Logistic twins final implementation review

**Verdict: ACCEPT for the approved implementation and evidence-verification slice.** The Julia underflow repair is covered by targeted scale tests and the latest retained numerical gates. The retained comparator now verifies both frozen audit/reference inputs and candidate fit CSV bytes before validating the outputs. The R documentation wrapper verifies the package identity used by the rendered article. Both language G6 records pass. This verdict does not certify the remaining root handoff/reconciliation work or release readiness.

## Scope and review limits

Read-only inspection of the final Julia repair and tests, comparator retained-input path, transport provenance, disposable-copy tamper control, R docs wrapper and article identity assertions, source and bundle manifests, exact candidate patches, and latest language G6 evidence. I did not run tests, fits, builds, or edit repository files. Gate and comparator outcomes below are retained evidence, not reruns in this review.

The exact worktree bases are Julia `9f0dd012f522b083a45ec03af7fad9bdbc9eb8e3` and R `f44a0bfe29d34f081f7eaca3d07b0fbf93a3bf2f`. Current source identities are Julia `src/GroundTruth.jl` SHA256 `197852caa75f56d0c3b56fbdd48775bb143c246f4dd89f185a64a51933d2089c` and R `R/groundtruth.R` SHA256 `b130c50fbf54e81a764c28684d5f085c7e0e1ecc8ab428198c443488d83717cb`. The R identity also matches `inst/source-identity.R`. Both candidates remain local and uncommitted.

## Implementation and independent numerical evidence

The final Julia repair computes beta standard error before scaling twice. The frozen regression cases require usable, noncollapsed 90% and 95% beta intervals at scales `1e200` and `1e-160`, and separately require finite points plus the unaffected alpha interval when beta interval width genuinely overflows at `1e-310` (`src/GroundTruth.jl:119-139`, `test/logistic_contract.jl:51-75`). The retained repair-3 Julia gates record G3-G5 passing.

The independent comparator still extracts only the unchanged scalar oracle functions from the hashed audit source and executes them after checking the selected audit/reference bytes (`scripts/compare_logistic.py:10-19`). Its numeric assertions are unchanged. In retained mode it reads the durable candidate CSVs and checks each CSV SHA256 against `transport-provenance.json` before parsing (`scripts/compare_logistic.py:33-41`). The receipts bind Julia fit CSV SHA256 `edcb0d21354e13938d040c03f8ec9a51398ec70da302fa0d61c3ea1c3c4f7040` to Julia source SHA256 `197852caa75f56d0c3b56fbdd48775bb143c246f4dd89f185a64a51933d2089c`, and R fit CSV SHA256 `6f2e596fe3bbd88f891df2447cb00ed3d7d7d102a44e530d7d4309a250fd8b21` to R source SHA256 `b130c50fbf54e81a764c28684d5f085c7e0e1ecc8ab428198c443488d83717cb`. Both source manifests record those same source identities and approved public bases. The bundle manifests include the source manifests, candidate patches, comparator, retained CSVs, and provenance receipts.

The retained positive comparison record reports `LOGISTIC_TWINS_SCIENCE_OK`. The disposable-copy control records positive exit 0, altered-candidate-CSV exit 1 with diagnosis `retained output bytes changed: julia`, and the original evidence untouched. This closes the prior gap: candidate CSV bytes are now checked before use. Source-to-fit attribution is recorded in transport provenance and sealed with the source and bundle manifests; the comparison command itself checks the candidate CSV digest, not a live refit.

## R package and documentation identity

The R verifier checks the private installed candidate's version and implementation hash, puts that private library first in `R_LIBS` and `.libPaths()`, and verifies the source namespace before rendering (`scripts/verify-docs.sh:95-150`). The quickstart article conditionally checks the namespace path, source hash, and package version when the wrapper supplies its identity variables, then writes a receipt. The wrapper removes any stale receipt before rendering and verifies the newly written receipt against the private installed path, current source hash, and package version. The retained `article-source-identity.dput` records `checks_passed = TRUE` for that exact private candidate. All checks are conditional on wrapper-provided variables; a separate normal article render without the harness is retained as `NORMAL_ARTICLE_RENDER_OK`, preserving ordinary user rendering.

R package check ends with `Status: OK`, and `r-docs-final.log` records `LOGISTIC_DOCS_PACKAGE_OK`. Julia `julia-docs-final.log` records its corresponding G6 pass. These are local package and docs checks only.

## Separate assessment gates

- Exact-draft style assessment: NOTASSESSED.
- Science gate: PASS for static review against the approved contract and retained independent comparator evidence; no numerical command was rerun here.
- Facts gate: PASS for the reported source identities, transport hashes/control outcome, article identity receipt, and G6 statuses checked against current files and retained logs.
- Reference gate: PASS for the retained scalar audit and reference files consumed by the comparator; their current SHA256 values match the recorded provenance. The earlier reference engines were reused, not refit.

## Scope boundary

This review covers the approved fixed-effect one-predictor Bernoulli-logit implementation and the bounded numerical evidence. It does not establish calibration, mixed-model behavior, arbitrary parity, CRAN status, remote CI, publication, or release readiness. Root G7 and G9 remain outside this review and must be completed separately.

## Review method

Independent read-only review. No source edits, tests, fits, builds, or nested delegation.
