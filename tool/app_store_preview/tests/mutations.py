#!/usr/bin/env python3
"""Watch every check go red.

A check that has never been seen to fail is not a check. This script breaks
the tool one check at a time — silences a refusal, makes a verification
always pass, bends a number — and requires a named test to fail each time.

    python3 tool/app_store_preview/tests/mutations.py            # all, ~20 min
    python3 tool/app_store_preview/tests/mutations.py edit       # one group
    python3 tool/app_store_preview/tests/mutations.py --list

It only runs on a clean, committed tree: every mutation is undone by
writing the file's committed text back, which would erase uncommitted work.
A mutation whose anchor is not in the source exactly as written here is an
ERROR, not a pass — and the script counts the refusals in each file, so a
new one that is not watched is an error too.

Three kinds of mutation:
  every `raise Refusal(` of edit.py and every `die(` of frames.py and
  brand.py is silenced in turn;
  every check of verify.py is made to pass whatever the file says;
  the table MANUAL below — numbers, comparisons, and the Swift helpers.
The Swift mutations recompile a helper and run the end-to-end tests: they
are the slow ones.
"""

from __future__ import annotations

import re
import subprocess
import sys
import time
from pathlib import Path

TOOL = Path(__file__).resolve().parent.parent
ROOT = TOOL.parents[1]

# ---- every refusal, silenced in turn ------------------------------------------
# (file, the call as a pattern, what it becomes, how many there must be, the tests that watch)
SILENCED = [
    ("edit.py", r"raise Refusal\(", "Refusal(", 51, ["tests.test_edit"]),
    ("frames.py", r"(?m)^( +)die\(", r"\1str(", 8, ["tests.test_frames"]),
    ("brand.py", r"(?m)^( +)die\(", r"\1str(", 5, ["tests.test_brand"]),
]

# ---- every check of verify.py, made to pass -----------------------------------
V = "tests.test_verify.VerifyRefuses."
VERIFY_CHECKS = {
    "readable (boxes)": V + "test_something_that_is_not_a_movie",
    "readable (AVFoundation)": V + "test_a_file_avfoundation_cannot_open",
    "container": V + "test_a_mov_container",
    "file size": V + "test_a_file_over_the_size_limit",
    "tracks": V + "test_no_sound_track",
    "avmediainfo reads it": V + "test_a_file_avmediainfo_finds_errors_in",
    "video track": V + "test_a_file_with_no_picture",
    "video enabled": V + "test_a_disabled_video_track",
    "codec": V + "test_hevc",
    "profile and level": V + "test_the_wrong_profile",
    "size": V + "test_a_header_that_claims_another_size",
    "upright, square pixels": V + "test_a_rotated_picture",
    "progressive": V + "test_interlaced",
    "no alpha, 8-bit 4:2:0": V + "test_a_depth_that_says_alpha",
    "every frame is 1/30 s": V + "test_a_variable_frame_rate",
    "frame rate": V + "test_25_frames_per_second",
    "no frame reordering": V + "test_reordered_frames",
    "frame count": V + "test_14_9_seconds",
    "duration": V + "test_14_9_seconds",
    "video bit rate": V + "test_a_blank_film",
    "poster frame": [V + "test_a_poster_time_past_the_end_of_the_film",       # the first `add`: cannot decode
                     V + "test_a_poster_frame_that_is_not_the_composed_one"],  # the second: the comparison
    "sound track": V + "test_no_sound_track",
    "sound enabled": V + "test_a_disabled_sound_track",
    "sound is AAC-LC": V + "test_sound_that_is_not_aac_lc",
    "sound is stereo at 48 kHz": V + "test_mono_sound",
    "sound runs the whole film": V + "test_sound_that_stops_early",
    "sound is digital silence": V + "test_sound_that_is_not_silence",
    "sound bit rate": V + "test_sound_declared_at_128_kbps",
}

# ---- numbers, comparisons, and the Swift helpers ------------------------------
E = "tests.test_edit."
F = "tests.test_frames."
B = "tests.test_brand."
P = "tests.test_mp4."
X = "tests.test_verify.EncoderRefuses."
E2E = "tests.test_e2e"
MANUAL = [
    # group, file, exactly this text (once), becomes, the test that must fail
    ("edit", "edit.py", "STRONG_MIN = 4 ", "STRONG_MIN = 6 ", E + "Kinds.test_what_is_a_change"),
    ("edit", "edit.py", "SOFT_MIN = 2000 ", "SOFT_MIN = 2001 ", E + "Kinds.test_what_is_a_change"),
    ("edit", "edit.py", "CARET_MIN_HEIGHT_PT <= h <= CARET_MAX_PT[1]", "h <= CARET_MAX_PT[1]",
     E + "Kinds.test_what_is_a_caret"),
    ("edit", "edit.py", "if w <= CARET_MAX_PT[0] and ", "if ", E + "Kinds.test_what_is_a_caret"),
    ("edit", "edit.py", "h <= CARET_MAX_PT[1]:", "h <= 999:", E + "Kinds.test_what_is_a_caret"),
    ("edit", "edit.py", "    if box and soft < SOFT_MIN:", "    if box:", E + "Kinds.test_what_is_a_caret"),
    ("edit", "edit.py", '        kinds[0] = "change"', "        pass",
     E + "Kinds.test_bursts_are_split_by_a_rest"),
    ("edit", "edit.py", 'f["pts"] - out[-1].end < rest_ticks', 'f["pts"] - out[-1].end <= rest_ticks',
     E + "Kinds.test_bursts_are_split_by_a_rest"),
    ("edit", "edit.py", "bisect.bisect_right(pts, instant)", "bisect.bisect_left(pts, instant)",
     E + "Kinds.test_frame_hold"),
    ("edit", "edit.py", "loc.down = b.start - lead", "loc.down = b.start",
     E + "Locate.test_touch_downs_and_responses_are_found_from_the_data"),
    ("edit", "edit.py", "loc.down = b.start - round(_slop_time_ms(path) * T / 1000)", "loc.down = b.start",
     E + "Locate.test_touch_downs_and_responses_are_found_from_the_data"),
    ("edit", "edit.py", "loc.last_change = max(p for p in changes if loc.first_change <= p < limit)",
     "loc.last_change = loc.burst_end", E + "Locate.test_touch_downs_and_responses_are_found_from_the_data"),
    ("edit", "edit.py", "first_tail_change if first_tail_change is not None else math.inf)", "math.inf)",
     E + "Locate.test_what_follows_the_film_is_not_part_of_the_last_response"),
    ("edit", "edit.py", "abs(b.start - near) <= tol and b.index > used", "b.index > used",
     E + "Locate.test_a_gesture_with_no_change_near_it_is_refused"),
    ("edit", "edit.py", "n = math.ceil((g.last_change + tail - a) / step) + 1",
     "n = math.ceil((g.last_change - a) / step) + 1", E + "Propose.test_the_film_is_rests_and_whole_responses"),
    ("edit", "edit.py", "        if ranges and a < ranges[-1][\"out\"]:", "        if False:",
     E + "Propose.test_responses_that_touch_are_one_piece"),
    ("edit", "edit.py", '"take": dict(scan.get("take", {})),', '"take": scan.get("take", {}),',
     E + "Refusals.test_an_edit_list_for_another_take_is_refused"),
    ("edit", "edit.py", "if not any(s.src_in <= g.down and g.last_change <= s.last for s in live):",
     "if not any(g.last_change <= s.last for s in live):", E + "Refusals.test_trimming_the_touch_down_is_refused"),
    ("edit", "edit.py", "if not any(s.src_in <= g.down and g.last_change <= s.last for s in live):",
     "if not any(s.src_in <= g.down and g.last_change < s.src_out for s in live):",
     E + "Refusals.test_ending_a_response_one_frame_early_is_refused"),
    ("edit", "edit.py", "if not any(s.src_in <= g.down and g.last_change <= s.last for s in live):",
     "if not any(s.first <= g.down and g.last_change <= sp[-1].last for s in sp):",
     E + "Refusals.test_a_cut_between_a_touch_down_and_the_end_of_the_response_is_refused"),
    ("edit", "edit.py", "        if out and s.first - out[-1][1] <= step:", "        if out:",
     E + "Refusals.test_a_cut_over_a_change_outside_any_response_is_refused"),
    ("edit", "edit.py", "        if first - tail < p <= first:", "        if first < p <= first:",
     E + "Refusals.test_starting_while_the_screen_still_changes_is_refused"),
    ("edit", "edit.py", 'if frame_kind(d, tm.px_per_pt) == "change":', 'if frame_kind(d, tm.px_per_pt) == "never":',
     E + "Refusals.test_a_cut_between_two_different_pictures_is_refused"),
    ("edit", "edit.py", "if total != want or not 15 * fps <= total <= 30 * fps:", "if total != want:",
     E + "Refusals.test_the_wrong_length_is_refused"),
    ("edit", "edit.py", "if total != want or not 15 * fps <= total <= 30 * fps:",
     "if not 15 * fps <= total <= 30 * fps:", E + "Refusals.test_the_wrong_length_is_refused"),
    ("edit", "edit.py", 'if final.kind != "hold" or edit.get("final_hold_from") != final.film_in:',
     'if final.kind != "hold":', E + "Refusals.test_a_short_or_missing_final_hold_is_refused"),
    ("edit", "edit.py", 'b["frame"] < a["frame"] + fade:', 'b["frame"] < a["frame"]:',
     E + "Refusals.test_captions_out_of_order_or_overlapping_are_refused"),
    ("edit", "edit.py", "    if not settled <= poster < total:", "    if not settled <= poster:",
     E + "Refusals.test_the_poster_frame_is_the_storyboards_and_falls_on_a_settled_screen"),
    ("edit", "edit.py", "    settled = max([final.film_in, caps[-1][\"frame\"] + fade]",
     "    settled = max([caps[-1][\"frame\"] + fade]",
     E + "Refusals.test_the_poster_frame_is_the_storyboards_and_falls_on_a_settled_screen"),
    ("edit", "edit.py", "    settled = max([final.film_in, caps[-1][\"frame\"] + fade]", "    settled = max([final.film_in]",
     E + "Refusals.test_the_poster_frame_waits_for_the_last_caption"),
    ("edit", "edit.py", "                  + [math.ceil(t[\"up\"] / step) + out_frames for t in mine])", "                  )",
     E + "Refusals.test_the_poster_frame_waits_for_the_last_touch_point"),
    ("edit", "edit.py", "            if set(seg) != LIVE_KEYS:", "            if not LIVE_KEYS <= set(seg):",
     E + "Refusals.test_a_speed_cannot_be_written"),

    ("frames", "frames.py", "self.s = s = self.W / STILLS_WIDTH", "self.s = s = self.W / (STILLS_WIDTH + 1)",
     F + "Frame.test_the_layout_is_the_stills_table_times_886_over_1320"),
    ("frames", "frames.py", "canvas.paste(card, (lay.card_x, lay.card_y), self.mask)",
     "canvas.paste(card, (lay.card_x, lay.card_y))", F + "Frame.test_a_film_frame_is_the_stills_frame"),
    ("frames", "frames.py", "        canvas.paste(self.border, (lay.card_x, lay.card_y), self.ring)\n", "",
     F + "Frame.test_a_film_frame_is_the_stills_frame"),
    ("frames", "frames.py", 'fill=c["textSecondary"], anchor="ma")', 'fill=c["textPrimary"], anchor="ma")',
     F + "Frame.test_a_film_frame_is_the_stills_frame"),
    ("frames", "frames.py", "layer = layer.filter(ImageFilter.GaussianBlur(blur * lay.s / 2))",
     "layer = layer.filter(ImageFilter.GaussianBlur(blur * lay.s))", F + "Frame.test_a_film_frame_is_the_stills_frame"),
    ("frames", "frames.py", "        if self.text_bottom(caption) >= lay.card_y:", "        if False:",
     F + "Guards.test_a_caption_that_reaches_the_capture_stops_the_tool"),
    ("frames", "frames.py", "        if _drawn(font, ch) == missing:", "        if False:",
     F + "Frame.test_a_character_the_font_lacks_stops_the_tool"),
    ("frames", "frames.py", 'return Image.fromarray(np.rint(a + (b - a) * k).astype(np.uint8), "RGB")',
     "return self.under(after)", F + "CrossFade.test_the_ends_are_the_two_captions_and_the_middle_is_between"),
    ("frames", "frames.py", "k = self._fade.at((n - since) / self.fps)",
     "k = min(1.0, (n - since) / self._fade.frames(self.fps))",
     F + "CrossFade.test_progress_follows_the_token_by_time"),
    ("frames", "frames.py", "alpha = self._in.at((t - down) / timescale)", "alpha = 1.0",
     F + "Touch.test_a_tap_fades_in_holds_and_fades_out_by_the_tokens"),
    ("frames", "frames.py", "alpha *= 1 - self._out.at((t - up) / timescale)", "alpha *= 1.0",
     F + "Touch.test_a_tap_fades_in_holds_and_fades_out_by_the_tokens"),
    ("frames", "frames.py", "x, y = xa + (xb - xa) * u, ya + (yb - ya) * u", "x, y = xb, yb",
     F + "Touch.test_a_drag_follows_the_finger_one_to_one"),
    ("frames", "frames.py", 'colour = self.c["secondary"] if tone == "light" else self.c["primary"]',
     'colour = self.c["primary"]', F + "Touch.test_light_on_a_dark_or_green_fill"),
    ("frames", "frames.py", 'return "light" if luminance < self.sb["touch"]["light_below_luminance"] else "dark"',
     'return "dark"', F + "Touch.test_light_on_a_dark_or_green_fill"),
    ("frames", "frames.py", 'd.ellipse(box, fill=round(255 * t["fill_opacity"] * alpha))',
     'd.ellipse(box, fill=round(255 * t["ring_opacity"] * alpha))',
     F + "Touch.test_the_disc_is_the_brand_black_at_low_opacity_with_a_ring"),
    ("frames", "frames.py",
     'd.ellipse(box, outline=round(255 * t["ring_opacity"] * alpha), width=max(1, round(ring_w * ss)))\n', "\n",
     F + "Touch.test_the_disc_is_the_brand_black_at_low_opacity_with_a_ring"),

    ("brand", "brand.py", '"easeOut": (0.0, 0.0, 0.58, 1.0),', '"easeOut": (0.0, 0.0, 0.6, 1.0),',
     B + "Curves.test_the_table_is_flutters_own"),   # needs the Flutter SDK on the machine
    ("brand", "brand.py", "if abs(t - estimate) < _CUBIC_ERROR_BOUND:", "if abs(t - estimate) < 0.2:",
     B + "Curves.test_every_curve_matches_the_bezier_it_names"),
    ("brand", "brand.py", "return cubic(CUBICS[self.curve], elapsed_s / self.seconds)",
     "return min(1.0, elapsed_s / self.seconds)", B + "Curves.test_progress_is_evaluated_by_time"),
    ("brand", "brand.py", 'COLOUR_TOKENS = stills.TOKENS + ("primary", "secondary")',
     'COLOUR_TOKENS = stills.TOKENS + ("primary",)', B + "Colours.test_the_real_file_has_them_all"),
    ("brand", "../app_store_screenshots/compose.py", "    for name in names:\n", "    for name in TOKENS:\n",
     B + "Colours.test_the_seven_tokens_come_from_colors_dart"),

    ("mp4", "mp4.py", 'out["width"] = out["coded_width"] - sub_w * (left + right)',
     'out["width"] = out["coded_width"]', P + "Sps.test_the_film_s_own_parameter_set"),
    ("mp4", "mp4.py", "if zeros >= 2 and byte == 3:", "if False:",
     P + "Sps.test_emulation_prevention_bytes_are_removed"),
    ("mp4", "mp4.py", 'out["frame_mbs_only_flag"] = frame_mbs_only', 'out["frame_mbs_only_flag"] = 1',
     P + "Sps.test_interlaced_is_read_as_interlaced"),
    ("mp4", "mp4.py", 'out["audio_object_type"] = aot', 'out["audio_object_type"] = 2',
     P + "Esds.test_other_configurations_are_told_apart"),

    ("verify", "verify.py", "PROFILE_HIGH, LEVEL_4_0 = 100, 40", "PROFILE_HIGH, LEVEL_4_0 = 100, 41",
     V + "test_the_wrong_level"),
    ("verify", "verify.py", "psnr >= POSTER_MIN_PSNR and block <= POSTER_MAX_BLOCK", "psnr >= POSTER_MIN_PSNR",
     V + "test_a_touch_point_left_on_the_poster"),
    ("verify", "verify.py", '            "tkhd": (v.get("tkhd_width"), v.get("tkhd_height")),\n', "",
     V + "test_a_header_that_claims_another_size"),
    ("verify", "verify.py", '            "stsd": (entry.get("width"), entry.get("height")),\n', "",
     V + "test_a_header_that_claims_another_size"),
    ("verify", "verify.py", "MIN_S <= seconds <= MAX_S and seconds == film[\"duration_s\"] and plain",
     "MIN_S <= seconds <= MAX_S and plain", V + "test_14_9_seconds"),
    ("verify", "verify.py", "and decoded.get(\"frames\") == round(seconds * AUDIO_RATE),", ",",
     V + "test_sound_at_44_1_khz"),
    ("verify", "verify.py", 'out: dict = {"ok": r.returncode == 0 and "Movie analyzed with 0 error" in text, "tracks": []}',
     'out: dict = {"ok": True, "tracks": []}', V + "test_something_that_is_not_a_movie"),
    ("verify", "preview.py", "    print(text, end=\"\")\n    if not ok:\n        sys.exit(1)\n", "    print(text, end=\"\")\n",
     V + "test_the_command_exits_non_zero_on_a_miss"),

    ("swift", "swift/Encode.swift", "guard names.count >= 15 * Int(fps), names.count <= 30 * Int(fps) else {",
     "guard names.count >= 1 else {", X + "test_a_film_under_15_s_or_over_30_s"),
    ("swift", "swift/Encode.swift",
     "manifest[\"width\"] as? Int == spec.width, manifest[\"height\"] as? Int == spec.height",
     "manifest[\"width\"] as? Int != nil", X + "test_another_frame_rate_or_size"),
    ("swift", "swift/Encode.swift", "    unfinished.append(outPath)\n", "", X + "test_another_frame_rate_or_size"),
    ("swift", "swift/Writer.swift", "        guard w == width, h == height else {", "        guard w > 0, h > 0 else {",
     X + "test_a_picture_of_another_size"),
    ("swift", "swift/Writer.swift", "  unfinished.append(outPath)\n", "",
     X + "test_a_test_clip_that_fails_leaves_nothing_either"),
    ("swift", "swift/Inspect.swift", "for v in data where abs(Int(v)) > peak { peak = abs(Int(v)) }", "_ = data",
     V + "test_sound_that_is_not_silence"),

    # the slow ones: each recompiles a helper and runs the end-to-end build
    ("e2e", "preview.py", "    diffs = checked(edit, scan, log, sb, a.take, out)\n", "    diffs = {}\n",
     E2E + ".Build.test_a_hand_written_cut_inside_a_response_stops_the_build"),
    ("e2e", "preview.py", '    clear(out, ("preview*.mp4", "verify.txt", "poster.png", "poster-decoded.png", '
                          '"contact-sheet.png",\n                "edit.json", "cuts.txt"))\n', "    out.mkdir(parents=True, exist_ok=True)\n",
     E2E + ".Build.test_a_hand_written_cut_inside_a_response_stops_the_build"),
    ("e2e", "preview.py", "    if not ok:\n        sys.exit(1)\n\n\ndef cmd_scan", "\n\ndef cmd_scan",
     E2E + ".Build.test_a_film_that_fails_a_check_fails_the_build"),
    ("e2e", "preview.py", '    if bool(edit.get("rehearsal")) != bool(a.rehearsal):\n'
                          '        die("the edit list and --rehearsal disagree")\n', "",
     E2E + ".Build.test_a_rehearsal_s_edit_list_cannot_make_the_film"),
    ("e2e", "preview.py", '        die(f"cannot propose an edit list {e}")', "        edit = {}",
     E2E + ".Build.test_a_gesture_the_take_does_not_show_stops_the_build"),
    ("e2e", "swift/Writer.swift", "profileLevel: AVVideoProfileLevelH264High40, averageBitRate: 11_000_000,",
     "profileLevel: AVVideoProfileLevelH264High41, averageBitRate: 11_000_000,", E2E),
    ("e2e", "swift/Writer.swift", "    audio: AudioSpec())", "    audio: nil)", E2E),
    ("e2e", "swift/Writer.swift",
     "keyFrameInterval: 30, expectedFrameRate: 30, frameReordering: false, maxFrameQP: 10,",
     "keyFrameInterval: 30, expectedFrameRate: 30, frameReordering: true, maxFrameQP: 10,", E2E),
    ("e2e", "swift/Conform.swift", "if pts[mid] * den <= num * timescale {", "if pts[mid] * den < num * timescale {",
     E2E),
    ("e2e", "swift/Conform.swift", "              c.strong += 1\n", "", E2E + ".Scan"),
    ("e2e", "swift/Conform.swift", "    var row = compare(a, b, soft: lv.soft, strong: lv.strong).json",
     "    var row = compare(a, a, soft: lv.soft, strong: lv.strong).json",
     E2E + ".Build.test_the_two_sides_of_a_cut_are_compared_on_the_decoded_frames"),
    ("e2e", "frames.py", "                tones[touch[\"gesture\"]] = composer.tone(card_for(j), touch[\"path\"][0][1], touch[\"path\"][0][2])",
     "                tones[touch[\"gesture\"]] = \"light\"",
     E2E + ".Build.test_the_touch_point_is_on_the_frames_it_should_be"),
    ("e2e", "frames.py", "                    composer.draw_touch(card, x, y, alpha, tone)", "                    pass",
     E2E + ".Build.test_the_touch_point_is_on_the_frames_it_should_be"),
]


def clean() -> bool:
    r = subprocess.run(["git", "status", "--porcelain", "--", "tool/app_store_preview", "tool/app_store_screenshots"],
                       cwd=ROOT, capture_output=True, text=True)
    return r.returncode == 0 and not r.stdout.strip()


def red(tests: list[str]) -> tuple[bool, str]:
    """True when the tests fail (or cannot even run): the mutation was seen."""
    r = subprocess.run([sys.executable, "-m", "unittest", *tests], cwd=TOOL, capture_output=True, text=True)
    tail = (r.stderr.strip().splitlines() or [""])[-1]
    return r.returncode != 0, tail


def plan(groups: set[str]) -> list[dict]:
    out = []

    def want(group: str) -> bool:
        return not groups or group in groups

    for name, pattern, silent, expected, tests in SILENCED:
        text = (TOOL / name).read_text(encoding="utf-8")
        spots = list(re.finditer(pattern, text))
        group = name.split(".")[0]
        if len(spots) != expected:
            out.append({"group": group, "error": f"{name}: {len(spots)} refusals, the table says {expected} — "
                                                 f"one was added or removed; watch it and correct the count"})
            continue
        for m in spots:
            line = text.count("\n", 0, m.start()) + 1
            what = text[m.start():text.index("\n", m.start())].strip()[:70]
            if want(group):
                out.append({"group": group, "file": name, "tests": tests,
                            "what": f"{name}:{line} silenced: {what}",
                            "mutate": (lambda t, m=m, silent=silent: t[:m.start()] + m.expand(silent) + t[m.end():])})

    text = (TOOL / "verify.py").read_text(encoding="utf-8")
    seen: dict[str, int] = {}
    names = re.findall(r'add\("([^"]+)",', text)
    for extra in sorted(set(names) - set(VERIFY_CHECKS)):
        out.append({"group": "verify", "error": f"verify.py: check `{extra}` is not in the table — watch it"})
    for name in names:
        if name not in VERIFY_CHECKS:
            continue
        k = seen.get(name, 0)
        seen[name] = k + 1
        tests = VERIFY_CHECKS[name]
        test = tests[k] if isinstance(tests, list) else tests
        anchor = f'add("{name}",'
        at = [m.start() for m in re.finditer(re.escape(anchor), text)][k]
        if want("verify"):
            out.append({"group": "verify", "file": "verify.py", "tests": [test],
                        "what": f"verify.py: check `{name}`" + (f" #{k + 1}" if isinstance(tests, list) else "")
                                + " always passes",
                        "mutate": (lambda t, at=at, anchor=anchor: t[:at] + anchor + " True or" + t[at + len(anchor):])})
    for name in sorted(set(VERIFY_CHECKS) - set(names)):
        out.append({"group": "verify", "error": f"verify.py has no check `{name}` any more"})

    for group, name, old, new, test in MANUAL:
        if not want(group):
            continue
        text = (TOOL / name).read_text(encoding="utf-8")
        if text.count(old) != 1:
            out.append({"group": group, "error": f"{name}: the anchor occurs {text.count(old)} times, not once: "
                                                 f"{old.strip()[:70]!r}"})
            continue
        out.append({"group": group, "file": name, "tests": [test],
                    "what": f"{name}: {old.strip()[:60]!r} -> {new.strip()[:40]!r}",
                    "mutate": (lambda t, old=old, new=new: t.replace(old, new))})
    return out


def main() -> None:
    args = sys.argv[1:]
    listing = "--list" in args
    groups = {a for a in args if not a.startswith("--")}
    steps = plan(groups)
    if listing:
        for s in steps:
            print(s.get("what") or "ERROR " + s["error"])
        print(f"{len(steps)} mutations")
        return
    if not clean():
        sys.exit("mutations: the tree has uncommitted changes under tool/ — commit first; undoing a mutation "
                 "would erase them")
    survived, errors = [], [s["error"] for s in steps if "error" in s]
    started = time.time()
    for n, s in enumerate([s for s in steps if "error" not in s], 1):
        path = TOOL / s["file"]
        original = path.read_text(encoding="utf-8")
        mutated = s["mutate"](original)
        if mutated == original:
            errors.append(f"{s['what']}: the mutation changes nothing")
            continue
        try:
            path.write_text(mutated, encoding="utf-8")
            failed, tail = red(s["tests"])
        finally:
            path.write_text(original, encoding="utf-8")
        print(f"{n:3d} {'red     ' if failed else 'SURVIVED'} {s['what']}  [{', '.join(s['tests'])}]  {tail[:60]}",
              flush=True)
        if not failed:
            survived.append(s["what"])
    if not clean():
        sys.exit("mutations: the tree is not clean after the run — a file was not restored")
    done = len([s for s in steps if "error" not in s])
    print(f"\n{done} mutations in {time.time() - started:.0f} s: {done - len(survived)} red, "
          f"{len(survived)} survived, {len(errors)} errors")
    for line in survived:
        print("  SURVIVED", line)
    for line in errors:
        print("  ERROR   ", line)
    sys.exit(1 if survived or errors else 0)


if __name__ == "__main__":
    main()
