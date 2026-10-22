"""promo.lottie — a small, exact Skia player for the Pro app's opening Lottie.

    from promo.lottie import Player, PRO_OPEN_ANIMATION
    player = Player(PRO_OPEN_ANIMATION)
    player.render(canvas, comp_frame=25.0, dst_rect=player.dst_rect((540, 680), 900))

See ``player.py`` for the rendering rules (lottie-flutter 3.5.1's, cited) and
``model.py`` for the feature contract; ``check.py`` holds the golden
acceptance; ``python -m promo.lottie --help`` for the command line.
"""

from pathlib import Path

from .model import LottieError, UnsupportedFeature
from .player import Player, device_frame

#: The repository root (tool/promo_reel/promo/lottie/ is four levels down).
REPO = Path(__file__).resolve().parents[4]

#: The file pro_splash_screen.dart:45 plays (mobile/lib/screens/provider/auth/).
PRO_OPEN_ANIMATION = REPO / 'mobile' / 'assets' / 'lottie' / 'open' / 'myweli_loader_mixed_pro.json'

__all__ = [
    'LottieError',
    'PRO_OPEN_ANIMATION',
    'Player',
    'REPO',
    'UnsupportedFeature',
    'device_frame',
]
