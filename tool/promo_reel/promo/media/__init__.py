"""Media in and out of the promo pipeline.

  takes     a recorded take's pictures at the take's own times (VFR, picture-accurate)
  masks     blurs on the source pictures (static, or tracking a scroll), applied by the take
  writer    raw RGBA frames + a WAV → H.264/AAC MP4, exact frame count
  probe     what a written film is, and whether it is what it should be
  sheets    frames pulled from a written film; labelled contact sheets
  touches   touch-downs from the gesture logs and the App Store tool's scans; cross-check
  tools     where ffmpeg, ffprobe and the recorded material are
"""
