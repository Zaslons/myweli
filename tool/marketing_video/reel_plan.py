"""The Reel's plan: the approved storyboard, in the numbers the frames are
drawn from. Design: docs/design/pro-marketing-reel.md.

`storyboard.json` (the owner-approved copy, minus `_ownerDecisions`) is the
film's single source for WHAT is on screen and WHEN. Read from it, never
typed here:

  - every word of the film: `scenes[].onScreenText`, by index;
  - every scene's start and end;
  - the film's size, rate and length, and its cut frames (`concept`);
  - the safe zone, the right-hand rail, the feed and grid crops and the
    cover frame (`rationale`, the scenes' prose, `hook`).

WHERE things sit and HOW they move is prose in the storyboard ("Poppins
Medium 92 px, line height 106, #FFFFFF, centred, block top y 316"). Those
numbers are transcribed below, once, and `ANCHORS` holds the storyboard's
own phrase for each of them: a storyboard that stops saying one of them is
refused, so the plan cannot silently drift from the approved film.

French typography: the storyboard asks for a narrow no-break space (U+202F)
before « ? » and « : » ("A U+202F narrow no-break space goes before « ? »");
its `onScreenText` lists carry plain spaces there. `typeset()` sets U+202F
— every width the storyboard states was measured with it (S1's 858 px, the
bubbles' 627, S6's « n° ? » at x 779–863).
"""

from __future__ import annotations

import json
import re
import sys
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
PREVIEW = ROOT / "tool/app_store_preview"
if str(PREVIEW) not in sys.path:
    sys.path.append(str(PREVIEW))

import brand  # noqa: E402  (tool/app_store_preview/brand.py — tokens, curves, the stills)

STORYBOARD = HERE / "storyboard.json"
POPPINS = brand.stills.POPPINS                     # tool/app_store_screenshots/fonts/Poppins-Medium.ttf
INTER = brand.stills.INTER                         # tool/app_store_screenshots/fonts/Inter-Variable.ttf
MARK_SVG = brand.stills.MARK_SVG                   # mobile/assets/brand/myweli_mark_black.svg
WORDMARK_SVG = ROOT / "mobile/assets/brand/myweli_wordmark_black.svg"
LOADER_FAST = ROOT / "mobile/assets/lottie/loader/myweli_mark_loader_fast.json"
PRO_OPEN = ROOT / "mobile/assets/lottie/open/myweli_loader_mixed_pro.json"
ICON_PRO = ROOT / "mobile/ios/Runner/Assets.xcassets/AppIcon-pro.appiconset/Icon-1024.png"
MOTION_DART = brand.MOTION_DART


def die(msg: str) -> None:
    print(f"reel: {msg}", file=sys.stderr)
    sys.exit(1)


def typeset(text: str) -> str:
    """The French narrow no-break space before « ? » and « : »."""
    return re.sub(r" ([?:;!])", " \\1", text)


# ---- colours ------------------------------------------------------------------
# App tokens are read from colors.dart (through the stills' reader); the
# storyboard's other greys are the brand book's (G700, the light pattern) or
# the film's own tone-on-tone ones, each quoted in ANCHORS.

APP_TOKENS = ("primary", "secondary", "surface", "textPrimary", "border", "borderStrong")


@lru_cache(maxsize=None)
def colours() -> dict[str, tuple[int, int, int]]:
    c = dict(brand.stills.tokens(APP_TOKENS))
    c.update({
        "g700": (0x3D, 0x3D, 0x3D),        # S2 tagline « #3D3D3D (G700) »
        "pattern": (0xED, 0xEE, 0xEF),     # S8 « mark outlines in #EDEEEF »
        "ruleMajor": (0x26, 0x26, 0x26),   # S1 « 2 px #262626 every 96 px »
        "ruleMinor": (0x14, 0x14, 0x14),   # S1 « 1 px #141414 every 24 px »
        "bubble": (0x1E, 0x1E, 0x1E),      # S4 « Fill #1E1E1E »
    })
    expect = {"primary": (0, 0, 0), "secondary": (255, 255, 255), "surface": (0xFA, 0xFA, 0xFA),
              "textPrimary": (0x1A, 0x1A, 0x1A), "border": (0xD0, 0xD0, 0xD0), "borderStrong": (0x8A, 0x8A, 0x8A)}
    for name, rgb in expect.items():
        if c[name] != rgb:
            die(f"colors.dart's `{name}` is now {c[name]}, the approved storyboard was drawn with {rgb} — "
                f"the film needs the owner's eye again before it is rebuilt")
    return c


# ---- motion -------------------------------------------------------------------

@lru_cache(maxsize=None)
def tokens() -> dict[str, brand.Motion]:
    return brand.motion_tokens()


def stagger_s() -> float:
    m = re.search(r"static const Duration stagger = Duration\(milliseconds: (\d+)\);",
                  MOTION_DART.read_text(encoding="utf-8"))
    if not m:
        die(f"no `stagger` token in {MOTION_DART}")
    return int(m.group(1)) / 1000


def exit_motion() -> brand.Motion:
    """« 200 ms easeIn (exits accelerate) »: `base`'s duration on the
    accelerating curve SYSTEM.md §9 pairs with exits."""
    return brand.Motion("exit", tokens()["base"].ms, "easeIn")


def stroke_curve(t: float) -> float:
    """« Every stroke draws by trim 0 → 100% on cubic (0.4, 0, 0.2, 1) »."""
    return brand.cubic(brand.CUBICS["fastOutSlowIn"], t)


def eased(curve: str, t: float) -> float:
    return brand.cubic(brand.CUBICS[curve], t)


# ---- the storyboard ---------------------------------------------------------------

SCENE_KEYS = ("S1", "S2", "S3", "S4", "S5", "S6", "S7", "S8")

# Phrases the transcribed numbers come from: (scene key or top-level key,
# field, phrase). Each must still be in the storyboard, verbatim.
ANCHORS = [
    ("concept", None, "The headline is Poppins Medium 84/96 px, #1A1A1A, centred in the column x 90–990, with the block at y 316–508"),
    ("concept", None, "A header band of paper covers y 0–552, then fades to transparent over y 552–600"),
    ("concept", None, "It is 900 px wide at x 90–990: scale 0.7463, which is 2.2388 px per pt. Radius 110, 3 px #D0D0D0 ring, the stills' shadows scaled to 1080 (0.10/blur 37/dy 25 and 0.05/blur 15/dy 10), 2× supersampled"),
    ("concept", None, "A camera window W (in screen points) places a screen point p at frame y = 600 + (p − W) × 2.2388 and x = 90 + pt × 2.2388"),
    ("S1", "visual", "Headline in Poppins Medium 92 px, line height 106, #FFFFFF, centred, block top y 316"),
    ("S1", "visual", "Notebook field** (y 600–1240, full width, feathered 80 px top and bottom)"),
    ("S1", "visual", "Major rules: 2 px #262626 every 96 px, on baselines 660 / 756 / 852 / 948 / 1044 / 1140"),
    ("S1", "visual", "Minor rules: 1 px #141414 every 24 px"),
    ("S1", "visual", "Margin rule: 2 px #262626 at x 150"),
    ("S1", "visual", "Inter Medium (Inter-Variable wght 500, opsz 14), 48 px, #FFFFFF at 85%, starting at x 180, on baselines 660–1044"),
    ("S1", "visual", "« → 11h » (127 px) sits at x 830 on baseline 852. « → 15h » (136 px) sits at x 830 on baseline 900"),
    ("S1", "visual", "#FAFAFA, 7 px, round caps, drawn through the x-height (baseline − 16)"),
    ("S1", "motion", "The headline settles from scale 1.02 to 1.00 over `fast` (frames 0–3)"),
    ("S1", "motion", "| 0.10 / 0.20 / 0.30 | 3 / 6 / 9 | Entries 3–5 pop: opacity 0 → 85% plus a 6 px rise, `fast` 100 ms easeOut |"),
    ("S1", "motion", "| 0.50–0.66 | 15–20 | Strike through « 10h  Aïcha — coupe femme » (x 180–804, y 836) |"),
    ("S1", "motion", "| 0.70 | 21 | « → 11h » pops (`fast`) |"),
    ("S1", "motion", "| 1.00–1.16 | 30–35 | « → 11h » is struck (x 830–957, y 836) |"),
    ("S1", "motion", "| 1.20 | 36 | « → 15h » pops (`fast`) |"),
    ("S1", "motion", "| 1.45–1.61 | | Strike through « 11h  Rokia — tresses » (x 180–642, y 932) |"),
    ("S1", "motion", "| 2.10–2.35 | 63–70 | One full-width #FAFAFA stroke, 8 px, round caps, draws left to right at y 836 from x 65 to x 1015 (250 ms) |"),
    ("S2", "visual", "220 px tall outside, scale 0.8499: stroke 24.5 px, x 476–604, y 470–690, centre (540, 580)"),
    ("S2", "visual", "The draw starts from the loader's start point, the middle of the right stem, at (591, 580)"),
    ("S2", "visual", "480 px wide and centred, top y 756"),
    ("S2", "visual", "« Plus de clients, moins de gestion. » in Poppins Medium 52 px, #3D3D3D (G700), one line of 862 px (x 109–971), line box at y 950–1014"),
    ("S2", "motion", "| 2.50–2.90 | 75–87 | The S1 stroke thickens from 8 px to 2400 px about y 836 (`slow` 400 ms easeInOutCubic)"),
    ("S2", "motion", "| 2.70–2.80 | | A pen dot pops at (591, 580): a #000 disc 24.5 px across"),
    ("S2", "motion", "| 2.80–3.40 | 84–102 | The mark draws out of the dot: trim end 0 → 100% over 0.6 s on (0.4, 0, 0.2, 1)"),
    ("S2", "motion", "| 3.15–3.45 | | Wordmark unit rises 16 px and fades in (`emphasis` 300 ms easeOutCubic) |"),
    ("S2", "motion", "| 3.20–3.50 | | Tagline rises 16 px and fades in (`emphasis`, 50 ms `stagger`) |"),
    ("S2", "motion", "| 6.00–6.20 | 180–186 | Mark, wordmark and tagline exit together: 40 px up plus a fade, 200 ms easeIn (exits accelerate)"),
    ("S3", "visual", "Phase A, W = 56."),
    ("S3", "visual", "Phase B, W = 350."),
    ("S3", "visual", "48 pt = 107 px, #000 at 12% fill with a 3.4 px ring at 45%"),
    ("S3", "motion", "| 6.00–6.30 | 180–189 | Card rises from top y 1920 to 600 (offset +1320 → 0, `emphasis` 300 ms easeOutCubic)"),
    ("S3", "motion", "| 6.20 / 6.25 | | Headline lines rise 24 px and fade in (`emphasis`, 50 ms `stagger`) |"),
    ("S3", "motion", "| 7.10–7.50 | 213–225 | Camera W 56 → 350 (`slow` 400 ms easeInOutCubic)"),
    ("S3", "motion", "| 7.50–7.60 | | Touch disc fades in at (336, 1039) (`fast`) |"),
    ("S3", "motion", "| 7.60–8.567 | 228–257 | LIVE, take1b 10.662–11.628 s (29 frames, 1:1). Touch-down lands at 7.61. The disc follows the logged drag from 110 to 250 pt (x 336 → 650), film 7.61–8.36"),
    ("S3", "motion", "| 8.567–10.00 | 257–300 | HOLD on take 11.595 s (43 frames): the pane stays open. The disc fades out over 8.57–8.77 (`base` 200 ms) |"),
    ("S4", "visual", "Poppins Medium 92 px, line height 106, #FFFFFF, centred, block top y 316"),
    ("S4", "visual", "Left-aligned at x 90. Fill #1E1E1E, radius 36, padding 28 px vertical and 36 px horizontal; each bubble is 116 px tall, with 24 px gaps"),
    ("S4", "visual", "Text: Inter Regular 48 px #FFFFFF"),
    ("S4", "visual", "Timestamp on the same baseline at the right of the text: Inter Regular 34 px in #8A8A8A"),
    ("S4", "visual", "| b1 | « C’est combien, les tresses ? » 22:41 | 614–730 |"),
    ("S4", "visual", "| b4 | « Allô ? » 23:02 | 1034–1150 |"),
    ("S4", "motion", "**10.30 / 10.60 / 10.90 (f309 / 318 / 327).** Bubbles 2, 3 and 4 arrive in the bottom slot: scale 0.96 → 1 plus a fade (`fast` 100 ms easeOut). At the same time the older bubbles move up one slot of 140 px (`base` 200 ms easeInOut)"),
    ("S4", "motion", "**11.90–12.15 (f357–364).** One full-width #FAFAFA 8 px stroke, round caps, draws left to right at y 952 through b3's text (250 ms, (0.4, 0, 0.2, 1))"),
    ("S5", "visual", "MASKED with rect_px [114, 1758, 546, 57] filled (255, 255, 255), applied in capture space before the camera transform"),
    ("S5", "visual", "The single frame at 30.000 s of build/app-store/pro/preview/v2/takes/take5b/take.mov"),
    ("S5", "motion", "| 12.50–12.90 | 375–387 | The S4 stroke thickens to 2400 px about y 952 (`slow`); the page becomes paper |"),
    ("S5", "motion", "| 12.75 / 12.80 | | Headline lines rise 24 px and fade in (`emphasis`, 50 ms `stagger`) |"),
    ("S5", "motion", "| 12.80–13.10 | 384–393 | Card enters from offset +1320 to rest at W = 100 (`emphasis`) |"),
    ("S5", "motion", "| 14.00–14.60 | 420–438 | Camera W 100 → 300: a camera move of 600 ms easeInOutCubic, not UI motion |"),
    ("S5", "motion", "| 15.50–16.10 | 465–483 | Camera W 300 → 470 (600 ms easeInOutCubic) |"),
    ("S6", "visual", "Entries in Inter Medium 48 px, white at 85%, x 180, baselines 660 / 756 / 852 / 948 / 1044"),
    ("S6", "visual", "The squeezed walk-in « + 14h45  coupe homme · n° ? » (663 px) sits at x 200 on the minor rule at baseline 804"),
    ("S6", "motion", "**17.60 / 17.70.** Entries 4 and 5 pop (opacity 0 → 85% plus a 6 px rise, `fast`)"),
    ("S6", "motion", "**17.95.** The squeezed entry pops: scale 0.96 → 1 plus a fade to 85% (`fast`)"),
    ("S6", "motion", "**18.45–18.61.** A short #FAFAFA 7 px strike through « n° ? » (x 779–863, y 788)"),
    ("S6", "motion", "**19.60–19.85 (f588–595).** One full-width #FAFAFA 8 px stroke draws left to right at y 788 through the squeezed line (250 ms, (0.4, 0, 0.2, 1))"),
    ("S7", "visual", "The « Libre » tap is a black disc (12% fill, 45% ring) at (381, 1093)"),
    ("S7", "visual", "The « Créer » tap is a WHITE disc, because it lands on a black button (the App Store film's dark-ground rule), at (540, 1225)"),
    ("S7", "visual", "take1b again (Conform.swift frame-hold), with the camera fixed at W = 553 for the whole scene"),
    ("S7", "motion", "| 20.00–20.40 | 600–612 | The S6 stroke thickens to 2400 px about y 788 (`slow`) |"),
    ("S7", "motion", "| 20.25 / 20.30 | | Headline lines rise 24 px and fade in (`emphasis`, 50 ms `stagger`) |"),
    ("S7", "motion", "| 20.30–20.60 | 609–618 | Card enters from offset +1320 to rest at W = 553 (`emphasis`), showing take1b at 32.165 s |"),
    ("S7", "motion", "| 20.60–21.00 | | Hold. The disc fades in at 20.90 (`fast`) |"),
    ("S7", "motion", "| 21.000–21.867 | 630–656 | LIVE, take1b 32.165–33.032 s (26 frames, 1:1). Tap on « Libre — 14:45 » at 21.00; « Réservation » pushes in 21.20–21.52; the disc fades out from 21.30 (`base`) |"),
    ("S7", "motion", "| 21.867–22.200 | 656–666 | HOLD on take 32.998 s (10 frames) |"),
    ("S7", "motion", "| 22.200–22.367 | 666–671 | DECLARED DISSOLVE (`base`, 5 frames) to take 130.262 s."),
    ("S7", "motion", "| 22.367–23.300 | 671–699 | HOLD on the filled form (28 frames). The white disc fades in at 23.20 (`fast`) |"),
    ("S7", "motion", "| 23.300–25.233 | 699–757 | LIVE, take1b 130.262–132.195 s (58 frames, 1:1). Touch-down on « Créer » at 23.30"),
    ("S7", "motion", "The disc fades out over 23.60–23.80."),
    ("S7", "motion", "| 25.233–26.300 | 757–789 | HOLD on take 132.162 s (32 frames)"),
    ("S7", "motion", "| 26.30–26.50 | 789–795 | Exit: the card drops 120 px and fades, and the headline fades (200 ms easeIn) |"),
    ("S8", "visual", "mark outlines in #EDEEEF, 72 px tall, 120 px column pitch, 132 px row pitch, alternate rows offset 60 px"),
    ("S8", "visual", "The pattern is kept out of a clear zone at x 140–940, y 380–1180, with an 80 px feather"),
    ("S8", "visual", "280×280 at x 400–680, y 450–730: a continuous-corner square (radius about 63 px), fill #FAFAFA, 2 px #D0D0D0 hairline, stills shadow at half strength"),
    ("S8", "visual", "The draw starts from the mid right stem at (582, 590)"),
    ("S8", "visual", "The same « MyWeli Pro » unit as S2: 560 px wide, centred, y 826–912"),
    ("S8", "visual", "A black #000 full-radius pill, 680×110, at x 200–880, y 1000–1110"),
    ("S8", "visual", "« Disponible sur l’App Store » in Inter SemiBold (wght 600) 46 px, #FFFFFF, 570 px wide"),
    ("S8", "motion", "**26.50–26.70 (f795–801).** The pattern fades in (`base`), then drifts up 12 px/s, linear, until the end"),
    ("S8", "motion", "**26.55–26.65.** The pen dot pops at (582, 590) (`fast`)"),
    ("S8", "motion", "**26.60–27.20 (f798–816).** The mark draws out of the dot"),
    ("S8", "motion", "**27.15–27.45.** The tile's fill edge, hairline and shadow fade in around the mark (`emphasis`)"),
    ("S8", "motion", "**27.25–27.55.** The wordmark rises 16 px and fades in (`emphasis`)"),
    ("S8", "motion", "**27.40–27.70.** The CTA pill rises 24 px and fades in (`emphasis`)"),
]


@dataclass(frozen=True)
class Scene:
    key: str
    id: str
    start: float
    end: float
    texts: tuple[str, ...]     # onScreenText, as the storyboard lists it

    def text(self, i: int) -> str:
        """Word `i` of the scene, typeset (U+202F before « ? » and « : »)."""
        return typeset(self.texts[i])


class Plan:
    """What the storyboard says, read once."""

    def __init__(self, sb: dict, source: Path | None = None):
        self.sb = sb
        self.source = source
        concept = sb["concept"]
        m = re.search(r"Spec: (\d+)×(\d+), (\d+) fps, (\d+) frames", concept)
        if not m:
            die("the storyboard's concept does not give « Spec: W×H, N fps, N frames »")
        self.width, self.height, self.fps, self.frames = map(int, m.groups())
        self.size = (self.width, self.height)
        self.duration = self.frames / self.fps
        m = re.search(r"Every cut sits on a 0\.5 s grid \(frames ([\d, ]+)\)", concept)
        if not m:
            die("the storyboard's concept does not list its cut frames")
        self.cuts = [int(v) for v in m.group(1).split(",")]

        self.scenes: dict[str, Scene] = {}
        for s in sb["scenes"]:
            key = s["id"].split("-")[0]
            if key not in SCENE_KEYS:
                die(f"unknown scene id {s['id']!r}")
            self.scenes[key] = Scene(key, s["id"], float(s["start"]), float(s["end"]), tuple(s["onScreenText"]))
        if list(self.scenes) != list(SCENE_KEYS):
            die(f"the storyboard's scenes are {list(self.scenes)}, the plan draws {list(SCENE_KEYS)}")
        starts = [round(self.scenes[k].start * self.fps) for k in SCENE_KEYS[1:]]
        if starts != self.cuts:
            die(f"the scenes start on frames {starts}, the concept's cuts are {self.cuts}")
        for a, b in zip(SCENE_KEYS, SCENE_KEYS[1:]):
            if self.scenes[a].end != self.scenes[b].start:
                die(f"{a} ends at {self.scenes[a].end}, {b} starts at {self.scenes[b].start}")
        if self.scenes["S1"].start != 0 or self.scenes["S8"].end != self.duration:
            die("the scenes do not cover the film from 0 to its length")
        if any(c % (self.fps // 2) for c in self.cuts):
            die(f"a cut is off the 0.5 s grid: {self.cuts}")

        m = re.search(r"all film text sits inside x (\d+)–(\d+) and y (\d+)–(\d+)", sb["rationale"])
        if not m:
            die("the storyboard's rationale does not state the safe zone (« all film text sits inside x …–… and y …–… »)")
        self.safe = tuple(int(v) for v in m.groups())            # x0, x1, y0, y1
        m = re.search(r"right-hand button rail \(which starts at y (\d+)\)", self.scene_field("S2", "visual"))
        m2 = re.search(r"The button's right end \(x > (\d+)\) sits under the like/comment rail", self.scene_field("S7", "visual"))
        if not m or not m2:
            die("the storyboard no longer says where the right-hand rail is (S2 and S7 visuals)")
        self.rail = (int(m2.group(1)), int(m.group(1)))          # x from, y from
        m = re.search(r"4:5 feed crop \(y (\d+)–(\d+)\) and the 3:4 grid crop \(y (\d+)–(\d+)\)", sb["hook"])
        if not m:
            die("the storyboard's hook does not state the 4:5 and 3:4 crops")
        self.crop_feed = (int(m.group(1)), int(m.group(2)))
        self.crop_grid = (int(m.group(3)), int(m.group(4)))
        m = re.search(r"The cover is frame (\d+) \(([\d.]+) s\)", sb["hook"])
        if not m:
            die("the storyboard's hook does not name its cover frame")
        self.cover_frame = int(m.group(1))

        for where, field, phrase in ANCHORS:
            hay = sb[where] if where in sb else self.scene_field(where, field)
            if phrase not in hay:
                die(f"the storyboard no longer says, in {where}{'.' + field if field else ''}: « {phrase} » — "
                    f"the plan transcribes that number; change both together")

    def scene_field(self, key: str, field: str) -> str:
        for s in self.sb["scenes"]:
            if s["id"].split("-")[0] == key:
                return s[field]
        die(f"no scene {key}")

    def scene_at(self, n: int) -> str:
        t = n / self.fps
        for k in SCENE_KEYS:
            if self.scenes[k].start <= t < self.scenes[k].end:
                return k
        die(f"frame {n} is outside the film")


def load(path: Path = STORYBOARD) -> Plan:
    sb = json.loads(path.read_text(encoding="utf-8"))
    if "_ownerDecisions" in sb:
        die(f"{path} carries `_ownerDecisions`: the tool's storyboard is the approved copy without them")
    return Plan(sb, path)


# ---- layout, transcribed (each number quoted in ANCHORS) ----------------------------

PX_PER_PT = 900 / 402            # « 2.2388 px per pt »: a 402-pt screen in a 900-px card

ANSWER = {
    "head_px": 84, "head_lh": 96, "head_top": 316, "column": (90, 990),
    "band_solid": 552, "band_clear": 600,
    "card_x": 90, "card_w": 900, "card_top_pt": 56, "rest_y": 600,
    "radius": 110, "ring": 3, "shadows": [(0.10, 37, 25), (0.05, 15, 10)],
    "screen_pt": (402, 874), "capture": (1206, 2622),
}

PAIN = {"head_px": 92, "head_lh": 106, "head_top": 316, "settle_from": 1.02}

NOTEBOOK = {
    "top": 600, "bottom": 1240, "feather": 80,
    "major": [660, 756, 852, 948, 1044, 1140], "major_w": 2, "minor_step": 24, "minor_w": 1,
    "margin_x": 150, "margin_w": 2,
    "entry_x": 180, "entry_px": 48, "entry_wght": 500, "entry_alpha": 0.85,
    "pop_rise": 6, "strike_w": 7, "strike_above_baseline": 16, "stroke_w": 8, "stroke_x": (65, 1015),
}

S1 = {
    "baselines": [660, 756, 852, 948, 1044],
    "pops": {2: 0.10, 3: 0.20, 4: 0.30},           # entries 3–5 (0-based 2–4)
    "arrows": [(830, 852, 0.70), (830, 900, 1.20)],
    "strikes": [((180, 804), 836, 0.50, 0.66), ((830, 957), 836, 1.00, 1.16), ((180, 642), 932, 1.45, 1.61)],
    "full": (836, 2.10, 2.35),
    "widths": [424, 510, 624, 462, 614],            # « Widths: 424 / 510 / 624 / 462 / 614 px »
    "head_widths": [547, 858],                      # « The two lines measure 547 px and 858 px »
}

S2 = {
    "thicken": (836, 2.50, 2.90, 8, 2400),
    "mark_centre": (540, 580), "mark_h": 220, "dot": (2.70, 2.80), "draw": 2.80,
    "unit_w": 480, "unit_top": 756, "unit_in": 3.15, "rise": 16,
    "tag_px": 52, "tag_box": (950, 1014), "tag_in": 3.20, "tag_width": 862,
    "exit": 6.00, "exit_rise": 40,
}

S3 = {
    "W": (56, 350), "move": (7.10, "slow"), "enter": 6.00, "head_in": 6.20,
    "head_widths": [589, 700],
    "disc_in": 7.50, "disc_out": 8.57, "drag_shift_s": 7.0,   # the App Store film's S1 drag, 7.0 s later
    "live": (7.60, 6397, 6977), "hold_before": 6397, "hold_after": 6957,
}

S4 = {
    "bubble_x": 90, "bubble_h": 116, "radius": 36, "pad_v": 28, "pad_h": 36, "gap": 24, "ts_gap": 24,
    "text_px": 48, "ts_px": 34, "slots": [614, 754, 894, 1034], "arrive": [10.00, 10.30, 10.60, 10.90],
    "stroke": (952, 11.90, 12.15), "head_widths": [846, 516],
}

S5 = {
    "thicken": (952, 12.50, 12.90, 8, 2400), "head_in": 12.75, "enter": 12.80,
    "W": [(100, None), (300, (14.00, 14.60)), (470, (15.50, 16.10))], "camera_curve": "easeInOutCubic",
    "take_s": 18000,                                  # 30.000 s, in the take's ticks (600 a second)
    "mask": [114, 1758, 546, 57], "mask_fill": (255, 255, 255),
    "head_widths": [884, 828],
}

S6 = {
    "baselines": [660, 756, 852, 948, 1044], "pops": {3: 17.60, 4: 17.70},
    "squeezed": (200, 804, 17.95), "strike": ((779, 863), 788, 18.45, 18.61), "full": (788, 19.60, 19.85),
    "widths": [553, 477, 672, 680, 441], "squeezed_width": 663, "head_widths": [402, 894],
}

S7 = {
    "thicken": (788, 20.00, 20.40, 8, 2400), "head_in": 20.25, "enter": 20.30, "W": 553,
    "head_widths": [836, 877],
    # film frame ranges → the take's ticks (600 a second); « take1b … » in S7's motion table
    "runs": [("hold", 609, 629, 19299), ("live", 630, 655, 19299), ("hold", 656, 665, 19799),
             ("dissolve", 666, 670, (19799, 78157)), ("hold", 671, 698, 78157),
             ("live", 699, 756, 78157), ("hold", 757, 794, 79297)],
    "taps": [((381, 1093), "primary", 20.90, 21.30), ((540, 1225), "secondary", 23.20, 23.60)],
    "exit": 26.30, "exit_drop": 120,
}

S8 = {
    "pattern_h": 72, "pattern_pitch": (120, 132), "pattern_shift": 60, "pattern_drift": 12.0,
    "pattern_in": 26.50, "clear": (140, 940, 380, 1180), "feather": 80,
    "tile": (400, 450, 280), "tile_radius": 63, "tile_hairline": 2, "shadow_strength": 0.5,
    "icon_box_of_1024": ((319, 704), (178, 845)),
    "dot": (26.55, 26.65), "draw": 26.60, "tile_in": 27.15,
    "unit_w": 560, "unit_top": 826, "unit_in": 27.25, "rise": 16,
    "pill": (200, 1000, 880, 1110), "cta_px": 46, "cta_wght": 600, "cta_in": 27.40, "cta_rise": 24, "cta_width": 570,
}

TOUCH = {"diameter": 107, "fill": 0.12, "ring": 3.4, "ring_alpha": 0.45}

# The three takes' frame-hold ranges, in ticks — the App Store film's verified
# cuts (build/app-store/pro/preview/v2/final/cuts.txt S1 and S2) — and the
# seconds the storyboard prints for them (to the millisecond).
TAKE1B_TICKS = {6397: 10.662, 6977: 11.628, 6957: 11.595, 19299: 32.165, 19819: 33.032,
                19799: 32.998, 78157: 130.262, 79317: 132.195, 79297: 132.162}
