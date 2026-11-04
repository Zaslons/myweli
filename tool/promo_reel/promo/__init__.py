"""MyWeli Pro social promo reel « CARNET → DROP » — a code-only pipeline.

Every frame is drawn with skia and piped raw to ffmpeg; the music is
synthesised and is the clock (``timebase``); ``storyboard.yaml`` is the one
source (``storyboard``). Real app pixels come from the recorded takes
(``media``). See tool/promo_reel/README.md.

    python -m promo build --all     # every cut × format
    python -m promo verify --all
"""
