"""Where things are: the ffmpeg/ffprobe binaries and the recorded material.

ffmpeg and ffprobe come from Homebrew (``brew install ffmpeg``). The order
looked in: ``PROMO_FFMPEG`` / ``PROMO_FFPROBE`` (build.sh sets them), the
PATH, ``/opt/homebrew/bin``, ``/usr/local/bin``. When no ffmpeg is found the
one bundled with imageio-ffmpeg (a pinned requirement) is used for encoding
and decoding; it has no ffprobe, so probing still needs Homebrew.

The takes, their gesture logs and the App Store tool's scans live under
``build/app-store/pro/preview/v2`` of the MAIN checkout — ``build/`` is
ignored by git, so a worktree does not have them. ``PROMO_MATERIAL`` points
elsewhere; otherwise the repository's own ``build/`` is tried, then the main
checkout's (found through the worktree's ``.git`` file, without running git).
The material is only ever read.
"""

from __future__ import annotations

import functools
import os
import shutil
from pathlib import Path

PROMO_REEL = Path(__file__).resolve().parents[2]
REPO = PROMO_REEL.parents[1]
MATERIAL_SUBDIR = Path("build/app-store/pro/preview/v2")
FONTS = REPO / "tool/app_store_screenshots/fonts"
APP_STORE_PREVIEW = REPO / "tool/app_store_preview"

INSTALL_HINT = ("install it with Homebrew: `brew install ffmpeg` (https://brew.sh) — it brings ffmpeg and "
                "ffprobe; or point PROMO_FFMPEG / PROMO_FFPROBE at the binaries")


class ToolMissing(RuntimeError):
    """ffmpeg, ffprobe or the recorded material is not where it is looked for."""


def _find(name: str, env: str) -> str | None:
    explicit = os.environ.get(env)
    if explicit:
        if Path(explicit).is_file() and os.access(explicit, os.X_OK):
            return explicit
        raise ToolMissing(f"{env}={explicit} is not an executable file")
    found = shutil.which(name)
    if found:
        return found
    for folder in ("/opt/homebrew/bin", "/usr/local/bin"):
        candidate = Path(folder) / name
        if candidate.is_file() and os.access(candidate, os.X_OK):
            return str(candidate)
    return None


@functools.lru_cache(maxsize=None)
def ffmpeg() -> str:
    """The ffmpeg binary (Homebrew's, else imageio-ffmpeg's bundled one)."""
    found = _find("ffmpeg", "PROMO_FFMPEG")
    if found:
        return found
    try:
        import imageio_ffmpeg  # a pinned requirement: the encoding fallback
        return imageio_ffmpeg.get_ffmpeg_exe()
    except Exception:  # noqa: BLE001 — any failure means: not available
        raise ToolMissing(f"ffmpeg not found: {INSTALL_HINT}") from None


@functools.lru_cache(maxsize=None)
def ffprobe() -> str:
    """The ffprobe binary (Homebrew's; there is no bundled fallback)."""
    found = _find("ffprobe", "PROMO_FFPROBE")
    if found:
        return found
    raise ToolMissing(f"ffprobe not found: {INSTALL_HINT}")


def main_checkout(repo: Path = REPO) -> Path:
    """The main checkout of the repository ``repo`` is a worktree of (or
    ``repo`` itself). Read from the worktree's ``.git`` file: ``gitdir:`` and
    the ``commondir`` file next to it."""
    dot_git = repo / ".git"
    if not dot_git.is_file():
        return repo
    text = dot_git.read_text(encoding="utf-8").strip()
    if not text.startswith("gitdir:"):
        return repo
    gitdir = Path(text.partition(":")[2].strip())
    if not gitdir.is_absolute():
        gitdir = (repo / gitdir).resolve()
    common = gitdir / "commondir"
    if common.is_file():
        common_dir = Path(common.read_text(encoding="utf-8").strip())
        common_dir = common_dir if common_dir.is_absolute() else (gitdir / common_dir).resolve()
    else:
        common_dir = gitdir.parent.parent
    return common_dir.parent


@functools.lru_cache(maxsize=None)
def material_root() -> Path:
    """``…/build/app-store/pro/preview/v2``: the takes (``takes/<name>/``) and
    the App Store film's scans (``final/takes/take-N/``)."""
    explicit = os.environ.get("PROMO_MATERIAL")
    if explicit:
        root = Path(explicit)
        if not (root / "takes").is_dir():
            raise ToolMissing(f"PROMO_MATERIAL={explicit} has no takes/ folder")
        return root
    tried = []
    for base in (REPO, main_checkout(REPO)):
        root = base / MATERIAL_SUBDIR
        tried.append(str(root))
        if (root / "takes").is_dir():
            return root
    raise ToolMissing("the recorded material is not here (looked in: " + ", ".join(dict.fromkeys(tried))
                      + "). It is gitignored and lives in the main checkout; set PROMO_MATERIAL to its "
                        "build/app-store/pro/preview/v2 folder.")


def material_available() -> bool:
    try:
        material_root()
        return True
    except ToolMissing:
        return False
