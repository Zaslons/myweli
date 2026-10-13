"""Shared by the tests."""

from __future__ import annotations

import contextlib
import io
import json
from pathlib import Path

TOOL = Path(__file__).resolve().parent.parent
STORYBOARD = json.loads((TOOL / "storyboard.json").read_text(encoding="utf-8"))


@contextlib.contextmanager
def dies(test, containing: str):
    """The tool stops (`die`) with a message that contains `containing`."""
    err = io.StringIO()
    with test.assertRaises(SystemExit) as cm, contextlib.redirect_stderr(err):
        yield
    test.assertEqual(cm.exception.code, 1)
    test.assertIn(containing, err.getvalue())
