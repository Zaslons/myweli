#!/usr/bin/env python3
"""Watch every check go red.

A check that has never been seen to fail is not a check. This script breaks
the tool one check at a time — silences a refusal, makes a verification
always pass, bends a number — and requires a named test to fail each time.

    python3 tool/app_store_preview/tests/mutations.py            # all, ~20 min
    python3 tool/app_store_preview/tests/mutations.py edit       # one group
    python3 tool/app_store_preview/tests/mutations.py e2e --match=Writer.swift
    python3 tool/app_store_preview/tests/mutations.py --list

Groups: edit, frames, track, brand, mp4, verify, cli, swift, e2e.

What this cannot see. The refusals of edit.py, frames.py and brand.py are
counted, and verify.py's checks are matched by name, so one added there
without a watch is an error. The Swift helpers, track.py and preview.py are
not counted: a new guard there is watched only if someone adds a line to
MANUAL.
Known to be unwatched today, because no file was found that makes them
fire: conform's « frames out of order », « frame size changed inside the
take », « two samples share the presentation time », the exact-tick
conversion, and the compile failure in swifttools.py.

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
    ("edit.py", r"raise Refusal\(", "Refusal(", 59, ["tests.test_edit"]),
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
C = "tests.test_cli."
K = "tests.test_track."
E2E = "tests.test_e2e"
MANUAL = [
    # group, file, exactly this text (once), becomes, the test that must fail
    ("edit", "edit.py", "STRONG_MIN = 4 ", "STRONG_MIN = 6 ", E + "Kinds.test_what_is_a_change"),
    ("edit", "edit.py", "SOFT_MIN = 2000 ", "SOFT_MIN = 2001 ", E + "Kinds.test_what_is_a_change"),
    # what a caret is
    ("edit", "edit.py", "CARET_MAX_PT = (3.0, 34.0)", "CARET_MAX_PT = (6.0, 34.0)", E + "Kinds.test_what_is_a_caret"),
    ("edit", "edit.py", "CARET_MAX_PT = (3.0, 34.0)", "CARET_MAX_PT = (3.0, 99.0)", E + "Kinds.test_what_is_a_caret"),
    ("edit", "edit.py", "CARET_MIN_HEIGHT_PT = 10.0", "CARET_MIN_HEIGHT_PT = 0.0", E + "Kinds.test_what_is_a_caret"),
    ("edit", "edit.py", "CARET_MIN_HEIGHT_PT = 10.0", "CARET_MIN_HEIGHT_PT = 0.0",
     E + "Kinds.test_small_changes_inside_the_last_burst_are_not_a_caret"),
    ("edit", "edit.py", "CARET_SLACK_PT = 1.0", "CARET_SLACK_PT = 0.0", E + "Kinds.test_what_is_a_caret"),
    ("edit", "edit.py", "CARET_SLACK_PT = 1.0", "CARET_SLACK_PT = 5.0", E + "Kinds.test_what_is_a_caret"),
    ("edit", "edit.py", "            if _caret_sized(_union(column, box), px_per_pt):", "            if True:",
     E + "Kinds.test_what_is_a_caret"),
    ("edit", "edit.py", "_caret_shaped(box, px_per_pt) and _inside(box, area, px_per_pt):",
     "_caret_shaped(box, px_per_pt):", E + "Kinds.test_what_is_a_caret"),
    ("edit", "edit.py", "_caret_shaped(box, px_per_pt) and _inside(box, area, px_per_pt):",
     "_inside(box, area, px_per_pt):", E + "Kinds.test_what_is_a_caret"),
    ("edit", "edit.py", "    if box and soft < SOFT_MIN and _caret_sized(box, px_per_pt):",
     "    if box and _caret_sized(box, px_per_pt):", E + "Kinds.test_what_is_a_caret"),
    ("edit", "edit.py", "        if column is not None:\n            if _caret_sized(",
     "        if column is not None and area is None:\n            if _caret_sized(", E + "Kinds.test_what_is_a_caret"),
    ("edit", "edit.py", "            column = ahead(i)\n", "            column = None\n", E + "Kinds.test_the_apps_own_caret"),
    ("edit", "edit.py", "            column = found[since] = _union(column, f[\"box\"])",
     "            column = found[since] = column", E + "Kinds.test_the_apps_own_caret"),
    ("edit", "edit.py", "            if not caret_sized(f):\n                return None", "            if not caret_sized(f):\n                continue",
     E + "Kinds.test_a_fragment_is_only_the_caret_of_its_own_stretch"),
    ("edit", "edit.py", "            if _caret_shaped(f[\"box\"], px_per_pt) and _inside(f[\"box\"], area, px_per_pt):\n                return f[\"box\"]",
     "            if _caret_shaped(f[\"box\"], px_per_pt):\n                return f[\"box\"]",
     E + "Kinds.test_a_caret_shape_where_nothing_changed_is_a_change_the_first_time"),
    ("edit", "edit.py", "        column, area = None, burst\n", "        area = burst\n",
     E + "Kinds.test_a_caret_that_turns_up_somewhere_new_is_a_change"),
    ("edit", "edit.py", "        joins = burst is not None and f[\"pts\"] - last_change < rest_ticks",
     "        joins = burst is not None and f[\"pts\"] - last_change <= rest_ticks",
     E + "Kinds.test_the_area_a_caret_may_appear_in_is_the_whole_burst"),
    ("edit", "edit.py", "        joins = burst is not None and f[\"pts\"] - last_change < rest_ticks", "        joins = False",
     E + "Kinds.test_the_area_a_caret_may_appear_in_is_the_whole_burst"),
    ("edit", "edit.py", "        box = f.get(\"box\") or whole ", "        box = f.get(\"box\") or [0, 0, 0, 0] ",
     E + "Kinds.test_the_area_a_caret_may_appear_in_is_the_whole_burst"),
    ("edit", "edit.py", '            kinds[0], last_change = "change", f["pts"]', '            kinds[0], last_change = "quiet", f["pts"]',
     E + "Kinds.test_bursts_are_split_by_a_rest"),
    ("edit", "edit.py", 'f["pts"] - out[-1].end < rest_ticks', 'f["pts"] - out[-1].end <= rest_ticks',
     E + "Kinds.test_bursts_are_split_by_a_rest"),
    ("edit", "edit.py", "bisect.bisect_right(pts, instant)", "bisect.bisect_left(pts, instant)",
     E + "Kinds.test_frame_hold"),
    ("edit", "edit.py", "loc.down = b.start - tap_lead", "loc.down = b.start",
     E + "Locate.test_touch_downs_and_responses_are_found_from_the_data"),
    ("edit", "edit.py", "loc.down = b.start - tap_lead", "loc.down = b.start - lead",
     E + "Locate.test_a_tap_point_appears_before_the_answer_and_leaves_after_it"),
    ("edit", "edit.py", "loc.up = b.start + tap_dwell", "loc.up = b.start",
     E + "Locate.test_touch_downs_and_responses_are_found_from_the_data"),
    ("edit", "edit.py", "    if tap_lead < lead:", "    if False:",
     E + "Locate.test_a_tap_point_appears_before_the_answer_and_leaves_after_it"),
    ("edit", "edit.py", "cands = [b for b in bursts if lo <= b.start <= hi and b.index > used]",
     "cands = [b for b in bursts if lo <= b.start <= hi]",
     E + "Locate.test_the_drivers_own_times_find_the_first_change_in_between"),
    ("edit", "edit.py", "cands = [b for b in bursts if lo <= b.start <= hi and b.index > used]",
     "cands = [b for b in bursts if lo < b.start <= hi and b.index > used]",
     E + "Locate.test_the_drivers_own_times_find_the_first_change_in_between"),
    ("edit", "edit.py", "cands = [b for b in bursts if lo <= b.start <= hi and b.index > used]",
     "cands = [b for b in bursts if lo <= b.start and b.index > used]",
     E + "Locate.test_the_drivers_own_times_find_the_first_change_in_between"),
    ("edit", "edit.py", "        return cands[0]      # what follows", "        return cands[-1]      # what follows",
     E + "Locate.test_the_drivers_own_times_find_the_first_change_in_between"),
    # typed keys
    ("edit", "edit.py", 'pid = gid if len(pieces) == 1 else f"{gid}[{n}]"', "pid = gid",
     E + "Keys.test_each_key_is_found_on_its_own"),
    ("edit", "edit.py", "b.index, b.start, b.start - lead, b.start, b.end,", "b.index, b.start, b.start, b.start, b.end,",
     E + "Keys.test_each_key_is_found_on_its_own"),
    ("edit", "edit.py", "                          last=n == len(pieces))", "                          last=True)",
     E + "Keys.test_the_waits_between_keys_are_cut_and_nothing_else"),
    ("edit", "edit.py", '            if g is r["gestures"][-1] and g.last:', '            if g is r["gestures"][-1]:',
     E + "Keys.test_the_waits_between_keys_are_cut_and_nothing_else"),
    ("edit", "edit.py", 'g = [x for x in tm.gestures if x.gesture == after["gesture"]][-1]',
     'g = [x for x in tm.gestures if x.gesture == after["gesture"]][0]',
     E + "Keys.test_the_waits_between_keys_are_cut_and_nothing_else"),
    ("edit", "edit.py", "        keys = g.get(\"keys\") if kind == \"type\" else None", "        keys = None",
     E + "Keys.test_each_key_is_found_on_its_own"),
    # a drag followed in the picture
    ("edit", "edit.py", "FOLLOW_MIN_PT = 0.5 ", "FOLLOW_MIN_PT = 5.0 ", E + "Follow.test_a_picture_that_gives_nothing_to_go_by"),
    ("edit", "edit.py", "FOLLOW_OVER_PT = 2.0 ", "FOLLOW_OVER_PT = 0.0 ",
     E + "Follow.test_a_picture_that_goes_further_than_the_finger_is_on_its_own"),
    ("edit", "edit.py", "        if s > reach + FOLLOW_OVER_PT or (seen and s < seen[-1][1]):",
     "        if seen and s < seen[-1][1]:", E + "Follow.test_a_picture_that_goes_further_than_the_finger_is_on_its_own"),
    ("edit", "edit.py", "        if s > reach + FOLLOW_OVER_PT or (seen and s < seen[-1][1]):",
     "        if s > reach + FOLLOW_OVER_PT:", E + "Follow.test_a_picture_that_dips_is_followed_no_further"),
    ("edit", "edit.py", "        seen.append((pts, min(s, reach)))", "        seen.append((pts, s))",
     E + "Follow.test_a_picture_that_goes_further_than_the_finger_is_on_its_own"),
    ("edit", "edit.py", "        if s >= top:\n            break\n", "",
     E + "Follow.test_the_point_is_where_the_log_has_the_finger_when_the_picture_is_that_far"),
    ("edit", "edit.py", "    if len(seen) < 2 or seen[-1][1] <= seen[0][1]:", "    if not seen:",
     E + "Follow.test_a_picture_that_gives_nothing_to_go_by"),
    ("edit", "edit.py", "    if any(b < a - 0.01 for a, b in zip(dist, dist[1:])):", "    if False:",
     E + "Follow.test_a_picture_that_gives_nothing_to_go_by"),
    ("edit", "edit.py", "[[seen[0][0] - (first - p[2]) * tick, p[0], p[1]] for p in path if p[2] < first]", "[]",
     E + "Follow.test_the_point_is_where_the_log_has_the_finger_when_the_picture_is_that_far"),
    ("edit", "edit.py", "    points += [[float(pts), *where(when(s))] for pts, s in seen]",
     "    points += [[float(pts), *where(when(s) + 16)] for pts, s in seen]",
     E + "Follow.test_between_two_logged_samples_the_point_is_between_them"),
    ("edit", "edit.py", "        t = seen[-1][0] + (p[2] - last) * tick", "        t = seen[-1][0] + p[2] * tick",
     E + "Follow.test_the_point_is_where_the_log_has_the_finger_when_the_picture_is_that_far"),
    ("edit", "edit.py", "        if turn is not None and t > turn:", "        if False:",
     E + "Follow.test_the_finger_has_left_when_the_picture_turns_back"),
    ("edit", "edit.py", '    axis = 0 if track.get("axis") == "x" else 1', "    axis = 0", E + "Follow.test_an_upward_drag"),
    ("edit", "edit.py", '    sign = track.get("sign", 1)', "    sign = 1", E + "Follow.test_an_upward_drag"),
    ("edit", "edit.py", 'seen_path = followed_path(path, track, T) if track and "down_s" not in g else None',
     "seen_path = followed_path(path, track, T) if track else None",
     E + "Follow.test_a_logged_touch_down_wins_over_the_picture"),
    ("edit", "edit.py", 'loc.down = min(math.floor(seen_path["down"]), b.start - lead)',
     'loc.down = math.floor(seen_path["down"])', E + "Follow.test_a_followed_drag_is_placed_by_its_frames"),
    ("edit", "edit.py", 'loc.down = min(math.floor(seen_path["down"]), b.start - lead)', "loc.down = b.start - lead",
     E + "Follow.test_a_log_that_starts_before_the_fade_in_keeps_its_own_start"),
    ("edit", "edit.py", "                    loc.step = list(seen_path[\"step\"])\n", "",
     E + "Follow.test_a_followed_drag_is_placed_by_its_frames"),
    ("edit", "edit.py", "        if g.step:\n", "        if False:\n", E + "Follow.test_a_followed_drag_is_placed_by_its_frames"),
    ("edit", "edit.py", 'touch["step"] = [down + (t - g.down) for t in g.step]', 'touch["step"] = list(g.step)',
     E + "Follow.test_a_followed_drag_is_placed_by_its_frames"),
    # the storyboard's variants
    ("edit", "edit.py", '    sb = {k: v for k, v in doc.items() if k != "variants"}', "    sb = dict(doc)",
     E + "Variants.test_the_film_itself_carries_no_variant"),
    ("edit", "edit.py", "        sb[key] = {**doc[key], **over.get(key, {})}", "        sb[key] = doc[key]",
     E + "Variants.test_a_variant_gives_its_shots_and_lays_its_numbers_over_the_films"),
    ("edit", "edit.py", "        sb[key] = {**doc[key], **over.get(key, {})}", "        sb[key] = over.get(key, doc[key])",
     E + "Variants.test_a_variant_gives_its_shots_and_lays_its_numbers_over_the_films"),
    ("edit", "edit.py", '        sb["shots"] = over["shots"]', "        pass",
     E + "Variants.test_a_variant_gives_its_shots_and_lays_its_numbers_over_the_films"),
    ("edit", "edit.py", '    sb["variant"] = variant\n', "",
     E + "Variants.test_a_variant_gives_its_shots_and_lays_its_numbers_over_the_films"),
    ("edit", "edit.py", 'over = {k: v for k, v in variants[variant].items() if not k.startswith("_")}',
     "over = dict(variants[variant])", E + "Variants.test_a_variant_gives_its_shots_and_lays_its_numbers_over_the_films"),
    ("edit", "edit.py", '        "variant": sb.get("variant"),\n', '        "variant": None,\n',
     E + "Variants.test_an_edit_list_cannot_cross_between_the_film_and_a_variant"),
    ("edit", "edit.py", '    if edit.get("variant") != sb.get("variant"):', "    if False:",
     E + "Variants.test_an_edit_list_cannot_cross_between_the_film_and_a_variant"),
    ("edit", "edit.py", '    if sb.get("variant") and not rehearsal:', "    if False:",
     E + "Variants.test_a_variants_edit_list_cannot_say_it_is_the_film"),
    ("edit", "edit.py", '    if sb.get("variant"):\n        w(f"REHEARSAL', '    if False:\n        w(f"REHEARSAL',
     E + "Variants.test_the_log_says_which_variant"),
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
    ("edit", "edit.py", 'if pair_kind(d, tm, b) == "change":', 'if pair_kind(d, tm, b) == "never":',
     E + "Refusals.test_a_cut_between_two_different_pictures_is_refused"),
    ("edit", "edit.py", "return frame_kind(d, tm.px_per_pt, r.columns[frame], r.areas[frame]) if r else",
     "return frame_kind(d, tm.px_per_pt, None, r.areas[frame]) if r else",
     E + "Keys.test_the_waits_between_keys_are_cut_and_nothing_else"),
    ("edit", "edit.py", "return frame_kind(d, tm.px_per_pt, r.columns[frame], r.areas[frame]) if r else",
     "return frame_kind(d, tm.px_per_pt, r.columns[frame], None) if r else",
     E + "Keys.test_a_cut_may_skip_a_caret_that_never_passed_the_thresholds"),
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
    ("edit", "edit.py", "list(zip(frames, tm.kinds))[1:] if k", "list(zip(frames, tm.kinds)) if k",
     E + "Describe.test_every_cut_is_logged_with_what_it_removes_and_where_it_lands"),

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
    ("frames", "frames.py", "                if held_from <= ta and tb <= held_to:", "                if False:",
     F + "Touch.test_a_drag_followed_in_the_picture_holds_with_each_frame"),
    ("frames", "frames.py", "                if held_from <= ta and tb <= held_to:", "                if True:",
     F + "Touch.test_a_drag_followed_in_the_picture_holds_with_each_frame"),
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

    ("track", "track.py", "PATCH_PT = (60.0, 24.0) ", "PATCH_PT = (600.0, 240.0) ",
     K + "Follow.test_the_patch_is_the_content_around_the_finger_and_no_more"),
    ("track", "track.py", "MIN_TEXTURE = 6.0 ", "MIN_TEXTURE = 0.0 ",
     K + "Follow.test_nothing_to_recognise_is_said_not_guessed"),
    ("track", "track.py", "MAX_ERROR = 6.0 ", "MAX_ERROR = 600.0 ",
     K + "Follow.test_what_is_no_longer_in_the_picture_is_lost_and_what_came_before_is_kept"),
    ("track", "track.py", "BEYOND_PT = 40.0 ", "BEYOND_PT = 0.0 ",
     K + "Follow.test_it_is_looked_for_a_little_past_the_end_of_the_logged_path"),
    ("track", "track.py", "TURN_PT = 1.0 ", "TURN_PT = 0.0 ", K + "Turned.test_the_first_frame_clearly_behind_the_furthest"),
    ("track", "track.py", "MAX_SECONDS = 3.0 ", "MAX_SECONDS = 300.0 ",
     K + "ReadDrags.test_a_drag_is_looked_at_for_three_seconds_and_no_longer"),
    ("track", "track.py", 'f["pts"] <= min(burst.end, burst.start + MAX_SECONDS * T)]', 'f["pts"] <= burst.start + MAX_SECONDS * T]',
     K + "ReadDrags.test_each_drag_is_read_on_the_frames_of_its_own_burst"),
    ("track", "track.py", '            dx, dy = (sign * s, 0) if axis == "x" else (0, sign * s)',
     '            dx, dy = (s, 0) if axis == "x" else (0, s)', K + "Follow.test_the_other_way_and_the_other_axis"),
    ("track", "track.py", '            dx, dy = (sign * s, 0) if axis == "x" else (0, sign * s)',
     "            dx, dy = (sign * s, 0)", K + "Follow.test_the_other_way_and_the_other_axis"),
    ("track", "track.py", "        if best is None or best[0] > MAX_ERROR:\n            return out,",
     "        if best is None:\n            return out,",
     K + "Follow.test_what_is_no_longer_in_the_picture_is_lost_and_what_came_before_is_kept"),
    ("track", "track.py", "    if patch.size == 0 or float(patch.std()) < MIN_TEXTURE:", "    if patch.size == 0:",
     K + "Follow.test_nothing_to_recognise_is_said_not_guessed"),
    ("track", "track.py", '        axis = "x" if abs(dx) >= abs(dy) else "y"', '        axis = "y"',
     K + "ReadDrags.test_the_axis_and_the_way_come_from_the_logged_path"),
    ("track", "track.py", '        sign = 1 if (dx if axis == "x" else dy) >= 0 else -1', "        sign = -1",
     K + "ReadDrags.test_the_axis_and_the_way_come_from_the_logged_path"),
    ("track", "track.py", "        ref = editlist.held(tm.pts, burst.start - 1)", "        ref = editlist.held(tm.pts, burst.start)",
     K + "ReadDrags.test_each_drag_is_read_on_the_frames_of_its_own_burst"),
    ("track", "track.py", '                  if k == "change" and burst.start <= f["pts"]', '                  if burst.start <= f["pts"]',
     K + "ReadDrags.test_each_drag_is_read_on_the_frames_of_its_own_burst"),
    ("track", "track.py", '        entry["turn"] = turned(entry["frames"])\n', "",
     K + "ReadDrags.test_each_drag_is_read_on_the_frames_of_its_own_burst"),
    ("track", "track.py", '        if g.kind != "drag":\n            continue\n', "",
     K + "ReadDrags.test_a_take_with_no_drag_asks_for_no_picture"),
    ("track", "track.py", '        with tempfile.TemporaryDirectory(prefix="follow-", dir=work) as tmp:\n            folder = Path(tmp)\n',
     '        if True:\n            folder = Path(tempfile.mkdtemp(prefix="follow-", dir=work))\n',
     K + "ReadDrags.test_each_drag_is_read_on_the_frames_of_its_own_burst"),

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
    ("mp4", "mp4.py", "    except (struct.error, IndexError, ValueError) as e:", "    except (ValueError,) as e:",
     V + "test_a_file_whose_headers_are_cut_or_hollow"),
    ("mp4", "mp4.py", "        if size < head or pos + size > end:", "        if size < head:",
     V + "test_a_file_cut_short"),
    ("mp4", "mp4.py", "    if nal[0] & 0x1F != 7:", "    if False:", P + "Sps.test_something_that_is_not_an_sps_is_refused"),
    ("mp4", "mp4.py", "    if tag != 0x03:", "    if False:",
     P + "Esds.test_a_payload_without_one_of_its_three_descriptors_is_refused"),
    ("mp4", "mp4.py", "    if tag != 0x04:", "    if False:",
     P + "Esds.test_a_payload_without_one_of_its_three_descriptors_is_refused"),
    ("mp4", "mp4.py", "    if tag != 0x05:", "    if False:",
     P + "Esds.test_a_payload_without_one_of_its_three_descriptors_is_refused"),

    ("frames", "storyboard.json", "Une cliente arrive" + chr(92) + "u202f?", "Une cliente arrive" + chr(0x202F) + "?",
     F + "Storyboard.test_the_file_has_no_invisible_character"),
    ("frames", "frames.py", "        if abs(raw_size[0] * device_points[1] - raw_size[1] * device_points[0]) > 0.001 * raw_size[1] * device_points[0]:",
     "        if False:", F + "Guards.test_a_capture_that_is_not_the_logged_screen_stops_the_tool"),

    ("cli", "swifttools.py", '["xcrun", "swiftc", "-O", "-parse-as-library", *map(str, sources), "-o", str(out)],',
     '["ffmpeg", "swiftc", "-O", "-parse-as-library", *map(str, sources), "-o", str(out)],',
     C + "WhatTheToolDoesNotDo.test_only_what_is_already_on_the_mac_is_started"),
    ("cli", "swifttools.py", '["xcrun", "swiftc", "-O", "-parse-as-library", *map(str, sources), "-o", str(out)],',
     '["ffmpeg", "swiftc", "-O", "-parse-as-library", *map(str, sources), "-o", str(out)],',
     C + "WhatTheToolDoesNotDo.test_no_installer_and_no_ffmpeg_in_the_sources"),
    ("cli", "preview.py", "sys.exit(0 if result.wasSuccessful() and result.testsRun else 1)",
     "sys.exit(0 if result.wasSuccessful() else 1)", C + "Command.test_a_self_test_that_runs_no_test_is_a_failure"),
    ("cli", "preview.py", '    if not a.take.exists():\n        die(f"no such take: {a.take}")\n', "",
     C + "Command.test_a_take_that_is_not_there_stops_the_build"),
    ("cli", "preview.py", '    except (OSError, ValueError) as e:\n        die(f"cannot read {path}: {e}")',
     '    except OSError as e:\n        die(f"cannot read {path}: {e}")',
     C + "Command.test_a_gesture_log_that_cannot_be_read_stops_the_build"),

    ("verify", "verify.py", "PROFILE_HIGH, LEVEL_4_0 = 100, 40", "PROFILE_HIGH, LEVEL_4_0 = 100, 41",
     V + "test_the_wrong_level"),
    ("verify", "verify.py", "psnr >= POSTER_MIN_PSNR and block <= POSTER_MAX_BLOCK", "psnr >= POSTER_MIN_PSNR",
     V + "test_a_touch_point_left_on_the_poster"),
    # Not here, on purpose: dropping the box reader's own `tkhd` or `stsd`
    # size from the `size` check. Both were tried and both survive — a header
    # that claims 887 is read by AVFoundation and avmediainfo from the same
    # bytes, so they refuse it too. The three readings cannot be made to
    # disagree on a header field; the check as a whole is watched above.
    ("verify", "verify.py", "MIN_S <= seconds <= MAX_S and seconds == film[\"duration_s\"] and plain",
     "MIN_S <= seconds <= MAX_S and plain", V + "test_a_length_apple_takes_but_the_storyboard_does_not_say"),
    ("verify", "verify.py", "MIN_S <= seconds <= MAX_S and seconds == film[\"duration_s\"] and plain",
     "seconds == film[\"duration_s\"] and plain", V + "test_a_length_the_storyboard_says_but_apple_does_not_take"),
    ("verify", "verify.py", "MIN_S <= seconds <= MAX_S and seconds == film[\"duration_s\"] and plain",
     "MIN_S <= seconds <= MAX_S and seconds == film[\"duration_s\"]", V + "test_reordered_frames"),
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
    ("swift", "swift/Encode.swift", 'guard outPath.hasSuffix(".mp4") else { die("the output must be a .mp4") }', "",
     X + "test_an_output_that_is_not_an_mp4_is_refused_and_left_alone"),
    ("swift", "swift/Common.swift", '    for k in flags.keys where !used.contains(k) { die("unknown flag --\\(k)") }', "",
     X + "test_there_is_nothing_to_configure"),
    ("swift", "swift/Conform.swift", "      guard ((b - a) * Int64(fps)) % scale == 0 else {", "      guard true else {",
     C + "Conform.test_a_range_that_is_not_whole_frames"),
    ("swift", "swift/Conform.swift", '      guard b > a else { die("segment \\(n): src_out is not after src_in") }', "",
     C + "Conform.test_a_range_that_ends_before_it_starts"),
    ("swift", "swift/Conform.swift", '      guard count > 0 else { die("segment \\(n): a hold needs at least one frame") }', "",
     C + "Conform.test_a_hold_of_no_frames_and_a_kind_it_does_not_know"),
    ("swift", "swift/Conform.swift", "  guard 0 <= soft, soft < strong, strong <= 254 else {", "  guard true else {",
     C + "Conform.test_levels_the_wrong_way_round"),
    ("swift", "swift/Conform.swift", "  for p in raw where p.count != 2 || p[0] < 0 || p[1] < p[0] {", "  for p in raw where p.count != 2 {",
     C + "Conform.test_a_pair_of_frames_the_take_does_not_have_or_in_the_wrong_order"),
    ("swift", "swift/Conform.swift", "          if d > soft {", "          if d > soft + 400 {",
     C + "Conform.test_what_it_does_do_on_the_same_take"),
    ("swift", "swift/Conform.swift", "    if pts[mid] * den <= num * timescale {", "    if pts[mid] * den < num * timescale {",
     C + "Conform.test_what_it_does_do_on_the_same_take"),

    # the slow ones: each recompiles a helper and runs the end-to-end build
    ("e2e", "preview.py", "    diffs = checked(edit, scan, log, sb, a.take, out, tracks)\n", "    diffs = {}\n",
     E2E + ".Build.test_a_hand_written_cut_inside_a_response_stops_the_build"),
    ("e2e", "preview.py", '    clear(out, ("preview*.mp4", "verify.txt", "poster.png", "poster-decoded.png", '
                          '"contact-sheet.png",\n                "edit.json", "cuts.txt", "track.json"))\n',
     "    out.mkdir(parents=True, exist_ok=True)\n",
     E2E + ".Build.test_a_hand_written_cut_inside_a_response_stops_the_build"),
    ("e2e", "preview.py", "    if not ok:\n        sys.exit(1)\n\n\ndef cmd_scan", "\n\ndef cmd_scan",
     E2E + ".Build.test_a_film_that_fails_a_check_fails_the_build"),
    ("e2e", "preview.py", '    if bool(edit.get("rehearsal")) != rehearsal:\n'
                          '        die("the edit list and --rehearsal disagree")\n', "",
     E2E + ".Build.test_a_rehearsal_s_edit_list_cannot_make_the_film"),
    ("e2e", "preview.py", '        die(f"cannot propose an edit list {e}")', "        edit = {}",
     E2E + ".Build.test_a_take_longer_than_the_storyboard_allows_stops_the_build"),
    ("e2e", "preview.py", '        die(f"cannot find the gestures in the take {e}")', "        tracks = {}",
     E2E + ".Build.test_a_gesture_the_take_does_not_show_stops_the_build"),
    ("e2e", "preview.py", "        tracks = tracking.read_drags(a.take, scan, log, sb, out, rehearsal)", "        tracks = {}",
     E2E + ".Build.test_the_drag_is_followed_in_the_picture"),
    ("e2e", "preview.py", "editlist.propose(scan, log, sb, rehearsal, tracks)", "editlist.propose(scan, log, sb, rehearsal)",
     E2E + ".Build.test_the_drag_is_followed_in_the_picture"),
    ("e2e", "preview.py", '    rehearsal = bool(a.rehearsal or sb.get("variant"))', "    rehearsal = bool(a.rehearsal)",
     E2E + ".Variant.test_it_is_built_as_a_rehearsal_and_says_so_everywhere"),
    ("e2e", "preview.py", '    name = "preview-rehearsal.mp4" if rehearsal else "preview.mp4"', '    name = "preview.mp4"',
     E2E + ".Variant.test_it_is_built_as_a_rehearsal_and_says_so_everywhere"),
    ("e2e", "preview.py", "    note = rehearsal_note(sb, log) if rehearsal else \"\"", "    note = \"\"",
     E2E + ".Variant.test_it_is_built_as_a_rehearsal_and_says_so_everywhere"),
    ("e2e", "preview.py", '    elif "rehearsal" in a.movie.name:', "    elif False:",
     E2E + ".Variant.test_the_checker_says_rehearsal_when_it_is_told_the_variant_or_reads_the_name"),
    ("e2e", "preview.py", "    if sb.get(\"variant\"):\n        note = rehearsal_note(sb)\n", "    if False:\n        note = rehearsal_note(sb)\n",
     E2E + ".Variant.test_the_checker_says_rehearsal_when_it_is_told_the_variant_or_reads_the_name"),
    ("e2e", "preview.py", "    tracks = load(a.tracks) if a.tracks else None", "    tracks = None",
     E2E + ".Build.test_the_check_command_needs_the_reading_of_the_picture_the_edit_list_was_made_with"),
    ("e2e", "preview.py", "        return editlist.storyboard(load(a.storyboard), getattr(a, \"variant\", None))",
     "        return editlist.storyboard(load(a.storyboard), None)",
     E2E + ".Variant.test_a_variant_the_storyboard_does_not_have_stops_the_build"),
    # Not here, on purpose: the `step` of frames.py (a followed drag's point
    # holds with each frame). It was tried and survives the end-to-end test:
    # the synthetic take has a frame every 1/60 s, so every film frame falls
    # exactly on one, where holding and moving agree. tests.test_frames sees
    # it (two rows above, group `frames`), on a path whose frames are uneven.
    ("e2e", "track.py", "        ref = editlist.held(tm.pts, burst.start - 1)", "        ref = editlist.held(tm.pts, burst.start)",
     E2E + ".Build.test_the_drag_is_followed_in_the_picture"),
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
    lines = [line.strip() for line in r.stderr.strip().splitlines()] or [""]
    # when the end-to-end build itself stops, its own last word says why
    why = next((line for line in reversed(lines) if line.startswith(("FAIL —", "preview:"))), lines[-1])
    return r.returncode != 0, why


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
    match = [a.split("=", 1)[1] for a in args if a.startswith("--match=")]
    steps = [s for s in plan(groups) if "error" in s or all(m in s["what"] for m in match)]
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
        print(f"{n:3d} {'red     ' if failed else 'SURVIVED'} {s['what']}  [{', '.join(s['tests'])}]  {tail[:90]}",
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
