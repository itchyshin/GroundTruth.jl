# Logistic twins review bundle

The approved local implementation is ready for review at `/Users/z3437171/Documents/Codex/2026-10-06/logistic-twins/GroundTruth.jl`. The candidate remains uncommitted; the reviewed public base is `9f0dd012f522b083a45ec03af7fad9bdbc9eb8e3`.

1. Read `AFTER-TASK.md`, `CONTRACT.md` and the fresh verdicts in `evidence/`.
2. Inspect `candidate.patch` and `SOURCE-MANIFEST.json`. `BUNDLE-MANIFEST.json` binds retained evidence and reports.
3. Open the local Julia `docs/build/index.html` and R `docs/site/index.html` previews. Automated local-file browser inspection was blocked; the builds, links and example checks are recorded.

Reproduce the independent comparison from either sibling repository with `python3 scripts/compare_logistic.py --retained-evidence`. This uses the preserved CSVs, scalar oracle and reference hashes in `evidence/`, without ignored source inputs. Live language gates use `scripts/verify-logistic.sh` in Julia and `scripts/verify.R` in R; local environment/preservation checks intentionally bind this Mac and its protected roots. Raw receipts and approvals are under `.unlazy/logistic-twins/`.

Proposed landing, requiring separate approval: commit the two sealed diffs on their existing `codex/logistic-twins` branches, with messages `Fix logistic MLE scaling and failure contracts` (Julia) and `Add native logistic study workflow` (R). Push review branches only after approval. Julia's existing main-push workflow deploys documentation, so a main update needs publication approval too. R documentation requires a separate manual workflow dispatch. Reconcile the preserved R branding before deployment; do not overwrite it with a whole-file baseline copy. No merge or deployment is authorized by the implementation approval.

The result supports tested fixed-effect numerical agreement and accounting. Calibration, mixed models and package-wide parity require separate work.
