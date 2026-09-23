#!/usr/bin/env python3
"""Offline procedural PBR texture + HDR environment generator.

Shared by Shadow Chess 3D and Shadow Checkers (the file is identical in both
repos; the game is auto-detected from project.godot or forced with --game).

    python3 tools/assetgen/gen_textures.py                 # everything
    python3 tools/assetgen/gen_textures.py --only sq_maple,env
    python3 tools/assetgen/gen_textures.py --preview-dir /tmp/tex_previews

Everything is generated from fixed seeds (derived from the material name with
crc32) using periodic spectral noise, periodic Worley noise and analytic
patterns, so every tileable map wraps seamlessly in both axes and re-running
the script reproduces byte-identical output.

Per material <name> it writes into assets/textures/:
    <name>_albedo.jpg   sRGB colour, JPEG q92
    <name>_normal.png   tangent-space normal, OpenGL convention (green = +Y up)
    <name>_rough.jpg    greyscale roughness (white = rough), JPEG q92
and HDR environment panoramas (Radiance RGBE, RLE) into assets/textures/env/.

Dependencies: numpy, scipy, Pillow.  No network, no external assets.
"""
from __future__ import annotations

import argparse
import math
import os
import sys
import time
import zlib
from concurrent.futures import ProcessPoolExecutor

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

F32 = np.float32
TAU = 2.0 * math.pi


# =============================================================================
# colour helpers
# =============================================================================
def srgb2lin(c):
    c = np.asarray(c, dtype=F32)
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4).astype(F32)


def lin2srgb(c):
    c = np.clip(np.asarray(c, dtype=F32), 0.0, 1.0)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * np.power(c, 1 / 2.4) - 0.055).astype(F32)


def C(r, g, b):
    """sRGB (0..1) colour literal -> linear float32 triple."""
    return srgb2lin(np.array([r, g, b], F32))


def lerp(a, b, t):
    return a + (b - a) * t


def lerp3(a, b, t):
    """Blend colour images / colour triples with a scalar map t (H,W)."""
    t = np.asarray(t, F32)[..., None]
    return (a + (b - a) * t).astype(F32)


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return (t * t * (3.0 - 2.0 * t)).astype(F32)


def luminance(lin):
    return (0.2126 * lin[..., 0] + 0.7152 * lin[..., 1] + 0.0722 * lin[..., 2]).astype(F32)


def solid(N, col):
    return np.broadcast_to(np.asarray(col, F32), (N, N, 3)).astype(F32)


def normalize01(a):
    lo, hi = float(a.min()), float(a.max())
    return ((a - lo) / (hi - lo + 1e-12)).astype(F32)


# =============================================================================
# periodic noise primitives
# =============================================================================
def rng_for(name, salt=0):
    return np.random.default_rng((zlib.crc32(name.encode("utf-8")) * 2654435761 + salt) % (2 ** 63))


def coords(N):
    y, x = np.mgrid[0:N, 0:N].astype(F32)
    return x, y


def spectral(N, rng, fmax, fmin=1.0, slope=1.0, stretch=(1.0, 1.0), angle=0.0):
    """Periodic Gaussian noise (zero mean, unit std) by spectral synthesis.

    Frequencies are in cycles per tile.  `stretch=(sx, sy)` elongates features
    along x / y by that factor (after rotating by `angle` radians).  Amplitude
    spectrum ~ f^-slope with a soft low cut at fmin and a Gaussian roll-off at
    fmax.  Because only integer frequencies exist on the grid the result wraps
    perfectly in both axes.
    """
    fy = (np.fft.fftfreq(N) * N).astype(F32)[:, None]
    fx = (np.fft.rfftfreq(N) * N).astype(F32)[None, :]
    if angle:
        ca, sa = math.cos(angle), math.sin(angle)
        u = fx * ca + fy * sa
        v = -fx * sa + fy * ca
    else:
        u, v = fx, fy
    f = np.sqrt((u * stretch[0]) ** 2 + (v * stretch[1]) ** 2)
    with np.errstate(divide="ignore"):
        amp = np.where(f > 0, np.maximum(f, 1e-3) ** (-slope), 0.0)
    amp *= np.exp(-((f / fmax) ** 2))
    amp *= 1.0 - np.exp(-((f / max(fmin, 1e-3)) ** 2) * 2.0)
    white = np.fft.rfft2(rng.standard_normal((N, N)).astype(F32))
    out = np.fft.irfft2(white * amp.astype(F32), s=(N, N)).astype(F32)
    out -= out.mean()
    out /= out.std() + 1e-12
    return out


def aniso(N, rng, fx, fy, slope=1.0, fmin=1.0, broken=0.0):
    """Noise with approx. cutoff fx cycles/tile along x and fy along y.

    With a power-law spectrum the pure-y (fx=0) components dominate strongly
    elongated noise and produce dead-straight bands across the whole tile.
    `broken` (0..1) low-cuts the effective frequency below broken*fy/fx so the
    streaks start, fade and wander along x instead.
    """
    fx = max(fx, 0.05)
    st = fy / fx
    return spectral(N, rng, fmax=fy, fmin=max(fmin, broken * st), slope=slope, stretch=(st, 1.0))


def samp(field, X, Y, order=1):
    """Sample a periodic grid at pixel coordinates (X=col, Y=row), wrapping."""
    return ndimage.map_coordinates(field, [Y, X], order=order, mode="grid-wrap",
                                   prefilter=order > 1).astype(F32)


def grad(a):
    gx = (np.roll(a, -1, 1) - np.roll(a, 1, 1)) * 0.5
    gy = (np.roll(a, -1, 0) - np.roll(a, 1, 0)) * 0.5
    return gx.astype(F32), gy.astype(F32)


def blur(a, sigma):
    if sigma <= 0:
        return a
    return ndimage.gaussian_filter(a, sigma, mode="wrap").astype(F32)


def noise1d(n, rng, fmax, slope=1.5):
    """Periodic 1-D noise of length n (unit std)."""
    f = np.fft.rfftfreq(n) * n
    with np.errstate(divide="ignore"):
        amp = np.where(f > 0, np.maximum(f, 1e-3) ** (-slope), 0.0) * np.exp(-((f / fmax) ** 2))
    out = np.fft.irfft(np.fft.rfft(rng.standard_normal(n)) * amp, n)
    out -= out.mean()
    return (out / (out.std() + 1e-12)).astype(F32)


class Worley:
    """Periodic cellular noise on an nx*ny jittered grid (period 1 in tile units).

    eval(u, v) takes tile coordinates (any range, period 1) and returns
    F1, F2 (in cell units) and a random id in [0,1) of the nearest feature.
    """

    def __init__(self, rng, nx, ny=None, jitter=0.9):
        self.nx, self.ny = int(nx), int(ny or nx)
        self.px = rng.random((self.ny, self.nx)).astype(F32)
        self.py = rng.random((self.ny, self.nx)).astype(F32)
        self.pid = rng.random((self.ny, self.nx)).astype(F32)
        self.jit = F32(jitter)

    def eval(self, u, v, want_f2=True):
        gx = np.asarray(u, F32) * self.nx
        gy = np.asarray(v, F32) * self.ny
        cx = np.floor(gx)
        cy = np.floor(gy)
        fx = (gx - cx).astype(F32)
        fy = (gy - cy).astype(F32)
        cx = cx.astype(np.int64)
        cy = cy.astype(np.int64)
        f1 = np.full(fx.shape, 1e9, F32)
        f2 = np.full(fx.shape, 1e9, F32)
        idd = np.zeros(fx.shape, F32)
        for oy in (-1, 0, 1):
            iy = (cy + oy) % self.ny
            for ox in (-1, 0, 1):
                ix = (cx + ox) % self.nx
                dx = ox + 0.5 + self.jit * (self.px[iy, ix] - 0.5) - fx
                dy = oy + 0.5 + self.jit * (self.py[iy, ix] - 0.5) - fy
                d = dx * dx + dy * dy
                closer = d < f1
                if want_f2:
                    f2 = np.where(closer, f1, np.minimum(f2, d))
                idd = np.where(closer, self.pid[iy, ix], idd)
                f1 = np.where(closer, d, f1)
        return np.sqrt(f1), np.sqrt(f2), idd


def zero_set_dist(F):
    """Approximate pixel distance to the zero set of a smooth periodic field."""
    gx, gy = grad(F)
    return (np.abs(F) / (np.hypot(gx, gy) + 1e-5)).astype(F32)


def warped(N, rng, fmax, slope, warp_px, warp_fmax, stretch=(1, 1), angle=0.0, order=3):
    """Periodic noise sampled through a periodic domain warp."""
    base = spectral(N, rng, fmax=fmax, slope=slope, stretch=stretch, angle=angle)
    wx = spectral(N, rng, fmax=warp_fmax, slope=1.6)
    wy = spectral(N, rng, fmax=warp_fmax, slope=1.6)
    X, Y = coords(N)
    return samp(base, X + warp_px * wx, Y + warp_px * wy, order=order)


# =============================================================================
# material container, normal maps, output
# =============================================================================
class Mat:
    def __init__(self, albedo, height, nstr, rough, metallic=0.0, tileable=True,
                 albedo_subsampling=None):
        self.albedo = albedo.astype(F32)          # linear RGB
        self.height = height.astype(F32)          # arbitrary units
        self.nstr = float(nstr)                   # slope multiplier
        self.rough = np.clip(rough, 0.02, 1.0).astype(F32)
        self.metallic = metallic
        self.tileable = tileable
        self.albedo_subsampling = albedo_subsampling


def height_to_normal(h, strength, wrap=True):
    """Tangent-space normal, OpenGL convention: +X right, +Y up (image row -1)."""
    if wrap:
        gx, gy = grad(h)
    else:
        gy, gx = np.gradient(h)
    nx = -gx * strength
    ny = gy * strength          # rows go down, +Y goes up
    nz = np.ones_like(nx)
    inv = 1.0 / np.sqrt(nx * nx + ny * ny + nz * nz)
    return np.stack([nx * inv, ny * inv, nz * inv], axis=-1).astype(F32)


def encode_normal(n):
    return np.clip(np.round((n * 0.5 + 0.5) * 255.0), 0, 255).astype(np.uint8)


def to_u8(a):
    return np.clip(np.round(a * 255.0), 0, 255).astype(np.uint8)


def seam_ratio(img, jpeg=False):
    """Wrap-around seam check.

    D(c) = mean |column c - column c-1| (indices mod N, so D(0) is the wrap
    pair column N-1 | column 0); same for rows.  Returns (ratio, frac):
      ratio = D(0) / mean(D over interior pairs)  (~1 = seam looks like any
              other neighbour pair; a real seam is typically >> 2)
      frac  = fraction of interior pairs at least as discontinuous as the
              seam (a real seam is the worst pair -> 0.0)
    For decoded JPEG maps (jpeg=True) the reference pairs are the interior
    16 px MCU boundaries, since the tile edge is itself a block boundary.
    Worst axis is reported.
    """
    a = img.astype(np.float32)
    if a.ndim == 3:
        a = a.mean(axis=2)
    worst = (0.0, 1.0)
    for m in (a, a.T):
        D = np.abs(m - np.roll(m, 1, axis=1)).mean(axis=0)
        ref = D[16::16] if jpeg else D[1:]
        ratio = float(D[0] / (ref.mean() + 1e-3))
        frac = float((ref >= D[0]).mean())
        if ratio > worst[0]:
            worst = (ratio, min(frac, worst[1]))
    return worst


def save_material(name, mat, out_dir):
    alb = lin2srgb(np.clip(mat.albedo, 0.0, 0.92))
    alb8 = to_u8(alb)
    wrap = mat.tileable
    nrm8 = encode_normal(height_to_normal(mat.height, mat.nstr, wrap=wrap))
    rgh8 = to_u8(mat.rough)
    paths = {
        "albedo": os.path.join(out_dir, f"{name}_albedo.jpg"),
        "normal": os.path.join(out_dir, f"{name}_normal.png"),
        "rough": os.path.join(out_dir, f"{name}_rough.jpg"),
    }
    sub = mat.albedo_subsampling if mat.albedo_subsampling is not None else 2
    Image.fromarray(alb8, "RGB").save(paths["albedo"], quality=92, subsampling=sub, optimize=True)
    Image.fromarray(nrm8, "RGB").save(paths["normal"], optimize=True, compress_level=9)
    Image.fromarray(rgh8, "L").save(paths["rough"], quality=92, optimize=True)
    return paths, alb8, nrm8, rgh8


# =============================================================================
# preview rendering (numpy "lit" render of the saved maps)
# =============================================================================
def _resize(a8, size, mode):
    return np.asarray(Image.fromarray(a8, mode).resize((size, size), Image.LANCZOS))


def shade(alb8, nrm8, rgh8, metallic):
    """Render a plane lit by a grazing point light, viewed from the front.

    Uses the *decoded* normal map (OpenGL convention) so a wrong green channel
    shows up as bumps lit from below.  Light sits at the top of the frame.
    """
    S = alb8.shape[0]
    alb = srgb2lin(alb8.astype(F32) / 255.0)
    n = nrm8.astype(F32) / 127.5 - 1.0
    nx, ny_up, nz = n[..., 0], n[..., 1], n[..., 2]
    ny = -ny_up                       # image space: y down
    ln = np.sqrt(nx * nx + ny * ny + nz * nz) + 1e-6
    nx, ny, nz = nx / ln, ny / ln, nz / ln
    rough = np.clip(rgh8.astype(F32) / 255.0, 0.03, 1.0)
    y, x = (np.mgrid[0:S, 0:S].astype(F32) + 0.5) / S
    Lp = np.array([0.35, -0.45, 0.55], F32)   # light above the top edge
    Cp = np.array([0.5, 1.45, 0.6], F32)      # camera in front of bottom edge
    lx, ly, lz = Lp[0] - x, Lp[1] - y, Lp[2]
    ld = np.sqrt(lx * lx + ly * ly + lz * lz)
    lx, ly, lz = lx / ld, ly / ld, lz / ld
    vx, vy, vz = Cp[0] - x, Cp[1] - y, np.full_like(x, Cp[2])
    vd = np.sqrt(vx * vx + vy * vy + vz * vz)
    vx, vy, vz = vx / vd, vy / vd, vz / vd
    hx, hy, hz = lx + vx, ly + vy, lz + vz
    hd = np.sqrt(hx * hx + hy * hy + hz * hz)
    hx, hy, hz = hx / hd, hy / hd, hz / hd
    ndl = np.clip(nx * lx + ny * ly + nz * lz, 0, 1)
    ndv = np.clip(nx * vx + ny * vy + nz * vz, 1e-3, 1)
    ndh = np.clip(nx * hx + ny * hy + nz * hz, 0, 1)
    vdh = np.clip(vx * hx + vy * hy + vz * hz, 0, 1)
    a = rough * rough
    a2 = a * a
    D = a2 / (math.pi * (ndh * ndh * (a2 - 1) + 1) ** 2)
    k = (rough + 1) ** 2 / 8
    G = (ndl / (ndl * (1 - k) + k)) * (ndv / (ndv * (1 - k) + k))
    F0 = lerp(np.full_like(alb, 0.04), alb, metallic)
    Fr = F0 + (1 - F0) * ((1 - vdh) ** 5)[..., None]
    spec = Fr * (D * G / (4 * np.maximum(ndl, 1e-3) * ndv))[..., None]
    diff = (1 - Fr) * alb * (1 - metallic) / math.pi
    power = 5.0
    col = (diff + spec) * (ndl * power)[..., None] + alb * (0.06 * (1 - metallic)) + F0 * 0.08
    col = col / (1 + col)            # Reinhard
    return to_u8(lin2srgb(col * 1.6))


def _label(img, text):
    d = ImageDraw.Draw(img)
    d.rectangle([4, 4, 8 + 7 * len(text), 20], fill=(0, 0, 0))
    d.text((6, 6), text, fill=(255, 220, 120))


def preview_sheet(name, alb8, nrm8, rgh8, mat, path):
    N = alb8.shape[0]
    P = 512
    sheet = Image.new("RGB", (3 * P, 3 * P), (20, 20, 20))
    for i, (img, mode, lab) in enumerate(((alb8, "RGB", "albedo"), (nrm8, "RGB", "normal"),
                                          (rgh8, "L", "roughness"))):
        tile = Image.fromarray(_resize(img, P, mode), mode).convert("RGB")
        _label(tile, lab)
        sheet.paste(tile, (i * P, 0))
    # 2x2 tiled lit render at half res per tile
    a = _resize(alb8, P, "RGB")
    nn = _resize(nrm8, P, "RGB")
    r = _resize(rgh8, P, "L")
    if mat.tileable:
        a2, n2, r2 = (np.tile(a, (2, 2, 1)), np.tile(nn, (2, 2, 1)), np.tile(r, (2, 2)))
    else:
        a2, n2, r2 = (_resize(alb8, 2 * P, "RGB"), _resize(nrm8, 2 * P, "RGB"),
                      _resize(rgh8, 2 * P, "L"))
    lit = Image.fromarray(shade(a2, n2, r2, mat.metallic))
    _label(lit, "lit 2x2 tiled" if mat.tileable else "lit (single)")
    sheet.paste(lit, (0, P))
    # full-res crops around the tile corner (seam at crop centre)
    h = N // 2
    sh = (h, h) if mat.tileable else (0, 0)
    ra = np.roll(alb8, sh, (0, 1))[h - P // 2:h + P // 2, h - P // 2:h + P // 2]
    rn = np.roll(nrm8, sh, (0, 1))[h - P // 2:h + P // 2, h - P // 2:h + P // 2]
    rr = np.roll(rgh8, sh, (0, 1))[h - P // 2:h + P // 2, h - P // 2:h + P // 2]
    c1 = Image.fromarray(shade(ra, rn, rr, mat.metallic))
    _label(c1, "lit 1:1 seam corner" if mat.tileable else "lit 1:1 centre")
    c2 = Image.fromarray(ra)
    _label(c2, "albedo 1:1 seam corner" if mat.tileable else "albedo 1:1 centre")
    sheet.paste(c1, (2 * P, P))
    sheet.paste(c2, (2 * P, 2 * P))
    d = ImageDraw.Draw(sheet)
    d.text((2 * P + 8, 3 * P - 16), name, fill=(255, 255, 255))
    sheet.save(path)


# =============================================================================
# WOOD
# =============================================================================
class Wood:
    """Periodic wood figure.  Grain runs along +x (U).

    Growth-ring contour r(x,y) = rings*y/Ns + warp fields (domain-warped,
    elongated along x), so ring lines are smooth, mostly parallel curves that
    occasionally form flat-sawn arches.  Pores, fibre streaks, grain lines,
    mineral streaks, medullary rays and ribbon figure are evaluated in a fibre
    coordinate system (x, Yf) that only loosely follows the ring warp (fibres
    run along the log axis), so nothing stretches where arches fold over.
    eval() accepts arbitrary coordinate arrays (e.g. plank-local coords).
    """

    def __init__(self, rng, Ns=1024, rings=16, warp=1.0, warp_f=(1.0, 3.0), wobble=0.08,
                 wobble_f=(4.0, 24.0), ring_var=0.3, late=(0.55, 0.95), ring_amp=(0.6, 1.0),
                 pore_len=14, pore_w=6, pore_keep=0.35, pore_r=0.3, ring_porous=False,
                 ray_len=0, ray_w=12, ray_keep=0.25, fibre_f=(10.0, 300.0),
                 streak_f=(3.0, 40.0), ribbon_k=0, curl_k=0, follow=0.3,
                 lines_f=(2.5, 110.0), lines_w=1.0, lines2_f=(1.5, 40.0), lines2_w=1.6):
        self.Ns, self.rings = Ns, int(rings)
        # sparse thin grain lines = zero sets of noise elongated along x
        self.gl_d = zero_set_dist(aniso(Ns, rng, lines_f[0], lines_f[1], slope=1.0, broken=0.5))
        self.gl_op = aniso(Ns, rng, 2.5, 10.0, slope=1.5, broken=0.5)
        self.gl_w = lines_w
        self.gl2_d = zero_set_dist(aniso(Ns, rng, lines2_f[0], lines2_f[1], slope=1.2, broken=0.5))
        self.gl2_op = aniso(Ns, rng, 2.0, 6.0, slope=1.5, broken=0.5)
        self.gl2_w = lines2_w
        self.warp, self.wobble, self.ring_var = warp, wobble, ring_var
        self.late = late
        self.wbig = aniso(Ns, rng, warp_f[0], warp_f[1], slope=2.0)
        self.wsmall = aniso(Ns, rng, wobble_f[0], wobble_f[1], slope=1.2)
        # limit how much the fibre coordinate follows the ring warp so it never folds
        gy = np.abs(np.gradient(warp * self.wbig + wobble * self.wsmall, axis=0)).max() * Ns / self.rings
        self.follow = float(min(follow, 0.45 / max(gy, 1e-6)))
        self.gres = 32
        self.gtab = noise1d(self.rings * self.gres, rng, fmax=self.rings * 1.5, slope=1.0) * 0.18
        self.ramp = (ring_amp[0] + (ring_amp[1] - ring_amp[0]) * rng.random(self.rings)).astype(F32)
        self.pores = Worley(rng, max(1, Ns // pore_len), max(1, Ns // pore_w), 0.95) if pore_keep > 0 else None
        self.pore_keep, self.pore_r, self.ring_porous = pore_keep, pore_r, ring_porous
        self.rays = Worley(rng, max(1, Ns // ray_len), max(1, Ns // ray_w), 0.9) if ray_len else None
        self.ray_keep = ray_keep
        self.fib = aniso(Ns, rng, fibre_f[0], fibre_f[1], slope=0.5, fmin=2.0, broken=0.6)
        self.fib2 = aniso(Ns, rng, fibre_f[0] * 3, fibre_f[1] * 1.5, slope=0.3, fmin=4.0, broken=0.6)
        self.strk = aniso(Ns, rng, streak_f[0], streak_f[1], slope=1.2, broken=0.7)
        self.cv = spectral(Ns, rng, fmax=5.0, slope=1.6)
        self.cv2 = aniso(Ns, rng, 2.0, 12.0, slope=1.4, broken=0.5)
        self.rib = spectral(Ns, rng, fmax=3.0, slope=2.0)
        self.ribbon_k = ribbon_k
        self.curl_k = curl_k
        self.curl_w = aniso(Ns, rng, 6.0, 2.0, slope=1.5)

    def eval(self, X, Y):
        Ns = self.Ns
        disp = self.warp * samp(self.wbig, X, Y, 3) + self.wobble * samp(self.wsmall, X, Y, 1)
        r = self.rings * Y / Ns + disp
        # fibres/pores run along the log axis (x) and only loosely follow the
        # ring waviness -> no stretching where flat-sawn arches fold over
        Yf = (Y + self.follow * disp * (Ns / self.rings)).astype(F32)
        rr = np.mod(r, self.rings) * self.gres
        g = np.interp(rr.ravel(), np.arange(self.gtab.size), self.gtab,
                      period=self.gtab.size).reshape(r.shape).astype(F32)
        r2 = (r + self.ring_var * g).astype(F32)
        k = np.floor(r2)
        f = (r2 - k).astype(F32)
        amp = self.ramp[np.mod(k, self.rings).astype(np.int64)]
        gx, gy = grad(disp)          # disp is periodic; the ramp adds rings/Ns along y
        pw = np.clip(np.hypot(gx, gy + self.rings / Ns), 1e-4, 0.5)
        a0, a1 = self.late
        lw = smoothstep(a0, a1, f)
        edge = np.clip(pw * 1.6, 0.02, 0.35)
        lw = lw * (1.0 - smoothstep(1.0 - edge, 1.0, f)) * amp
        u, v = X / Ns, Yf / Ns
        out = {"lw": lw.astype(F32), "f": f, "r": r2, "yg": Yf}
        if self.pores is not None:
            f1, _, pid = self.pores.eval(u, v, want_f2=False)
            keep = np.full_like(f1, self.pore_keep)
            if self.ring_porous:
                keep = self.pore_keep * (0.12 + 0.88 * (1 - smoothstep(0.04, 0.32, f)))
            sel = (smoothstep(keep + 0.02, keep - 0.02, pid)
                   * (0.35 + 0.65 * np.clip(pid / np.maximum(keep, 1e-3), 0, 1)))
            out["pores"] = (smoothstep(self.pore_r, self.pore_r * 0.4, f1) * sel).astype(F32)
        else:
            out["pores"] = np.zeros_like(f)
        if self.rays is not None:
            f1, _, rid = self.rays.eval(u + 0.37, v * 1.0 + 0.11, want_f2=False)
            sel = smoothstep(self.ray_keep + 0.02, self.ray_keep - 0.02, rid) * (0.4 + 0.6 * rid / self.ray_keep)
            out["rays"] = (smoothstep(0.40, 0.18, f1) * sel).astype(F32)
        else:
            out["rays"] = np.zeros_like(f)
        out["fibre"] = (0.7 * samp(self.fib, X, Yf, 1) + 0.5 * samp(self.fib2, X, Yf, 1)).astype(F32)
        out["streak"] = samp(self.strk, X, Yf, 1)
        l1 = np.exp(-(samp(self.gl_d, X, Yf, 1) / self.gl_w) ** 2) * smoothstep(-0.8, 1.0, samp(self.gl_op, X, Yf))
        l2 = np.exp(-(samp(self.gl2_d, X, Yf, 1) / self.gl2_w) ** 2) * smoothstep(-0.4, 1.4, samp(self.gl2_op, X, Yf))
        out["lines"] = np.maximum(l1, l2).astype(F32)
        out["colvar"] = samp(self.cv, X, Y, 1)
        out["colvar2"] = samp(self.cv2, X, Yf, 1)
        if self.ribbon_k:
            ph = TAU * self.ribbon_k * Yf / Ns + 1.5 * samp(self.rib, X, Y, 1)
            out["ribbon"] = np.sin(ph).astype(F32)
        else:
            out["ribbon"] = np.zeros_like(f)
        if self.curl_k:
            ph = TAU * self.curl_k * X / Ns + 2.0 * samp(self.curl_w, X, Y, 1)
            out["curl"] = np.sin(ph).astype(F32)
        else:
            out["curl"] = np.zeros_like(f)
        return out


def wood_shade(d, s, rng=None):
    """Combine wood field maps with a style dict -> (albedo_lin, height, rough)."""
    col = lerp3(s["early"], s["late"], d["lw"] * s.get("contrast", 1.0))
    if "alt" in s:   # large-scale colour zones
        z = smoothstep(-0.6, 1.2, d["colvar"]) * s.get("alt_amt", 0.5)
        col = lerp3(col, np.asarray(s["alt"], F32) * (col / (np.asarray(s["early"], F32) + 1e-4)), z)
    col = col * (1.0 + s.get("bright_var", 0.05) * d["colvar2"])[..., None]
    col = col * (1.0 - s.get("fibre_amt", 0.04) * d["fibre"])[..., None]
    if "streak_col" in s:
        st = smoothstep(s.get("streak_lo", 0.8), s.get("streak_hi", 2.2), d["streak"]) * s.get("streak_amt", 0.6)
        col = lerp3(col, s["streak_col"], st)
    else:
        st = np.zeros_like(d["lw"])
    if s.get("line_amt", 0.0) > 0:
        lc = s.get("line_col", np.asarray(s["late"], F32) * 0.7)
        col = lerp3(col, lc, d["lines"] * s["line_amt"])
    if "pore_col" in s:
        col = lerp3(col, s["pore_col"], d["pores"] * s.get("pore_amt", 0.8))
    if "ray_col" in s:
        col = lerp3(col, s["ray_col"], d["rays"] * s.get("ray_amt", 0.6))
    col = col * (1.0 + s.get("ribbon_amt", 0.0) * d["ribbon"])[..., None]
    col = col * (1.0 + s.get("curl_amt", 0.0) * d["curl"])[..., None]
    h = (-s.get("pore_depth", 1.0) * d["pores"] + s.get("late_h", 0.15) * d["lw"]
         - s.get("line_depth", 0.1) * d["lines"]
         + s.get("fibre_h", 0.08) * d["fibre"] + s.get("ray_h", 0.2) * d["rays"])
    r0, r1 = s.get("rough", (0.35, 0.45))
    rough = (r0 + (r1 - r0) * (0.5 + 0.25 * d["colvar2"])
             + s.get("r_pore", 0.25) * d["pores"]
             + s.get("r_late", 0.03) * d["lw"]
             - s.get("r_ray", 0.08) * d["rays"]
             + s.get("r_fibre", 0.02) * d["fibre"]
             + s.get("r_ribbon", 0.0) * d["ribbon"]
             + s.get("r_streak", 0.0) * st
             + s.get("r_line", 0.03) * d["lines"])
    return col.astype(F32), h.astype(F32), rough.astype(F32)


def wood_material(N, rng, wood_kw, style, nstr):
    if N < 1024:     # keep pore / ray figure the same size relative to the tile
        k = N / 1024.0
        wood_kw = dict(wood_kw)
        for key in ("pore_len", "ray_len"):
            if wood_kw.get(key):
                wood_kw[key] = max(8, int(wood_kw[key] * k))
        wood_kw["pore_w"] = max(3, int(wood_kw.get("pore_w", 6) * k))
        style = dict(style, pore_depth=style.get("pore_depth", 1.0) * 0.5)
    X, Y = coords(N)
    w = Wood(rng, Ns=N, **wood_kw)
    d = w.eval(X, Y)
    col, h, rough = wood_shade(d, style)
    return Mat(col, h, nstr, rough)


# ---- wood species --------------------------------------------------------------
def _rings(n, N):
    return max(4, int(round(n * N / 1024)))


def m_maple(N, rng, warm=0.0):
    wk = dict(rings=_rings(30, N), warp=3.5, warp_f=(0.7, 2.2), wobble=0.10, ring_var=0.5,
              follow=0.25, late=(0.74, 0.97), ring_amp=(0.35, 1.0), pore_len=40, pore_w=3,
              pore_keep=0.12, pore_r=0.3, fibre_f=(8.0, 380.0), streak_f=(2.5, 30.0),
              lines_f=(2.5, 120.0), lines_w=0.9)
    st = dict(early=C(0.90 - 0.02 * warm, 0.815 - 0.03 * warm, 0.645 - 0.045 * warm),
              late=C(0.80 - 0.01 * warm, 0.665 - 0.03 * warm, 0.47 - 0.04 * warm), contrast=0.8,
              alt=C(0.87, 0.755, 0.56), alt_amt=0.35, bright_var=0.035, fibre_amt=0.035,
              streak_col=C(0.78, 0.66, 0.50), streak_lo=1.6, streak_hi=2.8, streak_amt=0.35,
              line_amt=0.14, pore_col=C(0.70, 0.57, 0.40), pore_amt=0.25,
              pore_depth=0.35, late_h=0.05, fibre_h=0.05, line_depth=0.05,
              rough=(0.33, 0.41), r_pore=0.06, r_late=0.02)
    return wood_material(N, rng, wk, st, nstr=1.4)


def m_ebony(N, rng, piece=False):
    wk = dict(rings=_rings(16, N), warp=3.0, warp_f=(0.7, 2.2), wobble=0.08, ring_var=0.4,
              late=(0.70, 0.97), ring_amp=(0.2, 1.0), pore_len=50, pore_w=3,
              pore_keep=0.12, pore_r=0.3, fibre_f=(6.0, 260.0), streak_f=(3.0, 50.0),
              lines_f=(3.0, 90.0), lines_w=1.1, lines2_f=(2.5, 30.0), lines2_w=2.0)
    st = dict(early=C(0.172, 0.155, 0.146), late=C(0.152, 0.140, 0.134), contrast=1.0,
              bright_var=0.05, fibre_amt=0.04,
              streak_col=C(0.25, 0.185, 0.145), streak_lo=0.9, streak_hi=2.6, streak_amt=0.6,
              line_amt=0.35, line_col=C(0.23, 0.175, 0.14),
              pore_col=C(0.148, 0.135, 0.13), pore_amt=0.5,
              pore_depth=0.15, late_h=0.02, fibre_h=0.03, line_depth=0.02,
              rough=(0.10, 0.15), r_pore=0.04, r_late=0.01, r_streak=0.02, r_line=0.01)
    return wood_material(N, rng, wk, st, nstr=0.9 if not piece else 0.6)


def m_boxwood(N, rng):
    wk = dict(rings=_rings(40, N), warp=3.0, warp_f=(0.7, 2.2), wobble=0.06, ring_var=0.5,
              late=(0.80, 0.98), ring_amp=(0.25, 0.9), pore_len=36, pore_w=3,
              pore_keep=0.10, pore_r=0.3, fibre_f=(8.0, 380.0), streak_f=(2.0, 20.0),
              lines_f=(2.5, 140.0), lines_w=0.8)
    st = dict(early=C(0.87, 0.73, 0.43), late=C(0.79, 0.61, 0.33), contrast=0.8,
              alt=C(0.84, 0.66, 0.36), alt_amt=0.4, bright_var=0.03, fibre_amt=0.03,
              line_amt=0.12, pore_col=C(0.70, 0.54, 0.29), pore_amt=0.25,
              pore_depth=0.3, late_h=0.04, fibre_h=0.04, line_depth=0.04,
              rough=(0.34, 0.42), r_pore=0.06)
    return wood_material(N, rng, wk, st, nstr=1.2)


def m_rosewood(N, rng):
    wk = dict(rings=_rings(12, N), warp=3.5, warp_f=(0.7, 2.2), wobble=0.10, ring_var=0.5,
              late=(0.62, 0.96), ring_amp=(0.4, 1.0), pore_len=70, pore_w=4,
              pore_keep=0.28, pore_r=0.32, fibre_f=(6.0, 280.0), streak_f=(2.5, 40.0),
              lines_f=(2.5, 100.0), lines_w=1.3, lines2_f=(2.0, 36.0), lines2_w=3.0)
    st = dict(early=C(0.39, 0.215, 0.205), late=C(0.27, 0.135, 0.14), contrast=0.9,
              alt=C(0.47, 0.275, 0.20), alt_amt=0.45, bright_var=0.08, fibre_amt=0.07,
              streak_col=C(0.14, 0.075, 0.075), streak_lo=0.9, streak_hi=2.2, streak_amt=0.75,
              line_amt=0.7, line_col=C(0.13, 0.07, 0.07),
              pore_col=C(0.14, 0.08, 0.07), pore_amt=0.8,
              pore_depth=0.8, late_h=0.06, fibre_h=0.07, line_depth=0.15,
              rough=(0.26, 0.36), r_pore=0.18)
    return wood_material(N, rng, wk, st, nstr=1.8)


def m_walnut(N, rng, dark=0.0):
    wk = dict(rings=_rings(14, N), warp=2.6, warp_f=(0.6, 2.2), wobble=0.08, ring_var=0.5,
              late=(0.62, 0.96), ring_amp=(0.45, 1.0), pore_len=80, pore_w=4,
              pore_keep=0.30, pore_r=0.32, fibre_f=(6.0, 260.0), streak_f=(2.5, 30.0),
              lines_f=(2.5, 90.0), lines_w=1.1, lines2_f=(2.0, 30.0), lines2_w=2.2)
    k = 1.0 - dark
    st = dict(early=C(0.42 * k, 0.285 * k, 0.18 * k), late=C(0.27 * k, 0.17 * k, 0.105 * k), contrast=0.9,
              alt=C(0.46 * k, 0.30 * k, 0.17 * k), alt_amt=0.45, bright_var=0.07, fibre_amt=0.06,
              streak_col=C(0.20 * k, 0.12 * k, 0.08 * k), streak_lo=1.0, streak_hi=2.4, streak_amt=0.5,
              line_amt=0.5, line_col=C(0.16, 0.10, 0.065),
              pore_col=C(0.12, 0.075, 0.05), pore_amt=0.8,
              pore_depth=0.6, late_h=0.08, fibre_h=0.06, line_depth=0.15,
              rough=(0.30, 0.42), r_pore=0.25)
    return wood_material(N, rng, wk, st, nstr=2.0)


def m_mahogany(N, rng, frame=False, piece=False):
    wk = dict(rings=_rings(14, N), warp=2.4, warp_f=(0.6, 2.2), wobble=0.06, ring_var=0.5,
              late=(0.68, 0.97), ring_amp=(0.35, 0.9), pore_len=64, pore_w=4,
              pore_keep=0.28, pore_r=0.32, fibre_f=(6.0, 260.0), streak_f=(1.5, 18.0),
              ribbon_k=max(2, int((5 if frame else 7) * N / 1024)),
              lines_f=(2.0, 100.0), lines_w=1.0)
    k = 0.82 if frame else 1.0
    st = dict(early=C(0.50 * k, 0.235 * k, 0.135 * k), late=C(0.38 * k, 0.165 * k, 0.095 * k), contrast=0.8,
              alt=C(0.53 * k, 0.215 * k, 0.11 * k), alt_amt=0.4, bright_var=0.05, fibre_amt=0.06,
              line_amt=0.35, line_col=C(0.26 * k, 0.10 * k, 0.06 * k),
              pore_col=C(0.20, 0.08, 0.05), pore_amt=0.7,
              ribbon_amt=0.12 if not frame else 0.07,
              pore_depth=0.45, late_h=0.06, fibre_h=0.05, line_depth=0.1,
              rough=(0.22, 0.32), r_pore=0.18, r_ribbon=0.035)
    if piece:
        st.update(early=C(0.45, 0.155, 0.10), late=C(0.34, 0.105, 0.07), line_col=C(0.24, 0.07, 0.05),
                  alt=C(0.47, 0.15, 0.09), rough=(0.18, 0.26), pore_amt=0.35, pore_depth=0.4)
    return wood_material(N, rng, wk, st, nstr=1.6 if not piece else 1.0)


def m_oak_smoked(N, rng):
    wk = dict(rings=_rings(18, N), warp=3.2, warp_f=(0.6, 2.2), wobble=0.08, ring_var=0.5,
              late=(0.30, 0.85), ring_amp=(0.5, 1.0), pore_len=40, pore_w=3,
              pore_keep=0.7, pore_r=0.34, ring_porous=True, ray_len=44, ray_w=5, ray_keep=0.10,
              fibre_f=(6.0, 260.0), streak_f=(1.5, 18.0), lines_f=(2.0, 100.0), lines_w=1.0)
    st = dict(early=C(0.37, 0.29, 0.215), late=C(0.24, 0.175, 0.125), contrast=1.0,
              alt=C(0.33, 0.27, 0.22), alt_amt=0.4, bright_var=0.06, fibre_amt=0.07,
              line_amt=0.3, line_col=C(0.17, 0.125, 0.09),
              pore_col=C(0.11, 0.085, 0.065), pore_amt=0.9,
              ray_col=C(0.44, 0.36, 0.27), ray_amt=0.55,
              pore_depth=0.8, late_h=0.1, fibre_h=0.06, ray_h=0.2, line_depth=0.1,
              rough=(0.46, 0.58), r_pore=0.2, r_ray=0.12)
    return wood_material(N, rng, wk, st, nstr=2.0)


# ---- burl ------------------------------------------------------------------------
def m_walnut_burl(N, rng):
    """Walnut burl: chaotic swirling figure from a 3-level domain-warped field,
    clustered 'eyes' (dark pith dots with rings wrapped around them), soft
    cos-profile figure lines with varying density/contrast, chatoyant fine curl."""
    X, Y = coords(N)
    s = N / 1024.0
    w1x, w1y = spectral(N, rng, 3, slope=2.0), spectral(N, rng, 3, slope=2.0)
    w2x, w2y = spectral(N, rng, 9, slope=1.4), spectral(N, rng, 9, slope=1.4)
    w3x, w3y = spectral(N, rng, 26, slope=1.2), spectral(N, rng, 26, slope=1.2)
    Xw, Yw = X + 70 * s * w1x, Y + 70 * s * w1y
    Xw2 = Xw + 22 * s * samp(w2x, Xw, Yw)
    Yw2 = Yw + 22 * s * samp(w2y, Xw, Yw)
    Xw3 = Xw2 + 5 * s * samp(w3x, Xw2, Yw2)
    Yw3 = Yw2 + 5 * s * samp(w3y, Xw2, Yw2)
    H = samp(spectral(N, rng, fmax=7, slope=1.4), Xw3, Yw3, 3)
    # clustered eyes
    eyes = Worley(rng, 44, 44, 0.95)
    f1, _, eid = eyes.eval(Xw2 / N, Yw2 / N, want_f2=False)
    cluster = samp(spectral(N, rng, fmax=5, slope=2.0), X, Y)
    thr = 0.06 + 0.55 * smoothstep(0.0, 1.6, cluster)
    keep = smoothstep(0.02, -0.02, eid - thr)
    H = H + 0.40 * np.exp(-(f1 / 0.62) ** 2) * keep
    dens = 7.0 + 2.5 * samp(spectral(N, rng, 3, slope=2.0), X, Y)
    fig = H * dens + 0.18 * samp(spectral(N, rng, 40, slope=1.0), Xw2, Yw2)
    gx, gy = grad(fig)
    pw = np.hypot(gx, gy)
    aa = smoothstep(0.30, 0.12, pw)
    expo = 2.0 + 4.0 * smoothstep(-1.2, 1.2, samp(spectral(N, rng, 10, slope=1.5), X, Y))
    line = (0.5 + 0.5 * np.cos(TAU * fig)) ** expo
    line = lerp(0.31, line, aa)
    fine = 0.5 + 0.5 * np.cos(TAU * fig * 3.0 + 1.3)
    fine = lerp(0.5, fine, smoothstep(0.12, 0.05, pw))
    contrast = 0.35 + 0.65 * smoothstep(-1.0, 1.2, samp(spectral(N, rng, 6, slope=1.6), X, Y))
    tone = 0.6 * smoothstep(-1.6, 1.6, samp(spectral(N, rng, fmax=5, slope=1.6), Xw, Yw)) \
        + 0.4 * smoothstep(-1.5, 1.5, samp(spectral(N, rng, fmax=16, slope=1.2), Xw2, Yw2))
    light, mid, dark = C(0.50, 0.33, 0.19), C(0.33, 0.205, 0.115), C(0.165, 0.10, 0.06)
    col = lerp3(mid, light, tone)
    col = lerp3(col, dark, line * contrast * 0.65)
    col = col * (1 - 0.08 * (fine - 0.5) * contrast)[..., None]
    core = smoothstep(0.16, 0.06, f1) * keep
    halo = smoothstep(0.34, 0.12, f1) * keep
    col = lerp3(col, C(0.22, 0.135, 0.08), halo * 0.45)
    col = lerp3(col, C(0.11, 0.07, 0.045), core * 0.92)
    pores = smoothstep(2.4, 3.2, spectral(N, rng, 300, slope=0.2))
    col = lerp3(col, C(0.16, 0.10, 0.06), pores * 0.35)
    h = 0.05 * line + 0.02 * fine - 0.12 * core - 0.12 * pores
    rough = 0.13 + 0.03 * line * contrast + 0.05 * pores + 0.03 * core + 0.015 * smoothstep(-1, 1, cluster)
    return Mat(col, h, 1.0, rough)


# =============================================================================
# STONE
# =============================================================================
def fractal_warp(N, rng, X, Y, warps):
    """Successive periodic domain warps [(amp_px, fmax), ...] (large -> small)."""
    Xw, Yw = X, Y
    for amp, wf in warps:
        wx = spectral(N, rng, wf, slope=1.3)
        wy = spectral(N, rng, wf, slope=1.3)
        Xw, Yw = Xw + amp * samp(wx, Xw, Yw), Yw + amp * samp(wy, Xw, Yw)
    return Xw, Yw


def vein_dist(N, rng, fmax, stretch, angle, warps, slope=1.5):
    """Pixel distance to natural-looking vein curves.

    The zero set of a low-frequency, strongly anisotropic field gives long,
    roughly parallel curves without little closed loops; a fractal domain
    warp (which preserves topology) then makes them jagged and meandering.
    """
    X, Y = coords(N)
    base = spectral(N, rng, fmax=fmax, slope=slope, stretch=(stretch, 1.0), angle=angle)
    Xw, Yw = fractal_warp(N, rng, X, Y, warps)
    return zero_set_dist(samp(base, Xw, Yw, 3))


def cell_edges(N, rng, cells, warps):
    """Pixel distance-ish to a warped Voronoi crack network + cell ids."""
    X, Y = coords(N)
    Xw, Yw = fractal_warp(N, rng, X, Y, warps)
    W = Worley(rng, cells, cells, 0.95)
    f1, f2, cid = W.eval(Xw / N, Yw / N)
    return (f2 - f1) * (N / cells) * 0.5, cid


def m_marble(N, rng, kind, scale=1.0):
    """kind in {'white', 'black', 'green'}; scale>1 = finer figure."""
    s = N / 1024.0
    k = scale

    def W(*ws):
        return [(a * s / k, f * k) for a, f in ws]

    def mod(fm, lo, hi, sl=1.5):
        return smoothstep(lo, hi, spectral(N, rng, fm * k, slope=sl))

    if kind == "white":        # Carrara: soft grey feathery veins, grey clouds
        clouds = warped(N, rng, 6 * k, 1.5, 70 * s, 4 * k)
        base = lerp3(C(0.885, 0.885, 0.875), C(0.775, 0.785, 0.795), smoothstep(-1.2, 1.8, clouds) * 0.85)
        mottle = spectral(N, rng, 60 * k, slope=0.8)
        base = base * (1 + 0.012 * mottle)[..., None]
        d1 = vein_dist(N, rng, 4 * k, 5.0, 0.5, W((60, 4), (14, 20), (3, 90)))
        w1 = (1.0 + 2.0 * mod(4, -1, 1.5)) * s
        op1 = mod(3, -0.9, 0.9, 1.8)
        v1 = (0.85 * np.exp(-(d1 / w1) ** 2) + 0.28 * np.exp(-(d1 / (8 * w1)) ** 2)) * op1
        d2 = vein_dist(N, rng, 9 * k, 3.5, 1.1, W((30, 6), (8, 30), (2, 120)))
        near = np.exp(-(d1 / (110 * s)) ** 2)
        v2 = np.exp(-(d2 / (0.8 * s)) ** 2) * mod(5, -0.2, 1.2) * (0.3 + 0.7 * near)
        d3 = vein_dist(N, rng, 3 * k, 4.0, 0.2, W((80, 3), (20, 12)))
        v3 = np.exp(-(d3 / (14 * s)) ** 2) * mod(3, 0.0, 1.5, 1.8)
        veins = np.clip(v1 + 0.55 * v2, 0, 1)
        col = lerp3(base, C(0.70, 0.715, 0.735), v3 * 0.35)
        col = lerp3(col, C(0.48, 0.50, 0.535), veins * 0.9)
        dots = smoothstep(2.6, 3.4, spectral(N, rng, 350 * k, slope=0.3))
        col = lerp3(col, C(0.64, 0.65, 0.66), dots * 0.35)
        h = -0.25 * veins - 0.5 * dots + 0.02 * mottle
        rough = 0.07 + 0.05 * veins + 0.10 * dots + 0.015 * spectral(N, rng, 30, slope=0.8)
        return Mat(col, h, 0.8, rough)
    if kind == "black":        # Nero Marquina: black, crisp white veins + hairline web
        clouds = warped(N, rng, 5 * k, 1.5, 60 * s, 4 * k)
        base = lerp3(C(0.150, 0.150, 0.155), C(0.19, 0.19, 0.195), smoothstep(-0.3, 2.2, clouds))
        base = base * (1 + 0.02 * spectral(N, rng, 80 * k, slope=0.8))[..., None]
        ang = -0.6
        d1 = vein_dist(N, rng, 3 * k, 6.0, ang, W((70, 3), (16, 18), (3, 80)))
        w1 = (0.8 + 2.4 * mod(5, -0.8, 1.8, 1.4)) * s
        op1 = mod(3, -0.9, 0.5, 1.8)
        v1 = smoothstep(w1 + 0.9, np.maximum(w1 - 0.6, 0.0), d1) * op1
        glow = np.exp(-(d1 / (9 * s)) ** 2) * op1
        d2 = vein_dist(N, rng, 7 * k, 3.0, ang + 0.8, W((30, 6), (8, 30), (2, 110)))
        near = np.exp(-(d1 / (90 * s)) ** 2)
        v2 = smoothstep(1.1, 0.2, d2) * mod(5, 0.0, 1.3, 1.4) * (0.2 + 0.8 * near)
        e3, _ = cell_edges(N, rng, int(9 * k), W((40, 5), (10, 25), (2, 100)))
        v3 = smoothstep(1.0, 0.25, e3) * mod(4, 0.5, 1.8) * 0.55
        veins = np.clip(v1 + 0.75 * v2 + v3, 0, 1)
        col = lerp3(base, C(0.30, 0.30, 0.30), glow * 0.3)
        col = lerp3(col, C(0.86, 0.855, 0.84), veins)
        h = -0.2 * veins
        rough = 0.07 + 0.06 * veins + 0.012 * spectral(N, rng, 40, slope=0.8)
        return Mat(col, h, 0.8, rough)
    # green: Verde Guatemala-like serpentine with a dense web of pale veins
    clouds = warped(N, rng, 5 * k, 1.4, 80 * s, 5 * k)
    tone = smoothstep(-1.4, 1.6, clouds)
    base = lerp3(C(0.085, 0.165, 0.125), C(0.15, 0.30, 0.215), tone)
    e1, cid = cell_edges(N, rng, int(6 * k), W((70, 3), (25, 10), (6, 40), (1.5, 150)))
    clast = blur(0.8 + 0.4 * cid, 3 * s)
    base = base * clast[..., None]
    mottle = warped(N, rng, 30 * k, 1.0, 10 * s, 20 * k)
    base = lerp3(base, C(0.075, 0.135, 0.105), smoothstep(0.6, 2.2, mottle) * 0.7)
    base = lerp3(base, C(0.22, 0.40, 0.30), smoothstep(1.2, 2.6, -mottle) * 0.4)
    w1 = (0.7 + 2.5 * mod(6, -0.3, 1.8)) * s
    v1 = smoothstep(w1 + 1.0, np.maximum(w1 - 0.5, 0.0), e1) * mod(4, -1.0, 0.6, 1.6)
    e2, _ = cell_edges(N, rng, int(17 * k), W((30, 6), (10, 20), (2.5, 80)))
    v2 = smoothstep(1.2, 0.2, e2) * mod(5, -0.2, 1.4)
    d3 = vein_dist(N, rng, 5 * k, 3.5, 0.9, W((50, 4), (12, 20), (3, 90)))
    v3 = smoothstep(1.6 * s + 0.6, 0.2, d3) * mod(4, -0.5, 1.2, 1.6)
    d4 = vein_dist(N, rng, 10 * k, 3.0, -0.4, W((25, 6), (8, 30), (2, 120)))
    v4 = smoothstep(1.0, 0.2, d4) * mod(5, 0.2, 1.5)
    veins = np.clip(v1 + 0.6 * v2 + 0.9 * v3 + 0.5 * v4, 0, 1)
    halo = blur(veins, 4 * s)
    vcol = lerp3(solid(N, C(0.80, 0.84, 0.78)), solid(N, C(0.52, 0.66, 0.56)), mod(10, -1, 1, 1.3))
    col = lerp3(base, C(0.25, 0.40, 0.31), np.clip(halo * 1.2, 0, 1) * 0.35)
    col = lerp3(col, vcol, veins * 0.92)
    h = -0.2 * veins
    rough = 0.08 + 0.05 * veins + 0.015 * spectral(N, rng, 40, slope=0.8)
    return Mat(col, h, 0.8, rough)


def m_limestone(N, rng):
    X, Y = coords(N)
    s = N / 1024.0
    clouds = warped(N, rng, 5, 1.5, 60 * s, 4)
    bands = samp(aniso(N, rng, 1.5, 10, slope=1.5), X, Y)
    base = lerp3(C(0.865, 0.805, 0.665), C(0.80, 0.735, 0.59), smoothstep(-1.5, 1.8, clouds + 0.4 * bands))
    grain = spectral(N, rng, 300, slope=0.4)
    base = base * (1 + 0.025 * grain)[..., None]
    # shell fragments: small elongated cells in random orientations
    frag = np.zeros((N, N), F32)
    for ang in (0.3, 1.4, 2.4):     # rotated anisotropic noise (still periodic)
        n = spectral(N, rng, 120, slope=0.6, stretch=(3.0, 1.0), angle=ang)
        frag = np.maximum(frag, smoothstep(2.2, 2.9, n))
    col = lerp3(base, C(0.92, 0.88, 0.78), frag * 0.5)
    fr2 = np.zeros((N, N), F32)
    for ang in (0.9, 2.0):
        n = spectral(N, rng, 90, slope=0.7, stretch=(2.5, 1.0), angle=ang)
        fr2 = np.maximum(fr2, smoothstep(2.4, 3.1, n))
    col = lerp3(col, C(0.66, 0.58, 0.44), fr2 * 0.45)
    pores = smoothstep(2.5, 3.3, spectral(N, rng, 400, slope=0.2))
    col = lerp3(col, C(0.55, 0.49, 0.38), pores * 0.6)
    h = 0.15 * clouds + 0.05 * blur(grain, 1.0) - 0.8 * blur(pores, 0.7) + 0.12 * frag - 0.08 * fr2
    rough = 0.58 + 0.03 * blur(grain, 0.6) + 0.2 * pores - 0.05 * frag
    return Mat(col, h, 1.3, rough)


def m_slate(N, rng):
    """Riven (cleft) slate: undulating split surface with a few flaky layer
    steps (warped Voronoi plates), granular matte texture, faint cleavage
    lineation, blue-grey with slight rust/green mineral staining."""
    X, Y = coords(N)
    s = N / 1024.0
    Xw, Yw = fractal_warp(N, rng, X, Y, [(90 * s, 3), (25 * s, 12), (6 * s, 50), (1.5 * s, 200)])
    W = Worley(rng, 6, 5, 0.95)
    f1, f2, cid = W.eval(Xw / N, Yw / N)
    level = np.floor(cid * 4.0) / 4.0
    plates = blur(level, 1.5 * s)
    riven = spectral(N, rng, 40, slope=1.25)
    lin = samp(aniso(N, rng, 14, 200, slope=0.7, broken=0.5), X, Y)
    grain = blur(spectral(N, rng, 350, slope=0.3), 0.6)
    h = 1.6 * plates + 0.9 * riven + 0.05 * lin + 0.04 * grain
    gy, gx = np.gradient(plates)
    step_edge = np.clip(np.hypot(gx, gy) * 12.0 / s, 0, 1)
    tone = smoothstep(-1.5, 1.5, spectral(N, rng, 6, slope=1.6))
    base = lerp3(C(0.21, 0.24, 0.275), C(0.255, 0.275, 0.305), tone)
    base = base * (0.93 + 0.14 * level)[..., None]
    rust = smoothstep(0.9, 2.3, warped(N, rng, 8, 1.3, 30 * s, 8))
    base = lerp3(base, C(0.30, 0.26, 0.22), rust * 0.3)
    base = lerp3(base, C(0.20, 0.25, 0.25), smoothstep(0.5, 2.0, spectral(N, rng, 10, 1.4)) * 0.35)
    base = base * (1 + 0.012 * lin + 0.045 * grain + 0.03 * riven)[..., None]
    col = lerp3(base, C(0.32, 0.34, 0.37), step_edge * 0.2)
    rough = 0.72 + 0.015 * lin + 0.05 * step_edge + 0.04 * grain - 0.03 * tone
    return Mat(col, h, 2.0, rough)


# =============================================================================
# FINISHES: vinyl, matte paint, lacquer, brass, felt, leather
# =============================================================================
def m_vinyl(N, rng, colour):
    X, Y = coords(N)
    c = np.asarray(colour, F32)
    # fine printed stipple
    st = spectral(N, rng, 420, slope=0.2)
    st2 = smoothstep(1.8, 2.8, spectral(N, rng, 300, slope=0.3))
    blot = spectral(N, rng, 12, slope=1.4)
    col = solid(N, c) * (1 + 0.018 * st + 0.012 * blot)[..., None]
    col = lerp3(col, c * 0.86, st2 * 0.5)
    # very subtle woven fabric backing embossed through the vinyl
    f = N // 8          # 8 px weave period -> exact repeats, compresses well
    wx = np.cos(TAU * f * X / N)
    wy = np.cos(TAU * f * Y / N)
    over = np.sign(np.sin(TAU * f * X / N * 0.5 + 0.3) * np.sin(TAU * f * Y / N * 0.5 + 0.3))
    weave = np.where(over > 0, 0.5 + 0.5 * wy, 0.5 + 0.5 * wx).astype(F32)
    weave = blur(weave, 0.7)
    h = 0.05 * weave + 0.02 * blot
    rough = 0.70 + 0.012 * blur(st, 0.6) + 0.03 * weave + 0.01 * blot
    return Mat(col, h, 1.0, rough)


def m_matte_black(N, rng):
    peel = spectral(N, rng, 90, slope=1.0)
    fine = spectral(N, rng, 400, slope=0.2)
    blot = spectral(N, rng, 6, slope=1.6)
    col = solid(N, C(0.165, 0.160, 0.158)) * (1 + 0.03 * blot + 0.012 * blur(fine, 0.7))[..., None]
    h = 0.35 * peel + 0.02 * blur(fine, 0.8)
    rough = 0.64 + 0.015 * blur(fine, 0.7) + 0.03 * blot
    return Mat(col, h, 0.45, rough)


def _crackle(N, rng, cells, warp_px, width_px):
    X, Y = coords(N)
    W = Worley(rng, cells, cells, 0.95)
    wx = spectral(N, rng, cells * 0.8, slope=1.3)
    wy = spectral(N, rng, cells * 0.8, slope=1.3)
    f1, f2, cid = W.eval((X + warp_px * wx) / N, (Y + warp_px * wy) / N)
    edge = (f2 - f1) * (N / cells)
    return smoothstep(width_px + 0.8, max(width_px - 0.5, 0.0), edge), cid


def m_lacquer(N, rng, colour, deep, crackle=0.0, frame=False):
    X, Y = coords(N)
    s = N / 1024.0
    depth = warped(N, rng, 4, 1.6, 60 * s, 4)
    col = lerp3(solid(N, colour), solid(N, deep), smoothstep(-1.6, 1.8, depth) * 0.45)
    col = col * (1 + 0.012 * spectral(N, rng, 60, slope=0.8))[..., None]
    peel = spectral(N, rng, 50, slope=1.2)
    h = 0.25 * peel
    rough = 0.075 + 0.015 * smoothstep(-1.5, 1.5, depth) + 0.01 * peel
    if crackle > 0:
        c1, cid = _crackle(N, rng, 16, 18 * s, 0.9 * s)
        c2, _ = _crackle(N, rng, 42, 8 * s, 0.6 * s)
        sel = smoothstep(0.35, 0.65, samp(spectral(N, rng, 4, 2.0), X, Y) * 0.5 + 0.5 + 0.2 * (cid - 0.5))
        cr = np.clip(c1 + c2 * (0.3 + 0.7 * sel), 0, 1) * crackle
        col = lerp3(col, deep * 0.55, cr * 0.55)
        col = col * (1 + 0.02 * (cid - 0.5))[..., None]
        h = h - 0.6 * blur(cr, 0.5)
        rough = rough + 0.22 * cr
    # faint polishing swirls / rub marks
    sw = np.zeros((N, N), F32)
    for ang in ((0.0,) if frame else (0.4, 1.9, 3.0)):
        sw = np.maximum(sw, smoothstep(2.4, 3.4, spectral(N, rng, 500, slope=0.1, stretch=(40, 1), angle=ang)))
    rough = rough + 0.05 * sw * smoothstep(-0.5, 1.5, samp(spectral(N, rng, 3, 2.0), X, Y))
    return Mat(col, h, 0.6, rough)


def m_brass(N, rng):
    X, Y = coords(N)
    s = N / 1024.0
    streak = aniso(N, rng, 1.2, 420, slope=0.25, fmin=2)
    streak2 = aniso(N, rng, 3.0, 160, slope=0.6, fmin=2)
    tarn = warped(N, rng, 6, 1.5, 50 * s, 5)
    base = lerp3(C(0.86, 0.70, 0.40), C(0.78, 0.61, 0.33), smoothstep(0.2, 2.4, tarn) * 0.6)
    col = base * (1 + 0.025 * streak + 0.02 * streak2)[..., None]
    # a few random fine scratches (analytic lines with integer direction -> periodic)
    scr = np.zeros((N, N), F32)
    for _ in range(18):
        a, b = int(rng.integers(-3, 4)), int(rng.integers(1, 5))
        if rng.random() < 0.5:
            a, b = b, a
        ph = rng.random()
        L = (a * X + b * Y) / N + ph
        dist = np.abs(L - np.round(L)) * N / math.hypot(a, b)
        seg = smoothstep(0.55, 0.9, samp(spectral(N, rng, 3, 2.0), X, Y) * 0.5 + 0.5)
        scr = np.maximum(scr, smoothstep(0.9, 0.2, dist) * seg * rng.uniform(0.3, 0.8))
    h = 0.30 * streak + 0.25 * streak2 - 0.5 * scr
    rough = 0.30 + 0.035 * streak + 0.025 * streak2 + 0.07 * smoothstep(0.2, 2.4, tarn) + 0.06 * scr
    return Mat(col, h, 0.4, rough, metallic=1.0)


def m_felt(N, rng, colour):
    """Pressed felt / baize: many short fibres in all directions, soft mottling."""
    fib = np.zeros((N, N), F32)
    for i in range(7):
        ang = i * math.pi / 7 + rng.uniform(-0.1, 0.1)
        n = spectral(N, rng, 380, fmin=20, slope=0.3, stretch=(5.0, 1.0), angle=ang)
        fib = np.maximum(fib, n)
    fib = normalize01(fib)
    mott = spectral(N, rng, 10, slope=1.5)
    pil = spectral(N, rng, 60, slope=0.8)
    c = np.asarray(colour, F32)
    fibb = blur(fib, 0.9)
    col = solid(N, c) * (0.90 + 0.18 * fibb + 0.04 * mott + 0.03 * pil)[..., None]
    h = 0.45 * fibb + 0.3 * blur(pil, 0.8) + 0.05 * mott
    rough = 0.9 + 0.05 * fibb
    return Mat(col, h, 1.0, rough)


def m_leather(N, rng, colour, crease_col, top_col, cells=58, nstr=2.2):
    X, Y = coords(N)
    s = N / 1024.0
    wx = spectral(N, rng, 20, slope=1.4)
    wy = spectral(N, rng, 20, slope=1.4)
    Xw, Yw = X + 6 * s * wx, Y + 6 * s * wy
    W = Worley(rng, cells, cells, 0.95)
    f1, f2, cid = W.eval(Xw / N, Yw / N)
    pebble = smoothstep(0.0, 0.35, f2 - f1) * (0.8 + 0.4 * cid)
    W2 = Worley(rng, 150, 150, 0.95)
    g1, g2, _ = W2.eval(Xw / N + 0.3, Yw / N + 0.7)
    fine = smoothstep(0.0, 0.3, g2 - g1)
    # creases: zero sets of a couple of warped fields
    cr = np.zeros((N, N), F32)
    for fm, w in ((5, 2.2), (9, 1.4), (16, 0.9)):
        F = warped(N, rng, fm, 1.4, 30 * s, fm * 1.5, stretch=(1.6, 1.0), angle=float(rng.uniform(0, math.pi)))
        d = zero_set_dist(F)
        op = smoothstep(-0.3, 1.2, spectral(N, rng, 4, slope=1.6))
        cr = np.maximum(cr, np.exp(-(d / (w * s)) ** 2) * op)
    pores = blur(smoothstep(2.6, 3.3, spectral(N, rng, 300, slope=0.2)), 0.5)
    macro = spectral(N, rng, 6, slope=1.8)
    h = 0.9 * pebble + 0.12 * fine - 1.2 * cr - 0.4 * pores + 0.3 * macro
    h = blur(h, 1.2)
    hn = normalize01(pebble * 0.8 + fine * 0.2)
    col = lerp3(solid(N, crease_col), solid(N, colour), smoothstep(0.1, 0.6, hn))
    col = lerp3(col, solid(N, top_col), smoothstep(0.75, 1.0, hn) * 0.5)
    col = lerp3(col, solid(N, crease_col), cr * 0.7)
    col = col * (1 + 0.06 * spectral(N, rng, 8, 1.5))[..., None]
    rough = 0.52 - 0.10 * smoothstep(0.6, 1.0, hn) + 0.15 * cr + 0.1 * pores + 0.03 * macro
    return Mat(col, h, nstr, rough)


# =============================================================================
# PIECE FINISHES (512, triplanar, subtle)
# =============================================================================
def m_ivory(N, rng):
    X, Y = coords(N)
    s = N / 512.0
    wx = spectral(N, rng, 3, slope=1.8)
    wy = spectral(N, rng, 3, slope=1.8)
    Xw, Yw = X + 18 * s * wx, Y + 18 * s * wy
    # Schreger lines: two families of fine curved lines crossing at ~115 deg
    a = (0.5 + 0.5 * np.cos(TAU * (22 * Xw + 13 * Yw) / N)) ** 3
    b = (0.5 + 0.5 * np.cos(TAU * (22 * Xw - 13 * Yw) / N)) ** 3
    sch = (a + b) - 0.25
    growth = samp(aniso(N, rng, 2.0, 30, slope=1.2, broken=0.5), X, Y)
    mott = warped(N, rng, 5, 1.6, 20 * s, 4)
    col = lerp3(C(0.90, 0.85, 0.72), C(0.87, 0.805, 0.66), smoothstep(-1.5, 1.8, mott) * 0.7)
    col = col * (1 - 0.028 * sch + 0.012 * growth)[..., None]
    h = 0.04 * sch + 0.06 * growth + 0.04 * mott
    rough = 0.22 + 0.02 * smoothstep(-1, 1, mott) + 0.015 * sch
    return Mat(col, h, 0.6, rough)


def m_cream(N, rng):
    X, Y = coords(N)
    s = N / 512.0
    mott = warped(N, rng, 6, 1.5, 25 * s, 5)
    streak = samp(aniso(N, rng, 1.5, 20, slope=1.3), X, Y)
    col = lerp3(C(0.885, 0.835, 0.70), C(0.855, 0.795, 0.65), smoothstep(-1.3, 1.8, mott + 0.3 * streak) * 0.7)
    specks = smoothstep(2.7, 3.4, spectral(N, rng, 200, slope=0.3))
    col = lerp3(col, C(0.72, 0.64, 0.50), specks * 0.5)
    fine = spectral(N, rng, 120, slope=0.6)
    col = col * (1 + 0.01 * fine)[..., None]
    h = 0.06 * mott + 0.04 * fine - 0.3 * specks
    rough = 0.26 + 0.03 * smoothstep(-1, 1, mott) + 0.08 * specks
    return Mat(col, h, 0.6, rough)


# =============================================================================
# FLOORS & PANELS (wood assemblies)
# =============================================================================
def _plank_wood(N, rng, Ns, wood_kw, style, along, across, pid, flip, ncolour, gapd_px, bevel_px,
                tint_amt=0.10):
    """Sample a periodic Wood source in plank-local coordinates.

    along/across: plank-local pixel coords, pid: integer plank id (periodic),
    gapd_px: distance to nearest plank edge in px.
    """
    wood = Wood(rng, Ns=Ns, **wood_kw)
    offs = rng.random((ncolour, 2)).astype(F32) * Ns
    tint = rng.standard_normal((ncolour, 3)).astype(F32)
    bright = rng.standard_normal(ncolour).astype(F32)
    Xs = along + offs[pid, 0]
    Ys = np.where(flip[pid] > 0.5, -across, across) + offs[pid, 1]
    d = wood.eval(Xs, Ys)
    col, h, rough = wood_shade(d, style)
    h = blur(h, 0.9)
    tb = (1 + tint_amt * bright[pid])[..., None] * (1 + 0.25 * tint_amt * tint[pid])
    col = col * tb
    bevel = smoothstep(0.0, bevel_px, gapd_px)
    gap = smoothstep(0.4, 1.3, gapd_px)
    col = lerp3(col * 0.25, col * (0.85 + 0.15 * bevel)[..., None], gap)
    h = h * gap + 1.2 * bevel + 1.0 * gap
    rough = lerp(0.9, rough, gap) + 0.04 * (1 - bevel)
    return col, h, rough


def herringbone_lattice(N, X, Y, n_ratio=5, k=3):
    """Herringbone plank lookup at 45 degrees (zigzag runs vertically).

    Lattice: planks n*W x W in plank-units (a,b) with lattice vectors (1,1) and
    (n,-n).  a=(x+y)/(W*sqrt2), b=(y-x)/(W*sqrt2) makes the lattice axis-aligned,
    so a square tile of k*n*sqrt2*W pixels repeats exactly.
    Returns (pid, n_ids, along_px, across_px, edge_dist_px, W).
    """
    m = k * n_ratio
    W = N / (m * math.sqrt(2.0))
    Xc, Yc = X + 0.5, Y + 0.5
    a = (Xc + Yc) / (W * math.sqrt(2.0))
    b = (Yc - Xc) / (W * math.sqrt(2.0))
    s = (a + b) * 0.5
    t = (a - b) / (2.0 * n_ratio)
    fs, ft = np.floor(s), np.floor(t)
    best_i = np.zeros_like(a)
    best_j = np.zeros_like(a)
    typ = np.full(a.shape, -1, np.int8)
    along = np.zeros_like(a)
    across = np.zeros_like(a)
    span = int(math.ceil((n_ratio + 2) / 2.0))
    for di in range(-span, 1):
        for dj in (0, 1):
            i = fs + di
            j = ft + dj
            qa = a - i - j * n_ratio
            qb = b - i + j * n_ratio
            inH = (qa >= 0) & (qa < n_ratio) & (qb >= 0) & (qb < 1) & (typ < 0)
            inV = (qa >= n_ratio) & (qa < n_ratio + 1) & (qb >= 1 - n_ratio) & (qb < 1) & (typ < 0)
            along = np.where(inH, qa, np.where(inV, qb - (1 - n_ratio), along))
            across = np.where(inH, qb, np.where(inV, qa - n_ratio, across))
            best_i = np.where(inH | inV, i, best_i)
            best_j = np.where(inH | inV, j, best_j)
            typ = np.where(inH, 0, np.where(inV, 1, typ)).astype(np.int8)
    assert (typ >= 0).all(), "herringbone lattice search failed"
    pid = ((np.mod(best_i, m) * k + np.mod(best_j, k)) * 2 + typ).astype(np.int64)
    ed = np.minimum(np.minimum(along, n_ratio - along), np.minimum(across, 1 - across)) * W
    return pid, m * k * 2, along * W, across * W, ed, W


def m_herringbone(N, rng):
    """Dark oak herringbone parquet (planks ~1:5, 45 degrees, see herringbone_lattice)."""
    X, Y = coords(N)
    pid, nid, along, across, ed, W = herringbone_lattice(N, X, Y)
    flip = (rng.random(nid) < 0.5).astype(F32)
    wood_kw = dict(rings=44, warp=3.0, warp_f=(0.6, 2.4), wobble=0.10, ring_var=0.5,
                   late=(0.34, 0.88), ring_amp=(0.5, 1.0), pore_len=40, pore_w=3, pore_keep=0.55,
                   pore_r=0.32, ring_porous=True, ray_len=40, ray_w=4, ray_keep=0.10,
                   fibre_f=(8.0, 500.0), streak_f=(2.5, 30.0), lines_f=(2.5, 160.0), lines_w=1.0)
    style = dict(early=C(0.335, 0.235, 0.155), late=C(0.22, 0.145, 0.09), contrast=0.9,
                 alt=C(0.30, 0.22, 0.16), alt_amt=0.45, bright_var=0.06, fibre_amt=0.06,
                 line_amt=0.25, line_col=C(0.17, 0.11, 0.07),
                 pore_col=C(0.13, 0.085, 0.055), pore_amt=0.6,
                 ray_col=C(0.38, 0.28, 0.19), ray_amt=0.4,
                 pore_depth=0.35, late_h=0.08, fibre_h=0.03, ray_h=0.1, line_depth=0.05,
                 rough=(0.36, 0.48), r_pore=0.10, r_ray=0.08)
    col, h, rough = _plank_wood(N, rng, 2048, wood_kw, style, along, across, pid, flip, nid,
                                ed, 3.0, tint_amt=0.16)
    return Mat(col, h, 1.6, rough)


def m_plank_floor(N, rng, rows=12):
    """Warm oak strip floor: `rows` plank courses (offset so no gap sits on the
    tile edge), 1-2 long planks per course with random joint positions that
    wrap around the tile, each plank a different region/tint of the wood."""
    X, Y = coords(N)
    rh = N / rows
    y0 = rh * 0.37
    Yr = np.mod(Y - y0, N)
    row = np.floor(Yr / rh).astype(np.int64)
    across = Yr - row * rh
    nmax = 2
    joints = np.zeros((rows, nmax + 1), F32)
    counts = np.zeros(rows, np.int64)
    for r in range(rows):
        c = int(rng.integers(1, nmax + 1))
        counts[r] = c
        start = rng.random() * N
        lens = rng.uniform(0.75, 1.25, c)
        lens = lens / lens.sum() * N
        js = start + np.concatenate([[0.0], np.cumsum(lens)])
        joints[r, :c + 1] = js
        joints[r, c + 1:] = js[-1]
    along = np.zeros_like(X)
    idx = np.zeros(X.shape, np.int64)
    jd = np.full(X.shape, 1e9, F32)
    xr = np.mod(X - joints[row, 0], N)
    for p_ in range(nmax):
        lo = joints[row, p_] - joints[row, 0]
        hi = joints[row, p_ + 1] - joints[row, 0]
        inside = (xr >= lo) & (xr < hi) & (p_ < counts[row])
        along = np.where(inside, xr - lo, along)
        idx = np.where(inside, p_, idx)
        jd = np.where(inside, np.minimum(xr - lo, hi - xr), jd)
    pid = (row * nmax + idx).astype(np.int64)
    flip = (rng.random(rows * nmax) < 0.5).astype(F32)
    ed = np.minimum(jd + 0.5, np.minimum(across + 0.5, rh - across - 0.5))
    wood_kw = dict(rings=40, warp=3.2, warp_f=(0.5, 2.4), wobble=0.10, ring_var=0.5,
                   late=(0.34, 0.88), ring_amp=(0.5, 1.0), pore_len=40, pore_w=3, pore_keep=0.55,
                   pore_r=0.32, ring_porous=True, ray_len=40, ray_w=4, ray_keep=0.10,
                   fibre_f=(8.0, 500.0), streak_f=(2.5, 30.0), lines_f=(2.5, 160.0), lines_w=1.0)
    style = dict(early=C(0.63, 0.46, 0.29), late=C(0.47, 0.315, 0.18), contrast=0.9,
                 alt=C(0.60, 0.41, 0.245), alt_amt=0.45, bright_var=0.06, fibre_amt=0.06,
                 line_amt=0.25, line_col=C(0.38, 0.25, 0.14),
                 pore_col=C(0.28, 0.18, 0.10), pore_amt=0.55,
                 ray_col=C(0.70, 0.54, 0.37), ray_amt=0.4,
                 pore_depth=0.35, late_h=0.08, fibre_h=0.03, ray_h=0.1, line_depth=0.05,
                 rough=(0.40, 0.52), r_pore=0.10, r_ray=0.08)
    col, h, rough = _plank_wood(N, rng, 2048, wood_kw, style, along, across, pid, flip,
                                rows * nmax, ed, 4.0, tint_amt=0.12)
    return Mat(col, h, 1.6, rough)


def m_wall_panel(N, rng):
    """Raised-panel wainscot: stiles (vertical grain), rails and panel field."""
    X, Y = coords(N)
    s = N / 1024.0
    stile = 110 * s          # half-stile at each tile edge -> full stile when tiled
    rail = 120 * s
    Xc, Yc = X + 0.5, Y + 0.5
    dx = np.minimum(Xc, N - Xc)          # distance from vertical tile edge
    dy = np.minimum(Yc, N - Yc)
    in_frame = (dx < stile) | (dy < rail)
    is_stile = dx < stile
    # panel-local distance to panel edge (inside the frame opening)
    pdx = dx - stile
    pdy = dy - rail
    pd = np.minimum(pdx, pdy)           # >0 inside opening
    wood_kw = dict(rings=22, warp=1.2, warp_f=(0.7, 2.5), wobble=0.06, ring_var=0.3,
                   late=(0.48, 0.93), ring_amp=(0.45, 1.0), pore_len=18, pore_w=6, pore_keep=0.42,
                   pore_r=0.3, fibre_f=(6.0, 300.0), streak_f=(1.5, 20.0), ribbon_k=4)
    style = dict(early=C(0.44, 0.235, 0.13), late=C(0.30, 0.15, 0.08), contrast=0.9,
                 alt=C(0.46, 0.22, 0.11), alt_amt=0.4, bright_var=0.05, fibre_amt=0.06,
                 pore_col=C(0.16, 0.08, 0.045), pore_amt=0.8, ribbon_amt=0.06,
                 pore_depth=0.9, late_h=0.06, fibre_h=0.07, rough=(0.30, 0.40), r_pore=0.2)
    wood = Wood(rng, Ns=N, **wood_kw)
    # vertical grain for stiles & panel: swap axes; horizontal for rails
    dv = wood.eval(Y, X)                 # grain along y
    dh = wood.eval(X + 311.0, Y + 173.0)  # grain along x (different region)
    cv, hv, rv = wood_shade(dv, style)
    ch, hh, rh = wood_shade(dh, style)
    rail_mask = in_frame & ~is_stile
    col = np.where(rail_mask[..., None], ch, cv)
    hw = np.where(rail_mask, hh, hv)
    rgh = np.where(rail_mask, rh, rv)
    # joint lines between stile and rail
    joint = (dy < rail) & (np.abs(dx - stile) < 0.8)
    # profile: frame flat 1.0; ogee groove around opening; bevel rising to raised field
    prof = np.ones_like(X)
    q = pd
    groove = np.exp(-((q - 10 * s) / (5 * s)) ** 2)
    bevel = smoothstep(18 * s, 70 * s, q)
    inside = q > 0
    prof = np.where(inside, 0.55 + 0.55 * bevel - 0.25 * groove, prof)
    lip = np.exp(-((q + 3 * s) / (3 * s)) ** 2)
    prof = prof + 0.15 * lip
    height = prof * 40.0 * s + 0.6 * hw
    ao = np.where(inside, 0.72 + 0.28 * smoothstep(0, 30 * s, q), 1.0) * (1 - 0.35 * groove)
    col = col * ao[..., None]
    col = np.where(joint[..., None], col * 0.45, col)
    rgh = rgh + 0.1 * groove
    return Mat(col, height, 0.5, rgh)


# =============================================================================
# WALLPAPER (damask) and RUG
# =============================================================================
def _bez(p0, p1, p2, p3, n=48):
    t = np.linspace(0.0, 1.0, n)[:, None]
    p0, p1, p2, p3 = (np.asarray(p, float) for p in (p0, p1, p2, p3))
    return ((1 - t) ** 3) * p0 + 3 * ((1 - t) ** 2) * t * p1 + 3 * (1 - t) * t * t * p2 + t ** 3 * p3


def _ribbon(pts, prof):
    """Variable-width stroke polygon around a centre line; prof = half-widths."""
    d = np.gradient(pts, axis=0)
    d /= np.linalg.norm(d, axis=1, keepdims=True) + 1e-9
    nrm = np.stack([-d[:, 1], d[:, 0]], axis=1)
    w = np.asarray(prof, float)[:, None]
    return np.concatenate([pts + nrm * w, (pts - nrm * w)[::-1]])


def _leaf(pts, width, lobes=0, lobe_depth=0.35, power=0.8):
    t = np.linspace(0, 1, len(pts))
    prof = np.sin(np.pi * t) ** power * width * 0.5
    if lobes:
        prof *= 1 - lobe_depth * (0.5 - 0.5 * np.cos(TAU * lobes * t))
    return _ribbon(pts, prof)


def _stroke(pts, w0, w1):
    return _ribbon(pts, np.linspace(w0, w1, len(pts)) * 0.5)


def _ellipse(cx, cy, rx, ry, rot=0.0, n=40):
    t = np.linspace(0, TAU, n, endpoint=False)
    x, y = rx * np.cos(t), ry * np.sin(t)
    c, s = math.cos(rot), math.sin(rot)
    return np.stack([cx + x * c - y * s, cy + x * s + y * c], axis=1)


def _spiral(cx, cy, r0, th0, turns, w0, w1, sgn=1, n=60):
    """Tapering spiral scroll (stroke polygon) winding inwards."""
    t = np.linspace(0, 1, n)
    r = r0 * (1 - 0.82 * t)
    th = th0 + sgn * TAU * turns * t
    pts = np.stack([cx + r * np.cos(th), cy + r * np.sin(th)], axis=1)
    return _stroke(pts, w0, w1), pts[-1]


def _ogee(y0, y1, wmax, n=80, scale=1.0, cy=None):
    """Symmetric pointed-top 'pomegranate' body (full closed polygon)."""
    u = np.linspace(0, 1, n)
    w = wmax * np.sin(np.pi * u) ** 0.9 * (0.55 + 0.45 * u)
    y = y0 + (y1 - y0) * u
    cy = (y0 + y1) / 2 if cy is None else cy
    right = np.stack([w * scale, cy + (y - cy) * scale], axis=1)
    left = right[::-1] * np.array([-1, 1])
    return np.concatenate([right, left]), (lambda px, py: abs(px) < np.interp(
        (py - cy) / scale + cy, y, w) * scale)


def _damask_motif():
    """Symmetric damask ornament in local units (x right, y down, height ~1).

    Returns [(polygon, value, mirror)] drawn in order: value 1 = satin
    ornament, 0 = cut back to ground.  mirror=True polygons are also drawn
    reflected about x = 0.
    """
    P = []

    def add(poly, v=1, m=True):
        P.append((np.asarray(poly, float), v, m))

    # --- pomegranate body with scale pattern ---
    body, _ = _ogee(-0.21, 0.17, 0.125)
    add(body, 1, False)
    inner, inside = _ogee(-0.21, 0.17, 0.125, scale=0.80, cy=-0.01)
    add(inner, 0, False)
    sp = 0.042
    for iy in range(-6, 7):
        for ix in range(-4, 5):
            px = ix * sp + (sp / 2 if iy % 2 else 0.0)
            py = -0.01 + iy * sp * 0.8
            if inside(px / 0.93, (py + 0.01) / 0.93 - 0.01) and abs(py) < 0.2:
                add(_ellipse(px, py, 0.010, 0.012), 1, False)
    for a in range(4):
        th = a * math.pi / 2
        add(_ellipse(0.026 * math.sin(th), 0.01 - 0.026 * math.cos(th), 0.013, 0.024, rot=th), 1, False)
    add(_ellipse(0, 0.01, 0.028, 0.028), 0, False)
    add(_ellipse(0, 0.01, 0.014, 0.014), 1, False)
    # --- crown palmette ---
    for ang, L, w in ((0.0, 0.17, 0.052), (0.36, 0.16, 0.048), (0.72, 0.135, 0.044), (1.08, 0.105, 0.038)):
        ox, oy = 0.0, -0.19
        tip = (ox + L * math.sin(ang), oy - L * math.cos(ang))
        ctrl = (ox + 0.55 * L * math.sin(ang * 1.25), oy - 0.55 * L * math.cos(ang * 1.25))
        pts = _bez((ox, oy), ctrl, (tip[0] - 0.01 * math.cos(ang), tip[1] + 0.01), tip)
        add(_leaf(pts, w, power=0.65), 1, ang > 0)
        add(_stroke(pts[8:-10], 0.009, 0.003), 0, ang > 0)
    add(_ellipse(0, -0.19, 0.04, 0.022), 1, False)
    # --- finial ---
    add(_leaf(_bez((0, -0.37), (0, -0.40), (0, -0.44), (0, -0.475)), 0.05, power=0.6), 1, False)
    add(_ellipse(0, -0.49, 0.011, 0.011), 1, False)
    # --- great acanthus leaves sweeping out and up, ending in scrolls ---
    ac = _bez((0.07, 0.11), (0.27, 0.14), (0.34, -0.08), (0.235, -0.19))
    add(_leaf(ac, 0.105, lobes=5, lobe_depth=0.5, power=0.55))
    add(_stroke(ac[4:-6], 0.010, 0.004), 0)
    for i in (10, 18, 26, 34):
        p = ac[i]
        q = ac[i + 3]
        d = (q - p) / (np.linalg.norm(q - p) + 1e-9)
        nvec = np.array([d[1], -d[0]])
        vein = _bez(p, p + nvec * 0.015 + d * 0.01, p + nvec * 0.03 + d * 0.02, p + nvec * 0.038 + d * 0.035, 12)
        add(_stroke(vein, 0.006, 0.002), 0)
    scr, _ = _spiral(0.205, -0.165, 0.045, -0.35, 1.15, 0.024, 0.008, sgn=-1)
    add(scr)
    add(_ellipse(0.198, -0.162, 0.011, 0.011))
    # tendril with berries rising beside the crown
    td = _bez((0.14, -0.05), (0.13, -0.18), (0.18, -0.28), (0.13, -0.34))
    add(_stroke(td, 0.012, 0.005))
    for bx, by in ((0.125, -0.365), (0.105, -0.345), (0.145, -0.39)):
        add(_ellipse(bx, by, 0.012, 0.012))
    add(_leaf(_bez((0.15, -0.23), (0.19, -0.25), (0.22, -0.27), (0.25, -0.31)), 0.035, power=0.7))
    # --- lower leaves curling down and out ---
    ll = _bez((0.03, 0.17), (0.14, 0.18), (0.24, 0.26), (0.22, 0.36))
    add(_leaf(ll, 0.075, lobes=3, lobe_depth=0.45, power=0.6))
    add(_stroke(ll[4:-6], 0.008, 0.003), 0)
    scr2, _ = _spiral(0.19, 0.355, 0.032, 0.6, 1.1, 0.018, 0.006, sgn=1)
    add(scr2)
    # stem + bottom pendant
    add(_stroke(_bez((0, 0.15), (0, 0.22), (0, 0.26), (0, 0.30)), 0.020, 0.016), 1, False)
    add(_leaf(_bez((0, 0.28), (0, 0.34), (0, 0.41), (0, 0.47)), 0.07, power=0.65), 1, False)
    add(_stroke(_bez((0, 0.30), (0, 0.35), (0, 0.40), (0, 0.44)), 0.008, 0.003), 0, False)
    add(_leaf(_bez((0.0, 0.29), (0.05, 0.28), (0.09, 0.32), (0.11, 0.40)), 0.04, power=0.7))
    for bx, by in ((0.29, 0.21), (0.31, 0.185), (0.27, 0.185)):
        add(_ellipse(bx, by, 0.011, 0.011))
    return P


def _sprig_motif():
    P = []

    def add(poly, v=1, m=True):
        P.append((np.asarray(poly, float), v, m))

    add(_leaf(_bez((0, 0.04), (0, -0.01), (0, -0.07), (0, -0.13)), 0.05, power=0.65), 1, False)
    add(_stroke(_bez((0, 0.02), (0, -0.03), (0, -0.07), (0, -0.10)), 0.006, 0.002), 0, False)
    add(_leaf(_bez((0, 0.03), (0.05, 0.0), (0.09, -0.01), (0.13, -0.05)), 0.04, power=0.7))
    s1, _ = _spiral(0.07, 0.07, 0.028, -2.6, 1.0, 0.012, 0.004, sgn=-1)
    add(s1)
    add(_ellipse(0.0, 0.06, 0.013, 0.013), 1, False)
    add(_ellipse(0.0, -0.16, 0.009, 0.009), 1, False)
    return P


def _render_motifs(S, placements):
    """placements: list of (motif, cx, cy, scale).  Drawn in order with mirror
    copies, wrapped around the tile (every copy is offset by whole tiles, so
    the rasterisation is identical on both sides of a seam)."""
    # Draw on a 3x3-tile canvas so every copy has positive, unclipped
    # coordinates (PIL truncates negative float coords differently), then keep
    # the centre tile.
    img = Image.new("L", (3 * S, 3 * S), 0)
    dr = ImageDraw.Draw(img)
    for motif, cx, cy, sc in placements:
        for poly, v, mirror in motif:
            for m in ((1, -1) if mirror else (1,)):
                pts = poly * np.array([m, 1.0])
                for ox in (0, S, 2 * S):
                    for oy in (0, S, 2 * S):
                        q = pts * sc * S + np.array([cx * S + ox, cy * S + oy])
                        dr.polygon([tuple(p) for p in q], fill=255 * v)
    return img.crop((S, S, 2 * S, 2 * S))


def m_damask(N, rng):
    S = 2 * N
    main, sprig = _damask_motif(), _sprig_motif()
    placements = [(main, 0.5, 0.5, 0.80), (main, 0.0, 0.0, 0.80),
                  (sprig, 0.5, 0.02, 0.95), (sprig, 0.0, 0.52, 0.95)]
    # draw ornaments in stacking order: fills first then cut-backs per motif
    img = _render_motifs(S, placements)
    # box-filter downsample (a wrap-safe exact 2x2 average; PIL resize clamps edges)
    M = np.asarray(img, F32).reshape(N, 2, N, 2).mean(axis=(1, 3)) / 255.0
    M = np.clip(M, 0, 1)
    X, Y = coords(N)
    f = float(N // 3)   # thread pitch ~3 px (integer cycles/tile -> periodic)
    satin = 0.5 + 0.5 * np.cos(TAU * f * Y / N) * (0.6 + 0.4 * spectral(N, rng, 300, 0.3, stretch=(8, 1)))
    ground = 0.5 + 0.5 * np.cos(TAU * f * X / N) * (0.6 + 0.4 * spectral(N, rng, 300, 0.3, stretch=(1, 8)))
    weave = lerp(ground, satin, M)
    age = spectral(N, rng, 5, slope=1.8)
    gcol, ocol = C(0.25, 0.10, 0.11), C(0.30, 0.13, 0.14)     # wine ground / charcoal-wine satin
    col = lerp3(solid(N, gcol), solid(N, ocol), M)
    col = col * (1 + 0.04 * (weave - 0.5) + 0.03 * age)[..., None]
    Mb = blur(M, 1.2)
    h = 1.2 * Mb + 0.25 * weave
    rough = lerp(0.82, 0.50, M) + 0.05 * (weave - 0.5) + 0.02 * age
    return Mat(col, h, 1.6, rough)


def m_rug(N, rng):
    """Single dark Persian-style rug (not tileable): medallion, spandrels, borders."""
    K = N // 2                                   # knots per side (2 px per knot)
    ky, kx = np.mgrid[0:K, 0:K].astype(F32)
    u = (kx + 0.5) / K * 2 - 1
    v = (ky + 0.5) / K * 2 - 1
    au, av = np.abs(u), np.abs(v)
    d = np.maximum(au, av)
    pal = {
        "red": (0.40, 0.075, 0.07), "dred": (0.29, 0.065, 0.06), "navy": (0.11, 0.13, 0.25),
        "ivory": (0.78, 0.72, 0.58), "gold": (0.70, 0.51, 0.22), "brown": (0.18, 0.12, 0.09),
        "rose": (0.60, 0.29, 0.23), "teal": (0.11, 0.27, 0.26), "sky": (0.34, 0.42, 0.54),
    }
    names = list(pal)
    PI = {n: i for i, n in enumerate(names)}
    idx = np.full((K, K), PI["red"], np.int32)

    def put(mask, name):
        idx[mask] = PI[name]

    r = np.sqrt(u * u + (v * 0.82) ** 2)
    th = np.arctan2(v, u)
    # ---------------- field -----------------
    field = d < 0.74
    # trellis lattice of small blossoms on a diamond grid
    cs = 0.125
    p1, p2 = (u + v), (u - v)
    l1 = p1 - cs * np.round(p1 / cs)
    l2 = p2 - cs * np.round(p2 / cs)
    put(field & ((np.abs(l1) < 0.0045) | (np.abs(l2) < 0.0045)), "dred")
    lr = np.sqrt(l1 ** 2 + l2 ** 2) / math.sqrt(2)
    lt = np.arctan2(l2, l1)
    blossom = lr < 0.022 * (0.55 + 0.45 * np.abs(np.cos(2 * lt)))
    put(field & blossom, "navy")
    put(field & (lr < 0.008), "gold")
    # half-offset small leaves (diamond centres)
    m1 = (p1 / cs - np.floor(p1 / cs)) - 0.5
    m2 = (p2 / cs - np.floor(p2 / cs)) - 0.5
    put(field & (np.abs(m1) + np.abs(m2) * 2.2 < 0.16), "rose")
    put(field & (np.abs(m1) + np.abs(m2) * 2.2 < 0.07), "ivory")
    # ---------------- corner spandrels ----------------
    rc = np.sqrt((au - 0.74) ** 2 + (av - 0.74) ** 2)
    tc = np.arctan2(0.74 - av, 0.74 - au)
    span = field & (rc < 0.33 + 0.018 * np.cos(14 * tc))
    put(span, "navy")
    put(field & (np.abs(rc - (0.33 + 0.018 * np.cos(14 * tc))) < 0.008), "gold")
    rs = np.abs(rc - 0.21)
    put(span & (rs < 0.035 * (0.5 + 0.5 * np.abs(np.cos(9 * tc)))), "rose")
    put(span & (rs < 0.012), "ivory")
    put(span & (rc < 0.09 * (0.7 + 0.3 * np.abs(np.cos(4 * tc)))), "teal")
    put(span & (rc < 0.035), "gold")
    stp = (np.pi / 2) / 6
    tl = (tc - stp * np.round(tc / stp)) * rc
    put(span & ((rc - 0.275) ** 2 + tl ** 2 < 0.021 ** 2), "red")
    put(span & ((rc - 0.275) ** 2 + tl ** 2 < 0.009 ** 2), "gold")
    put(span & ((rc - 0.135) ** 2 + ((tc - stp * 0.5 - stp * np.round((tc - stp * 0.5) / stp)) * rc) ** 2
                < 0.008 ** 2), "ivory")
    # ---------------- central medallion ----------------
    R = 0.36 + 0.022 * np.cos(16 * th) + 0.035 * np.cos(8 * th)
    med = r < R
    put(med, "navy")
    put(np.abs(r - R) < 0.009, "gold")
    put(med & (np.abs(r - (R - 0.04)) < 0.004), "ivory")
    # ring of 8 palmettes
    ang8 = th - (np.pi / 4) * np.round(th / (np.pi / 4))
    pr = r - 0.235
    palm = (np.abs(pr) / 0.07) ** 2 + (ang8 / (0.20 * (1.2 - pr * 4))) ** 2 < 1
    put(med & palm, "rose")
    put(med & palm & ((np.abs(pr) / 0.045) ** 2 + (ang8 / 0.09) ** 2 < 1), "ivory")
    put(med & palm & (np.abs(ang8) < 0.012), "red")
    # ring of 16 small dots
    ang16 = th - (np.pi / 8) * np.round(th / (np.pi / 8))
    put(med & ((r - 0.31) ** 2 + (ang16 * r) ** 2 < 0.012 ** 2), "gold")
    # inner star
    Rs = 0.15 * (1 + 0.16 * np.cos(8 * th))
    put(r < Rs, "red")
    put(np.abs(r - Rs) < 0.006, "gold")
    Rr = 0.075 * (0.6 + 0.4 * np.abs(np.cos(4 * th)))
    put(r < Rr, "gold")
    put(r < 0.028, "navy")
    put(r < 0.012, "ivory")
    # pendants top & bottom
    for sgn in (-1, 1):
        pv = v - sgn * 0.47
        dia = np.abs(u) / 0.06 + np.abs(pv) / 0.075 < 1
        put(dia, "navy")
        put(np.abs(np.abs(u) / 0.06 + np.abs(pv) / 0.075 - 1) < 0.1, "gold")
        put(np.abs(u) / 0.025 + np.abs(pv) / 0.035 < 1, "rose")
        fin = u ** 2 + (v - sgn * 0.565) ** 2 < 0.022 ** 2
        put(fin, "ivory")
        put(u ** 2 + (v - sgn * 0.565) ** 2 < 0.009 ** 2, "red")
    # ---------------- borders ----------------
    side_v = au >= av
    along = np.where(side_v, v, u)
    across = d
    # inner guard 0.745-0.79: zig-zag "running" band on red
    ig = (d >= 0.745) & (d < 0.79)
    put(ig, "red")
    zz = np.abs(((along / 0.03) % 2) - 1) * 0.03 + 0.752
    put(ig & (np.abs(across - zz) < 0.006), "ivory")
    put((np.abs(d - 0.742) < 0.003) | (np.abs(d - 0.793) < 0.003), "gold")
    # main border 0.80-0.945 on navy with rosettes and a meandering vine
    mb = (d >= 0.797) & (d < 0.945)
    put(mb, "navy")
    P = 0.8725 / 4.0
    a_loc = along - P * np.round(along / P)
    b_loc = across - 0.8725
    ph = np.round(along / P).astype(np.int64)
    vine = 0.035 * np.sin(np.pi * a_loc / P) * np.where(ph % 2 == 0, 1, -1)
    put(mb & (np.abs(b_loc - vine) < 0.005), "gold")
    lf = ((a_loc - P * 0.5 * np.sign(a_loc)) / 0.03) ** 2 + ((b_loc + 0.02 * np.sign(a_loc)) / 0.014) ** 2 < 1
    put(mb & lf, "teal")
    rr = np.sqrt(a_loc ** 2 + b_loc ** 2)
    rt = np.arctan2(b_loc, a_loc)
    ros = rr < 0.058 * (0.6 + 0.4 * np.abs(np.cos(4 * rt)))
    put(mb & ros, "red")
    put(mb & (rr < 0.034 * (0.7 + 0.3 * np.abs(np.cos(4 * rt + np.pi / 4)))), "gold")
    put(mb & (rr < 0.014), "ivory")
    # corners: rosette exactly on the diagonal
    put((np.abs(d - 0.797) < 0.003) | (np.abs(d - 0.945) < 0.003), "gold")
    # outer guard 0.95-0.982: small reciprocal dots
    og = (d >= 0.948) & (d < 0.982)
    put(og, "dred")
    oa = along - 0.02 * np.round(along / 0.02)
    put(og & (oa ** 2 + (across - 0.965) ** 2 < 0.0065 ** 2), "ivory")
    put(d >= 0.982, "brown")
    # ---------------- outlines (dark brown, 1 knot, on the lighter side) ----------------
    lum = np.array([0.3 * c[0] + 0.6 * c[1] + 0.1 * c[2] for c in pal.values()], F32)
    L = lum[idx]
    edge = np.zeros((K, K), bool)
    for sh, ax in ((1, 0), (-1, 0), (1, 1), (-1, 1)):
        nb = np.roll(idx, sh, ax)
        edge |= (nb != idx) & (lum[nb] < L) & (np.abs(lum[nb] - L) > 0.08)
    edge &= d < 0.982
    keep_gold = idx == PI["gold"]
    idx = np.where(edge & ~keep_gold, PI["brown"], idx)
    # ---------------- colour with dye variation, abrash, wear ----------------
    cols = srgb2lin(np.array(list(pal.values()), F32))
    col = cols[idx]
    krand = rng.standard_normal((K, K)).astype(F32)
    col = col * (1 + 0.035 * krand)[..., None]
    abrash = noise1d(K, rng, fmax=10, slope=1.2)
    col = col * (1 + 0.06 * abrash[:, None])[..., None]
    col[..., 2] *= (1 - 0.03 * abrash[:, None])
    col = np.repeat(np.repeat(col, 2, 0), 2, 1)
    dfull = np.repeat(np.repeat(d, 2, 0), 2, 1)
    wear = smoothstep(0.6, 2.2, spectral(N, rng, 5, slope=1.8))
    col = lerp3(col, col * 0.8 + 0.2 * luminance(col)[..., None] * 1.4, wear * 0.6)
    fuzz = spectral(N, rng, 400, slope=0.2)
    col = col * (1 + 0.03 * blur(fuzz, 0.6))[..., None]
    # selvedge overcasting at the edge: diagonal wrap stripes
    X, Y = coords(N)
    edge_band = smoothstep(0.978, 0.986, dfull)
    wrap_st = 0.5 + 0.5 * np.sin(TAU * (X + Y) / 6.0)
    col = col * (1 - 0.25 * edge_band * wrap_st)[..., None]
    # pile relief: knot rows (weft lines, constant along x -> tiny PNG), soft
    # large-scale pile undulation and worn patches; fine fuzz lives in albedo
    rows_ = np.tile(np.array([[1.0], [0.35]], F32), (K, N))
    pile = spectral(N, rng, 40, slope=1.2)
    fz = blur(fuzz, 0.8)
    h = 0.12 * rows_ + 0.25 * pile - 0.6 * wear + edge_band * (0.6 + 0.4 * wrap_st)
    rough = 0.88 + 0.03 * fz - 0.03 * wear
    return Mat(col, h, 1.0, rough, tileable=False, albedo_subsampling=0)


# =============================================================================
# HDR environments
# =============================================================================
def _rle_channel(v):
    n = v.size
    out = bytearray()
    brk = np.flatnonzero(v[1:] != v[:-1]) + 1
    starts = np.concatenate(([0], brk))
    lens = np.diff(np.concatenate((starts, [n])))
    long_ = lens >= 4
    pos = 0

    def dump(a, b):
        while a < b:
            c = min(128, b - a)
            out.append(c)
            out.extend(v[a:a + c].tobytes())
            a += c

    for s0, L in zip(starts[long_].tolist(), lens[long_].tolist()):
        dump(pos, s0)
        val = int(v[s0])
        rem = L
        while rem > 0:
            c = min(127, rem)
            out.append(128 + c)
            out.append(val)
            rem -= c
        pos = s0 + L
    dump(pos, n)
    return bytes(out)


def float_to_rgbe(img):
    m = img.max(axis=2).astype(np.float64)
    mant, ex = np.frexp(m)
    ok = m > 1e-32
    scale = np.where(ok, mant * 256.0 / np.where(ok, m, 1.0), 0.0)
    rgbe = np.zeros(img.shape[:2] + (4,), np.uint8)
    # round to nearest (readers such as Godot/OpenCV decode byte * 2^(e-136))
    rgbe[..., :3] = np.clip(np.floor(img * scale[..., None] + 0.5), 0, 255).astype(np.uint8)
    rgbe[..., 3] = np.where(ok, ex + 128, 0).astype(np.uint8)
    return rgbe


def write_hdr(path, img):
    H, W, _ = img.shape
    rgbe = float_to_rgbe(img.astype(np.float64))
    with open(path, "wb") as fp:
        fp.write(b"#?RADIANCE\n# procedural environment, tools/assetgen/gen_textures.py\n"
                 b"FORMAT=32-bit_rle_rgbe\n\n")
        fp.write(f"-Y {H} +X {W}\n".encode("ascii"))
        for y in range(H):
            fp.write(bytes((2, 2, W >> 8, W & 255)))
            for c in range(4):
                fp.write(_rle_channel(np.ascontiguousarray(rgbe[y, :, c])))
    return rgbe


def read_hdr(path):
    """Minimal Radiance reader (new-style RLE and flat) used to verify output."""
    data = open(path, "rb").read()
    pos = 0
    assert data.startswith(b"#?RADIANCE") or data.startswith(b"#?RGBE")
    while True:
        e = data.index(b"\n", pos)
        line = data[pos:e]
        pos = e + 1
        if line == b"" and pos > 11:
            break
    e = data.index(b"\n", pos)
    parts = data[pos:e].split()
    pos = e + 1
    H, W = int(parts[1]), int(parts[3])
    rgbe = np.zeros((H, W, 4), np.uint8)
    buf = memoryview(data)
    for y in range(H):
        assert data[pos] == 2 and data[pos + 1] == 2, "not RLE"
        assert (data[pos + 2] << 8 | data[pos + 3]) == W
        pos += 4
        for c in range(4):
            x = 0
            row = rgbe[y, :, c]
            while x < W:
                cnt = data[pos]
                pos += 1
                if cnt > 128:
                    cnt -= 128
                    row[x:x + cnt] = data[pos]
                    pos += 1
                else:
                    assert cnt > 0
                    row[x:x + cnt] = np.frombuffer(buf[pos:pos + cnt], np.uint8)
                    pos += cnt
                x += cnt
            assert x == W
    return rgbe


def rgbe_to_float(rgbe):
    e = rgbe[..., 3].astype(np.int32)
    f = np.where(e > 0, np.ldexp(1.0, e - 136), 0.0)
    return rgbe[..., :3].astype(np.float64) * f[..., None]


def env_dirs(W, H):
    """Equirect directions matching Godot 4 panorama sky lookup:
    u = atan2(x, -z) / 2pi (wrapped to 0..1), v = acos(y) / pi.
    So u=0 / u=1 edges face -Z (Godot's default forward), u=0.25 -> +X,
    u=0.5 (image centre) -> +Z, u=0.75 -> -X; top row = +Y (up)."""
    u = (np.arange(W) + 0.5) / W
    v = (np.arange(H) + 0.5) / H
    ph = u[None, :] * TAU
    th = v[:, None] * math.pi
    x = np.sin(th) * np.sin(ph)
    y = np.cos(th) * np.ones_like(ph)
    z = -np.sin(th) * np.cos(ph)
    return x, y, z


class Room:
    """Tiny analytic room renderer: box walls, emitters, point-ish lights."""

    def __init__(self, W, H, box):
        self.W, self.H = W, H
        self.dx, self.dy, self.dz = env_dirs(W, H)
        (x0, x1), (y0, y1), (z0, z1) = box
        dx, dy, dz = self.dx, self.dy, self.dz
        with np.errstate(divide="ignore", invalid="ignore"):
            tx = np.where(dx > 0, x1 / dx, np.where(dx < 0, x0 / dx, np.inf))
            ty = np.where(dy > 0, y1 / dy, np.where(dy < 0, y0 / dy, np.inf))
            tz = np.where(dz > 0, z1 / dz, np.where(dz < 0, z0 / dz, np.inf))
        t = np.minimum(np.minimum(tx, ty), tz)
        self.t = t
        self.px, self.py, self.pz = dx * t, dy * t, dz * t
        self.face = np.where(t == tx, np.where(dx > 0, "+x", "-x"),
                             np.where(t == ty, np.where(dy > 0, "ceil", "floor"),
                                      np.where(dz > 0, "+z", "-z")))
        n = np.zeros(t.shape + (3,))
        n[self.face == "+x"] = (-1, 0, 0)
        n[self.face == "-x"] = (1, 0, 0)
        n[self.face == "ceil"] = (0, -1, 0)
        n[self.face == "floor"] = (0, 1, 0)
        n[self.face == "+z"] = (0, 0, -1)
        n[self.face == "-z"] = (0, 0, 1)
        self.n = n
        self.albedo = np.zeros(t.shape + (3,))
        self.E = np.zeros(t.shape + (3,))
        self.emit = np.zeros(t.shape + (3,))

    def light(self, pos, colour, power, lobe=None, falloff_min=0.05):
        """Point light irradiance on the walls (no shadows)."""
        lx = pos[0] - self.px
        ly = pos[1] - self.py
        lz = pos[2] - self.pz
        d2 = lx * lx + ly * ly + lz * lz
        d = np.sqrt(d2)
        cos = np.clip((lx * self.n[..., 0] + ly * self.n[..., 1] + lz * self.n[..., 2]) / d, 0, 1)
        g = np.ones_like(d) if lobe is None else lobe(-lx / d, -ly / d, -lz / d)
        E = power * g * cos / np.maximum(d2, falloff_min)
        self.E += E[..., None] * np.asarray(colour)[None, None, :]

    def ambient(self, colour):
        self.E += np.asarray(colour)[None, None, :]

    def sphere(self, pos, radius, radiance, soft=0.3):
        """Visible emissive sphere (lamp bulb/shade) seen from the origin."""
        p = np.asarray(pos, float)
        dist = np.linalg.norm(p)
        c = (self.dx * p[0] + self.dy * p[1] + self.dz * p[2]) / dist
        ang = np.arccos(np.clip(c, -1, 1))
        ar = math.asin(min(radius / dist, 0.99))
        m = smoothstep(ar, ar * (1 - soft), ang)
        self.emit += m[..., None] * np.asarray(radiance)[None, None, :]
        return m

    def shade(self):
        return self.albedo * self.E / math.pi + self.emit


def _tonemap_preview(img, path, exposure=1.0):
    x = img * exposure
    x = x / (1 + x)
    x = lin2srgb(x.astype(F32) * 1.5)
    small = Image.fromarray(to_u8(x)).resize((512, 256), Image.LANCZOS)
    small.save(path)


def env_salon(W=2048, H=1024):
    box = ((-4.5, 4.5), (-1.05, 2.45), (-5.0, 5.0))
    R = Room(W, H, box)
    px, py, pz, f = R.px, R.py, R.pz, R.face
    wall = (f == "+x") | (f == "-x") | (f == "+z") | (f == "-z")
    along = np.where((f == "+x") | (f == "-x"), pz, px)
    # --- surface albedos ---
    damask = C(0.20, 0.06, 0.07).astype(float)
    alb = np.zeros(px.shape + (3,))
    patt = 0.5 + 0.5 * np.cos(TAU * along / 0.55) * np.cos(TAU * py / 0.8)
    alb[wall] = damask * (0.8 + 0.25 * patt[wall, None])
    wains = wall & (py < -0.05)
    alb[wains] = C(0.16, 0.10, 0.07)
    panel = wains & ((np.abs(((along + 0.3) % 1.2) - 0.6) > 0.5) | (np.abs(py + 0.55) > 0.38))
    alb[panel] = C(0.12, 0.075, 0.05)
    rail = wall & (np.abs(py + 0.05) < 0.025)
    alb[rail] = C(0.55, 0.42, 0.22)
    # paintings with gilt frames on +/-z walls between sconces
    for zc_face in ("+z", "-z"):
        sel = f == zc_face
        fr = sel & (np.abs(px) < 0.95) & (np.abs(py - 0.95) < 0.62)
        canvas = sel & (np.abs(px) < 0.82) & (np.abs(py - 0.95) < 0.50)
        alb[fr & ~canvas] = C(0.62, 0.46, 0.20)
        tone = 0.5 + 0.5 * np.sin(px[canvas] * 3.1 + py[canvas] * 2.3)
        alb[canvas] = np.stack([0.10 + 0.08 * tone, 0.07 + 0.04 * tone, 0.05 + 0.02 * tone], -1)
    # bookcase on -x wall
    bc = (f == "-x") & (np.abs(pz) < 2.4) & (py < 1.9)
    shelf = np.floor((py + 1.05) / 0.42)
    spine = np.floor((pz + 3.0) / 0.045)
    hsh = (np.sin(spine * 12.9898 + shelf * 78.233) * 43758.5453) % 1.0
    books = np.stack([0.08 + 0.10 * hsh, 0.05 + 0.04 * ((hsh * 7) % 1), 0.04 + 0.03 * ((hsh * 13) % 1)], -1)
    alb[bc] = books[bc]
    alb[bc & (((py + 1.05) % 0.42) < 0.03)] = C(0.14, 0.09, 0.06)
    fl = f == "floor"
    herr = 0.5 + 0.5 * np.sign(np.sin(TAU * (px + pz) / 0.5) * np.sin(TAU * (px - pz) / 0.5))
    alb[fl] = C(0.14, 0.095, 0.06) * (0.85 + 0.2 * herr[fl, None])
    rug = fl & (np.abs(px) < 1.8) & (np.abs(pz) < 2.4)
    alb[rug] = C(0.20, 0.06, 0.055)
    alb[f == "ceil"] = C(0.10, 0.085, 0.075)
    R.albedo = alb
    # --- lights ---
    warm = np.array([1.0, 0.72, 0.42])
    sconces = [(-1.9, 0.95, -4.72), (1.9, 0.95, -4.72), (-1.9, 0.95, 4.72), (1.9, 0.95, 4.72)]

    def updown(dx, dy, dz):        # open-top/bottom shade: light pools above & below
        return 0.08 + 0.92 * np.abs(dy) ** 1.5

    for p in sconces:
        R.light(p, warm, 4.0, lobe=updown)
    soft = np.array([1.0, 0.86, 0.68])
    R.light((0.0, 2.35, 0.0), soft, 10.0, lobe=lambda dx, dy, dz: np.clip(-dy, 0, 1) ** 1.2)
    cool = np.array([0.55, 0.68, 1.0])
    R.light((4.3, 1.0, 0.0), cool, 1.2, lobe=lambda dx, dy, dz: np.clip(-dx, 0, 1))
    R.ambient(np.array([0.030, 0.022, 0.017]))
    img = R.shade()
    # --- visible emitters ---
    # window on +x wall with mullions, framed by dark curtains
    win = (f == "+x") & (np.abs(pz) < 1.0) & (py > -0.1) & (py < 2.0)
    mull = (np.abs(pz) < 0.03) | (np.abs(py - 0.95) < 0.03) | (np.abs(np.abs(pz) - 0.5) < 0.015)
    grad_ = 0.7 + 0.3 * smoothstep(-0.1, 2.0, py)
    wcol = np.array([0.55, 0.68, 1.0]) * 1.6
    img[win & ~mull] = (wcol * grad_[win & ~mull, None])
    img[win & mull] = 0.02
    curt = (f == "+x") & (np.abs(pz) >= 1.0) & (np.abs(pz) < 1.45) & (py > -1.0) & (py < 2.2)
    folds = 0.5 + 0.5 * np.cos(TAU * pz / 0.12)
    img[curt] = (np.array([0.10, 0.03, 0.035]) * (0.3 + 0.7 * folds[curt, None])
                 * (0.4 + 0.6 * smoothstep(1.45, 1.0, np.abs(pz[curt])))[:, None])
    # overhead softbox
    sb = (f == "ceil") & (np.abs(px) < 0.75) & (np.abs(pz) < 0.55)
    edge = smoothstep(0.0, 0.18, np.minimum(0.75 - np.abs(px), 0.55 - np.abs(pz)))
    img[sb] = soft * 4.5 * (0.6 + 0.4 * edge[sb, None])
    # brass lamps: glowing shade + bright bulb core
    for p in sconces:
        shade_col = np.array([1.0, 0.70, 0.40])
        R.emit[:] = 0
        m = R.sphere(p, 0.13, shade_col * 16.0, soft=0.25)
        img = img * (1 - m[..., None]) + R.emit
        R.emit[:] = 0
        R.sphere((p[0], p[1] - 0.02, p[2]), 0.05, np.array([1.0, 0.82, 0.6]) * 40.0, soft=0.4)
        img = np.maximum(img, R.emit)
    # table below the origin
    dy = R.dy
    tt = np.where(dy < 0, -0.40 / np.minimum(dy, -1e-6), np.inf)
    tx, tz = R.dx * tt, R.dz * tt
    table = (dy < 0) & (tx ** 2 + tz ** 2 < 0.70 ** 2)
    tE = soft * 10.0 / (2.75 ** 2) + 0.03
    img[table] = C(0.12, 0.07, 0.04) * tE / math.pi
    return np.asarray(img, np.float64)


def env_club(W=2048, H=1024):
    box = ((-4.0, 4.0), (-1.0, 2.4), (-4.5, 4.5))
    R = Room(W, H, box)
    px, py, pz, f = R.px, R.py, R.pz, R.face
    wall = (f == "+x") | (f == "-x") | (f == "+z") | (f == "-z")
    along = np.where((f == "+x") | (f == "-x"), pz, px)
    alb = np.zeros(px.shape + (3,))
    wood = C(0.36, 0.19, 0.10).astype(float)
    grain = 0.85 + 0.15 * np.sin(TAU * py * 9 + np.sin(along * 3.0) * 2)
    alb[wall] = wood * grain[wall, None]
    # panel mouldings: darker frames around raised panels
    pa = (along + 0.35) % 0.7
    pyl = (py + 1.0) % 0.85
    frame = (np.abs(pa - 0.35) > 0.27) | (np.abs(pyl - 0.425) > 0.33)
    alb[wall & frame] = wood * 0.72
    upper = wall & (py > 1.55)
    alb[upper] = C(0.09, 0.17, 0.12)
    alb[wall & (np.abs(py - 1.55) < 0.03)] = C(0.55, 0.42, 0.22)
    fl = f == "floor"
    plank = np.floor(px / 0.18)
    ph = (np.sin(plank * 12.9898) * 43758.5453) % 1.0
    alb[fl] = C(0.36, 0.22, 0.12) * (0.8 + 0.3 * ph[fl, None])
    rug = fl & (np.abs(px) < 1.6) & (np.abs(pz) < 2.2)
    alb[rug] = C(0.18, 0.10, 0.07)
    alb[f == "ceil"] = C(0.20, 0.13, 0.08)
    beam = (f == "ceil") & ((np.abs((px % 1.3) - 0.65) > 0.58) | (np.abs((pz % 1.3) - 0.65) > 0.58))
    alb[beam] = C(0.14, 0.085, 0.05)
    R.albedo = alb
    warm = np.array([1.0, 0.74, 0.45])
    # banker's lamp above the table: strong downward cone, little upward
    R.light((0.0, 1.05, 0.0), warm, 7.0, lobe=lambda dx, dy, dz: 0.10 + 0.90 * np.clip(-dy, 0, 1) ** 3)
    R.light((0.0, 1.20, 0.0), np.array([0.35, 0.8, 0.45]), 0.25)       # green glass glow
    # fireplace on -x wall
    fire = np.array([1.0, 0.45, 0.14])
    R.light((-3.7, -0.55, 0.0), fire, 5.0, lobe=lambda dx, dy, dz: np.clip(dx, 0, 1) ** 0.7 + 0.1)
    # two wall sconces on +z wall
    sconces = [(-1.6, 0.9, 4.25), (1.6, 0.9, 4.25)]
    for p in sconces:
        R.light(p, warm, 2.5, lobe=lambda dx, dy, dz: 0.2 + 0.8 * dy ** 2)
    R.light((3.8, 1.0, 0.0), np.array([0.6, 0.7, 1.0]), 0.2, lobe=lambda dx, dy, dz: np.clip(-dx, 0, 1))
    R.ambient(np.array([1.2, 0.85, 0.55]))
    img = R.shade()
    # fireplace opening + mantel
    fp = (f == "-x") & (np.abs(pz) < 0.85) & (py < -0.15)
    hot = smoothstep(-0.15, -1.0, py) * smoothstep(0.85, 0.2, np.abs(pz))
    flick = 0.8 + 0.2 * np.sin(pz * 23.0 + np.sin(py * 17.0) * 3)
    img[fp] = np.array([1.0, 0.42, 0.10])[None, :] * ((0.6 + 5.5 * hot[fp] ** 1.5) * flick[fp])[:, None]
    surround = (f == "-x") & (np.abs(pz) < 1.25) & (py < 0.25) & ~fp
    img[surround] = img[surround] * 0.6 + np.array([0.09, 0.06, 0.05]) * 0.3
    mantel = (f == "-x") & (np.abs(pz) < 1.4) & (np.abs(py - 0.3) < 0.06)
    img[mantel] = C(0.40, 0.22, 0.12) * 0.25
    # dim window on +x wall, green curtains
    win = (f == "+x") & (np.abs(pz) < 0.8) & (py > 0.0) & (py < 1.9)
    mull = (np.abs(pz) < 0.025) | (np.abs(py - 0.95) < 0.025)
    img[win & ~mull] = np.array([0.40, 0.48, 0.66]) * 0.9 * (0.7 + 0.3 * smoothstep(0, 1.9, py[win & ~mull]))[:, None]
    img[win & mull] = 0.015
    curt = (f == "+x") & (np.abs(pz) >= 0.8) & (np.abs(pz) < 1.25) & (py < 2.1)
    folds = 0.5 + 0.5 * np.cos(TAU * pz / 0.11)
    img[curt] = np.array([0.03, 0.07, 0.04]) * (0.4 + 0.6 * folds[curt, None])
    # banker's lamp (green glass shade, ~1.1 m above) seen from below: hot bulb,
    # bright reflector interior, glowing green rim
    ang = np.arccos(np.clip(R.dy, -1, 1))
    shade_m = smoothstep(0.215, 0.195, ang)
    rim = smoothstep(0.15, 0.20, ang) * shade_m
    inner = smoothstep(0.17, 0.12, ang)
    glass = np.array([0.20, 0.62, 0.30]) * 2.0
    img = img * (1 - shade_m[..., None]) + shade_m[..., None] * (
        glass * rim[..., None] + np.array([1.0, 0.85, 0.62]) * 12.0 * inner[..., None])
    bulb = smoothstep(0.06, 0.03, ang)
    img = img + bulb[..., None] * np.array([1.0, 0.85, 0.62]) * 45.0
    for p in sconces:
        R.emit[:] = 0
        m = R.sphere(p, 0.11, np.array([1.0, 0.72, 0.42]) * 18.0, soft=0.3)
        img = img * (1 - m[..., None]) + R.emit
    # table (green baize) below the origin, lit by the lamp
    dy = R.dy
    tt = np.where(dy < 0, -0.40 / np.minimum(dy, -1e-6), np.inf)
    tx, tz = R.dx * tt, R.dz * tt
    table = (dy < 0) & (tx ** 2 + tz ** 2 < 0.70 ** 2)
    rr = np.sqrt(tx ** 2 + tz ** 2)
    tE = 9.0 / (1.45 ** 2) * np.exp(-(rr / 1.0) ** 2)
    tcol = C(0.10, 0.25, 0.14)
    img[table] = (tcol * warm)[None, :] * (tE[table] / math.pi)[:, None] + 0.005
    return img


def solid_angle_mean(img):
    H = img.shape[0]
    th = (np.arange(H) + 0.5) / H * math.pi
    w = np.sin(th)[:, None]
    lum = 0.2126 * img[..., 0] + 0.7152 * img[..., 1] + 0.0722 * img[..., 2]
    return float((lum * w).sum() / (w.sum() * img.shape[1]))


def build_env(name, out_dir, preview_dir):
    img = env_salon() if name == "salon" else env_club()
    img = np.nan_to_num(np.clip(img, 0, 1e4))
    os.makedirs(os.path.join(out_dir, "env"), exist_ok=True)
    path = os.path.join(out_dir, "env", f"{name}.hdr")
    rgbe = write_hdr(path, img)
    back = read_hdr(path)
    ok = bool(np.array_equal(back, rgbe))
    rec = rgbe_to_float(back)
    rel = float(np.abs(rec - img).max() / max(img.max(), 1e-6))
    info = dict(path=path, kb=os.path.getsize(path) / 1024, mean_lum=solid_angle_mean(img),
                max=float(img.max()), roundtrip=ok, relerr=rel)
    if preview_dir:
        _tonemap_preview(img, os.path.join(preview_dir, f"env_{name}.png"), exposure=1.0)
    return info


# =============================================================================
# registry
# =============================================================================
def _reg():
    cg = C
    return {
        # --- chess board themes ---
        "sq_salon_light": (1024, lambda N, r: m_maple(N, r)),
        "sq_salon_dark": (1024, lambda N, r: m_ebony(N, r)),
        "frame_walnut_burl": (1024, m_walnut_burl),
        "sq_boxwood": (1024, m_boxwood),
        "sq_rosewood": (1024, m_rosewood),
        "frame_walnut": (1024, lambda N, r: m_walnut(N, r)),
        "sq_marble_white": (1024, lambda N, r: m_marble(N, r, "white")),
        "sq_marble_black": (1024, lambda N, r: m_marble(N, r, "black")),
        "frame_marble_green": (1024, lambda N, r: m_marble(N, r, "green")),
        "sq_vinyl_buff": (1024, lambda N, r: m_vinyl(N, r, cg(0.84, 0.77, 0.60))),
        "sq_vinyl_green": (1024, lambda N, r: m_vinyl(N, r, cg(0.20, 0.40, 0.26))),
        "frame_matte_black": (1024, m_matte_black),
        # --- chess room ---
        "floor_herringbone": (2048, m_herringbone),
        "wall_damask": (1024, m_damask),
        "rug_persian": (2048, m_rug),
        "felt_black": (1024, lambda N, r: m_felt(N, r, cg(0.17, 0.165, 0.17))),
        "brass_brushed": (1024, m_brass),
        "leather_black": (1024, lambda N, r: m_leather(N, r, cg(0.175, 0.165, 0.16), cg(0.15, 0.142, 0.138),
                                                       cg(0.22, 0.21, 0.20))),
        # --- chess pieces ---
        "piece_ivory": (512, m_ivory),
        "piece_ebony": (512, lambda N, r: m_ebony(N, r, piece=True)),
        "piece_boxwood": (512, m_boxwood),
        "piece_rosewood": (512, m_rosewood),
        "piece_marble_white": (512, lambda N, r: m_marble(N, r, "white", scale=1.0)),
        "piece_marble_black": (512, lambda N, r: m_marble(N, r, "black", scale=1.0)),
        # --- checkers board themes ---
        "sq_maple": (1024, lambda N, r: m_maple(N, r, warm=1.0)),
        "sq_mahogany": (1024, lambda N, r: m_mahogany(N, r)),
        "frame_mahogany": (1024, lambda N, r: m_mahogany(N, r, frame=True)),
        "sq_lacquer_red": (1024, lambda N, r: m_lacquer(N, r, cg(0.47, 0.065, 0.055), cg(0.33, 0.035, 0.04),
                                                        crackle=1.0)),
        "sq_lacquer_black": (1024, lambda N, r: m_lacquer(N, r, cg(0.165, 0.158, 0.152), cg(0.15, 0.145, 0.142),
                                                          crackle=0.35)),
        "frame_lacquer_black": (1024, lambda N, r: m_lacquer(N, r, cg(0.165, 0.158, 0.152),
                                                             cg(0.15, 0.145, 0.142), frame=True)),
        "sq_stone_cream": (1024, m_limestone),
        "sq_slate": (1024, m_slate),
        "frame_oak_smoked": (1024, m_oak_smoked),
        # --- checkers room ---
        "table_leather_green": (1024, lambda N, r: m_leather(N, r, cg(0.13, 0.27, 0.17), cg(0.08, 0.165, 0.105),
                                                             cg(0.18, 0.33, 0.21), cells=96, nstr=1.4)),
        "floor_plank_oak": (2048, m_plank_floor),
        "wall_panel_wood": (1024, m_wall_panel),
        "felt_green": (1024, lambda N, r: m_felt(N, r, cg(0.15, 0.36, 0.19))),
        # --- checkers pieces ---
        "piece_cream": (512, m_cream),
        "piece_mahogany_red": (512, lambda N, r: m_mahogany(N, r, piece=True)),
    }


GAMES = {
    "chess": dict(
        materials=["sq_salon_light", "sq_salon_dark", "frame_walnut_burl",
                   "sq_boxwood", "sq_rosewood", "frame_walnut",
                   "sq_marble_white", "sq_marble_black", "frame_marble_green",
                   "sq_vinyl_buff", "sq_vinyl_green", "frame_matte_black",
                   "floor_herringbone", "wall_damask", "rug_persian", "felt_black",
                   "brass_brushed", "leather_black",
                   "piece_ivory", "piece_ebony", "piece_boxwood", "piece_rosewood",
                   "piece_marble_white", "piece_marble_black"],
        env="salon"),
    "checkers": dict(
        materials=["sq_maple", "sq_mahogany", "frame_mahogany",
                   "sq_lacquer_red", "sq_lacquer_black", "frame_lacquer_black",
                   "sq_stone_cream", "sq_slate", "frame_oak_smoked",
                   "sq_marble_white", "sq_marble_black", "frame_marble_green",
                   "table_leather_green", "floor_plank_oak", "wall_panel_wood", "felt_green",
                   "brass_brushed",
                   "piece_cream", "piece_mahogany_red", "piece_ebony", "piece_ivory"],
        env="club"),
}


def build_material(args):
    name, out_dir, preview_dir = args
    t0 = time.time()
    size, fn = _reg()[name]
    rng = rng_for(name)
    mat = fn(size, rng)
    paths, alb8, nrm8, rgh8 = save_material(name, mat, out_dir)
    if preview_dir:
        preview_sheet(name, alb8, nrm8, rgh8, mat, os.path.join(preview_dir, f"{name}.png"))
    lin = srgb2lin(alb8.astype(F32) / 255.0)
    lum = luminance(lin)
    row = dict(name=name, size=size,
               kb=sum(os.path.getsize(p) for p in paths.values()) / 1024.0,
               kb_parts={k: os.path.getsize(p) / 1024.0 for k, p in paths.items()},
               mean_srgb=alb8.reshape(-1, 3).mean(0) / 255.0,
               mean_lum=float(lum.mean()), p01_lum=float(np.percentile(lum, 1)),
               max_lin=float(lin.max()),
               rough=(float(rgh8.min()) / 255, float(rgh8.mean()) / 255, float(rgh8.max()) / 255),
               seam=(max(seam_ratio(alb8), seam_ratio(nrm8), seam_ratio(rgh8)) if mat.tileable else None),
               seam_file=(max(seam_ratio(np.asarray(Image.open(paths["albedo"])), True),
                              seam_ratio(np.asarray(Image.open(paths["normal"]))),
                              seam_ratio(np.asarray(Image.open(paths["rough"])), True))
                          if mat.tileable else None),
               secs=time.time() - t0)
    return row


def selftest():
    """Periodicity self-test of the primitives: evaluating any field one whole
    tile away (x+N or y+N) must give the same values."""
    N = 256
    X, Y = coords(N)
    rng = rng_for("selftest")
    worst = {}
    f = spectral(N, rng, 30, slope=1.0)
    worst["spectral+samp"] = float(np.abs(samp(f, X + N, Y - N, 3) - samp(f, X, Y, 3)).max())
    W = Worley(rng, 7, 5)
    a, b = W.eval(X / N, Y / N), W.eval(X / N + 1, Y / N - 2)
    worst["worley"] = max(float(np.abs(p - q).max()) for p, q in zip(a, b))
    Xa, Ya = fractal_warp(N, rng_for("st_w"), X, Y, [(30, 3), (8, 12)])
    Xb, Yb = fractal_warp(N, rng_for("st_w"), X + N, Y + N, [(30, 3), (8, 12)])
    worst["fractal_warp"] = float(max(np.abs(Xb - N - Xa).max(), np.abs(Yb - N - Ya).max()))
    wood = Wood(rng_for("st_wood"), Ns=N, rings=8, ray_len=24, ribbon_k=3, curl_k=2)
    d0, d1, d2 = wood.eval(X, Y), wood.eval(X + N, Y), wood.eval(X, Y + N)
    keys = ("lw", "pores", "rays", "fibre", "streak", "lines", "colvar", "colvar2", "ribbon", "curl")
    worst["wood"] = max(float(max(np.abs(d0[k_] - d1[k_]).max(), np.abs(d0[k_] - d2[k_]).max())) for k_ in keys)
    p0 = herringbone_lattice(N, X, Y)
    p1 = herringbone_lattice(N, X + N, Y)
    p2 = herringbone_lattice(N, X, Y + N)
    # pixels exactly on a plank edge (distance 0) may round to either plank
    m1 = (p0[4] > 1e-3) & (p1[4] > 1e-3)
    m2 = (p0[4] > 1e-3) & (p2[4] > 1e-3)
    worst["herringbone ids"] = float(max(np.abs(p0[0] - p1[0])[m1].max(), np.abs(p0[0] - p2[0])[m2].max()))
    worst["herringbone coords"] = float(max(np.abs(p0[2] - p1[2])[m1].max(), np.abs(p0[3] - p2[3])[m2].max()))
    ok = True
    for k_, v in worst.items():
        good = v < 5e-3
        ok &= good
        print(f"  {k_:<20} max |f(x+N) - f(x)| = {v:.2e}  {'OK' if good else 'FAIL'}")
    img = np.zeros((4, 16, 3))
    img[1, 3] = (12.5, 3.0, 0.25)
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), ".selftest.hdr")
    try:
        rgbe = write_hdr(path, np.tile(img, (1, 1, 1)))
        good = np.array_equal(read_hdr(path), rgbe)
    finally:
        if os.path.exists(path):
            os.remove(path)
    ok &= good
    print(f"  {'hdr rle round-trip':<20} {'OK' if good else 'FAIL'}")
    print("selftest", "passed" if ok else "FAILED")
    return 0 if ok else 1


def detect_game(root):
    try:
        txt = open(os.path.join(root, "project.godot"), encoding="utf-8").read()
    except OSError:
        txt = ""
    if "Checkers" in txt or "checkers" in os.path.basename(os.path.abspath(root)).lower():
        return "checkers"
    return "chess"


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    root_default = os.path.abspath(os.path.join(here, "..", ".."))
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--game", choices=sorted(GAMES), default=None)
    ap.add_argument("--root", default=root_default, help="repo root (default: two dirs above this script)")
    ap.add_argument("--out", default=None, help="output dir (default: <root>/assets/textures)")
    ap.add_argument("--only", default="", help="comma separated material names (and/or 'env')")
    ap.add_argument("--preview-dir", default=os.environ.get("TEXGEN_PREVIEW_DIR", ""),
                    help="write QC preview sheets here (optional)")
    ap.add_argument("--jobs", type=int, default=min(8, os.cpu_count() or 1))
    ap.add_argument("--no-env", action="store_true")
    ap.add_argument("--selftest", action="store_true", help="run periodicity/HDR self-tests and exit")
    a = ap.parse_args()
    if a.selftest:
        return selftest()
    game = a.game or detect_game(a.root)
    out_dir = a.out or os.path.join(a.root, "assets", "textures")
    os.makedirs(out_dir, exist_ok=True)
    if a.preview_dir:
        os.makedirs(a.preview_dir, exist_ok=True)
    cfg = GAMES[game]
    only = [s.strip() for s in a.only.split(",") if s.strip()]
    mats = [m for m in cfg["materials"] if not only or m in only]
    do_env = not a.no_env and (not only or "env" in only)
    print(f"[gen_textures] game={game} out={out_dir} materials={len(mats)} env={do_env}")
    t0 = time.time()
    jobs = [(m, out_dir, a.preview_dir or None) for m in mats]
    rows = []
    if a.jobs > 1 and len(jobs) > 1:
        # big maps first so the pool stays busy
        jobs.sort(key=lambda j: -_reg()[j[0]][0])
        with ProcessPoolExecutor(max_workers=a.jobs) as ex:
            rows = list(ex.map(build_material, jobs))
    else:
        rows = [build_material(j) for j in jobs]
    order = {m: i for i, m in enumerate(cfg["materials"])}
    rows.sort(key=lambda r: order[r["name"]])
    env_info = build_env(cfg["env"], out_dir, a.preview_dir or None) if do_env else None
    print()
    hdr = f"{'material':<22}{'size':>6}{'KB':>8}  {'alb/nrm/rgh KB':<17}{'mean sRGB':<18}" \
          f"{'lumLin':>7}{'p1':>7}{'rough min/mean/max':>20}{'seam':>6}{'file':>6}{'rank':>6}{'sec':>6}"
    print(hdr)
    print("-" * len(hdr))
    total = 0.0
    for r in rows:
        total += r["kb"]
        kp = r["kb_parts"]
        ms = r["mean_srgb"]
        seam = (f"{r['seam'][0]:.2f}{r['seam_file'][0]:>6.2f}{100 * r['seam'][1]:>5.0f}%"
                if r["seam"] is not None else "   n/a   n/a     ")
        print(f"{r['name']:<22}{r['size']:>6}{r['kb']:>8.0f}  "
              f"{kp['albedo']:>4.0f}/{kp['normal']:>5.0f}/{kp['rough']:>4.0f}  "
              f"({ms[0]:.2f},{ms[1]:.2f},{ms[2]:.2f})  {r['mean_lum']:>6.3f}{r['p01_lum']:>7.3f}"
              f"{r['rough'][0]:>8.2f}/{r['rough'][1]:.2f}/{r['rough'][2]:.2f}{seam:>18}{r['secs']:>6.1f}")
    if env_info:
        total += env_info["kb"]
        print(f"\nenv {os.path.relpath(env_info['path'], a.root)}: {env_info['kb']:.0f} KB, "
              f"mean luminance {env_info['mean_lum']:.3f}, peak {env_info['max']:.1f}, "
              f"RLE round-trip {'OK' if env_info['roundtrip'] else 'FAILED'}, "
              f"max rel. quantisation err {env_info['relerr']:.4f}")
    print("\nseam = wrap-pair difference / mean interior neighbour difference on the 8-bit maps "
          "(worst of albedo/normal/rough, worst axis; ~1 = seamless);\n"
          "file = same on the decoded files vs 16 px JPEG block boundaries; rank = share of interior "
          "neighbour pairs at least as different as the wrap pair (a real seam is the worst pair: 0%).")
    print(f"\ntotal written this run: {total / 1024:.1f} MB in {time.time() - t0:.0f}s")
    bad = [r["name"] for r in rows if r["seam"] is not None
           and max(r["seam"][0], r["seam_file"][0]) > 2.0 and r["seam"][1] == 0.0]
    if bad:
        print("WARNING: possible seam (ratio > 2 and worst neighbour pair) for:", ", ".join(bad))
    if env_info and not env_info["roundtrip"]:
        print("ERROR: HDR round-trip failed")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
