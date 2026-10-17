#!/usr/bin/env python3
"""Source-bind retained local package and documentation verification receipts."""
import hashlib
import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
EVIDENCE = ROOT / ".unlazy" / "inference" / "evidence"


def files_for(kind):
    if kind == "package":
        roots = [ROOT / "src", ROOT / "test", ROOT / "test" / "fixtures", ROOT / "adapters" / "lmm",
                 ROOT / "scripts", ROOT / "audit" / "inference"]
        extras = [ROOT / "Project.toml", ROOT / "adapters" / "lmm" / "Project.toml"]
    elif kind == "docs":
        roots = [ROOT / "src", ROOT / "docs" / "src"]
        extras = [ROOT / "Project.toml", ROOT / "docs" / "Project.toml", ROOT / "docs" / "make.jl"]
    else:
        raise ValueError(kind)
    found = set(extras)
    for directory in roots:
        if directory.is_dir():
            if kind == "package":
                suffixes = {".csv", ".json"} if directory.name == "fixtures" else (
                    {".jl", ".py", ".sh"} if directory.name in ("scripts", "inference") else {".jl"})
            else:
                suffixes = {".jl", ".md", ".css", ".png"}
            found.update(p for p in directory.rglob("*") if p.is_file() and p.suffix in suffixes)
    return sorted((p for p in found if p.is_file()), key=lambda p: p.relative_to(ROOT).as_posix())


def fingerprint(kind):
    entries = [(p.relative_to(ROOT).as_posix(), hashlib.sha256(p.read_bytes()).hexdigest()) for p in files_for(kind)]
    blob = "\n".join(path + "\0" + digest for path, digest in entries).encode()
    return hashlib.sha256(blob).hexdigest(), entries


def build_digest():
    build = ROOT / "docs" / "build"
    if not (build / "index.html").is_file():
        raise RuntimeError("docs/build/index.html is missing")
    entries = [(p.relative_to(build).as_posix(), hashlib.sha256(p.read_bytes()).hexdigest())
               for p in sorted((p for p in build.rglob("*") if p.is_file()), key=lambda p: p.relative_to(build).as_posix())]
    return hashlib.sha256("\n".join(path + "\0" + digest for path, digest in entries).encode()).hexdigest(), entries


def receipt_path(kind):
    return EVIDENCE / f"{kind}-verification.json"


def write(kind):
    source_hash, source_files = fingerprint(kind)
    data = {"schema": f"groundtruth-inference-{kind}-verification-v1",
            "source_sha256": source_hash,
            "source_files": [path for path, _ in source_files],
            "source_file_sha256": {path: digest for path, digest in source_files},
            "verified_at_utc": datetime.now(timezone.utc).isoformat()}
    if kind == "docs":
        output_hash, output_files = build_digest()
        data["docs_build_sha256"] = output_hash
        data["docs_build_files"] = len(output_files)
    EVIDENCE.mkdir(parents=True, exist_ok=True)
    path = receipt_path(kind)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n")
    os.replace(tmp, path)
    print(f"INFERENCE_{kind.upper()}_RECEIPT_WRITTEN {source_hash}")


def check(kind):
    path = receipt_path(kind)
    if not path.is_file():
        raise RuntimeError(f"missing source-bound receipt: {path}")
    data = json.loads(path.read_text())
    source_hash, source_files = fingerprint(kind)
    current = {p: h for p, h in source_files}
    if data.get("schema") != f"groundtruth-inference-{kind}-verification-v1":
        raise RuntimeError(f"unexpected {kind} receipt schema")
    if data.get("source_sha256") != source_hash or data.get("source_file_sha256") != current:
        raise RuntimeError(f"{kind} receipt is stale for current source/tests")
    if kind == "docs":
        output_hash, _ = build_digest()
        if data.get("docs_build_sha256") != output_hash:
            raise RuntimeError("documentation build output differs from its retained receipt")
    print(f"INFERENCE_{kind.upper()}_RECEIPT_OK {source_hash}")


if __name__ == "__main__":
    if len(sys.argv) != 3 or sys.argv[1] not in ("write", "check") or sys.argv[2] not in ("package", "docs"):
        raise SystemExit("usage: inference-receipts.py write|check package|docs")
    try:
        (write if sys.argv[1] == "write" else check)(sys.argv[2])
    except Exception as exc:
        print(f"INFERENCE_RECEIPT_ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)
