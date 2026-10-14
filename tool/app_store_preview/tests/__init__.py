"""The App Preview tool's own tests — no simulator needed.

    python3 tool/app_store_preview/preview.py selftest

Importing this package puts the tool's folder on the import path, so the
tests import `brand`, `edit`, `frames`, … as the tool does.
"""

import sys
from pathlib import Path

TOOL = Path(__file__).resolve().parent.parent
if str(TOOL) not in sys.path:
    sys.path.insert(0, str(TOOL))
