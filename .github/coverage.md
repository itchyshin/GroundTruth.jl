# Coverage evidence for GroundTruth.jl

This document is configuration/process only. It does not record a coverage
percentage, a Codecov processed report, or a `main` baseline.

## What runs

The existing GitHub Actions workflow `.github/workflows/CI.yml` keeps the
original `test` job (`Pkg.test()` on Julia 1.12.6). That job is the normal
package check.

A separate `coverage` job instruments the same existing Julia test suite:

1. `julia-actions/julia-buildpkg`
2. `julia-actions/julia-runtest` with `--code-coverage=user`
3. `julia-actions/julia-processcoverage` writing `lcov.info` from `src/`
4. `codecov/codecov-action@v5` with `use_oidc: true`, `files: lcov.info`,
   and `disable_search: true`

There is no OS/version matrix in this repository today, so there is one
coverage upload and no Codecov flags. Do not add a second uploader, a token
path, or a search over extra coverage files.

## Least-privilege OIDC

- Workflow permissions: `contents: read`
- Coverage job permissions: `contents: read` and `id-token: write`
- No `CODECOV_TOKEN` secret
- `GITHUB_TOKEN` is never passed to Codecov and is not a Codecov token
- Documenter continues to use `GITHUB_TOKEN` only for the documentation
  workflow, which does not upload coverage

OIDC is documented by [codecov-action](https://github.com/codecov/codecov-action)
as `use_oidc: true` plus `id-token: write`. Owner GitHub-App / org
authorization is asked for only after an actual uploader failure in this
workflow. A Codecov “Configure” page or an API “unknown” response is not
proof of that failure.

## Evidence stages (keep them separate)

| Stage | What it is | What it is not |
| --- | --- | --- |
| 1. Configuration | This file, `codecov.yml`, and the workflow YAML | A measured % |
| 2. Coverage execution | `lcov.info` produced by processcoverage; local line rate in the job summary | Codecov’s processed report |
| 3. Upload reception | codecov-action log showing the upload was accepted | A processed report or `main` baseline |
| 4. Processed report | Codecov UI / PR comment / informational status after processing | A `main` baseline |
| 5. Main baseline | Owner-authorized merge to `main` **and** a successful default-branch workflow upload | This PR’s head or merge-commit coverage |

Do not add README badges before stage 5 exists.

## Branch head vs synthetic-merge checkout

- **Branch head:** the tip commit of the feature branch (`pull_request.head.sha`).
- **PR base:** the default-branch commit the PR targets (`pull_request.base.sha`).
- **Actions checkout on `pull_request`:** the synthetic merge commit
  (`github.sha` / `refs/pull/*/merge`). Coverage numbers from that job are of
  that merge tree, not the exact branch head.
- **Actions checkout on `push` to `main`:** the exact default-branch commit.

Do not set `override_commit` to blur those identities. A PR upload is not a
`main` baseline. Default `main` coverage requires an owner-authorized merge
and a successful default-branch workflow; agents must not merge.

## Out of scope

No scientific `src/`, `test/`, fixture, results, or assertion edits. No new
skips, weakened tests, or timing-limit changes. No other repositories.
