# Gates: language implementation
OWNS: src/**, test/runtests.jl, test/logistic*.jl, scripts/verify-logistic.sh, scripts/export_logistic.jl
Scope: scientific implementation with regression, compatibility, accounting and checker controls.
- [x] G3: language logistic regression and numerical outputs
  CHECK: python3 scripts/timed_gate.py sh scripts/verify-logistic.sh logistic
  EXPECT: LOGISTIC_LANGUAGE_OK
  EVIDENCE: exit=0; shell=/bin/sh; cwd=/Users/z3437171/Documents/Codex/2026-10-06/logistic-twins/GroundTruth.jl; path=8d2e6e29f6f6/39 entries; output=LOGISTIC_LANGUAGE_OK | NUMERICAL_SECONDS 5.976 CHARGED_TOTAL 211.824
- [x] G4: core and compatibility regressions
  CHECK: python3 scripts/timed_gate.py sh scripts/verify-logistic.sh core
  EXPECT: LOGISTIC_CORE_OK
  EVIDENCE: exit=0; shell=/bin/sh; cwd=/Users/z3437171/Documents/Codex/2026-10-06/logistic-twins/GroundTruth.jl; path=8d2e6e29f6f6/39 entries; output=LOGISTIC_CORE_OK | NUMERICAL_SECONDS 10.306 CHARGED_TOTAL 222.13
- [x] G5: failure/accounting and wrong-answer controls
  CHECK: python3 scripts/timed_gate.py sh scripts/verify-logistic.sh controls
  EXPECT: LOGISTIC_CONTROLS_OK
  EVIDENCE: exit=0; shell=/bin/sh; cwd=/Users/z3437171/Documents/Codex/2026-10-06/logistic-twins/GroundTruth.jl; path=8d2e6e29f6f6/39 entries; output=LOGISTIC_CONTROLS_OK | NUMERICAL_SECONDS 6.02 CHARGED_TOTAL 228.15
