"""2.5D: a flat object (a phone, a carnet page) turned in 3D and seen through
a pinhole camera — exactly, as a 3×3 projective skia.Matrix.

A planar object seen in perspective is a homography of the plane, so ONE
skia.Matrix with its perspective row maps the object's own 2D coordinates to
the frame: images, paths and text drawn under it are perspective-correct
(skia resamples per pixel through the inverse map), with no mesh and no
approximation.

Conventions (frame px, y down):
  rot_x  degrees about the horizontal axis through the pivot; POSITIVE tips
         the TOP AWAY from the viewer (a page lying back on a desk).
  rot_y  degrees about the vertical axis; POSITIVE turns the RIGHT edge away.
  rot_z  degrees of in-plane roll, clockwise on screen.
  focal  the camera's distance to the object plane, in px. It sets how
         strong the perspective is: at 2400 px a 1080-wide frame sees about
         the field of view of a 50 mm lens on full frame turned vertical.
  scale  a zoom of the projected picture about the pivot (a camera push-in;
         it does not change the perspective). `z` moves the object away
         along the view axis (a dolly: perspective and size change together).
  dx, dy a move of the projected picture, in frame px.
The pivot is the object point that stays put under rotation and zoom: by
default the centre of the object's rest rectangle.
"""

from __future__ import annotations

import math
from dataclasses import dataclass, replace

import numpy as np
import skia

DEFAULT_FOCAL = 2400.0


@dataclass(frozen=True)
class Pose:
    rot_x: float = 0.0
    rot_y: float = 0.0
    rot_z: float = 0.0
    scale: float = 1.0
    dx: float = 0.0
    dy: float = 0.0
    z: float = 0.0
    focal: float = DEFAULT_FOCAL
    pivot: tuple[float, float] | None = None

    def but(self, **changes) -> "Pose":
        """A copy with some fields changed."""
        return replace(self, **changes)

    @property
    def is_flat(self) -> bool:
        return self.rot_x == 0.0 and self.rot_y == 0.0 and self.z == 0.0


def lerp_pose(a: Pose, b: Pose, t: float) -> Pose:
    """Field-by-field interpolation (pivots must agree)."""
    if a.pivot != b.pivot:
        raise ValueError("lerp_pose: the two poses have different pivots")
    f = lambda x, y: x + (y - x) * t if t != 1.0 else y
    return Pose(f(a.rot_x, b.rot_x), f(a.rot_y, b.rot_y), f(a.rot_z, b.rot_z), f(a.scale, b.scale),
                f(a.dx, b.dx), f(a.dy, b.dy), f(a.z, b.z), f(a.focal, b.focal), a.pivot)


def rotation(pose: Pose) -> np.ndarray:
    """R = Ry · Rx · Rz (roll, then tilt, then yaw), in a right-handed frame
    with x right, y down, z AWAY from the viewer."""
    ax, ay, az = (math.radians(v) for v in (pose.rot_x, pose.rot_y, pose.rot_z))
    cx, sx, cy, sy, cz, sz = math.cos(ax), math.sin(ax), math.cos(ay), math.sin(ay), math.cos(az), math.sin(az)
    rz = np.array([[cz, -sz, 0], [sz, cz, 0], [0, 0, 1]], dtype=np.float64)
    # top (y < 0) goes away (z > 0) for rot_x > 0: z' = -y·sin, y' = y·cos
    rx = np.array([[1, 0, 0], [0, cx, 0], [0, -sx, cx]], dtype=np.float64)
    rx[1, 2] = sx
    # right (x > 0) goes away (z > 0) for rot_y > 0: z' = x·sin, x' = x·cos
    ry = np.array([[cy, 0, -sy], [0, 1, 0], [sy, 0, cy]], dtype=np.float64)
    return ry @ rx @ rz


def homography(pose: Pose, rest: tuple[float, float, float, float]) -> np.ndarray:
    """The 3×3 map from rest-frame coordinates (the object drawn flat where it
    rests: `rest` = its (x0, y0, x1, y1) in frame px) to the frame under
    `pose`. Rows act on column vectors (x, y, 1)."""
    px, py = pose.pivot if pose.pivot is not None else ((rest[0] + rest[2]) / 2, (rest[1] + rest[3]) / 2)
    r = rotation(pose)
    f = pose.focal
    # an object point (X, Y, 0) relative to the pivot lands at R·(X, Y, 0) + (0, 0, f + z);
    # the pinhole puts it at f·(Px, Py)/Pz relative to the pivot.
    h0 = np.array([[r[0, 0], r[0, 1], 0.0],
                   [r[1, 0], r[1, 1], 0.0],
                   [r[2, 0] / f, r[2, 1] / f, (f + pose.z) / f]], dtype=np.float64)
    to_pivot = np.array([[1, 0, -px], [0, 1, -py], [0, 0, 1]], dtype=np.float64)
    back = np.array([[pose.scale, 0, px + pose.dx], [0, pose.scale, py + pose.dy], [0, 0, 1]], dtype=np.float64)
    h = back @ h0 @ to_pivot
    return h / h[2, 2]


def project(pose: Pose, rest: tuple[float, float, float, float], pts: np.ndarray, depth: float = 0.0) -> np.ndarray:
    """(n, 2) rest-frame points lifted to object depth `depth` (px, positive
    = behind the front face) and projected under `pose`. At depth 0 this is
    exactly `apply_many(homography(pose, rest), pts)`; the phone's back face
    (its slab thickness) is the same outline at depth > 0."""
    px, py = pose.pivot if pose.pivot is not None else ((rest[0] + rest[2]) / 2, (rest[1] + rest[3]) / 2)
    p = np.asarray(pts, dtype=np.float64)
    obj = np.c_[p[:, 0] - px, p[:, 1] - py, np.full(len(p), float(depth))]
    cam = obj @ rotation(pose).T
    d = cam[:, 2] + pose.focal + pose.z
    if np.any(d <= 0):
        raise ValueError("part of the object is behind the camera")
    k = pose.focal / d
    return np.c_[px + pose.dx + pose.scale * cam[:, 0] * k, py + pose.dy + pose.scale * cam[:, 1] * k]


def to_skia(h: np.ndarray) -> skia.Matrix:
    return skia.Matrix.MakeAll(*(float(v) for v in h.reshape(9)))


def from_skia(m: skia.Matrix) -> np.ndarray:
    return np.array([[m.get(i * 3 + j) for j in range(3)] for i in range(3)], dtype=np.float64)


def affine(scale_x: float, scale_y: float, tx: float, ty: float) -> np.ndarray:
    return np.array([[scale_x, 0, tx], [0, scale_y, ty], [0, 0, 1]], dtype=np.float64)


def apply(h: np.ndarray, x: float, y: float) -> tuple[float, float]:
    """Where `h` sends the point (x, y)."""
    X, Y, W = h @ np.array([x, y, 1.0])
    if W <= 0:
        raise ValueError("the point is behind the camera")
    return float(X / W), float(Y / W)


def apply_many(h: np.ndarray, pts: np.ndarray) -> np.ndarray:
    """(n, 2) points through `h`."""
    pts = np.asarray(pts, dtype=np.float64)
    hom = np.c_[pts, np.ones(len(pts))] @ h.T
    return hom[:, :2] / hom[:, 2:3]


def solve_offset(pose: Pose, rest, point: tuple[float, float], target: tuple[float, float]) -> Pose:
    """`pose` moved (dx, dy changed) so that the rest-frame `point` lands on
    the frame `target` — e.g. a macro that keeps one carnet entry centred."""
    x, y = apply(homography(pose.but(dx=0.0, dy=0.0), rest), *point)
    return pose.but(dx=target[0] - x, dy=target[1] - y)


def convex_hull(points: np.ndarray) -> np.ndarray:
    """The convex hull of (n, 2) points, counter-clockwise (monotone chain)."""
    pts = np.unique(np.asarray(points, dtype=np.float64), axis=0)
    if len(pts) < 3:
        return pts
    pts = pts[np.lexsort((pts[:, 1], pts[:, 0]))]

    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])

    lower: list = []
    for p in pts:
        while len(lower) >= 2 and cross(lower[-2], lower[-1], p) <= 0:
            lower.pop()
        lower.append(p)
    upper: list = []
    for p in pts[::-1]:
        while len(upper) >= 2 and cross(upper[-2], upper[-1], p) <= 0:
            upper.pop()
        upper.append(p)
    return np.array(lower[:-1] + upper[:-1])
