#!/usr/bin/env python3
"""Preflight and launch the bounded, source-frozen Julia native capture."""
import hashlib
import json
import os
import shlex
import signal
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FIXTURES = ROOT / "test" / "fixtures" / "inference"
AUDIT = ROOT / "audit" / "inference"
EVIDENCE = ROOT / ".unlazy" / "inference" / "evidence"
CSV = EVIDENCE / "julia-capture.csv"
SIDECAR = EVIDENCE / "julia-capture.json"
LOG = EVIDENCE / "julia-capture.log"
JULIA_DEFAULT = "/Users/z3437171/.julia/juliaup/julia-1.12.6+0.aarch64.apple.darwin14/Julia-1.12.app/Contents/Resources/julia/bin/julia"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def production_files():
    files = [p for base in (ROOT / "src", ROOT / "adapters" / "lmm")
             for p in base.glob("*.jl")]
    return sorted(files, key=lambda p: p.relative_to(ROOT).as_posix())


def source_identity():
    files = production_files()
    entries = [(p.relative_to(ROOT).as_posix(), sha(p)) for p in files]
    payload = "\n".join(path + "\0" + digest for path, digest in entries).encode()
    return hashlib.sha256(payload).hexdigest(), entries


def check_fixtures():
    local_manifest = FIXTURES / "manifest.json"
    audit_manifest = AUDIT / "fixtures" / "manifest.json"
    if sha(local_manifest) != sha(audit_manifest):
        raise RuntimeError("package fixture manifest differs from the frozen audit manifest")
    manifest = json.loads(local_manifest.read_text())
    verified = 0
    for entry in manifest["fixtures"]:
        path = FIXTURES / entry["file"]
        if sha(path) != entry["sha256"]:
            raise RuntimeError(f"fixture hash mismatch: {path.name}")
        verified += 1
    if verified != 11:
        raise RuntimeError(f"expected 11 frozen fixture identities, found {verified}")
    return sha(local_manifest)


def process_group_exists(pid):
    try:
        os.killpg(pid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True


def main():
    for path in (CSV, SIDECAR, LOG):
        if path.exists():
            raise RuntimeError(f"refusing to overwrite existing capture artifact: {path}")
    EVIDENCE.mkdir(parents=True, exist_ok=True)
    fixture_sha = check_fixtures()
    source_sha, source_entries = source_identity()
    julia = os.environ.get("JULIA_BIN", JULIA_DEFAULT)
    if not Path(julia).is_file() or not os.access(julia, os.X_OK):
        raise RuntimeError(f"Julia executable not found or not executable: {julia}")
    flags = shlex.split(os.environ.get("INFERENCE_JULIA_FLAGS", "--compiled-modules=no --compile=min -O0"))
    env = os.environ.copy()
    env.setdefault("JULIA_LOAD_PATH", f"{ROOT}:{ROOT / 'adapters' / 'lmm'}:@stdlib")
    env.update({"JULIA_PROJECT": str(ROOT), "JULIA_PKG_OFFLINE": "true",
                "JULIA_PKG_PRECOMPILE_AUTO": "0", "JULIA_SCRATCH_TRACK_ACCESS": "0",
                "JULIA_NUM_THREADS": "1", "OPENBLAS_NUM_THREADS": "1",
                "OMP_NUM_THREADS": "1", "MKL_NUM_THREADS": "1",
                "VECLIB_MAXIMUM_THREADS": "1", "BLIS_NUM_THREADS": "1"})
    command = [julia, "--startup-file=no", *flags, "--threads=1", f"--project={ROOT}",
               str(ROOT / "scripts" / "inference-julia-capture.jl")]
    start = time.monotonic()
    with LOG.open("x") as out:
        out.write("command=" + json.dumps(command) + "\n")
        out.write("source_sha256=" + source_sha + "\nfixture_manifest_sha256=" + fixture_sha + "\n")
        out.flush()
        proc = subprocess.Popen(command, cwd=ROOT, env=env, stdout=out, stderr=subprocess.STDOUT,
                                start_new_session=True)
        try:
            returncode = proc.wait(timeout=320)
            timed_out = False
        except subprocess.TimeoutExpired:
            os.killpg(proc.pid, signal.SIGKILL)
            returncode = proc.wait()
            timed_out = True
        elapsed = time.monotonic() - start
        out.write(f"\nwrapper_pid={proc.pid} returncode={returncode} timed_out={timed_out} elapsed_seconds={elapsed:.6f}\n")
    for _ in range(50):
        if not process_group_exists(proc.pid):
            break
        time.sleep(.1)
    if process_group_exists(proc.pid):
        raise RuntimeError(f"owned Julia process group {proc.pid} remains after termination")
    after_sha, after_entries = source_identity()
    if after_sha != source_sha or after_entries != source_entries:
        raise RuntimeError("production source changed during capture; retained output is not source-bound")
    if SIDECAR.is_file():
        sidecar = json.loads(SIDECAR.read_text())
        if sidecar.get("source_sha256") != source_sha or sidecar.get("fixture_manifest_sha256") != fixture_sha:
            raise RuntimeError("capture sidecar does not match preflight source/fixture identity")
        if sidecar.get("complete") is not True and not timed_out:
            print(f"INFERENCE_CAPTURE_INCOMPLETE rows={sidecar.get('output_rows')} profiles={sidecar.get('profile_calls')} log={LOG}")
            return 3
    print(f"pid={proc.pid} returncode={returncode} timed_out={timed_out} elapsed_seconds={elapsed:.3f} log={LOG}")
    if timed_out:
        return 124
    return returncode


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:
        print(f"INFERENCE_CAPTURE_LAUNCH_ERROR: {exc}", file=sys.stderr)
        sys.exit(2)
