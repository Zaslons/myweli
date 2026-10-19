"""Verify a built film — automatically, on the WRITTEN file wherever it can be.

    python -m promo verify --cut 30s --format 9x16 --out DIR      (promo/__main__.py)

Writes DIR/<cut>-<format>/verify/: report.json, report.txt, beats.png,
transitions.png, probe.json, meter.json, spectrogram.png, frames/*.png.

  (a) BEATS: the RENDERER's own frame on every beat (60 in the 30-s cut, 32
      in the 15-s), a sheet labelled « f144 · 4.800 s · 3.2.0 »; and the same
      beats pulled from the MP4 compared with them (PSNR) — the film holds the
      frames rendered, in order.
  (b) TRANSITIONS: every cut, whip and declared dissolve, frames T−1, T, T+1
      pulled from the MP4; and full-size frames to look at (`look_frames`:
      derived from the film's own transitions and events, never a list typed
      per cut).
  (c) TOUCHES: every touch-down the film draws, held to the gesture logs by
      promo.media.touches.cross_check (half a frame at 1×, on the 16th grid,
      never on a typed key, each gesture once, every storyboard touch drawn);
      each disc's tone re-measured on the ground under the finger.
  (d) AUDIO: ITU-R BS.1770-4 on the MP4's decoded AAC (integrated ≈ −14 LUFS,
      true peak ≤ −1.0 dBTP), ffmpeg's ebur128 as a second opinion, a
      spectrogram with bar ticks — and each AIR beat (the ``air…`` reverse
      cues' spans) K-weighted, at least 7 LU under the groove (the cut's
      drop/groove sections together), on the WAV master AND on the MP4's
      AAC (a pass never rests on the codec): the storyboard's « near
      silence ».
  (e) FILE: ffprobe + assertions (1080×1920, 30 fps CFR, the cut's frames —
      960 for the 30-s cut, 512 for the 15-s —, H.264 High yuv420p BT.709, AAC 48 kHz stereo,
      duration, +faststart).
  (f) A/V SYNC: for every UI click and typing cue, the click's onset in the
      decoded MP4 audio against the frame its disc or character first
      appears in the MP4's PIXELS: a disc by its own ring (promo.pixels.
      ring_contrast, against the frames before it), a key by the first frame
      whose box looks like the take's picture with the character rather than
      the one before it. render.json only says where to look.
  (g) SAFE ZONES: the INK measured on MP4 frames — each caption on the frame
      it is whole, the counter (mid-roll, landing with its punch, landed),
      every lift, the credit — inside the format's text area (9:16: x
      120–900 × y 270–1248, and to x 960 above y 840), captions inside the
      caption column; and every box render.json records, on every frame.
  (h) HONESTY: every generated element with its cited source (none without);
      every blur measured on every picture the film uses (≤ 15 % of the
      digits' detail left); the hidden 13:15 row on EVERY frame of its scene,
      the whip and the form's push and pop included (HiddenRow): in the MP4's
      pixels, its blocks that identify it (found nowhere else on the scene's
      take pictures — the new booking is the same client, every card says
      « Confirmé ») searched over the WHOLE window — visible = the share
      found × the window's alpha where it was found ≤ 5 %; all its blocks
      at the renderer's place ≤ 25 %; and, outside the whip, the share of
      its place the window shows × the share the take's own picture shows
      there (a push covers it) ≤ 5 %; every timeline rate (no wait faster
      than 1×); every dissolve declared (cited) and going forward in its take
      (`dissolve_problems`: the 15-s cut's one, 32.998 → 130.262).
  (i) READING: characters per second of everything on screen together —
      for every window from an arrival to a departure, the characters that
      arrive in it and leave by its end (promo.verify.reading_windows) — ≤ 17,
      the end card included (its figure is reported); never two lines
      receiving words on one frame; the longest stretch without a visual
      event (≤ 2 s).

Statuses: PASS or FAIL (the end card's « owner decision pending » is retired:
the owner added a bar, 2026-10-19); the film's is the worst of its checks.
``python -m promo verify`` exits 0 / 1.
"""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path
from typing import Any

import numpy as np

from . import pixels
from . import storyboard as sbmod
from .audio import analysis, loudness, wav
from .media import probe as probemod
from .media import sheets, tools
from .media import touches as touchmod
from .media.masks import MaskError
from .media.takes import Take
from .render import film_dir, not_built
from .storyboard import Rect, covered_by

LUFS_TARGET, LUFS_TOLERANCE, TP_CEILING = -14.0, 0.5, -1.0
MAX_CPS = 17.0
MAX_GAP_FRAMES = 60          # 2 s
AIR_UNDER_LU = 7.0           # an AIR beat (« near silence ») sits at least this far under the groove, master AND MP4
HIDDEN_ALPHA = 0.05          # the 13:15 row: at most 5 % of it may show outside a whip
BEAT_PSNR_DB = 30.0
CLICK_KINDS = ("click", "key")


PASS, FAIL = "PASS", "FAIL"


def worst(statuses) -> str:
    """FAIL over PASS (nothing is PASS by default)."""
    statuses = list(statuses)
    return FAIL if not statuses or FAIL in statuses else PASS


class Result:
    def __init__(self) -> None:
        self.sections: dict[str, dict] = {}

    def add(self, key: str, title: str, ok: bool, summary: str, status: str | None = None, **data: Any) -> None:
        status = status or (PASS if ok else FAIL)
        if status == PASS and not ok:
            status = FAIL
        self.sections[key] = {"title": title, "ok": status == PASS, "status": status, "summary": summary, **data}

    @property
    def status(self) -> str:
        return worst(s["status"] for s in self.sections.values())

    @property
    def ok(self) -> bool:
        return self.status == PASS


class Verdict:
    """What ``verify`` hands back: true only when every film PASSES."""

    def __init__(self, status: str):
        self.status = status

    def __bool__(self) -> bool:
        return self.status == PASS

    def __repr__(self) -> str:
        return f"Verdict({self.status!r})"


def _decode_audio(mp4: Path) -> np.ndarray:
    raw = subprocess.run([tools.ffmpeg(), "-v", "error", "-i", str(mp4), "-map", "0:a:0", "-f", "f32le", "-ac", "2",
                          "-ar", "48000", "-"], check=True, capture_output=True).stdout
    return np.frombuffer(raw, np.float32).reshape(-1, 2).astype(np.float64)


def _bandpass(x: np.ndarray, lo: float = 2000.0, hi: float = 5000.0) -> np.ndarray:
    from scipy.signal import butter, sosfiltfilt
    sos = butter(4, [lo, hi], btype="bandpass", fs=48000, output="sos")
    return sosfiltfilt(sos, x)


def _psnr(a: np.ndarray, b: np.ndarray) -> float:
    d = np.mean((a.astype(np.float64) - b.astype(np.float64)) ** 2)
    return float("inf") if d == 0 else float(10 * np.log10(255.0 ** 2 / d))


def click_lag(written: np.ndarray, master: np.ndarray, sample: int, search: int = 2400) -> int:
    """How many samples later than in the master a click sits in the written
    file, near ``sample``: the lag of best correlation of the two (band-passed)
    signals over a window around it."""
    a0, a1 = max(0, sample - 3200), min(len(written), len(master), sample + 4800)
    seg_m, seg_w = written[a0:a1], master[a0:a1]

    def score(L: int) -> float:
        return float(np.dot(seg_w[max(0, -L):len(seg_w) - max(0, L)], seg_m[max(0, L):len(seg_m) - max(0, -L)]))

    return max(range(-search, search + 1), key=score)


def click_onset(written: np.ndarray, sample: int, search: int = 3200) -> int:
    """The click's onset read straight off the written (band-passed) audio:
    the loudest 2–5 kHz event within ``search`` samples of the cue (the click
    is the loudest thing in that band there), then back to where its envelope
    first reached half its peak."""
    from scipy.signal import hilbert
    a0, a1 = max(0, sample - search), min(len(written), sample + search)
    env = np.abs(hilbert(written[a0:a1]))
    k = int(np.argmax(env))
    half = 0.5 * env[k]
    while k > 0 and env[k - 1] >= half:
        k -= 1
    return a0 + k


def outside_safe(records: list[dict], fmt) -> tuple[int, list[dict]]:
    """(boxes checked, boxes outside the format's text area — captions also
    outside the caption column). The mark (the Lottie) is placed by the
    layout, not by text rules, and is not counted."""
    area = list(fmt.text_area)
    col = fmt.layout["caption_column_x"]
    bad, counted = [], 0
    for r in records:
        for b in r.get("boxes", []):
            if b["kind"] == "mark":
                continue
            counted += 1
            rect = Rect(*b["rect"])
            ok = covered_by(rect, area)
            if b["kind"] == "caption":
                ok = ok and col[0] - 0.5 <= rect.x0 and rect.x1 <= col[1] + 0.5
            if not ok:
                bad.append({"frame": r["f"], **b})
    return counted, bad


def air_levels(audio: np.ndarray, events: dict, samples_per_frame: int = 1600) -> dict:
    """Each AIR beat (an ``air…`` reverse cue's span in events.json) against
    the groove (the cut's ``drop…`` and ``groove…`` sections, measured
    together): K-weighted loudness of the segment, and how far under the
    groove it sits. The storyboard's AIR is « near silence »."""
    groove = [s for s in events.get("sections", []) if s["name"].startswith(("drop", "groove"))]
    spans = [(s["frame"] * samples_per_frame, s["end_frame"] * samples_per_frame) for s in groove]
    ref = loudness.segment(audio, spans) if spans else float("nan")
    rows = []
    for c in events.get("cues", []):
        if c["id"].startswith("air") and c["kind"] == "reverse" and c.get("end_frame") is not None:
            v = loudness.segment(audio, (c["frame"] * samples_per_frame, c["end_frame"] * samples_per_frame))
            under = ref - v
            rows.append({"cue": c["id"], "frames": [c["frame"], c["end_frame"]], "lufs": round(v, 2),
                         "under_groove_lu": round(under, 2), "ok": bool(under >= AIR_UNDER_LU)})
    return {"groove_sections": [s["name"] for s in groove], "groove_lufs": round(ref, 2), "air": rows,
            "ok": bool(rows) and all(r["ok"] for r in rows)}


def caption_reading(items, fps: int) -> list[dict]:
    """Characters per second of each caption (every character, spaces too),
    from its first word to its end."""
    out = []
    for c in items:
        dur_s = (c.until - c.first) / fps
        n = len(c.text)
        out.append({"caption": c.id, "text": c.text, "chars": n, "seconds": round(dur_s, 3),
                    "cps": round(n / dur_s, 2), "ok": n / dur_s <= MAX_CPS})
    return out


def reading_items(film) -> list[dict]:
    """Everything a viewer reads, as items that ARRIVE on a frame and LEAVE on
    another, with their characters (spaces included): every caption word
    (the space after it counts with it; it leaves when its caption does), and
    the counter — its labels (« Aujourd’hui » until the switch's midpoint,
    then « Mois »), its digits (the start's « 0 » until the roll starts, the
    landed « 77 000 » from the landing) and its static « FCFA », all leaving
    as it exits. The digits rolling in between are motion, not reading. Not
    counted: the map credit (attribution, not a message) and the lifted cards
    (the app's own pixels, shown as proof)."""
    from .fx import type as ty
    items = []
    for c in film.captions.items:
        words = [w for line in c.caption.lines for w in line]
        for i, w in enumerate(words):
            items.append({"what": f"{c.id}: « {w.text} »", "arrive": float(w.at), "leave": float(c.until),
                          "chars": len(w.text) + (1 if i < len(words) - 1 else 0), "group": c.id,
                          "scene": c.owner})
    for sc in film.scenes:
        c = getattr(sc, "counter", None)
        if not c:
            continue
        leave = (c["exit"] + 2.0) if c["exit"] is not None else float(sc.end)
        mid = c["switch"] + 2.0                       # the 6-frame crossfade's midpoint
        start_digits = ty.fcfa(c["start"])[:-len(" FCFA")]
        end_digits = ty.fcfa(c["end"])[:-len(" FCFA")]
        g = f"{sc.id} counter"
        items += [
            {"what": f"{g}: « {c['labels'][0]} »", "arrive": float(sc.start), "leave": mid,
             "chars": len(c["labels"][0]) + 1, "group": g, "scene": sc.id},
            {"what": f"{g}: « {start_digits} »", "arrive": float(sc.start), "leave": c["from"],
             "chars": len(start_digits), "group": g, "scene": sc.id},
            {"what": f"{g}: « FCFA »", "arrive": float(sc.start), "leave": leave, "chars": 5, "group": g,
             "scene": sc.id},
            {"what": f"{g}: « {c['labels'][1]} »", "arrive": mid, "leave": leave, "chars": len(c["labels"][1]) + 1,
             "group": g, "scene": sc.id},
            {"what": f"{g}: « {end_digits} »", "arrive": c["land"], "leave": leave, "chars": len(end_digits),
             "group": g, "scene": sc.id}]
    return items


def reading_windows(items: list[dict], fps: int) -> list[dict]:
    """For every window [a, b) from an arrival to a departure: the characters
    that arrive in it and must be read before it closes (they leave by b),
    per second. A caption alone gives its own cps; text arriving together, or
    over text still to be read, adds up. Worst first."""
    arrivals = sorted({i["arrive"] for i in items})
    leaves = sorted({i["leave"] for i in items})
    out = []
    for a in arrivals:
        for b in leaves:
            if b <= a:
                continue
            inside = [i for i in items if i["arrive"] >= a and i["leave"] <= b]
            if not inside:
                continue
            n = sum(i["chars"] for i in inside)
            out.append({"from": a, "to": b, "seconds": round((b - a) / fps, 3), "chars": n,
                        "cps": round(n * fps / (b - a), 2), "groups": sorted({i["group"] for i in inside})})
    return sorted(out, key=lambda w: -w["cps"])


def end_card_window(items: list[dict], scene_id: str, fps: int) -> dict | None:
    """The end card read as a whole: every character arriving in its scene,
    from its first arrival to its last departure."""
    mine = [i for i in items if i.get("scene") == scene_id]
    if not mine:
        return None
    a, b = min(i["arrive"] for i in mine), max(i["leave"] for i in mine)
    n = sum(i["chars"] for i in items if i["arrive"] >= a and i["leave"] <= b)
    return {"from": a, "to": b, "chars": n, "seconds": round((b - a) / fps, 3), "cps": round(n * fps / (b - a), 2),
            "groups": sorted({i["group"] for i in mine})}


def reading_verdict(windows: list[dict], captions: list[dict], two_lines: list, gaps: list) -> bool:
    """(i) passes when every arrival window, every caption alone, reads at
    ≤ 17 cps — the end card like the rest —, no two lines take words on one
    frame and no stretch without a visual event is longer than 2 s."""
    return not (windows and windows[0]["cps"] > MAX_CPS) and all(c["ok"] for c in captions) and not two_lines \
        and not (gaps and gaps[0][0] > MAX_GAP_FRAMES)


def look_frames(doc: dict, frames: int) -> list[int]:
    """The full-size frames (b) saves from the MP4 for a person to look at,
    derived from the film itself (render.json), never typed per cut: every
    cut, whip and dissolve at T−1, T, T+1 and its end (a whip's crest, T+3);
    every visual event on its frame and three frames on (a lift up, a move
    under way, a punch at its peak) — but not the take's own picture changes
    nor the caption words, which are many and on the sheets; the first and
    last frames."""
    out = {0, frames - 1}
    for t in doc["plan"]["transitions"]:
        f = int(t["frame"])
        out |= {f - 1, f, f + 1}
        if t.get("frames"):
            out.add(f + int(t["frames"]))
        if "whip" in t["kind"]:
            out.add(f + 3)
    for f, what in doc["events"]:
        if what == "ui change" or what.startswith("word "):
            continue
        out |= {int(f), int(f) + 3}
    return sorted(x for x in out if 0 <= x < frames)


def dissolves(timelines: dict) -> list[dict]:
    """Every dissolve the film's timelines declare (render.json's plan)."""
    return [{"scene": sid, "take": tl["take"], **s} for sid, tl in timelines.items() for s in tl["segments"]
            if s["kind"] == "dissolve"]


def dissolve_problems(timelines: dict) -> list[str]:
    """Why the film's dissolves fail honesty (empty: they pass): each skips
    footage, so each says where it is declared (``cite``), and none goes
    back in the take or blends a picture into itself — re-read from
    render.json, not taken on the renderer's word."""
    out = []
    for d in dissolves(timelines):
        what = f"{d['scene']}: the dissolve {d['take']} {d['src_s']:.3f} → {d['to_s']:.3f} s (f{d['from_frame']:g})"
        if not d.get("cite"):
            out.append(f"{what} is not declared (no cite)")
        a, b = d.get("pictures") or (None, None)
        if not (d["to_s"] > d["src_s"] and a is not None and b is not None and b > a):
            out.append(f"{what} goes back in the take (pictures {a} → {b})")
    return out


def blurs_checked(declared: dict, checked: list[dict]) -> bool:
    """(h)'s blur rule: every take the film declares a blur on (render.json
    ``masks``: take → blurs) was measured on the pictures it uses. A film
    that declares none — the 15-s cut: take1b shows only the « Téléphone du
    client » placeholder, N1 no number — has nothing to measure; that is said
    in the report, never read as « measured »."""
    want = {take for take, specs in declared.items() if specs}
    return want <= {c["take"] for c in checked}


def event_gaps(event_frames, frames: int) -> list[tuple[int, int, int]]:
    """(length, from, to) of every stretch between visual events, longest first."""
    ev = sorted(set(event_frames) | {0, frames})
    return sorted(((b - a, a, b) for a, b in zip(ev, ev[1:])), reverse=True)


# ---- the written film's pixels: (f) discs and keys, (g) ink, (h) the hidden row ----------------------

DISC_STEP = 25.0             # a disc's ring changes the ring contrast by this much (levels) on its first frame
KEY_STEP = 20.0              # a key's box is this much closer (mean |ΔL|, levels) to the picture with the character
ROW_SHOWS_MP4 = 0.25         # the MP4 may show at most a quarter of the old row's text blocks (as recorded)
LIFT_INK, TEXT_INK = "deep", "dark"


def _touch_boxes(records: list[dict], gesture: str) -> dict[int, tuple[float, float, float]]:
    """frame → (cx, cy, R) of a gesture's disc, from the frames' touch boxes
    (where to look; whether it is there is the pixels' call)."""
    out = {}
    for r in records:
        for b in r.get("boxes", []):
            if b["kind"] == "touch" and b["label"] == gesture:
                x0, y0, x1, y1 = b["rect"]
                R = (x1 - x0) / 2
                out[r["f"]] = ((x0 + x1) / 2, (y0 + y1) / 2, R)
    return out


def pixel_plan(film, records: list[dict], events: dict) -> dict:
    """What to measure on which frames of the MP4."""
    from .scenes.phone import PhoneScene
    W = film.fmt.width
    plan = {"clicks": [], "keys": [], "ink": [], "rows": []}
    cue_of_touch = {}
    for sc in film.scenes:
        if isinstance(sc, PhoneScene):
            for spec_t, tp in zip(sc.spec.get("touches") or [], sc.touches):
                at = str(spec_t.get("at", ""))
                if at.startswith("cue:"):
                    cue_of_touch[at[4:]] = (sc, tp)
    for c in events["cues"]:
        f = c["frame"]
        if c["kind"] == "click":
            sc_tp = cue_of_touch.get(c["id"])
            entry = {"cue": c["id"], "frame": f, "sample": c["sample"], "gesture": None, "tone": None, "centres": {}}
            if sc_tp:
                sc, tp = sc_tp
                boxes = _touch_boxes(records, tp.gesture)
                if boxes:
                    # the disc's radius is its own (the box of the frame before the touch-down, before any
                    # ripple widens the box); only its centre moves (a drag)
                    first = min(boxes)
                    R = boxes[first][2]
                    near = lambda g: boxes.get(g, boxes[first] if g < first else boxes[min(boxes, key=lambda k: abs(k - g))])
                    entry.update(gesture=tp.gesture, tone=tp.tone,
                                 centres={g: (near(g)[0], near(g)[1], R) for g in range(f - 5, f + 4)})
            plan["clicks"].append(entry)
        elif c["kind"] == "key":
            sc = film.scene_at(f)
            entry = {"cue": c["id"], "frame": f, "sample": c["sample"], "box": None}
            if isinstance(sc, PhoneScene):
                i_old, i_new = sc.timeline.index(float(f - 1)), sc.timeline.index(float(f + 1))
                if i_old != i_new:
                    a = pixels.luminance(sc.source.rgba(i_old)[..., :3])
                    b = pixels.luminance(sc.source.rgba(i_new)[..., :3])
                    ys, xs = np.nonzero(np.abs(b - a) > 24)
                    # the character's own change, inside the phone window (a status-bar clock under the band
                    # does not count): the largest cluster of change on the window's rows
                    k = sc.source.take.px_per_pt
                    y_lo = (sc.W(float(f)) + 0.0) * k
                    y_hi = (sc.W(float(f)) + (sc.window.floor - sc.window.top) / sc.window.px_per_pt) * k
                    keep = (ys >= y_lo) & (ys < y_hi)
                    ys, xs = ys[keep], xs[keep]
                    if len(xs):
                        pad = 6
                        tb = (max(0, xs.min() - pad), max(0, ys.min() - pad), xs.max() + 1 + pad, ys.max() + 1 + pad)
                        rect_pt = tuple(v / k for v in tb)
                        box = sc.phone.map_rect(rect_pt, sc.pose(float(f)), W=sc.W(float(f)), window=sc.window)
                        entry.update(box=box, pictures=[i_old, i_new],
                                     old=a[tb[1]:tb[3], tb[0]:tb[2]], new=b[tb[1]:tb[3], tb[0]:tb[2]])
            plan["keys"].append(entry)
    # (g) ink: each caption on its full-reveal frame, the counter, every lift, the credit
    from .fx.brand import PALETTE
    for c in film.captions.items:
        last = max(w.at for line in c.caption.lines for w in line)
        fr = int(min(last + c.reveal.frames - c.reveal.lead, c.until - 1))
        sc = film.scene_at(fr)
        px = c.font.getSize()
        ys = [p.baseline for p in c.caption.placed]
        ink = "white" if c.colour_on(sc.stage.dark) == PALETTE.WHITE else TEXT_INK
        plan["ink"].append({"frame": fr, "kind": "caption", "label": c.id, "ink": ink,
                            "region": (0, min(ys) - 1.1 * px, W, max(ys) + 0.35 * px)})
        if c.underline:                                  # the stroke drawn whole, alone in its band
            u = c.underline
            fr_u = int(min(u["at"] + u["frames"] + 1, c.until - 1))
            plan["ink"].append({"frame": fr_u, "kind": "caption", "label": f"{c.id} underline", "ink": ink,
                                "region": (0, u["rect"][1] - 3, W, u["rect"][3] + 3)})
    for sc in film.scenes:
        cnt = getattr(sc, "counter", None)
        if cnt:
            band = film.fmt.zones["caption_band"]
            for fr, what in ((cnt["switch"] + 6, "label « Mois », mid-roll"), (cnt["land"], "landing (punch 1.08)"),
                             (cnt["land"] + 3, "landed")):
                plan["ink"].append({"frame": int(fr), "kind": "counter", "label": what, "ink": TEXT_INK,
                                    "region": (0, 250, W, band.y1)})
        if not isinstance(sc, PhoneScene):
            continue
        veil = (0, sc.window.top - sc.window.band_fade, W, sc.window.floor + sc.window.floor_fade)
        for L in sc.lifts:
            frames = [int(L["up"]) + 5] + ([int(L["down"]) - 1] if L.get("down") else [])
            for fr in frames:
                plan["ink"].append({"frame": fr, "kind": "lift", "label": L["id"], "ink": LIFT_INK, "region": veil})
        st = sc.stack
        if st:
            for i, u in enumerate(st["ups"]):
                plan["ink"].append({"frame": int(u) + 5, "kind": "lift", "label": f"tiles 1–{i + 1}", "ink": LIFT_INK,
                                    "region": veil})
        if sc.credit:
            shown = [r["f"] for r in records if r["scene"] == sc.id and any(b["kind"] == "credit" for b in r.get("boxes", []))]
            if shown:
                floor = film.fmt.zones["floor"]
                plan["ink"].append({"frame": shown[len(shown) // 2], "kind": "credit", "label": "map credit",
                                    "ink": TEXT_INK, "region": (0, floor.y0, W, floor.y0 + 90)})
    # (h) EVERY frame of a scene with a hidden row — its whip, push and pop included
    plan["hidden"] = {}
    for sid, specs in (film.plan().get("hidden") or {}).items():
        mine = [r for r in records if r["scene"] == sid]
        for h in specs:
            plan["hidden"][h["label"]] = {**h, "scene": sid, "pictures": sorted({r["picture"] for r in mine})}
        for r in mine:
            for h in r.get("hidden", []):
                plan["rows"].append({"frame": r["f"], "label": h["label"], "scene": sid, "picture": r["picture"],
                                     "take": r["take"], "alpha": h["alpha"], "rect": h["rect"],
                                     "zoom": r.get("zoom", 1.0), "whip": bool(h["whip"])})
    return plan


class HiddenRow:
    """A row the framing must keep unreadable (the old 13:15 « Yao K. »), as
    (h) looks for it in the MP4's pixels, frame by frame.

    Its template is the take's own picture of it (``shown_on``), cut into
    96-px text blocks (the take's scale; `pixels.row_parts`). On a frame:

      at its place   all its blocks, at the renderer's rect (± 2 px, sliding
                     sideways as a push moves it): the share found;
      anywhere       its DISTINCTIVE blocks — found on no picture the scene
                     shows at another height (`pixels.distinctive`) — over
                     the WHOLE window: the share found and the window's alpha
                     where it was found; visible = their product. The new
                     booking is the same demo client — « Yao K. », « 1
                     prestation » and « Confirmé » are on its row too, and
                     every card says « Confirmé » — so only the old booking's
                     own times say « this is the old row » (measured on the
                     30-s cut: 1 of its 6 blocks, « 13:15 / 13:45 »). A row
                     without one block of its own cannot be searched for:
                     that is a failure, never a pass;
      its place      (outside a whip) the share of its place the window shows
                     × the share of it the take's own picture shows there.
    """

    BLOCK = 96

    def __init__(self, take: str, label: str, rect_pt, shown_on_s: float, pictures, film_px_per_pt: float = 1.791):
        self.take = Take(take)
        self.label = label
        k = self.take.px_per_pt
        L = pixels.luminance(self.take.raw_picture(self.take.index_at(shown_on_s))[..., :3])
        x0, y0, x1, y1 = (int(round(v * k)) for v in rect_pt)
        self.template, self.tx, self.ty = L[y0:y1, x0:x1], x0, y0
        self.parts = pixels.row_parts(self.template, self.BLOCK)
        self.base = film_px_per_pt / k                    # take px → film px at zoom 1
        refs = (pixels.luminance(self.take.raw_picture(i)[..., :3]) for i in sorted(set(pictures)))
        self.distinct_mask = pixels.distinctive(self.parts, refs, own_y=y0, scale=self.base)
        self.distinct = [p for p, keep in zip(self.parts, self.distinct_mask) if keep]
        self._share: dict[int, float] = {}
        self._templates: dict[float, np.ndarray] = {}

    def take_shows(self, picture: int) -> float:
        """How much of the row the take's own picture shows at its place (1 at
        rest, 0 once a push has covered it)."""
        if picture not in self._share:
            L = pixels.luminance(self.take.raw_picture(picture)[..., :3])
            self._share[picture] = pixels.row_fraction(L, self.template, self.tx, self.ty, range(-1210, 41, 2),
                                                       block=self.BLOCK)[0]
        return self._share[picture]

    def template_at(self, scale: float) -> np.ndarray:
        key = round(scale, 4)
        if key not in self._templates:
            self._templates[key] = pixels._resized(self.template, scale)
        return self._templates[key]

    def measure(self, L: np.ndarray, row: dict, window, width: int) -> dict:
        """One frame's luminance `L`; `row` = where the renderer put the row
        (rect, alpha of its place, zoom, whip, take picture)."""
        sc = self.base * float(row["zoom"])
        T = self.template_at(sc)
        at_place = pixels.row_fraction(L, T, row["rect"][0], row["rect"][1], range(-300, 31), dys=(-2, 0, 2),
                                       block=max(24, round(self.BLOCK * sc)))[0]
        region = (0, window.top - window.band_fade, width, window.floor + window.floor_fade)
        found, fx, fy = pixels.row_anywhere(L, self.distinct, region, scale=sc)
        alpha = max(window.alpha_at(float(y)) for y in np.linspace(fy, fy + T.shape[0], 12)) if found > 0 else 0.0
        return {"mp4_shows": round(at_place, 3), "found": round(found, 3), "found_at": [round(fx, 1), round(fy, 1)],
                "found_alpha": round(alpha, 3), "found_visible": round(found * alpha, 4),
                "visible": None if row["whip"] else round(row["alpha"] * self.take_shows(row["picture"]), 4)}

    @staticmethod
    def over(m: dict) -> list[str]:
        """Why a frame's measure fails (empty: it passes)."""
        why = []
        if m["visible"] is not None and m["visible"] > HIDDEN_ALPHA:
            why.append(f"its place shows {m['visible']:.1%} of it")
        if m["mp4_shows"] > ROW_SHOWS_MP4:
            why.append(f"{m['mp4_shows']:.0%} of its blocks at its place")
        if m["found_visible"] > HIDDEN_ALPHA:
            why.append(f"found at {m['found_at']} where the window shows {m['found_alpha']:.0%}")
        return why

    def close(self) -> None:
        self.take.close()


def run_pixels(mp4: Path, film, plan: dict, fmt) -> dict:
    """Measure the plan on ONE decode of the MP4."""
    want = set()
    for c in plan["clicks"]:
        want |= set(range(c["frame"] - 5, c["frame"] + 4))
    for k in plan["keys"]:
        want |= set(range(k["frame"] - 3, k["frame"] + 4))
    want |= {t["frame"] for t in plan["ink"]} | {r["frame"] for r in plan["rows"]}
    want = {f for f in want if 0 <= f < film.frames}
    ring: dict[str, dict[int, float]] = {c["cue"]: {} for c in plan["clicks"]}
    change: dict[str, dict[int, float]] = {k["cue"]: {} for k in plan["keys"]}
    ink: list[dict] = []
    rows: list[dict] = []
    hidden = {label: HiddenRow(h["take"], label, h["rect_pt"], h["shown_on_s"], h["pictures"],
                               float(fmt.layout["px_per_pt"]))
              for label, h in (plan.get("hidden") or {}).items()}
    windows = {sc.id: sc.window for sc in film.scenes if hasattr(sc, "window")}
    for r in plan["rows"]:
        r["take_shows"] = hidden[r["label"]].take_shows(r["picture"])
    prev = None
    for f, rgb in pixels.stream_frames(mp4, want, fmt.width, fmt.height):
        L = pixels.luminance(rgb)
        for c in plan["clicks"]:
            if f in c["centres"]:
                cx, cy, R = c["centres"][f]
                ring[c["cue"]][f] = pixels.ring_contrast(L, cx, cy, R)
        for k in plan["keys"]:
            if k["box"] is not None and k["frame"] - 3 <= f <= k["frame"] + 3:
                change[k["cue"]][f] = pixels.closer_to(L, k["box"], k["old"], k["new"])
        for t in plan["ink"]:
            if t["frame"] == f:
                box = pixels.ink_box(rgb, t["region"], t["ink"])
                ink.append({**t, "box": None if box is None else [round(v, 1) for v in box]})
        for r in plan["rows"]:
            if r["frame"] == f:
                rows.append({**r, **hidden[r["label"]].measure(L, r, windows[r["scene"]], fmt.width)})
        prev = (f, L)
    info = {label: {"blocks": len(h.parts), "identifying": [b0 for (b0, _), keep in zip(h.parts, h.distinct_mask)
                                                              if keep]} for label, h in hidden.items()}
    for h in hidden.values():
        h.close()
    return {"ring": ring, "change": change, "ink": ink, "rows": rows, "hidden": info}


def visual_frames(plan: dict, measured: dict) -> dict[str, dict]:
    """The frame each click's disc / each key's character FIRST appears in
    the MP4's pixels (None: not found, or already there before the window)."""
    out = {}
    for c in plan["clicks"]:
        r = measured["ring"].get(c["cue"], {})
        f0 = c["frame"]
        base = [r[g] for g in (f0 - 5, f0 - 4, f0 - 3) if g in r]
        sign = -1.0 if c["tone"] == "dark" else 1.0
        seen = None
        if base and c["tone"]:
            b = float(np.median(base))
            for g in range(f0 - 2, f0 + 4):
                if g in r and sign * (r[g] - b) >= DISC_STEP:
                    seen = g
                    break
        out[c["cue"]] = {"visual": seen, "what": f"disc of {c['gesture']} appears", "ring": {g: round(v, 1) for g, v in r.items()}}
    for k in plan["keys"]:
        ch = measured["change"].get(k["cue"], {})
        seen = None
        before = [ch[g] for g in range(k["frame"] - 3, k["frame"] - 1) if g in ch]
        if before and max(before) < 0:                       # the frames before show the picture before it …
            for g in range(k["frame"] - 1, k["frame"] + 4):
                if g in ch and ch[g] >= KEY_STEP:            # … the first that shows the character's picture
                    seen = g
                    break
        out[k["cue"]] = {"visual": seen, "what": "key's character appears",
                         "change": {g: round(v, 2) for g, v in ch.items()}}
    return out


def verify_film(sb, cut: str, fmt_id: str, d: Path) -> Result:
    res = Result()
    vdir = d / "verify"
    vdir.mkdir(parents=True, exist_ok=True)
    mp4 = d / "reel.mp4"
    doc = json.loads((d / "render.json").read_text(encoding="utf-8"))
    events = json.loads((d / "events.json").read_text(encoding="utf-8"))
    records = doc["records"]
    fmt = sb.formats[fmt_id]
    tbase = sb.timebase
    frames = sb.cuts[cut].frames

    # (e) the file ------------------------------------------------------------------------
    rep = probemod.probe(mp4)
    expect = probemod.Expect(frames=frames, width=fmt.width, height=fmt.height, fps=sb.meta.fps)
    problems = probemod.check(rep, expect)
    probemod.write_report(rep, vdir / "probe.json", expect)
    v, a = rep["video"], rep["audio"]
    res.add("e", "ffprobe of reel.mp4", not problems,
            f"{v['codec']} {v['profile']} {v['width']}×{v['height']} {v['pix_fmt']} {v['color_space']}, "
            f"{v['frames']} frames, CFR {v['cfr']} at {v['measured_fps']} fps, {v['duration_s']:.4f} s; "
            f"{a['codec']} {a['sample_rate']} Hz × {a['channels']} at {a['bit_rate'] // 1000} kb/s, "
            f"{a['duration_s']:.4f} s; A/V Δ {rep['av']['duration_difference_s'] * 1000:+.1f} ms; "
            f"faststart {rep['container']['faststart']}", problems=problems)

    # (a) the renderer's beats, and the MP4's ------------------------------------------------
    beat_frames = list(range(0, frames, tbase.frames_per_beat))
    tiles, missing = [], []
    for f in beat_frames:
        p = d / "verify" / "renderer" / f"f{f:04d}.png"
        if not p.is_file():
            missing.append(f)
            continue
        pos = tbase.pos(f)
        tiles.append(sheets.Tile(p, f"f{f} · {f / sb.meta.fps:.3f} s · {pos.bar}.{pos.beat}"))
    if tiles:
        sheets.contact_sheet(tiles, vdir / "beats.png", columns=8, tile_width=200,
                             title=f"{cut} {fmt_id} — the renderer's frame on every beat ({len(tiles)})")
    pulled = sheets.pull_frames(mp4, beat_frames)
    from PIL import Image
    psnrs = {}
    for f in beat_frames:
        p = d / "verify" / "renderer" / f"f{f:04d}.png"
        if p.is_file():
            ref = np.asarray(Image.open(p).convert("RGB"))
            got = np.asarray(Image.fromarray(pulled[f][..., :3]).resize((ref.shape[1], ref.shape[0]), Image.LANCZOS))
            psnrs[f] = round(_psnr(ref, got), 1)
    psnr_min = min(psnrs.values()) if psnrs else 0.0
    res.add("a", "beat sheet (renderer) and the MP4's beats", not missing and len(tiles) == len(beat_frames)
            and psnr_min >= BEAT_PSNR_DB,
            f"{len(tiles)} of {len(beat_frames)} beats on the sheet; MP4 vs renderer PSNR min {psnr_min} dB "
            f"(≥ {BEAT_PSNR_DB} dB: same frames, same order)", missing=missing, psnr_db=psnrs, sheet="beats.png")

    # (b) transitions from the MP4 --------------------------------------------------------------
    trans = doc["plan"]["transitions"]
    want = sorted({x for t in trans for x in (t["frame"] - 1, t["frame"], t["frame"] + 1) if 0 <= x < frames})
    pulled_t = sheets.pull_frames(mp4, want)
    ttiles = []
    for t in trans:
        for x in (t["frame"] - 1, t["frame"], t["frame"] + 1):
            if x in pulled_t:
                lab = sheets.label(x, tbase) + (f" · {t['kind']} → {t['into']}" if x == t["frame"] else "")
                ttiles.append(sheets.Tile(pulled_t[x], lab))
    sheets.contact_sheet(ttiles, vdir / "transitions.png", columns=6, tile_width=220,
                         title=f"{cut} {fmt_id} — every cut, whip and dissolve from reel.mp4 (T−1, T, T+1)")
    frames_dir = vdir / "frames"
    looks = look_frames(doc, frames)
    sheets.save_frames(mp4, looks, frames_dir)
    res.add("b", "transitions from reel.mp4", len(ttiles) == sum(1 for t in trans for x in (-1, 0, 1)
                                                                 if 0 <= t["frame"] + x < frames),
            f"{len(trans)} transitions, {len(ttiles)} frames pulled; full-size frames in verify/frames/",
            transitions=trans, sheet="transitions.png", frames=[f"f{f:04d}.png" for f in looks])

    # (c) touches against the gesture logs --------------------------------------------------------
    rendered = [touchmod.RenderedTouch(t["take"], r["f"], t["src_s"], t["gesture"])
                for r in records for t in r.get("touch_downs", [])]
    takes = sorted({t.take for t in rendered})
    downs = [dd for name in takes for dd in touchmod.touch_downs(name)]
    required = [(tl["take"], t["gesture"]) for tl in doc["plan"]["timelines"].values() for t in tl["touches"]]
    cc = touchmod.cross_check(rendered, downs, required=required)
    tones = []
    for r in records:
        for t in r.get("touch_downs", []):
            dd = next(x for x in downs if x.take == t["take"] and x.gesture == t["gesture"])
            tk = Take(t["take"])
            rgba = tk.raw_picture(tk.index_at(dd.down_s))
            from .fx.touch import STYLE, tone_at
            k = tk.px_per_pt
            measured = tone_at(rgba, dd.at_pt[0] * k, dd.at_pt[1] * k, STYLE.diameter_pt * k)
            tones.append({"frame": r["f"], "gesture": t["gesture"], "drawn": t["tone"], "ground_asks": measured,
                          "ok": measured == t["tone"]})
            tk.close()
    res.add("c", "touch indicators vs the gesture logs", cc.ok and all(t["ok"] for t in tones),
            f"{len(cc.matches)} touch-downs drawn, {len(cc.problems)} problems; tones "
            f"{sum(t['ok'] for t in tones)}/{len(tones)} as the ground asks", report=cc.report().splitlines(),
            tones=tones)

    # the film as the storyboard describes it (where to look), and ONE decode of the MP4 (what is there)
    from .scenes import Clock, Film
    film = Film(sb, cut, fmt_id, Clock(events, frames))
    pplan = pixel_plan(film, records, events)
    measured = run_pixels(mp4, film, pplan, fmt)
    seen = visual_frames(pplan, measured)

    # (d) loudness of the MUXED audio ---------------------------------------------------------------
    audio = _decode_audio(mp4)
    m = loudness.measure(audio)
    eb = analysis.ffmpeg_ebur128(mp4)
    meter = analysis.meter(audio, events=events, target_lufs=LUFS_TARGET, ceiling_dbtp=TP_CEILING)
    meter["source"] = "reel.mp4 (AAC, decoded by ffmpeg)"
    meter["ffmpeg_ebur128"] = eb
    master, _ = wav.read(d / "track.wav")
    meter["master_wav"] = loudness.measure(master).as_dict()
    air = air_levels(audio, events, tbase.samples_per_frame)
    air_master = air_levels(master, events, tbase.samples_per_frame)
    meter["air"] = air
    meter["air_master_wav"] = air_master
    (vdir / "meter.json").write_text(json.dumps(meter, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
    analysis.spectrogram_png(audio.astype(np.float32), vdir / "spectrogram.png", events=events, meter_report=meter,
                             title=f"reel.mp4 audio (AAC decoded) — {cut}, {frames} frames, bar ticks")
    ok_d = abs(m.integrated_lufs - LUFS_TARGET) <= LUFS_TOLERANCE and m.true_peak_dbtp <= TP_CEILING \
        and len(audio) == frames * tbase.samples_per_frame and air["ok"] and air_master["ok"]

    def air_text(a: dict) -> str:
        return ", ".join(f"{r['cue']} f{r['frames'][0]}–{r['frames'][1] - 1} {r['lufs']} LUFS ({r['under_groove_lu']} LU "
                         f"under{'' if r['ok'] else ' — TOO LOUD'})" for r in a["air"])
    res.add("d", "BS.1770-4 on the MP4's audio, and the AIR beats", ok_d,
            f"integrated {m.integrated_lufs:.2f} LUFS (target {LUFS_TARGET} ± {LUFS_TOLERANCE}), true peak "
            f"{m.true_peak_dbtp:.2f} dBTP (≤ {TP_CEILING}), LRA {m.lra_lu:.1f} LU; ffmpeg ebur128: "
            f"I {eb and eb['integrated_lufs']} LUFS, peak {eb and eb['true_peak_dbfs']} dBTP; decoded "
            f"{len(audio)} samples (expected {frames * tbase.samples_per_frame}); the WAV master was "
            f"{meter['master_wav']['integrated_lufs']:.2f} LUFS / {meter['master_wav']['true_peak_dbtp']:.2f} dBTP; "
            f"AIR (near silence, ≥ {AIR_UNDER_LU:g} LU under the groove = {'+'.join(air['groove_sections'])}) on the "
            f"WAV master (groove {air_master['groove_lufs']} LUFS): {air_text(air_master)}; on the MP4 (groove "
            f"{air['groove_lufs']} LUFS): {air_text(air)}",
            loudness=m.as_dict(), ffmpeg=eb, air=air, air_master=air_master, spectrogram="spectrogram.png")

    # (f) A/V sync on the written file: the sound's onset in the MP4's audio against the frame its disc or
    #     character first appears in the MP4's PIXELS ------------------------------------------------------
    rows, ok_f = [], True
    bp_mp4 = _bandpass(audio.mean(axis=1))
    bp_wav = _bandpass(master.mean(axis=1))
    for c in events["cues"]:
        if c["kind"] not in CLICK_KINDS:
            continue
        s_ = c["sample"]
        best = click_lag(bp_mp4, bp_wav, s_)
        onset = s_ + best
        v_ = seen.get(c["id"], {"visual": None, "what": "nothing measured"})
        visual = v_["visual"]
        delta = onset / tbase.samples_per_frame - (visual if visual is not None else -999)
        heard = click_onset(bp_mp4, s_)
        delta_heard = heard / tbase.samples_per_frame - (visual if visual is not None else -999)
        ok = visual is not None and abs(delta) < 0.5 and abs(delta_heard) < 0.5
        ok_f &= ok
        rows.append({"cue": c["id"], "kind": c["kind"], "cue_frame": c["frame"], "visual_frame_mp4": visual,
                     "visual": v_["what"], "onset_sample": int(onset),
                     "onset_frames": round(onset / tbase.samples_per_frame, 3), "lag_ms": round(best / 48.0, 2),
                     "onset_read_sample": heard,
                     "onset_read_ms_from_frame": round((heard - (visual or 0) * tbase.samples_per_frame) / 48.0, 2),
                     "pixels": v_.get("ring") or v_.get("change"), "ok": ok})
    lagmax = max(abs(r["lag_ms"]) for r in rows) if rows else 0
    readmax = max(abs(r["onset_read_ms_from_frame"]) for r in rows) if rows else 0
    res.add("f", "A/V sync of every UI click and key on reel.mp4 (visual frames read off its pixels)",
            ok_f and bool(rows),
            f"{sum(r['ok'] for r in rows)}/{len(rows)} sounds land on the frame their disc / character first "
            f"appears in the MP4's pixels (" + ", ".join(f"{r['cue']} f{r['visual_frame_mp4']}" for r in rows)
            + f"); the MP4's audio sits {lagmax:.2f} ms at most from the master's (correlation); each onset read "
              f"off the MP4 is at most {readmax:.2f} ms from its frame's first sample", rows=rows)

    # (g) safe zones: the ink measured on MP4 frames, and every box the renderer recorded ------------------
    area = list(fmt.text_area)
    col = fmt.layout["caption_column_x"]
    ink_rows, ink_bad = [], []
    for t in measured["ink"]:
        box = t["box"]
        ok = box is not None and covered_by(Rect(*box), area)
        if ok and t["kind"] == "caption":
            ok = col[0] - 0.5 <= box[0] and box[2] <= col[1] + 0.5
        row = {"frame": t["frame"], "kind": t["kind"], "label": t["label"], "ink_box": box, "ok": bool(ok)}
        ink_rows.append(row)
        if not ok:
            ink_bad.append(row)
    counted, bad = outside_safe(records, fmt)
    res.add("g", "safe zones: ink on MP4 frames, and every recorded box", not bad and not ink_bad and bool(ink_rows),
            f"ink measured on {len(ink_rows)} MP4 frames (each caption whole, the counter landing, every lift, the "
            f"credit): {len(ink_bad)} outside {' ∪ '.join(str(x) for x in fmt.text_area)}; and {counted} recorded "
            f"boxes on {len(records)} frames, {len(bad)} outside", ink=ink_rows, outside=bad[:40],
            ink_outside=ink_bad)

    # (h) honesty ----------------------------------------------------------------------------------------
    gen = doc["generated"]
    uncited = [g for g in gen if not g.get("cite")]
    used: dict[str, set[int]] = {}
    for r in records:
        if r.get("take") is not None:
            used.setdefault(r["take"], set()).add(r["picture"])
    masks_out, mask_problems = [], []
    for name, specs in doc["masks"].items():
        if not specs:
            continue
        from .scenes.sources import TakeSource
        src = TakeSource(name)
        src.add_masks([{"label": s["label"], "rect_pt": s["rect_pt"], "sigma_px": s["sigma_px"],
                        "margin_pt": s["margin_pt"], "from_s": s["from_s"], "to_s": s["to_s"],
                        "clip_y_pt": s["clip_y_pt"],
                        **({"track": "phone_rect_per_frame.csv"} if s["tracked"] else {})} for s in specs], "verify")
        ms = src.take.masks
        idx = sorted(i for i in used.get(name, ()) if ms.placed(src.take.pts[i]))
        try:
            cov = ms.verify(idx)
            from .media.masks import FLAT
            shares = [c.detail_after / c.detail_before for c in cov if c.detail_before >= FLAT]
            share = max(shares) if shares else 0.0
            masks_out.append({"take": name, "pictures_checked": len(idx), "blurs": [s["label"] for s in specs],
                              "most_detail_left": round(share, 3)})
        except MaskError as e:
            mask_problems.append(f"{name}: {e}")
        src.take.close()
    # the old 13:15 row, on EVERY frame of its scene (the whip, the form's push and pop included): its own
    # blocks searched over the whole window (visible = share found × the window's alpha there, ≤ 5 %); all
    # its blocks at the renderer's place (≤ 25 %); outside the whip, its place × the take's picture (≤ 5 %)
    hrows = measured["rows"]
    hidden_bad = [{**r, "why": HiddenRow.over(r)} for r in hrows if HiddenRow.over(r)]
    for label, info in measured.get("hidden", {}).items():
        if not info["identifying"]:
            mask_problems.append(f"{label}: none of its {info['blocks']} blocks identifies it (each is found elsewhere "
                                 f"on the scene's pictures) — it cannot be searched for")
    hidden_max = max((r["visible"] for r in hrows if r["visible"] is not None), default=0.0)
    found_max = max((r["found_visible"] for r in hrows), default=0.0)
    mp4_max = max((r["mp4_shows"] for r in hrows), default=0.0)
    in_push = [r for r in hrows if 0.0 < r["take_shows"] < 1.0]
    in_whip = [r for r in hrows if r["whip"]]
    ident = "; ".join(f"{len(i['identifying'])} of its {i['blocks']} blocks identify it (at x "
                      f"{', '.join(str(b) for b in i['identifying'])} take px)" for i in measured.get("hidden", {}).values())
    rates = []
    for sid, tl in doc["plan"]["timelines"].items():
        for s in tl["segments"]:
            if s["kind"] not in ("hold", "dissolve"):
                rates.append({"scene": sid, "take": tl["take"], **s})
    blends = dissolves(doc["plan"]["timelines"])
    blend_problems = dissolve_problems(doc["plan"]["timelines"])
    def is_tap(r):
        return (r.get("gesture") or "").startswith("tap")
    waits = [r for r in rates if is_tap(r)]                      # a server wait follows a tap
    ramps = [r for r in rates if r["rate"] > 1.0 + 1e-6 and not is_tap(r)]
    waits_ok = all(r["rate"] <= 1.0 + 1e-6 for r in waits)
    lines = [f"{g['element']} — {g.get('cite') or 'NO CITATION'}" for g in gen]
    (vdir / "honesty.txt").write_text("\n".join(lines) + "\n", encoding="utf-8")
    ok_h = not uncited and not mask_problems and not hidden_bad and blurs_checked(doc["masks"], masks_out) and waits_ok \
        and (bool(hrows) or not doc["plan"].get("hidden")) and not blend_problems
    res.add("h", "honesty", ok_h,
            f"{len(gen)} generated elements, {len(uncited)} without a source; "
            + (f"blurs checked on {sum(m_['pictures_checked'] for m_ in masks_out)} pictures, at most "
               f"{max((m_['most_detail_left'] for m_ in masks_out), default=0):.0%} of the digits' detail left; "
               if any(doc["masks"].values()) else
               f"no blur declared (no phone number on {', '.join(sorted(doc['masks'])) or 'any take'}): none to measure; ")
            + f"the 13:15 row checked on {len(hrows)} frames ({len(in_whip)} in the whip, {len(in_push)} with the row "
            f"half-covered by the form's push or pop; {ident}): searched over the whole window, at most "
            f"{found_max:.1%} of it visible where found (≤ {HIDDEN_ALPHA:.0%}); at its place at most {mp4_max:.0%} of "
            f"its blocks in the MP4's pixels (≤ {ROW_SHOWS_MP4:.0%}) and, outside the whip, at most {hidden_max:.1%} "
            f"of it visible (≤ {HIDDEN_ALPHA:.0%}); {len(hidden_bad)} frames over; waits (from a tap) at "
            + ", ".join(f"{r['rate']:.3f}×" for r in waits)
            + "; gesture ramps (drags) at " + ", ".join(f"{r['rate']:.3f}×" for r in ramps)
            + "; dissolves: " + (", ".join(f"{b['take']} {b['src_s']:.3f} → {b['to_s']:.3f} s over f{b['from_frame']:g}–"
                                          f"f{b['until_frame']:g} ({'declared' if b.get('cite') else 'NOT DECLARED'})"
                                          for b in blends) or "none")
            + (f" — {'; '.join(blend_problems)}" if blend_problems else ""),
            generated=gen, masks=masks_out, mask_problems=mask_problems, hidden_over=hidden_bad[:20],
            hidden_rows=hrows, rates=rates, dissolves=blends, dissolve_problems=blend_problems, list="honesty.txt")

    # (i) reading speed (each caption, and EVERYTHING on screen together), pattern interrupts -------------
    from .scenes.captions import arrivals_on_two_lines
    caps = caption_reading(film.captions.items, sb.meta.fps)
    items = reading_items(film)
    gating = reading_windows(items, sb.meta.fps)
    end_scene = next((sc.id for sc in film.scenes if sc.kind == "end_card"), None)
    end_card = end_card_window(items, end_scene, sb.meta.fps) if end_scene else None
    two = arrivals_on_two_lines(film.captions.items)
    gaps = event_gaps([f for f, _ in doc["events"]], frames)
    worst_g = gating[0] if gating else None
    status_i = PASS if reading_verdict(gating, caps, two, gaps) else FAIL
    summary_i = (f"everything on screen together, worst window {worst_g['cps']:.1f} cps "
                 f"(f{worst_g['from']:g}→f{worst_g['to']:g}, {worst_g['chars']} characters in {worst_g['seconds']} s: "
                 f"{', '.join(worst_g['groups'])}; ≤ {MAX_CPS:g})" if worst_g else "no text")
    if end_card:
        summary_i += (f"; END CARD {end_card['chars']} characters in {end_card['seconds']} s "
                      f"(f{end_card['from']:g}→f{end_card['to']:g}) = {end_card['cps']:.1f} cps"
                      + ("" if end_card["cps"] <= MAX_CPS else " — TOO FAST"))
    summary_i += (f"; {len(two)} frames with words arriving on two lines"
                  + (f" ({two[0][0]:g}: {'; '.join(two[0][1])})" if two else "")
                  + f"; fastest single caption {max(c['cps'] for c in caps):.1f} cps; longest stretch without a "
                    f"visual event {gaps[0][0]} frames = {gaps[0][0] / sb.meta.fps:.2f} s (f{gaps[0][1]}→f{gaps[0][2]}; "
                    f"≤ {MAX_GAP_FRAMES / sb.meta.fps:g} s)")
    res.add("i", "reading speed (combined) and pattern interrupts", status_i == PASS, summary_i,
            windows=gating[:12], end_card=end_card, captions=caps, items=items,
            two_lines=two, longest_gaps=[{"frames": g, "from": a, "to": b} for g, a, b in gaps[:6]],
            events=len(doc["events"]),
            not_counted=["the map credit (attribution, not a message)",
                         "the lifted cards (the app's own pixels, shown as proof)",
                         "the counter's rolling digits (motion; its start « 0 » and landed figure are counted)"])
    film.ctx.sources.clear()

    report = {"cut": cut, "format": fmt_id, "film": str(mp4), "ok": res.ok, "status": res.status,
              "checks": res.sections, "render_seconds": doc.get("render_seconds"), "frame_ms": doc.get("frame_ms")}
    (vdir / "report.json").write_text(json.dumps(report, indent=1, ensure_ascii=False, default=str) + "\n",
                                      encoding="utf-8")
    txt = [f"{cut} {fmt_id} — {res.status} — {mp4}"]
    for k, s in res.sections.items():
        txt.append(f"({k}) {s['status']}  {s['title']}: {s['summary']}")
    (vdir / "report.txt").write_text("\n".join(txt) + "\n", encoding="utf-8")
    print("\n".join(txt))
    return res


def verify(storyboard, cuts: list[str], formats: list[str], out_dir: Path) -> bool:
    """``python -m promo verify``: every selected film that can be built."""
    statuses, seen = [], 0
    for cut in cuts:
        for fmt in formats:
            why = not_built(storyboard, cut, fmt)
            if why:
                print(f"NOT BUILT {cut}/{fmt}: {why} — nothing to verify")
                continue
            d = film_dir(out_dir, cut, fmt)
            if not (d / "reel.mp4").is_file() or not (d / "render.json").is_file():
                print(f"FAIL {cut}/{fmt}: no film at {d} (run `python -m promo build` first)")
                statuses.append(FAIL)
                continue
            seen += 1
            statuses.append(verify_film(storyboard, cut, fmt, d).status)
    if not seen:
        print("verify: no film was verified")
        return Verdict(FAIL)
    return Verdict(worst(statuses))


if __name__ == "__main__":  # pragma: no cover
    from .__main__ import main
    sys.exit(main(["verify", *sys.argv[1:]]))
