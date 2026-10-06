# Logistic twins plan versus actual reconciliation

Parent closure update, 6 October 2026: manual G7 and G9 are closed, and both final root `--reverify` runs report ALL MET. Current receipts are `evidence/julia-root-close.log` and `evidence/r-root-close.log` in their respective bundles. Language and documentation leaves also pass. All 500 protected original paths and Git states remain unchanged. The routing and visual-inspection limitations remain explicit. The reconciliation snapshot below was written just before this final manual closure.

As of 2026-10-06, after final leaf and automated root reruns. This is a read-only reconciliation snapshot, except for this report under `/private/tmp`. Both leaf G3-G6 and root G1/G2/G3/G8 pass; no technical checks remain running. The parent will manually close root G7/G9 after this reconciliation and the completed after-task reports. I ran no fits, builds, tests, or package checks.

## Approved scope and finish line

The approved contract is `docs/dev-log/logistic-twins/CONTRACT.md` in both exact worktrees. It authorizes a bounded fixed-effect one-predictor Bernoulli-logit repair in Julia and a native R implementation, locally and uncommitted. The scientific target is named alpha and beta log-odds coefficients, with normal 90% and 95% intervals for logistic fits. Gaussian Student t behavior, existing Gaussian random-number draw order, frozen fixtures, schemas, and caller compatibility remain protected. The scope excludes calibration claims, fitted GLMMs, LMM integration, package-wide parity, dependency installation, remote changes, commits, pushes, merges, and publication.

The planned gates are language G3 numerical implementation, G4 compatibility, G5 accounting and wrong-answer controls, G6 package and documentation checks, then root G7 independent review, G8 preservation, and G9 after-task/reconciliation. Leaf G3-G6 evidence passes in both worktrees. Root G1, G2, G3, and G8 are recorded as passing. Root G7 and G9 remain manual parent closures following this reconciliation; the parent has completed core reruns and will update the root ledgers using the final reviews and completed after-task reports.

## Exact worktrees and preservation

The worktrees are on `codex/logistic-twins` at the approved bases: Julia `9f0dd012f522b083a45ec03af7fad9bdbc9eb8e3` and R `f44a0bfe29d34f081f7eaca3d07b0fbf93a3bf2f`. The setup records explain why direct worktree creation was used: the canonical lane launcher would auto-commit, which conflicts with the approved local, uncommitted boundary.

Final preservation checks confirm all 500 protected original paths are unchanged across three roots: 53 in canonical `GroundTruth.jl`, 232 in canonical `groundtruth`, and 215 in protected `GroundTruth-lmm`. HEAD, status, and diffs are unchanged for those protected roots. This preserves the LMM handover and R branding. Both task worktrees have uncommitted implementation, documentation, evidence, and fixture additions as expected. No commit, push, remote edit, dependency installation, or publication is recorded.

Setup and preservation sources: each worktree's `.unlazy/logistic-twins/source/setup.json`, `.unlazy/logistic-twins/source/preservation-baseline.json`, and `.unlazy/logistic-twins/evidence/preservation.json`.

## Planned routing versus actual routing

The plan requested a tiered CLI dispatch, including Luna for R and docs, Luna for recon, and Sol high for Julia and the contract challenge. The CLI catalogue exposed Luna, but the account rejected `gpt-6-luna` as unsupported. The attempted worker did not run. Subsequent role receipts record native explicit model and effort settings, with `enforced_cli: false`. They prove the requested settings and dispatch method, not strict CLI enforcement or a runtime model ceiling. No nested delegation or model escalation is recorded.

The two exact worktrees were prepared directly because the canonical launcher auto-commits. The Julia Graft caller-query cache is now external at `/private/tmp/graft-logistic-twins-julia-9f0dd01`; the R caller-query cache is also under `/private/tmp`. This kept generated graph data out of the repositories. These are recorded workflow adaptations, not changes to scientific scope.

Routing evidence is in each worktree's `.unlazy/logistic-twins/dispatch/routing-deviation.md`, role dispatch JSON files, and `source/setup.json`. Recon receipts note that an initial wrong-root statement was corrected against the exact source.

## Work completed and evidence

**Julia.** The original rescaling failure was reproduced before the implementation repair. The bounded solver uses predictor standardization, stable logistic tails, guarded Newton updates, and recomputed score, predictor-step, and objective convergence criteria. A later science review found a real interval underflow at predictor scale `1e200`; repair 3 computes slope SE before scaling. Regressions retain noncollapsed beta intervals at `1e200` and `1e-160`, while a `1e-310` case keeps finite points and alpha intervals when beta intervals are genuinely unrepresentable. The saved final Julia leaf log records G3, G4, and G5 passing; the paired checker log records `LOGISTIC_TWINS_SCIENCE_OK`.

**R.** The native `stats::glm` path uses standardized predictors, exact support-based separation checks, stable sign-specific residuals and loss, an independent standardized score and predictor-correction check, and final-information Wald intervals. Legacy family-less objects normalize to Gaussian; mixed-family mismatches fail before the mismatched fitter runs. The first G3 run exposed fixture path, extra-column, analytic coefficient, and denominator mistakes. Repairs use the logistic fixture directory and x/y columns, the exact two-point analytic logits, and four pair attempts. Later fixes address extreme-logit residual underflow, target-specific interval retention, and tiny-predictor covariance transformation. The saved final R leaf log records G3, G4, and G5 passing.

**Paired evidence.** The shared checker uses an independent scalar oracle sourced from the retained audit. It validates seven accepted data fits per engine, 14 engine-by-fixture fits total, 14 accepted coefficient-target rows per engine, and five rejected design cases per engine. The saved science report records worst paired absolute differences of about `6.87e-11` for coefficients, `7.12e-12` for SEs, `8.28e-11` for endpoints, and `9.99e-16` for mean NLL. Wrong-answer controls reject sign flips, swapped/missing/duplicate targets, initial-information intervals, and altered fixture bytes; row permutation passes. The comparison is bounded to those fixtures and unit-weight one-predictor logistic fits. It does not establish calibration or mixed-model behavior. The science report also retains differences against older native GLM reference intervals; those are not erased by the paired-agreement result.

**Frozen limits.** The ten original CSV bytes and manifests remain frozen. Shifted and tied fixtures were added as separate cases. Contract tolerances were not widened. The audit contract JSON remains as evidence of the earlier audit-only scope; the approved implementation contract governs the current work.

## Timing record

The shared parent `numerical-budget.json` is the single cumulative record for the 900-second allowance. Its final charge is 233.778 seconds of 900, including a conservative 60-second startup charge; it is not the sum of Julia and R snapshots, which mirror the same cumulative budget. The `timed_gate.py` utility takes an exclusive lock on the shared `numerical.lock` around each core numerical command, so serialization of those gated core commands is enforced. The documented first R documentation check may have overlapped Julia core work because it ran outside that wrapper; this is the known exception and prevents a claim that every fit-bearing command was globally serialized. The plan estimated four to six engineering hours. No reliable aggregate wall time across asynchronous lanes is recorded. Failed attempts and successful reruns are reflected in the shared budget.

## Reviews and current limits

The saved reviews include `/private/tmp/logistic-twins-science-review.md`, `/private/tmp/logistic-twins-implementation-review-final.md`, and `/private/tmp/logistic-twins-rose-review-final.md`. Final science and implementation reviews accept the bounded implementation. Final Rose review accepts the bounded bundle after the fit counts and snapshot pointers were corrected in both after-task reports. This reconciliation uses the final receipt paths and corrected counts. The parent still must mark manual root G7/G9 closure after this report; a review outcome does not itself close those root gates.

No claim is made that the prescribed CLI routing was enforced, that every fit launched under a single global lock, or that the package is release-ready. No release, submission, publication, CI, or remote-state claim follows from these local checks.

## Final package and documentation evidence; remaining closure

- Julia G6 passes in `GroundTruth.jl/.unlazy/logistic-twins/evidence/julia-docs-final.log`, with `LOGISTIC_DOCS_PACKAGE_OK`.
- R G6 passes in `groundtruth/.unlazy/logistic-twins/evidence/r-docs-final.log`, with `R CMD check: Status: OK` and `LOGISTIC_DOCS_PACKAGE_OK`. The R package check recorded 346 passing tests. The ordinary article render passes in `groundtruth/.unlazy/logistic-twins/evidence/normal-article-check.log` with `NORMAL_ARTICLE_RENDER_OK`, without the harness. `docs-package/article-source-identity.dput` matches the candidate source identity.
- Final source identity manifests match the exact code snapshots. Core reruns pass in `GroundTruth.jl/.unlazy/logistic-twins/evidence/julia-core-close.log` and `groundtruth/.unlazy/logistic-twins/evidence/r-core-close.log`; all three leaf gates pass in each. Automated root reruns pass G1/G2/G3/G8 in `julia-root-close-pre.log` and `r-root-close-pre.log`; their exit status remains nonzero only because manual G7/G9 are intentionally unchecked until this reconciliation and parent closure.
- Browser-based visual proof was attempted but the local file URL was blocked by policy. Rendered files and structural checks passed, but there is no browser automation visual inspection receipt. This remains a material evidence limitation.

These final G6 and core receipt paths supersede earlier interim pointers. The pre-close root receipts show G1/G2/G3/G8 passing in both worktrees and G7/G9 pending manual parent closure.

## Refresh notes

This refresh corrects the earlier timing interpretation: the per-worktree numerical timing files are snapshots of one shared cumulative file, not additive budgets. The latest shared record is `logistic-twins/numerical-budget.json` at 233.778 charged seconds of 900. The lock wrapper confirms that core numerical commands run under the shared exclusive lock; the known first R documentation overlap remains documented above.

The fresh implementation-review dispatch receipts specify native/explicit Luna medium for both language worktrees, and fresh science-review dispatch receipts specify native/explicit Sol high for both. These receipts record requested roles and settings; their `enforced_cli: false` field means they do not prove strict CLI enforcement. Fresh final reviews accept the bounded bundle; the parent performs manual G7/G9 ledger closure after this report.


## Current finish line

The approved technical and documentation leaf work is evidenced through G6, final independent reviews accept within the frozen scope, core G3-G5 reruns pass, and protected-root checks G1/G2/G3/G8 pass. No technical checks remain running. Both after-task reports now contain the corrected fit counts and current reviewer receipts; the parent will manually record G7/G9 closure after this reconciliation. No commits, pushes, merges, installs, publications, or LMM/GLMM expansions occurred.

## Separate prose assessment

**Style:** 3/10, medium confidence. The report is specific and audit-oriented; repeated gate and receipt language is partly required by its purpose.

**Genre/coverage:** Independent technical reconciliation, whole report body before this assessment section; 1,460 words. SHA256 of that assessed body: `b91757fa777eddda3e629434e3a85e201a8daf816f5d8f0e272ea85adbebc121`.

**Evidence/repair:** The paired `Julia` and `R` paragraphs and the `G6` bullets are parallel, scannable evidence labels. The repeated phrases “passes” and “root G7/G9” make the current gate state easy to locate, though slightly formulaic; no change needed because these labels prevent ambiguity in a handoff record. The separate slop check found 5 pattern hits per 1,460 words and `FINDINGS: 0`.

**Gates:** Science = PASS for the bounded one-predictor fixture comparisons, with calibration and mixed-model claims explicitly excluded. Facts = PASS against the final core/G6/root receipts, shared budget, review receipts, preservation record, and parent-provided corrections; manual G7/G9 closure remains pending. References = NOT APPLICABLE; the report cites local evidence paths and no external references.

**Provenance:** Self-assessment with the local `slop_check.py` mechanical lint, 6 October 2026. Final receipt set reviewed; the earlier interim snapshot and review feedback were already known, so this is not a held-out style assessment.

## Parent routing and closure note

Rose's read-only final confirmation is retained in `evidence/rose-close-confirmation.md`. Her exact spawn-input record was unavailable. `evidence/dispatch/rose-routing-limitation.json` preserves that gap; planned Luna/medium settings are unverified. The other available manifests retain requested settings and the CLI fallback. The parent incorporates the three review lenses and closes G7/G9 after the completed reports and reconciliation. Final gate receipts govern the resulting status.
