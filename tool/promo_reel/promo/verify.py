"""Verify a built film — automatically, on the WRITTEN file wherever it can be.

    python -m promo verify --cut 30s --format 9x16 --out DIR      (promo/__main__.py)

Writes DIR/<cut>-<format>/verify/: report.json, report.txt, beats.png,
transitions.png, probe.json, meter.json, spectrogram.png, frames/*.png.

  (a) BEATS: the RENDERER's own frame on every beat (56 in the 30-s cut), a
      sheet labelled « f144 · 4.800 s · 3.2.0 »; and the same beats pulled from
      the MP4 compared with them (PSNR) — the film holds the frames rendered,
      in order.
  (b) TRANSITIONS: every cut and whip, frames T−1, T, T+1 pulled from the MP4.
  (c) TOUCHES: every touch-down the film draws, held to the gesture logs by
      promo.media.touches.cross_check (half a frame at 1×, on the 16th grid,
      never on a typed key, each gesture once, every storyboard touch drawn);
      each disc's tone re-measured on the ground under the finger.
  (d) AUDIO: ITU-R BS.1770-4 on the MP4's decoded AAC (integrated ≈ −14 LUFS,
      true peak ≤ −1.0 dBTP), ffmpeg's ebur128 as a second opinion, and a
      spectrogram with bar ticks.
  (e) FILE: ffprobe + assertions (1080×1920, 30 fps CFR, 896 frames, H.264
      High yuv420p BT.709, AAC 48 kHz stereo, duration, +faststart).
  (f) A/V SYNC: for every UI click and typing cue, the click's onset in the
      decoded MP4 audio (found by correlating with the master around the cue)
      ÷ 1600 against the frame the touch disc or the key's picture appears on.
  (g) SAFE ZONES: every caption, lift, counter, disc and credit box, on every
      frame, inside the format's text area (9:16: x 120–900 × y 270–1248, and
      to x 960 above y 840); captions inside the caption column.
  (h) HONESTY: every generated element with its cited source (none without);
      every blur measured on every picture the film uses (≤ 15 % of the
      digits' detail left); the hidden 13:15 row never readable outside a
      whip; every timeline rate (no wait faster than 1×).
  (i) READING: characters per second of every caption (≤ 17), and the
      longest stretch without a visual event (≤ 2 s).
"""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path
from typing import Any

import numpy as np

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
HIDDEN_ALPHA = 0.05          # the 13:15 row: at most 5 % of it may show outside a whip
BEAT_PSNR_DB = 30.0
CLICK_KINDS = ("click", "key")


class Result:
    def __init__(self) -> None:
        self.sections: dict[str, dict] = {}

    def add(self, key: str, title: str, ok: bool, summary: str, **data: Any) -> None:
        self.sections[key] = {"title": title, "ok": bool(ok), "summary": summary, **data}

    @property
    def ok(self) -> bool:
        return all(s["ok"] for s in self.sections.values())


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


def event_gaps(event_frames, frames: int) -> list[tuple[int, int, int]]:
    """(length, from, to) of every stretch between visual events, longest first."""
    ev = sorted(set(event_frames) | {0, frames})
    return sorted(((b - a, a, b) for a, b in zip(ev, ev[1:])), reverse=True)


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
    worst = min(psnrs.values()) if psnrs else 0.0
    res.add("a", "beat sheet (renderer) and the MP4's beats", not missing and len(tiles) == len(beat_frames)
            and worst >= BEAT_PSNR_DB,
            f"{len(tiles)} of {len(beat_frames)} beats on the sheet; MP4 vs renderer PSNR min {worst} dB "
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
                         title=f"{cut} {fmt_id} — every cut and whip from reel.mp4 (T−1, T, T+1)")
    frames_dir = vdir / "frames"
    looks = sorted({0, 40, 104, 120, 160, 184, 240, 300, 316, 376, 404, 452, 492, 515, 545, 552, 600, 700, 740,
                    756, 790, 815, 880} & set(range(frames)))
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

    # (d) loudness of the MUXED audio ---------------------------------------------------------------
    audio = _decode_audio(mp4)
    m = loudness.measure(audio)
    eb = analysis.ffmpeg_ebur128(mp4)
    meter = analysis.meter(audio, events=events, target_lufs=LUFS_TARGET, ceiling_dbtp=TP_CEILING)
    meter["source"] = "reel.mp4 (AAC, decoded by ffmpeg)"
    meter["ffmpeg_ebur128"] = eb
    master, _ = wav.read(d / "track.wav")
    meter["master_wav"] = loudness.measure(master).as_dict()
    (vdir / "meter.json").write_text(json.dumps(meter, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
    analysis.spectrogram_png(audio.astype(np.float32), vdir / "spectrogram.png", events=events, meter_report=meter,
                             title=f"reel.mp4 audio (AAC decoded) — {cut}, {frames} frames, bar ticks")
    ok_d = abs(m.integrated_lufs - LUFS_TARGET) <= LUFS_TOLERANCE and m.true_peak_dbtp <= TP_CEILING \
        and len(audio) == frames * tbase.samples_per_frame
    res.add("d", "BS.1770-4 on the MP4's audio", ok_d,
            f"integrated {m.integrated_lufs:.2f} LUFS (target {LUFS_TARGET} ± {LUFS_TOLERANCE}), true peak "
            f"{m.true_peak_dbtp:.2f} dBTP (≤ {TP_CEILING}), LRA {m.lra_lu:.1f} LU; ffmpeg ebur128: "
            f"I {eb and eb['integrated_lufs']} LUFS, peak {eb and eb['true_peak_dbfs']} dBTP; decoded "
            f"{len(audio)} samples (expected {frames * tbase.samples_per_frame}); the WAV master was "
            f"{meter['master_wav']['integrated_lufs']:.2f} LUFS / {meter['master_wav']['true_peak_dbtp']:.2f} dBTP",
            loudness=m.as_dict(), ffmpeg=eb, spectrogram="spectrogram.png")

    # (f) A/V sync on the written file ----------------------------------------------------------------
    rows, ok_f = [], True
    bp_mp4 = _bandpass(audio.mean(axis=1))
    bp_wav = _bandpass(master.mean(axis=1))
    touch_frames = {r["f"] for r in records if r.get("touch_downs")}
    pictures = [r.get("picture") for r in records]
    for c in events["cues"]:
        if c["kind"] not in CLICK_KINDS:
            continue
        s = c["sample"]
        best = click_lag(bp_mp4, bp_wav, s)
        onset = s + best
        # the visual frame: the touch disc's touch-down, or the typed key's picture
        if c["kind"] == "click":
            visual = c["frame"] if c["frame"] in touch_frames else None
            what = "touch-down drawn"
        else:
            f = c["frame"]
            visual = f if 0 < f < len(pictures) and pictures[f] != pictures[f - 1] else None
            what = "key's picture appears"
        delta = onset / tbase.samples_per_frame - (visual if visual is not None else -999)
        seen = click_onset(bp_mp4, s)
        delta_seen = seen / tbase.samples_per_frame - (visual if visual is not None else -999)
        ok = visual is not None and abs(delta) < 0.5 and abs(delta_seen) < 0.5
        ok_f &= ok
        rows.append({"cue": c["id"], "kind": c["kind"], "cue_frame": c["frame"], "visual_frame": visual,
                     "visual": what, "onset_sample": int(onset), "onset_frames": round(onset / tbase.samples_per_frame, 3),
                     "lag_ms": round(best / 48.0, 2), "onset_read_sample": seen,
                     "onset_read_ms_from_frame": round((seen - (visual or 0) * tbase.samples_per_frame) / 48.0, 2),
                     "ok": ok})
    lagmax = max(abs(r["lag_ms"]) for r in rows) if rows else 0
    readmax = max(abs(r["onset_read_ms_from_frame"]) for r in rows) if rows else 0
    res.add("f", "A/V sync of every UI click and key on reel.mp4", ok_f and bool(rows),
            f"{sum(r['ok'] for r in rows)}/{len(rows)} clicks land on their visual frame; the MP4's audio sits "
            f"{lagmax:.2f} ms at most from the master's (correlation); each onset read off the MP4 is at most "
            f"{readmax:.2f} ms from its frame's first sample", rows=rows)

    # (g) safe zones ---------------------------------------------------------------------------------------
    counted, bad = outside_safe(records, fmt)
    res.add("g", "safe zones, every frame", not bad,
            f"{counted} boxes on {len(records)} frames; {len(bad)} outside "
            f"{' ∪ '.join(str(x) for x in fmt.text_area)}", outside=bad[:40])

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
    hidden_bad = [{"frame": r["f"], **h} for r in records for h in r.get("hidden", [])
                  if h["alpha"] > HIDDEN_ALPHA and not h["whip"]]
    hidden_max = max((h["alpha"] for r in records for h in r.get("hidden", []) if not h["whip"]), default=0.0)
    rates = []
    for sid, tl in doc["plan"]["timelines"].items():
        for s in tl["segments"]:
            if s["kind"] != "hold":
                rates.append({"scene": sid, "take": tl["take"], **s})
    def is_tap(r):
        return (r.get("gesture") or "").startswith("tap")
    waits = [r for r in rates if is_tap(r)]                      # a server wait follows a tap
    ramps = [r for r in rates if r["rate"] > 1.0 + 1e-6 and not is_tap(r)]
    waits_ok = all(r["rate"] <= 1.0 + 1e-6 for r in waits)
    lines = [f"{g['element']} — {g.get('cite') or 'NO CITATION'}" for g in gen]
    (vdir / "honesty.txt").write_text("\n".join(lines) + "\n", encoding="utf-8")
    ok_h = not uncited and not mask_problems and not hidden_bad and bool(masks_out) and waits_ok
    res.add("h", "honesty", ok_h,
            f"{len(gen)} generated elements, {len(uncited)} without a source; blurs checked on "
            f"{sum(m_['pictures_checked'] for m_ in masks_out)} pictures, at most "
            f"{max((m_['most_detail_left'] for m_ in masks_out), default=0):.0%} of the digits' detail left; "
            f"the 13:15 row shows at most {hidden_max:.1%} outside the whip ({len(hidden_bad)} frames over "
            f"{HIDDEN_ALPHA:.0%}); waits (from a tap) at " + ", ".join(f"{r['rate']:.3f}×" for r in waits)
            + "; gesture ramps (drags) at " + ", ".join(f"{r['rate']:.3f}×" for r in ramps),
            generated=gen, masks=masks_out, mask_problems=mask_problems, hidden_over=hidden_bad[:20], rates=rates,
            list="honesty.txt")

    # (i) reading speed, pattern interrupts ------------------------------------------------------------------
    from .scenes import Clock, Film
    film = Film(sb, cut, fmt_id, Clock(events, frames))
    caps = caption_reading(film.captions.items, sb.meta.fps)
    gaps = event_gaps([f for f, _ in doc["events"]], frames)
    ok_i = all(c["ok"] for c in caps) and gaps[0][0] <= MAX_GAP_FRAMES
    res.add("i", "reading speed and pattern interrupts", ok_i,
            f"fastest caption {max(c['cps'] for c in caps):.1f} cps (≤ {MAX_CPS:g}); longest stretch without a "
            f"visual event {gaps[0][0]} frames = {gaps[0][0] / sb.meta.fps:.2f} s (f{gaps[0][1]}→f{gaps[0][2]}; "
            f"≤ {MAX_GAP_FRAMES / sb.meta.fps:g} s)", captions=caps,
            longest_gaps=[{"frames": g, "from": a, "to": b} for g, a, b in gaps[:6]], events=len(doc["events"]))
    film.ctx.sources.clear()

    report = {"cut": cut, "format": fmt_id, "film": str(mp4), "ok": res.ok, "checks": res.sections,
              "render_seconds": doc.get("render_seconds"), "frame_ms": doc.get("frame_ms")}
    (vdir / "report.json").write_text(json.dumps(report, indent=1, ensure_ascii=False, default=str) + "\n",
                                      encoding="utf-8")
    txt = [f"{cut} {fmt_id} — {'PASS' if res.ok else 'FAIL'} — {mp4}"]
    for k, s in res.sections.items():
        txt.append(f"({k}) {'PASS' if s['ok'] else 'FAIL'}  {s['title']}: {s['summary']}")
    (vdir / "report.txt").write_text("\n".join(txt) + "\n", encoding="utf-8")
    print("\n".join(txt))
    return res


def verify(storyboard, cuts: list[str], formats: list[str], out_dir: Path) -> bool:
    """``python -m promo verify``: every selected film that can be built."""
    ok, seen = True, 0
    for cut in cuts:
        for fmt in formats:
            why = not_built(storyboard, cut, fmt)
            if why:
                print(f"NOT BUILT {cut}/{fmt}: {why} — nothing to verify")
                continue
            d = film_dir(out_dir, cut, fmt)
            if not (d / "reel.mp4").is_file() or not (d / "render.json").is_file():
                print(f"FAIL {cut}/{fmt}: no film at {d} (run `python -m promo build` first)")
                ok = False
                continue
            seen += 1
            ok &= verify_film(storyboard, cut, fmt, d).ok
    if not seen:
        print("verify: no film was verified")
        return False
    return ok


if __name__ == "__main__":  # pragma: no cover
    from .__main__ import main
    sys.exit(main(["verify", *sys.argv[1:]]))
