# Logistic twins mechanical review (read-only)

Date: 2026-10-06. Exact roots inspected: `/Users/z3437171/Documents/Codex/2026-10-06/logistic-twins/GroundTruth.jl` and sibling `groundtruth`.

## Root identity and current state

Julia: branch `codex/logistic-twins`, HEAD `9f0dd012f522b083a45ec03af7fad9bdbc9eb8e3`; modified tracked `.gitignore`, README.md, STATUS.md, docs/src/capabilities.md, index.md, quickstart.md, roadmap.md, validation.md, src/GroundTruth.jl, test/runtests.jl; untracked docs/dev-log/, graft/, scripts/, test/fixtures/, and four focused logistic test files.

R: branch `codex/logistic-twins`, HEAD `f44a0bfe29d34f081f7eaca3d07b0fbf93a3bf2f`; modified tracked .Rbuildignore, .gitignore, DESCRIPTION, NAMESPACE, R/groundtruth.R, README.md, inst/source-identity.R, generated man files, and vignette; untracked docs/, scripts/, gt_glm_adapter Rd, logistic fixtures, and logistic test file. These are current slice state; do not overwrite.

## Protected baseline

Inspected both `scripts/verify_common.py` copies and independently recomputed every comparison read-only rather than running them (the scripts write evidence files). Both baseline JSONs agree: all 53 protected Julia canonical files, 232 protected R canonical files, and 215 protected GroundTruth-lmm files match expected hashes; protected repo HEAD, status, unstaged diff hash, and staged diff hash all match the snapshot. No protected mismatch found.

## Fixtures and transport

Both language fixture freeze manifests contain 12 fixtures, 10 originals. All 12 per-language SHA256 checks match; no fixture mismatch. The Julia and R fit transport files exist, each with 24 rows, 12 fixture names, 12 alpha and 12 beta rows, and the common 17-column contract header. Both contain 14 `ok` rows and 10 expected failure-status rows (`nonconverged` in Julia, `fit_error` in R). Sample retained alpha estimates and information agree to displayed precision. This is a shape/identity inspection, not independent numerical validation.

## Dispatch and recorded deviations

Four JSON dispatch receipts (recon, Julia, R, docs) record `native/explicit`, `enforced_cli:false`, and the CLI unsupported-model/account rejection as fallback. Requested tiers are recorded (recon Luna low, Julia Sol high, R Luna medium, docs Luna medium). `routing-deviation.md` explicitly says the CLI invocation started no worker and no enforced CLI proof is claimed. I found no contradiction in the receipts inspected; actual account-side rejection is documented there, not independently re-exercised.

## Pending / limits

Parent is rerunning gates separately. This review ran no tests, numerical fits, build, or mutating verification script. I did not verify the source claims represented by logs or the whole scientific contract. This review only establishes root identities, preserved-state hashes/status, fixture hashes/counts, transport shape, and the contents of dispatch records.
