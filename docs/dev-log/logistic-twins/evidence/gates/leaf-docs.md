# Gates: documentation and package preview
OWNS: _pkgdown.yml reference index only, README.md, STATUS.md, docs/src/**, man/**, NAMESPACE, DESCRIPTION, vignettes/**, .Rbuildignore, scripts/verify-docs.sh
Scope: honest reader-facing documentation and local build/check previews.
- [x] G6: package and documentation check
  CHECK: bash scripts/verify-docs.sh
  EXPECT: LOGISTIC_DOCS_PACKAGE_OK
  EVIDENCE: exit=0; shell=/bin/sh; cwd=/Users/z3437171/Documents/Codex/2026-10-06/logistic-twins/GroundTruth.jl; path=8d2e6e29f6f6/39 entries; output=LOGISTIC_DOCS_PACKAGE_OK
