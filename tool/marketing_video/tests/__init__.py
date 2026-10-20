"""The Reel tool's own tests — no take and no simulator needed.

    python3 tool/marketing_video/reel.py selftest

Importing this package puts the tool's folder on the import path, so the
tests import `reel_plan`, `reel_verify`, … as the tool does.
"""

import sys
from pathlib import Path

TOOL = Path(__file__).resolve().parent.parent
if str(TOOL) not in sys.path:
    sys.path.insert(0, str(TOOL))
