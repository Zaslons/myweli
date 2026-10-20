"""storyboard.yaml — the one source of the promo — loaded and checked.

The document has exactly five top-level keys (plus any ``x-…`` key, which
only holds a YAML anchor for values shared below it, and is not read):

  meta     title, fps, bpm, key, sample_rate. Checked strictly: the time base
           must be the contract's (30 fps, 112.5 BPM, 48 kHz — promo/timebase.py),
           because every module counts 16 frames a beat.
  cuts     one entry per cut (``30s``, ``15s``): its number of bars and frames.
           Positions inside a cut are relative to its start, so every cut is
           bars 1…n. A cut runs the whole bars its name holds plus at most
           ONE (the owner's outro bar, 2026-10-19: 30s = 14 + 1, 15s = 7 + 1).
  formats  one entry per output format (``9x16``, ``1x1``, ``16x9``): canvas,
           safe area, working zones and layout rules. Checked strictly — the
           geometry too (zones inside the canvas, text inside the safe area,
           the same pixel sizes in every format, the mark's clear space).
           ONE format is the ``reference: true`` (9x16): the format the
           scenes' camera W values are measured in; every other format
           re-lays them out by each key's ``keep`` (storyboard « 1:1 and
           16:9 »: « camera rules are written as where the active element
           sits inside the phone window »). Everything else a scene places —
           captions, the counter, lifts, the hook's page, the map credit —
           comes from the format's ``layout``: no scene carries a pixel
           position of its own.
  music    AUDIO's section. The cue ids have ONE source: the scores.
           ``music.scores`` maps each cut to its score (AUDIO's
           ``promo/audio/score_<cut>.yaml``, a path from tool/promo_reel):
           the score is the music, and its ``cues[].id`` are the cut's cue
           ids. ``music.cues`` may declare more inline (a list of ``{id: …}``,
           or a mapping cut → such a list) — the tests' small storyboards do.
  scenes   SCENES' section: a mapping cut → that cut's list of scenes (or a
           plain list). Every cue it refers to must be one of the cut's cues
           (or, for a plain list, of any cut). A reference is the value of a
           key named ``cue`` (one id) or ``cues`` (a list of ids), or any
           string written ``cue:<id>`` (optionally ``+N``/``-N`` frames, or
           ``@end`` for a span's end), at any depth.

Variants: ``--set path.to.key=value`` overrides one value before the document
is checked, so a variant is held to the same rules. The value is read as YAML
(``--set meta.title="Test"``, ``--set formats.9x16.safe=[120,270,900,1248]``);
list items are addressed by index (``--set scenes.0.id=hook``). Every key on
the path must exist except the last, which may be added.

Every problem found is reported at once, each with its path in the document.
"""

from __future__ import annotations

import copy
import re
from dataclasses import dataclass, field
from fractions import Fraction
from pathlib import Path
from typing import Any, Iterable, Iterator, NamedTuple, Sequence

import yaml

from . import timebase as tb

PROMO_REEL = Path(__file__).resolve().parents[1]
DEFAULT_PATH = PROMO_REEL / "storyboard.yaml"

TOP_LEVEL = ("meta", "cuts", "formats", "music", "scenes")
#: Top-level keys starting with this only hold YAML anchors for shared values.
EXTENSION_PREFIX = "x-"

#: The device the takes were recorded on: 402 × 874 points (iPhone 17 Pro,
#: ``device_points`` in every gesture log). The phone's screen in every format
#: shows its full width.
DEVICE_WIDTH_PT = 402.0

#: Zones that hold something to read or see (text, demonstrated UI, lifts):
#: they must lie inside the safe area (or the caption extension above the
#: platforms' button rail). The phone window may run past the safe area's
#: BOTTOM — app pixels only, never text — when the format says why
#: (`phone_window_note`: the owner's 9:16 floor, 2026-10-19).
CONTENT_ZONES = ("captions", "hook_block", "phone_window", "overlays", "slot_card")
#: Type roles a format may set larger than the reference's (`type_note` says
#: why: the owner's 16:9 « larger captions », 2026-10-19) — the column's words
#: and the counter; the end card's lockup (tagline, store line) and the credit
#: keep one size everywhere.
CAPTION_TYPE_ROLES = ("hook", "app", "counter", "counter_label")
PHONE_ANCHORS = (None, "floor")
#: Zones of the stage itself (bands, fades, the floor): anywhere on the canvas.
STAGE_ZONES = ("caption_band", "caption_fade", "top_fade", "floor_fade", "floor")
REQUIRED_ZONES = ("captions", "phone_window")

SAFE_BASES = ("platform", "ebu_r95_graphics")
EBU_R95_GRAPHICS_INSET = Fraction(5, 100)
TYPE_ROLES = ("hook", "app", "counter", "counter_label", "tagline", "store", "site", "credit")
#: The smallest type a viewer must READ (the end card's « Sur l’App Store et
#: Google Play » and « myweli.com »); the map credit is attribution, not a message.
MIN_READ_PX = 40
#: The type roles held to MIN_READ_PX: the end card's lines under the tagline.
READ_ROLES = ("store", "site")
KEY_RE = re.compile(r"^[A-G](?:#|b|♯|♭)? (?:major|minor)$")
CUT_RE = re.compile(r"^([1-9][0-9]*)s$")
FORMAT_RE = re.compile(r"^([1-9][0-9]*)x([1-9][0-9]*)$")
SHORT_SIDE_PX = 1080


class StoryboardError(ValueError):
    """The storyboard (or a variant of it) breaks the schema. ``problems``
    lists every one found, each starting with its path in the document."""

    def __init__(self, source: str, problems: Sequence[str]):
        self.source, self.problems = source, list(problems)
        lines = "\n".join(f"  - {p}" for p in self.problems)
        n = len(self.problems)
        super().__init__(f"{source}: {n} problem{'s' if n != 1 else ''}:\n{lines}")


class Rect(NamedTuple):
    """An axis-aligned rectangle in pixels: x0, y0 (inclusive) to x1, y1."""

    x0: float
    y0: float
    x1: float
    y1: float

    @property
    def width(self) -> float:
        return self.x1 - self.x0

    @property
    def height(self) -> float:
        return self.y1 - self.y0

    def contains(self, other: "Rect") -> bool:
        return (self.x0 <= other.x0 and self.y0 <= other.y0
                and other.x1 <= self.x1 and other.y1 <= self.y1)

    def contains_point(self, x: float, y: float) -> bool:
        return self.x0 <= x <= self.x1 and self.y0 <= y <= self.y1

    def __str__(self) -> str:
        return f"x {self.x0:g}–{self.x1:g}, y {self.y0:g}–{self.y1:g}"


def covered_by(rect: Rect, cover: Sequence[Rect]) -> bool:
    """Whether every point of ``rect`` lies in at least one of ``cover``.
    Exact for axis-aligned rectangles: the plane is cut on every edge, and
    the centre of every cell of ``rect`` is tested."""
    xs = sorted({rect.x0, rect.x1, *(c for r in cover for c in (r.x0, r.x1) if rect.x0 < c < rect.x1)})
    ys = sorted({rect.y0, rect.y1, *(c for r in cover for c in (r.y0, r.y1) if rect.y0 < c < rect.y1)})
    for xa, xb in zip(xs, xs[1:]):
        for ya, yb in zip(ys, ys[1:]):
            cx, cy = (xa + xb) / 2, (ya + yb) / 2
            if not any(r.contains_point(cx, cy) for r in cover):
                return False
    return True


@dataclass(frozen=True)
class Meta:
    title: str
    fps: int
    bpm: Fraction
    key: str
    sample_rate: int

    @property
    def timebase(self) -> tb.TimeBase:
        return tb.TimeBase(fps=self.fps, bpm=self.bpm, sample_rate=self.sample_rate)


@dataclass(frozen=True)
class Cut:
    id: str
    bars: int
    frames: int
    description: str
    fps: int = tb.FPS

    @property
    def nominal_s(self) -> int:
        """The length the cut is named after (``30s`` → 30)."""
        return int(CUT_RE.match(self.id).group(1))

    @property
    def duration_s(self) -> Fraction:
        return Fraction(self.frames, self.fps)

    @property
    def samples(self) -> int:
        return self.frames * tb.SAMPLE_RATE // self.fps


@dataclass(frozen=True)
class Format:
    id: str
    width: int
    height: int
    safe: Rect
    safe_basis: str
    safe_note: str
    rail_free: Rect | None
    zones: dict[str, Rect]
    layout: dict[str, Any]
    reference: bool = False
    phone_window_note: str = ""
    type_note: str = ""

    @property
    def size(self) -> tuple[int, int]:
        return self.width, self.height

    @property
    def text_area(self) -> tuple[Rect, ...]:
        """Where text may sit: the safe area, plus the extension above the
        button rail when the format has one."""
        return (self.safe,) + ((self.rail_free,) if self.rail_free else ())


@dataclass(frozen=True)
class Storyboard:
    source: str
    document: dict[str, Any]
    meta: Meta
    cuts: dict[str, Cut]
    formats: dict[str, Format]
    music: dict[str, Any]
    scenes: Any
    overrides: tuple[str, ...] = field(default=())

    @property
    def timebase(self) -> tb.TimeBase:
        return self.meta.timebase

    def cue_ids(self, cut: str | None = None) -> set[str]:
        """The cue ids declared for ``cut`` (by its score and ``music.cues``),
        or for every cut."""
        return _declared_ids(self.music, self.cuts, cut)

    @property
    def reference_format(self) -> "Format":
        """The format the scenes' camera W values are measured in."""
        return next(f for f in self.formats.values() if f.reference)

    def score_path(self, cut: str) -> Path | None:
        """The score a cut's music is rendered from (``music.scores``)."""
        scores = self.music.get("scores") or {}
        return (PROMO_REEL / scores[cut]) if cut in scores else None

    def cut_scenes(self, cut: str, fmt: str | None = None) -> list:
        """The scenes of one cut ([] when it has none yet) — as ``fmt`` reads
        them (`formats:` overrides resolved, `for_format`), or as written."""
        if isinstance(self.scenes, dict):
            items = list(self.scenes.get(cut) or [])
        else:
            items = list(self.scenes or [])
        return items if fmt is None else for_format(items, fmt)

    def plan(self, cuts: Iterable[str] | None = None, formats: Iterable[str] | None = None) -> str:
        """What a build of ``cuts`` × ``formats`` (default: all) makes, in words."""
        cuts = list(cuts) if cuts is not None else list(self.cuts)
        formats = list(formats) if formats is not None else list(self.formats)
        m = self.meta
        t = self.timebase
        lines = [f"{self.source} — {m.title}",
                 f"  time base: {float(m.bpm):g} BPM · {m.fps} fps · {m.sample_rate} Hz · {m.key} · "
                 f"beat {t.frames_per_beat} frames · bar {t.frames_per_bar} frames · "
                 f"{t.samples_per_frame} samples a frame"]
        if self.overrides:
            lines.append("  variant: " + " ".join(f"--set {o}" for o in self.overrides))
        for cid in cuts:
            c = self.cuts[cid]
            lines.append(f"  cut {cid}: {c.bars} bars = {c.frames} frames = {float(c.duration_s):.3f} s "
                         f"= {c.samples} samples — {c.description}")
        for fid in formats:
            f = self.formats[fid]
            lines.append(f"  format {fid}: {f.width}×{f.height}, safe {f.safe} ({f.safe_basis}); "
                         f"zones: {', '.join(f.zones)}")
        for cid in cuts:
            sp = self.score_path(cid)
            lines.append(f"  music {cid}: {len(self.cue_ids(cid))} cues declared"
                         + (f" (score {sp.relative_to(PROMO_REEL)})" if sp else "")
                         + f" · scenes: {len(self.cut_scenes(cid))}")
        lines.append(f"  films: {len(cuts) * len(formats)} — " + ", ".join(f"{c}/{f}" for c in cuts for f in formats))
        return "\n".join(lines)


# ---- per-format values in the scenes ------------------------------------------------

#: Any mapping in the scenes may carry `formats: {<format id>: {key: value, …}}`:
#: in that format those keys replace the mapping's own; every other format reads
#: the mapping as written. ONE scene, re-laid out — the owner's round-5 16:9
#: decisions (2026-10-20) are written so: the push-in about the floor
#: (`camera.formats.16x9.fill`), the 15-s form's hard cut at f193 and the
#: framing that needs no band-edge curtain after it.
FORMATS_KEY = "formats"


def for_format(node: Any, fmt: str) -> Any:
    """``node`` as format ``fmt`` reads it: every `formats:` override for it
    applied, every `formats:` key dropped (a new copy; ``node`` is untouched)."""
    if isinstance(node, dict):
        out = {k: for_format(v, fmt) for k, v in node.items() if k != FORMATS_KEY}
        over = node.get(FORMATS_KEY)
        if isinstance(over, dict) and isinstance(over.get(fmt), dict):
            for k, v in over[fmt].items():
                out[k] = for_format(v, fmt)
        return out
    if isinstance(node, list):
        return [for_format(v, fmt) for v in node]
    return node


def _format_overrides(node: Any, path: str) -> Iterator[tuple[str, Any]]:
    """(path, value) of every `formats:` key under ``node``."""
    if isinstance(node, dict):
        for k, v in node.items():
            if k == FORMATS_KEY:
                yield f"{path}.{k}", v
            yield from _format_overrides(v, f"{path}.{k}")
    elif isinstance(node, list):
        for i, v in enumerate(node):
            yield from _format_overrides(v, f"{path}[{i}]")


def _check_format_overrides(c: "_Check", items: list, base: str, format_ids: set[str]) -> None:
    for path, over in _format_overrides(items, base):
        if not isinstance(over, dict) or not over:
            c.fail(path, f"must map format ids to the keys they change ({{16x9: {{…}}}}), not {_kind(over)}")
            continue
        for fid, keys in over.items():
            if fid not in format_ids:
                c.fail(f"{path}.{fid}", f"is not a format (formats: {', '.join(sorted(format_ids)) or 'none'})")
            elif not isinstance(keys, dict) or not keys:
                c.fail(f"{path}.{fid}", f"must be the keys this format changes (a mapping), not {_kind(keys)}")


# ---- loading -------------------------------------------------------------------

def load(path: Path | str = DEFAULT_PATH, overrides: Sequence[str] = ()) -> Storyboard:
    """Read, override and check a storyboard. Raises ``StoryboardError``."""
    path = Path(path)
    source = path.name
    try:
        text = path.read_text(encoding="utf-8")
    except OSError as e:
        raise StoryboardError(source, [f"cannot read {path}: {e.strerror or e}"]) from None
    return loads(text, source=source, overrides=overrides)


def loads(text: str, source: str = "storyboard.yaml", overrides: Sequence[str] = ()) -> Storyboard:
    """``load`` from a string."""
    try:
        doc = _unshare(yaml.safe_load(text))
    except yaml.YAMLError as e:
        raise StoryboardError(source, [f"not valid YAML: {e}"]) from None
    doc = apply_overrides(doc, overrides, source=source)
    return validate(doc, source=source, overrides=overrides)


def _unshare(node: Any) -> Any:
    """A copy in which no mapping or list appears twice. A YAML alias makes
    one object appear wherever it is used; an override of one use must not
    change the others (`--set formats.9x16.layout.type_px.app=80` changes the
    9:16 format only — and is then refused, the sizes being the same in every
    format)."""
    if isinstance(node, dict):
        return {k: _unshare(v) for k, v in node.items()}
    if isinstance(node, list):
        return [_unshare(v) for v in node]
    return node


def parse_override(text: str) -> tuple[list[str], Any]:
    """``"a.b.c=value"`` → (``["a", "b", "c"]``, the value read as YAML)."""
    if not isinstance(text, str) or "=" not in text:
        raise ValueError(f"--set {text!r}: write path.to.key=value")
    key, _, raw = text.partition("=")
    parts = key.strip().split(".")
    if not key.strip() or any(not p for p in parts):
        raise ValueError(f"--set {text!r}: the path {key!r} has an empty part")
    try:
        value = yaml.safe_load(raw) if raw.strip() else None
    except yaml.YAMLError as e:
        raise ValueError(f"--set {text!r}: the value is not valid YAML ({e})") from None
    return parts, value


def apply_overrides(doc: Any, overrides: Sequence[str], source: str = "storyboard.yaml") -> Any:
    """A deep copy of ``doc`` with every ``path=value`` applied in order."""
    if not overrides:
        return doc
    doc = copy.deepcopy(doc)
    problems = []
    for text in overrides:
        try:
            parts, value = parse_override(text)
            _set_path(doc, parts, value)
        except (ValueError, KeyError, IndexError, TypeError) as e:
            problems.append(str(e.args[0]) if e.args else repr(e))
    if problems:
        raise StoryboardError(source, problems)
    return doc


def _set_path(doc: Any, parts: list[str], value: Any) -> None:
    node, walked = doc, []
    for i, part in enumerate(parts):
        last = i == len(parts) - 1
        where = ".".join(walked) or "(top level)"
        if isinstance(node, dict):
            key = _existing_key(node, part)
            if key is None:
                if not last:
                    raise KeyError(f"--set {'.'.join(parts)}: {where} has no key {part!r}")
                key = part
            if last:
                node[key] = value
                return
            node = node[key]
        elif isinstance(node, list):
            if not re.fullmatch(r"\d+", part):
                raise KeyError(f"--set {'.'.join(parts)}: {where} is a list; address an item by its index, "
                               f"not {part!r}")
            idx = int(part)
            if idx >= len(node):
                raise IndexError(f"--set {'.'.join(parts)}: {where} has {len(node)} items, no item {idx}")
            if last:
                node[idx] = value
                return
            node = node[idx]
        else:
            raise TypeError(f"--set {'.'.join(parts)}: {where} is a {type(node).__name__}, not a mapping or a list")
        walked.append(part)


def _existing_key(node: dict, part: str) -> Any:
    """The key of ``node`` written ``part`` (YAML may have read it as a number)."""
    if part in node:
        return part
    for key in node:
        if str(key) == part:
            return key
    return None


# ---- checking ------------------------------------------------------------------

class _Check:
    """Collects problems, each prefixed with its path in the document."""

    def __init__(self) -> None:
        self.problems: list[str] = []

    def fail(self, path: str, message: str) -> None:
        self.problems.append(f"{path}: {message}")

    def mapping(self, value: Any, path: str, required: Sequence[str] = (),
                optional: Sequence[str] = ()) -> dict | None:
        if not isinstance(value, dict):
            self.fail(path, f"must be a mapping, not {_kind(value)}")
            return None
        allowed = set(required) | set(optional)
        for key in value:
            if key not in allowed:
                self.fail(f"{path}.{key}", f"unknown key (allowed: {', '.join(sorted(allowed))})")
        for key in required:
            if key not in value:
                self.fail(path, f"missing key {key!r}")
        return value

    def integer(self, value: Any, path: str, minimum: int | None = None) -> int | None:
        if isinstance(value, bool) or not isinstance(value, int):
            self.fail(path, f"must be a whole number, not {_kind(value)}")
            return None
        if minimum is not None and value < minimum:
            self.fail(path, f"must be at least {minimum}, not {value}")
            return None
        return value

    def number(self, value: Any, path: str, minimum: float | None = None,
               maximum: float | None = None) -> float | None:
        if isinstance(value, bool) or not isinstance(value, (int, float)):
            self.fail(path, f"must be a number, not {_kind(value)}")
            return None
        if minimum is not None and value < minimum:
            self.fail(path, f"must be at least {minimum:g}, not {value:g}")
            return None
        if maximum is not None and value > maximum:
            self.fail(path, f"must be at most {maximum:g}, not {value:g}")
            return None
        return value

    def string(self, value: Any, path: str) -> str | None:
        if not isinstance(value, str) or not value.strip():
            self.fail(path, f"must be a non-empty string, not {_kind(value)}")
            return None
        return value

    def boolean(self, value: Any, path: str) -> bool | None:
        if not isinstance(value, bool):
            self.fail(path, f"must be true or false, not {_kind(value)}")
            return None
        return value

    def choice(self, value: Any, path: str, choices: Sequence[Any]) -> Any:
        if value not in choices:
            self.fail(path, f"must be one of {', '.join(map(str, choices))}, not {value!r}")
            return None
        return value

    def numbers(self, value: Any, path: str, n: int) -> list[float] | None:
        if (not isinstance(value, list) or len(value) != n
                or any(isinstance(v, bool) or not isinstance(v, (int, float)) for v in value)):
            self.fail(path, f"must be a list of {n} numbers, not {value!r}")
            return None
        return value

    def span(self, value: Any, path: str, lo: float, hi: float) -> tuple[float, float] | None:
        """[a, b] with lo ≤ a < b ≤ hi."""
        v = self.numbers(value, path, 2)
        if v is None:
            return None
        if not (lo <= v[0] < v[1] <= hi):
            self.fail(path, f"{v} must be [a, b] with {lo:g} ≤ a < b ≤ {hi:g}")
            return None
        return v[0], v[1]

    def rect(self, value: Any, path: str, width: float, height: float) -> Rect | None:
        """[x0, y0, x1, y1] inside a width × height canvas, not empty."""
        v = self.numbers(value, path, 4)
        if v is None:
            return None
        r = Rect(*v)
        if not (r.x0 < r.x1 and r.y0 < r.y1):
            self.fail(path, f"{v} is empty: write [x0, y0, x1, y1] with x0 < x1 and y0 < y1")
            return None
        if not Rect(0, 0, width, height).contains(r):
            self.fail(path, f"{v} leaves the {width:g}×{height:g} canvas")
            return None
        return r


def _kind(value: Any) -> str:
    if value is None:
        return "nothing"
    if isinstance(value, bool):
        return f"{value!r} (a boolean)"
    if isinstance(value, (int, float, str)):
        return f"{value!r}"
    return f"a {type(value).__name__}"


def validate(doc: Any, source: str = "storyboard.yaml", overrides: Sequence[str] = ()) -> Storyboard:
    """Check a whole document; returns the typed ``Storyboard`` or raises
    ``StoryboardError`` listing every problem."""
    c = _Check()
    if isinstance(doc, dict):
        # `x-…` keys hold YAML anchors (shared values aliased below them) and
        # are not read: what counts is where the alias is used.
        extensions = [k for k in doc if isinstance(k, str) and k.startswith(EXTENSION_PREFIX)]
        top = c.mapping({k: v for k, v in doc.items() if k not in extensions}, "(top level)", required=TOP_LEVEL)
    else:
        top = c.mapping(doc, "(top level)", required=TOP_LEVEL)
    if top is None:
        raise StoryboardError(source, c.problems)
    meta = _meta(c, top.get("meta"))
    timebase = tb.DEFAULT
    cuts = _cuts(c, top.get("cuts"), timebase)
    formats = _formats(c, top.get("formats"))
    music = top.get("music")
    if not isinstance(music, dict):
        c.fail("music", f"must be a mapping (AUDIO's section; `cues: []` when empty), not {_kind(music)}")
        music = {}
    declared = _check_cues(c, music, cuts)
    # a cut the document names but that broke a rule is still a cut here:
    # its problem is reported once, at the cut, not again at every use
    named_cuts = set(top.get("cuts") or {}) if isinstance(top.get("cuts"), dict) else set(cuts)
    _check_scores(c, music, cuts, named_cuts)
    scenes = top.get("scenes")
    if not isinstance(scenes, (list, dict)):
        c.fail("scenes", f"must be a list or a mapping (SCENES' section; `[]` when empty), not {_kind(scenes)}")
    else:
        if isinstance(scenes, dict):
            groups = []
            for cut, items in scenes.items():
                if cut not in named_cuts:
                    c.fail(f"scenes.{cut}", f"is not a cut (cuts: {', '.join(cuts) or 'none'})")
                    continue
                if not isinstance(items, list):
                    c.fail(f"scenes.{cut}", f"must be a list of scenes, not {_kind(items)}")
                    continue
                groups.append((f"scenes.{cut}", items, _declared_ids(music, cuts, cut)))
        else:
            groups = [("scenes", scenes, declared | _declared_ids(music, cuts, None))]
        for base, items, known_ids in groups:
            bad_refs = False
            for path, ref in _cue_references(items, base):
                if ref not in known_ids:
                    bad_refs = True
                    known = ", ".join(sorted(known_ids)) or "none declared yet"
                    where = "the cut's cues" if base != "scenes" else "music.cues"
                    c.fail(path, f"cue {ref!r} is not in {where} (known: {known})")
            format_ids = set(top.get("formats") or {}) if isinstance(top.get("formats"), dict) else set()
            _check_format_overrides(c, items, base, format_ids)
            if not bad_refs and isinstance(scenes, dict):
                cut = base.split(".", 1)[1]
                if cut in cuts:
                    # keys in time order in every format (an override changes a key's value, never the order)
                    for variant in [items] + [for_format(items, fid) for fid in sorted(format_ids)]:
                        _check_key_order(c, variant, base, _cue_frames(music, cut), cuts[cut].frames)
    if c.problems:
        c.problems = list(dict.fromkeys(c.problems))
    if c.problems:
        raise StoryboardError(source, c.problems)
    return Storyboard(source, doc, meta, cuts, formats, music, scenes, tuple(overrides))


def _meta(c: _Check, value: Any) -> Meta | None:
    before = len(c.problems)
    m = c.mapping(value, "meta", required=("fps", "bpm", "key", "sample_rate"), optional=("title",))
    if m is None:
        return None
    title = c.string(m["title"], "meta.title") if "title" in m else "(untitled)"
    fps = c.integer(m.get("fps"), "meta.fps", 1) if "fps" in m else None
    bpm = c.number(m.get("bpm"), "meta.bpm", 1) if "bpm" in m else None
    rate = c.integer(m.get("sample_rate"), "meta.sample_rate", 1) if "sample_rate" in m else None
    key = c.string(m.get("key"), "meta.key") if "key" in m else None
    if key is not None and not KEY_RE.match(key):
        c.fail("meta.key", f"{key!r} is not a key: write e.g. 'C minor' or 'Eb major'")
    contract = tb.DEFAULT
    for name, got, want in (("fps", fps, contract.fps), ("sample_rate", rate, contract.sample_rate)):
        if got is not None and got != want:
            c.fail(f"meta.{name}", f"{got} is not the contract's {want} (promo/timebase.py): every module "
                                   f"counts {contract.frames_per_beat} frames a beat and "
                                   f"{contract.samples_per_frame} samples a frame")
    exact = None
    if bpm is not None:
        exact = tb._fraction(bpm, "meta.bpm")
        if exact != contract.bpm:
            c.fail("meta.bpm", f"{bpm:g} is not the contract's {float(contract.bpm):g} BPM (promo/timebase.py): "
                               f"the music is the clock, {contract.frames_per_beat} frames a beat")
    if len(c.problems) > before or None in (fps, exact, rate, key, title):
        return None
    return Meta(title, fps, exact, key, rate)


#: The owner's decision after the first 30-s review (2026-10-19, « Add one bar »): a cut may run this many
#: bars past the whole bars its name holds — the calm outro under the end card, so the card's full wording
#: holds ≈ 4.3 s. Never more: a « 30s » cut is at most 15 bars (32.0 s), a « 15s » cut 8 (17.07 s).
OUTRO_BARS = 1


def _cuts(c: _Check, value: Any, timebase: tb.TimeBase) -> dict[str, Cut]:
    if not isinstance(value, dict) or not value:
        c.fail("cuts", f"must be a mapping of at least one cut (e.g. 30s: …), not {_kind(value)}")
        return {}
    out = {}
    for cid, spec in value.items():
        path = f"cuts.{cid}"
        m = CUT_RE.match(str(cid))
        if not m or not isinstance(cid, str):
            c.fail(path, "a cut is named by its length in seconds, e.g. '30s' or '15s'")
            continue
        s = c.mapping(spec, path, required=("bars", "frames"), optional=("description",))
        if s is None:
            continue
        bars = c.integer(s.get("bars"), f"{path}.bars", 1) if "bars" in s else None
        frames = c.integer(s.get("frames"), f"{path}.frames", 1) if "frames" in s else None
        desc = c.string(s["description"], f"{path}.description") if "description" in s else ""
        if bars is None or frames is None or desc is None:
            continue
        want = bars * timebase.frames_per_bar
        if frames != want:
            c.fail(f"{path}.frames", f"{frames} is not {bars} bars × {timebase.frames_per_bar} = {want} frames")
            continue
        nominal = int(m.group(1))
        fit = (nominal * timebase.fps) // timebase.frames_per_bar        # whole bars inside the name
        if bars > fit + OUTRO_BARS:
            c.fail(path, f"{bars} bars run {frames / timebase.fps:.3f} s: the {nominal} s the cut is named after "
                         f"hold {fit} bars, plus the {OUTRO_BARS} outro bar the owner allowed (2026-10-19) — at "
                         f"most {fit + OUTRO_BARS}")
            continue
        out[cid] = Cut(cid, bars, frames, desc or "", timebase.fps)
    return out


_LAYOUT_KEYS = ("caption_band", "caption_column_x", "caption_centre_x", "caption_centre_y",
                "caption_line_max_px", "caption_lines_max", "phone_screen_x", "px_per_pt",
                "screen_crop_top_pt", "phone_bezel_px", "phone_radius_px", "type_px",
                "lottie_centre", "lottie_comp_width_px", "end_mark_scale", "end_mark_ink_y",
                "end_tagline_cap_top_y", "lift_x", "lift_veil", "lift_path", "tilt_axis", "tilt_max_deg",
                "scene_whip_axis", "zoom_pivot_x", "phone_anchor",
                # where the scenes put what they place (one storyboard, re-laid out per format)
                "caption_align", "caption_cap_top", "counter_baselines", "lift_y", "hook_page",
                "hook_scrim", "map_credit")
CAPTION_ALIGNS = ("centre", "left")
CAPTION_KINDS = ("hook", "app")
LIFT_PLACES = ("card_on_floor", "card_under_caption", "tile_row")
#: how a lift travels from its place on the phone (promo/fx/lift.py): straight, or `under` — down beside the phone,
#: then across under the caption (16:9). A lift whose place lies outside the text rectangle pops in place anyway.
LIFT_PATHS = ("straight", "under")
LIFT_Y_KEYS = ("top", "centre_y", "bottom")
#: a lift place may give its own columns (else the layout's `lift_x`)
LIFT_X_KEY = "x"


def _formats(c: _Check, value: Any) -> dict[str, Format]:
    if not isinstance(value, dict) or not value:
        c.fail("formats", f"must be a mapping of at least one format (e.g. 9x16: …), not {_kind(value)}")
        return {}
    out = {}
    for fid, spec in value.items():
        f = _format(c, fid, spec)
        if f is not None:
            out[fid] = f
    refs = [fid for fid, spec in value.items() if isinstance(spec, dict) and spec.get("reference") is True]
    if len(refs) != 1:
        c.fail("formats", "exactly ONE format is the `reference: true` — the one the scenes' camera W values are "
                          f"measured in (have {len(refs)}: {', '.join(map(str, refs)) or 'none'})")
    # One storyboard, three formats: the same pixel sizes everywhere — but a format may set its column's words
    # and its counter larger than the reference's, saying why (`type_note`; the 16:9 feed, 2026-10-19)
    ref = next((out[fid] for fid in refs if fid in out), None)
    for fid, f in out.items():
        if ref is None or f is ref:
            continue
        mine, theirs = f.layout.get("type_px") or {}, ref.layout.get("type_px") or {}
        differ = sorted(role for role in TYPE_ROLES if mine.get(role) != theirs.get(role))
        if not differ:
            continue
        fixed = [role for role in differ if role not in CAPTION_TYPE_ROLES]
        smaller = [role for role in differ if role in CAPTION_TYPE_ROLES and isinstance(mine.get(role), int)
                   and isinstance(theirs.get(role), int) and mine[role] < theirs[role]]
        if fixed:
            c.fail(f"formats.{fid}.layout.type_px", f"{', '.join(fixed)} must be the reference's "
                                                    f"({', '.join(f'{r_} {theirs.get(r_)}' for r_ in fixed)}): "
                                                    f"only {', '.join(CAPTION_TYPE_ROLES)} may be set larger")
        elif smaller:
            c.fail(f"formats.{fid}.layout.type_px", f"{', '.join(smaller)} smaller than the reference's: a "
                                                    f"format may set its captions larger, never smaller")
        elif not f.type_note.strip():
            c.fail(f"formats.{fid}.layout.type_px", f"{', '.join(differ)} differ from the reference's — say why "
                                                    f"in the format's `type_note`")
    for key in ("px_per_pt", "lottie_comp_width_px", "end_mark_scale", "screen_crop_top_pt"):
        seen = {fid: f.layout.get(key) for fid, f in out.items()}
        if len({repr(v) for v in seen.values()}) > 1:
            c.fail(f"formats.*.layout.{key}",
                   "must be the same in every format — each format is re-laid out, never resized: "
                   + "; ".join(f"{fid}: {v!r}" for fid, v in seen.items()))
    return out


def _format(c: _Check, fid: Any, spec: Any) -> Format | None:
    path = f"formats.{fid}"
    m = FORMAT_RE.match(str(fid)) if isinstance(fid, str) else None
    if not m:
        c.fail(path, "a format is named by its aspect ratio, e.g. '9x16', '1x1' or '16x9'")
        return None
    s = c.mapping(spec, path, required=("size", "safe", "safe_basis", "zones", "layout"),
                  optional=("safe_note", "rail_free", "reference", "phone_window_note", "type_note"))
    if s is None:
        return None
    before = len(c.problems)
    size = s.get("size")
    if (not isinstance(size, list) or len(size) != 2
            or any(isinstance(v, bool) or not isinstance(v, int) or v <= 0 for v in size)):
        c.fail(f"{path}.size", f"must be [width, height] in whole pixels, not {size!r}")
        return None
    w, h = size
    a, b = int(m.group(1)), int(m.group(2))
    if w * b != h * a:
        c.fail(f"{path}.size", f"{w}×{h} is not {a}:{b}")
    if min(w, h) != SHORT_SIDE_PX:
        c.fail(f"{path}.size", f"the short side must be {SHORT_SIDE_PX} px, so type, phone and Lottie keep "
                               f"their pixel sizes in every format (have {min(w, h)})")
    safe = c.rect(s.get("safe"), f"{path}.safe", w, h) if "safe" in s else None
    basis = c.choice(s.get("safe_basis"), f"{path}.safe_basis", SAFE_BASES) if "safe_basis" in s else None
    if safe is not None and basis == "ebu_r95_graphics":
        want = Rect(float(w * EBU_R95_GRAPHICS_INSET), float(h * EBU_R95_GRAPHICS_INSET),
                    float(w * (1 - EBU_R95_GRAPHICS_INSET)), float(h * (1 - EBU_R95_GRAPHICS_INSET)))
        if tuple(map(float, safe)) != tuple(want):
            c.fail(f"{path}.safe", f"EBU R95 graphics-safe is a 5 % inset: [{want.x0:g}, {want.y0:g}, "
                                   f"{want.x1:g}, {want.y1:g}], not {list(safe)}")
    note = c.string(s["safe_note"], f"{path}.safe_note") if "safe_note" in s else ""
    rail = c.rect(s["rail_free"], f"{path}.rail_free", w, h) if s.get("rail_free") is not None else None
    if rail is not None and safe is not None and not (rail.y1 <= safe.y1 and rail.y0 >= safe.y0):
        c.fail(f"{path}.rail_free", f"{rail} must lie within the safe area's rows (y {safe.y0:g}–{safe.y1:g})")
    if "reference" in s:
        c.boolean(s["reference"], f"{path}.reference")
    for key in ("phone_window_note", "type_note"):
        if key in s:
            c.string(s[key], f"{path}.{key}")
    zones = _zones(c, s.get("zones"), f"{path}.zones", w, h, safe, rail, s.get("phone_window_note"))
    layout = _layout(c, s.get("layout"), f"{path}.layout", w, h, zones, safe, rail)
    if len(c.problems) > before or safe is None or basis is None or layout is None or zones is None:
        return None
    return Format(fid, w, h, safe, basis, note or "", rail, zones, layout, s.get("reference") is True,
                  s.get("phone_window_note") or "", s.get("type_note") or "")


def _zones(c: _Check, value: Any, path: str, w: int, h: int, safe: Rect | None,
           rail: Rect | None, phone_note: Any = None) -> dict[str, Rect] | None:
    z = c.mapping(value, path, required=REQUIRED_ZONES, optional=CONTENT_ZONES + STAGE_ZONES)
    if z is None:
        return None
    out = {}
    for name, raw in z.items():
        r = c.rect(raw, f"{path}.{name}", w, h)
        if r is None:
            continue
        if name == "phone_window" and safe is not None and r.y1 > safe.y1:
            # app pixels past the safe area's bottom: only with the reason, and only downwards
            if not (isinstance(phone_note, str) and phone_note.strip()):
                c.fail(f"{path}.{name}", f"{r} runs past the safe area's bottom (y {safe.y1:g}): app pixels may, "
                                         f"text never — say why in the format's `phone_window_note`")
                continue
            if not covered_by(Rect(r.x0, r.y0, r.x1, safe.y1), [safe] + ([rail] if rail else [])):
                c.fail(f"{path}.{name}", f"{r} must lie inside the safe area's columns and below its top ({safe})")
                continue
        elif name in CONTENT_ZONES and safe is not None:
            cover = [safe] + ([rail] if rail else [])
            if not covered_by(r, cover):
                where = f"the safe area ({safe})" + (f" or the rail-free extension ({rail})" if rail else "")
                c.fail(f"{path}.{name}", f"{r} must lie inside {where}: it holds text or UI")
                continue
        out[name] = r
    return out


def _layout(c: _Check, value: Any, path: str, w: int, h: int, zones: dict[str, Rect] | None,
            safe: Rect | None, rail: Rect | None) -> dict[str, Any] | None:
    lay = c.mapping(value, path, required=_LAYOUT_KEYS)
    if lay is None:
        return None
    before = len(c.problems)
    c.boolean(lay.get("caption_band"), f"{path}.caption_band")
    if zones is not None and lay.get("caption_band") is True and "caption_band" not in zones:
        c.fail(f"{path}.caption_band", "is true, but the format has no `caption_band` zone")
    if zones is not None and lay.get("caption_band") is False and "caption_band" in zones:
        c.fail(f"{path}.caption_band", "is false, but the format has a `caption_band` zone")
    column = c.span(lay.get("caption_column_x"), f"{path}.caption_column_x", 0, w)
    if column is not None and safe is not None:
        cover = [safe] + ([rail] if rail else [])
        if not any(r.x0 <= column[0] and column[1] <= r.x1 for r in cover):
            c.fail(f"{path}.caption_column_x", f"{list(column)} must lie within the safe area's columns")
    for key, limit in (("caption_centre_x", w), ("caption_centre_y", h)):
        v = lay.get(key)
        if v is not None:
            c.number(v, f"{path}.{key}", 0, limit)
    if lay.get("caption_centre_x") is not None and column is not None:
        cx = lay["caption_centre_x"]
        if isinstance(cx, (int, float)) and abs((column[0] + column[1]) / 2 - cx) > 0.5:
            c.fail(f"{path}.caption_centre_x", f"{cx:g} is not the centre of the caption column {list(column)}")
    line = c.integer(lay.get("caption_line_max_px"), f"{path}.caption_line_max_px", 1)
    if line is not None and column is not None and line > column[1] - column[0]:
        c.fail(f"{path}.caption_line_max_px", f"{line} px is wider than the caption column ({column[1] - column[0]:g} px)")
    c.integer(lay.get("caption_lines_max"), f"{path}.caption_lines_max", 1)
    screen = c.span(lay.get("phone_screen_x"), f"{path}.phone_screen_x", 0, w)
    ppt = c.number(lay.get("px_per_pt"), f"{path}.px_per_pt", 0.1)
    if screen is not None and ppt is not None:
        shown_pt = (screen[1] - screen[0]) / ppt
        if abs(shown_pt - DEVICE_WIDTH_PT) > 0.5:
            c.fail(f"{path}.phone_screen_x", f"{screen[1] - screen[0]:g} px at {ppt:g} px/pt shows {shown_pt:.1f} pt; "
                                             f"the screen is {DEVICE_WIDTH_PT:g} pt wide")
    if screen is not None and zones is not None and "phone_window" in zones:
        win = zones["phone_window"]
        if not (win.x0 <= screen[0] and screen[1] <= win.x1):
            c.fail(f"{path}.phone_screen_x", f"{list(screen)} leaves the phone window ({win})")
    c.number(lay.get("screen_crop_top_pt"), f"{path}.screen_crop_top_pt", 0)
    c.integer(lay.get("phone_bezel_px"), f"{path}.phone_bezel_px", 0)
    c.integer(lay.get("phone_radius_px"), f"{path}.phone_radius_px", 0)
    types = c.mapping(lay.get("type_px"), f"{path}.type_px", required=TYPE_ROLES)
    if types is not None:
        for role in TYPE_ROLES:
            if role in types:
                c.integer(types[role], f"{path}.type_px.{role}", 1)
        for role in READ_ROLES:
            if isinstance(types.get(role), int) and types[role] < MIN_READ_PX:
                c.fail(f"{path}.type_px.{role}", f"{types[role]} px: a line the viewer must read is at least "
                                                 f"{MIN_READ_PX} px")
    centre = c.numbers(lay.get("lottie_centre"), f"{path}.lottie_centre", 2)
    comp = c.integer(lay.get("lottie_comp_width_px"), f"{path}.lottie_comp_width_px", 1)
    if centre is not None and comp is not None and not (comp / 2 <= centre[0] <= w - comp / 2 and 0 <= centre[1] <= h):
        c.fail(f"{path}.lottie_centre", f"a {comp}-px comp centred on {centre} leaves the {w}×{h} canvas")
    c.number(lay.get("end_mark_scale"), f"{path}.end_mark_scale", 0.1)
    ink = c.span(lay.get("end_mark_ink_y"), f"{path}.end_mark_ink_y", 0, h)
    cap = c.number(lay.get("end_tagline_cap_top_y"), f"{path}.end_tagline_cap_top_y", 0, h)
    if ink is not None and cap is not None:
        clear = cap - ink[1]
        if clear < (ink[1] - ink[0]) / 2:
            c.fail(f"{path}.end_tagline_cap_top_y",
                   f"{cap:g} leaves {clear:g} px under the mark; its clear space is half its height "
                   f"({(ink[1] - ink[0]) / 2:g} px)")
    lift = c.span(lay.get("lift_x"), f"{path}.lift_x", 0, w)
    if lift is not None and safe is not None and not (safe.x0 <= lift[0] and lift[1] <= safe.x1):
        c.fail(f"{path}.lift_x", f"{list(lift)} must lie within the safe area's columns (x {safe.x0:g}–{safe.x1:g})")
    c.number(lay.get("lift_veil"), f"{path}.lift_veil", 0, 1)
    c.choice(lay.get("lift_path"), f"{path}.lift_path", LIFT_PATHS)
    c.choice(lay.get("tilt_axis"), f"{path}.tilt_axis", ("x", "y"))
    if lay.get("tilt_max_deg") is not None:
        c.number(lay.get("tilt_max_deg"), f"{path}.tilt_max_deg", 0, 90)
    if lay.get("scene_whip_axis") is not None:
        c.choice(lay.get("scene_whip_axis"), f"{path}.scene_whip_axis", ("horizontal", "vertical"))
    if "phone_anchor" in lay:
        c.choice(lay.get("phone_anchor"), f"{path}.phone_anchor", PHONE_ANCHORS)
    if lay.get("zoom_pivot_x") is not None:
        pv = c.number(lay.get("zoom_pivot_x"), f"{path}.zoom_pivot_x", 0, w)
        bezel = lay.get("phone_bezel_px") if isinstance(lay.get("phone_bezel_px"), (int, float)) else 0
        if pv is not None and screen is not None and not (screen[0] - bezel <= pv <= screen[1] + bezel):
            c.fail(f"{path}.zoom_pivot_x", f"{pv:g} is off the slab's columns ({screen[0] - bezel:g}–"
                                           f"{screen[1] + bezel:g}): a push-in scales about a point of the phone")
    _placements(c, lay, path, w, h, zones, safe, rail, column)
    return lay if len(c.problems) == before else None


def _placements(c: _Check, lay: dict, path: str, w: int, h: int, zones: dict[str, Rect] | None,
                safe: Rect | None, rail: Rect | None, column: tuple[float, float] | None) -> None:
    """The layout keys that say where the scenes put what they place."""
    align = c.choice(lay.get("caption_align"), f"{path}.caption_align", CAPTION_ALIGNS)
    if align == "centre" and lay.get("caption_centre_x") is None:
        c.fail(f"{path}.caption_align", "centre: the lines are centred on `caption_centre_x`, which is not given")
    if align == "left" and lay.get("caption_centre_x") is not None:
        c.fail(f"{path}.caption_align", "left: the lines start at `caption_column_x`'s left edge; "
                                        "`caption_centre_x` must be null")
    tops = c.mapping(lay.get("caption_cap_top"), f"{path}.caption_cap_top", required=CAPTION_KINDS)
    if tops is not None:
        for kind in CAPTION_KINDS:
            v = tops.get(kind)
            if v is None:
                if kind in tops and lay.get("caption_centre_y") is None:
                    c.fail(f"{path}.caption_cap_top.{kind}", "null: the block is centred on `caption_centre_y`, "
                                                             "which is not given")
            else:
                c.number(v, f"{path}.caption_cap_top.{kind}", 0, h)
    cb = c.numbers(lay.get("counter_baselines"), f"{path}.counter_baselines", 2)
    if cb is not None and not (0 < cb[0] < cb[1] <= h):
        c.fail(f"{path}.counter_baselines", f"{cb} must be [label, figure] baselines, the label above")
    overlays = zones.get("overlays") if zones else None
    places = c.mapping(lay.get("lift_y"), f"{path}.lift_y", required=LIFT_PLACES)
    if places is not None:
        for name, spec in places.items():
            p = f"{path}.lift_y.{name}"
            ys = [k for k in spec if k in LIFT_Y_KEYS] if isinstance(spec, dict) else []
            if (not isinstance(spec, dict) or len(ys) != 1
                    or any(k not in LIFT_Y_KEYS + (LIFT_X_KEY,) for k in spec)):
                c.fail(p, f"must be ONE of {{{', '.join(LIFT_Y_KEYS)}: y}} (and, optionally, `{LIFT_X_KEY}: "
                          f"[x0, x1]`), not {spec!r}")
                continue
            y = c.number(spec[ys[0]], p, 0, h)
            if y is not None and overlays is not None and not (overlays.y0 <= y <= overlays.y1):
                c.fail(p, f"y {y:g} is outside the overlays zone's rows ({overlays})")
            if LIFT_X_KEY in spec:
                # this place's own columns (16:9, the owner's round-5 decision: the « Arrivé » card and the Fiche's
                # tiles at the left column's full width) — inside the safe area's and the overlays zone's columns
                xs = c.span(spec[LIFT_X_KEY], f"{p}.{LIFT_X_KEY}", 0, w)
                if xs is not None and safe is not None and not (safe.x0 <= xs[0] and xs[1] <= safe.x1):
                    c.fail(f"{p}.{LIFT_X_KEY}", f"{list(xs)} must lie within the safe area's columns "
                                                f"(x {safe.x0:g}–{safe.x1:g})")
                elif xs is not None and overlays is not None and not (overlays.x0 <= xs[0] and xs[1] <= overlays.x1):
                    c.fail(f"{p}.{LIFT_X_KEY}", f"{list(xs)} must lie within the overlays zone's columns ({overlays})")
    page = c.mapping(lay.get("hook_page"), f"{path}.hook_page", required=("x", "top", "pivot", "macro_to"))
    if page is not None:
        if c.numbers(page.get("x"), f"{path}.hook_page.x", 2) is not None and not page["x"][0] < page["x"][1]:
            c.fail(f"{path}.hook_page.x", f"{page['x']} must be [x0, x1] with x0 < x1")
        c.number(page.get("top"), f"{path}.hook_page.top")
        for key in ("pivot", "macro_to"):
            v = c.numbers(page.get(key), f"{path}.hook_page.{key}", 2)
            if v is not None and not (0 <= v[0] <= w and 0 <= v[1] <= h):
                c.fail(f"{path}.hook_page.{key}", f"{v} is off the {w}×{h} canvas")
    scrim = c.mapping(lay.get("hook_scrim"), f"{path}.hook_scrim", required=("rect", "fade"), optional=("macro",))
    if scrim is not None:
        # the scrim, and the macro shot's own (`macro`, optional: 16:9 keeps the black behind the question only,
        # so the margin note writes itself in view)
        for sp, where in ((scrim, f"{path}.hook_scrim"),) + (
                ((scrim["macro"], f"{path}.hook_scrim.macro"),) if scrim.get("macro") is not None else ()):
            if sp is not scrim and c.mapping(sp, where, required=("rect", "fade")) is None:
                continue
            r = c.rect(sp.get("rect"), f"{where}.rect", w, h)
            fade = c.numbers(sp.get("fade"), f"{where}.fade", 2)
            if fade is not None and any(v < 0 for v in fade):
                c.fail(f"{where}.fade", f"{fade} must be [right, bottom] fades of 0 px or more")
            hook = zones.get("hook_block") if zones else None
            if r is not None and hook is not None and not r.contains(Rect(hook.x0, hook.y0, hook.x1, min(hook.y1, r.y1))):
                c.fail(f"{where}.rect", f"{r} must hold the hook block's columns ({hook}): white words sit on it")
    credit = c.mapping(lay.get("map_credit"), f"{path}.map_credit", required=("x", "baseline", "align"))
    if credit is not None:
        c.number(credit.get("x"), f"{path}.map_credit.x", 0, w)
        c.number(credit.get("baseline"), f"{path}.map_credit.baseline", 0, h)
        c.choice(credit.get("align"), f"{path}.map_credit.align", ("left", "right"))


def _declared_cues(music: dict) -> Iterator[tuple[str | None, str]]:
    """(cut or None, id) of every cue declared inline in ``music.cues``."""
    cues = music.get("cues", [])
    groups = cues.items() if isinstance(cues, dict) else [(None, cues)]
    for cut, items in groups:
        if isinstance(items, list):
            for item in items:
                if isinstance(item, dict) and isinstance(item.get("id"), str):
                    yield cut, item["id"]


def _check_cues(c: _Check, music: dict, cuts: dict[str, Cut]) -> set[str]:
    cues = music.get("cues", [])
    if isinstance(cues, dict):
        groups = list(cues.items())
        for cut in cues:
            if cut not in cuts:
                c.fail(f"music.cues.{cut}", f"is not a cut (cuts: {', '.join(cuts) or 'none'})")
    elif isinstance(cues, list):
        groups = [(None, cues)]
    else:
        c.fail("music.cues", f"must be a list of {{id: …}} (or a mapping cut → list), not {_kind(cues)}")
        return set()
    declared: set[str] = set()
    for cut, items in groups:
        base = "music.cues" + (f".{cut}" if cut is not None else "")
        if not isinstance(items, list):
            c.fail(base, f"must be a list of {{id: …}}, not {_kind(items)}")
            continue
        seen: set[str] = set()
        for i, item in enumerate(items):
            p = f"{base}[{i}]"
            if not isinstance(item, dict) or "id" not in item:
                c.fail(p, "a cue is a mapping with an `id`")
                continue
            cid = item["id"]
            if not isinstance(cid, str) or not cid or any(ch.isspace() for ch in cid):
                c.fail(f"{p}.id", f"must be a non-empty id without spaces, not {cid!r}")
                continue
            if cid in seen:
                c.fail(f"{p}.id", f"{cid!r} is declared twice")
            seen.add(cid)
            declared.add(cid)
    return declared


#: A time written as a cue: ``cue:drop1.impact``, ``cue:swipe.open-1``,
#: ``cue:riser1@end`` (the span's end), ``cue:whip1+3``.
CUE_TIME_RE = re.compile(r"^cue:([^\s@+-][^\s@+]*?)(@end)?([+-]\d+)?$")


def _cue_references(node: Any, path: str) -> Iterator[tuple[str, Any]]:
    """(path, id) of every cue a section refers to: the value of a key
    ``cue``, each item of a key ``cues``, or a string ``cue:<id>…``, at any
    depth."""
    if isinstance(node, dict):
        for key, value in node.items():
            p = f"{path}.{key}"
            if key == "cue":
                yield p, value
            elif key == "cues" and isinstance(value, list):
                for i, item in enumerate(value):
                    yield f"{p}[{i}]", item
            else:
                yield from _cue_references(value, p)
    elif isinstance(node, list):
        for i, item in enumerate(node):
            yield from _cue_references(item, f"{path}[{i}]")
    elif isinstance(node, str) and node.startswith("cue:"):
        m = CUE_TIME_RE.match(node)
        yield path, (m.group(1) if m else node)


def _score_cue_ids(path: Path) -> list[str] | None:
    """The cue ids a score declares (its ``cues[].id``), or None when it
    cannot be read."""
    try:
        doc = yaml.safe_load(path.read_text(encoding="utf-8"))
    except (OSError, yaml.YAMLError):
        return None
    if not isinstance(doc, dict) or not isinstance(doc.get("cues"), list):
        return None
    return [c["id"] for c in doc["cues"] if isinstance(c, dict) and isinstance(c.get("id"), str)]


def _cue_frames(music: dict, cut: str) -> dict[str, tuple[int, int | None]]:
    """(frame, end frame) of every cue of ``cut``, from its score's positions
    (the frames events.json will carry: the engine checks that each sound
    lands there). Inline ``music.cues`` with a ``pos`` count too."""
    out: dict[str, tuple[int, int | None]] = {}
    for c_, item in ((c_, i) for c_, i in _declared_cue_items(music) if c_ in (None, cut)):
        try:
            out[item["id"]] = (tb.DEFAULT.frame(str(item["pos"])), None)
        except (KeyError, tb.TimeBaseError):
            pass
    scores = music.get("scores") or {}
    rel = scores.get(cut) if isinstance(scores, dict) else None
    if isinstance(rel, str):
        from .audio import score as score_mod          # the score's own reading of pos / offset / end / dur
        try:
            sc = score_mod.load(PROMO_REEL / rel)
        except (OSError, ValueError, yaml.YAMLError):
            return out                                  # a broken score is reported by _check_scores
        out.update({cue.id: (cue.frame, cue.end_frame) for cue in sc.cues})
    return out


def _declared_cue_items(music: dict) -> Iterator[tuple[str | None, dict]]:
    cues = music.get("cues", [])
    groups = cues.items() if isinstance(cues, dict) else [(None, cues)]
    for cut, items in groups:
        if isinstance(items, list):
            for item in items:
                if isinstance(item, dict) and isinstance(item.get("id"), str):
                    yield cut, item


_POS_TIME_RE = re.compile(r"^(\d+\.\d+(?:\.\d+|[e&a])?)([+-]\d+)?$")


def time_frame(ref: Any, cue_frames: dict[str, tuple[int, int | None]], frames: int) -> int | None:
    """The frame a scene time names (the grammar of promo/scenes/clock.py:
    ``cue:<id>[@end][±N]``, ``bar.beat.step[±N]``, ``end``, ``fN``, an int),
    resolved from the score's positions; None when it cannot be read here."""
    if isinstance(ref, bool):
        return None
    if isinstance(ref, int):
        return ref
    if not isinstance(ref, str):
        return None
    text = ref.strip()
    if text == "end":
        return frames
    m = CUE_TIME_RE.match(text)
    if m:
        if m.group(1) not in cue_frames:
            return None
        f, end = cue_frames[m.group(1)]
        if m.group(2):
            if end is None:
                return None
            f = end
        return f + int(m.group(3) or 0)
    m = _POS_TIME_RE.match(text)
    if m:
        try:
            return tb.DEFAULT.frame(m.group(1)) + int(m.group(2) or 0)
        except tb.TimeBaseError:
            return None
    if re.fullmatch(r"f\d+", text):
        return int(text[1:])
    return None


def _key_lists(node: Any, path: str) -> Iterator[tuple[str, list]]:
    """(path, keys) of every keyframe list under a scene's ``camera``: a list
    whose items are all ``{at, value, …}`` mappings, at any depth."""
    if isinstance(node, dict):
        for k, v in node.items():
            yield from _key_lists(v, f"{path}.{k}")
    elif isinstance(node, list) and node and all(isinstance(k, dict) and "at" in k and "value" in k for k in node):
        yield path, node


def _check_key_order(c: _Check, scenes: list, base: str, cue_frames: dict, frames: int) -> None:
    """Camera keys are written in time order: each key after the one before.
    The renderer sorts nothing — a key written out of order is a typo (a
    glide that snaps, a push that holds), so it is refused here, with both
    keys' frames."""
    for i, sc in enumerate(scenes):
        if not isinstance(sc, dict) or not isinstance(sc.get("camera"), dict):
            continue
        for path, keys in _key_lists(sc["camera"], f"{base}[{i}].camera"):
            prev = None
            for j, k in enumerate(keys):
                f = time_frame(k["at"], cue_frames, frames)
                if f is None:
                    c.fail(f"{path}[{j}].at", f"{k['at']!r} is not a time (cue:<id>, bar.beat.step, end)")
                    prev = None
                    continue
                if prev is not None and f <= prev[0]:
                    c.fail(f"{path}[{j}].at", f"{k['at']} is f{f}, not after the key before it ({prev[1]}, "
                                              f"f{prev[0]}): camera keys are written in time order")
                prev = (f, k["at"])


def _declared_ids(music: dict, cuts: dict[str, "Cut"], cut: str | None) -> set[str]:
    """Cue ids of ``cut`` (or of every cut): its score's, plus ``music.cues``."""
    ids = {cue_id for c_, cue_id in _declared_cues(music) if cut is None or c_ in (None, cut)}
    scores = music.get("scores") or {}
    if isinstance(scores, dict):
        for c_, rel in scores.items():
            if (cut is None or c_ == cut) and isinstance(rel, str):
                ids |= set(_score_cue_ids(PROMO_REEL / rel) or [])
    return ids


def _check_scores(c: _Check, music: dict, cuts: dict[str, "Cut"], named_cuts: set[str] | None = None) -> None:
    scores = music.get("scores")
    if scores is None:
        return
    if not isinstance(scores, dict):
        c.fail("music.scores", f"must be a mapping cut → score path, not {_kind(scores)}")
        return
    for cut, rel in scores.items():
        p = f"music.scores.{cut}"
        if cut not in (named_cuts if named_cuts is not None else cuts):
            c.fail(p, f"is not a cut (cuts: {', '.join(cuts) or 'none'})")
            continue
        if cut not in cuts:
            continue                       # the cut itself is broken: reported there
        if not isinstance(rel, str):
            c.fail(p, f"must be a path from tool/promo_reel, not {_kind(rel)}")
            continue
        path = PROMO_REEL / rel
        try:
            doc = yaml.safe_load(path.read_text(encoding="utf-8"))
        except OSError:
            c.fail(p, f"{rel}: no such score")
            continue
        except yaml.YAMLError as e:
            c.fail(p, f"{rel}: not valid YAML: {e}")
            continue
        if not isinstance(doc, dict):
            c.fail(p, f"{rel}: not a score")
            continue
        if doc.get("cut") != cut:
            c.fail(p, f"{rel} is the score of cut {doc.get('cut')!r}, not {cut}")
        if doc.get("bars") != cuts[cut].bars:
            c.fail(p, f"{rel} has {doc.get('bars')!r} bars; cut {cut} has {cuts[cut].bars}")
        ids = _score_cue_ids(path)
        if ids is None:
            c.fail(p, f"{rel} declares no cues")
            continue
        dup = sorted({i for i in ids if ids.count(i) > 1})
        if dup:
            c.fail(p, f"{rel} declares {', '.join(dup)} twice")
        inline = {cue_id for c_, cue_id in _declared_cues(music) if c_ in (None, cut)}
        both = sorted(inline & set(ids))
        if both:
            c.fail(f"music.cues", f"{', '.join(both)} already declared by the {cut} score ({rel}): one source")
