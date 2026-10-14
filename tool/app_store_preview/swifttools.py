"""Build and run the Swift helpers (tool/app_store_preview/swift).

They are compiled with `xcrun swiftc` into build/bin — a build product, git
ignores it — and rebuilt whenever one of their sources changes: the binary's
name carries a hash of the sources it was made from, so a stale helper cannot
be run by mistake.
"""

from __future__ import annotations

import hashlib
import subprocess
from pathlib import Path

from brand import die

HERE = Path(__file__).resolve().parent
SWIFT = HERE / "swift"
BIN = HERE / "build" / "bin"

SOURCES = {
    "conform": ["Common.swift", "Conform.swift"],
    "encode": ["Common.swift", "Writer.swift", "Encode.swift"],
    "inspect": ["Common.swift", "Inspect.swift"],
    "testclip": ["Common.swift", "Writer.swift", "TestClip.swift"],
}


def binary(name: str) -> Path:
    sources = [SWIFT / s for s in SOURCES[name]]
    digest = hashlib.sha256(b"".join(s.read_bytes() for s in sources)).hexdigest()[:12]
    out = BIN / f"{name}-{digest}"
    if not out.exists():
        BIN.mkdir(parents=True, exist_ok=True)
        for old in BIN.glob(f"{name}-*"):
            old.unlink()
        r = subprocess.run(
            ["xcrun", "swiftc", "-O", "-parse-as-library", *map(str, sources), "-o", str(out)],
            capture_output=True, text=True)
        if r.returncode != 0 or not out.exists():
            die(f"cannot compile the `{name}` helper:\n{r.stderr.strip()}")
    return out


def run(name: str, *args, check: bool = True) -> subprocess.CompletedProcess:
    """Run a helper. With check=True a failure stops the tool with the
    helper's own message; with check=False the caller reads the result."""
    r = subprocess.run([str(binary(name)), *map(str, args)], capture_output=True, text=True)
    if check and r.returncode != 0:
        die(f"{name} failed: {r.stderr.strip() or r.stdout.strip()}")
    return r
