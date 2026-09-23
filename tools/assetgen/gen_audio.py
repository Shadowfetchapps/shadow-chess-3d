#!/usr/bin/env python3
"""Shadow Chess 3D -- offline audio synthesis pipeline ("private salon").

Every sound effect and the ambient music loop is synthesised from scratch with
numpy/scipy (modal/physical models, additive mallet and piano tones, synthetic
room reverb) -- no samples, no network.  The result is encoded to Ogg Vorbis
(44.1 kHz, ``libvorbis -q:a 5``) with ffmpeg and written to ``assets/audio/``.
Afterwards every file is decoded again and a QC table is printed (peak, true
peak, loudness, DC, edge clicks, attack time, loop seam for music).

Usage (from the repository root)::

    python3 tools/assetgen/gen_audio.py                 # render everything + QC
    python3 tools/assetgen/gen_audio.py --only move_1 check
    python3 tools/assetgen/gen_audio.py --analyze-only  # QC of existing files
    python3 tools/assetgen/gen_audio.py --plots /tmp/x  # + PNG contact sheets

Deterministic: each sound draws from its own RNG seeded with crc32(name) and
ffmpeg runs in bit-exact mode, so re-running reproduces identical files.
Requires python3 + numpy + scipy and ffmpeg with libvorbis; matplotlib is
optional (only for ``--plots``).
"""
from __future__ import annotations

import argparse
import math
import shutil
import subprocess
import sys
import tempfile
import time
import zlib
from pathlib import Path

import numpy as np
from scipy import signal
from scipy.io import wavfile

SR = 44100
GAME = "chess"
REPO = Path(__file__).resolve().parents[2]
OUT_DIR = REPO / "assets" / "audio"
FFMPEG = shutil.which("ffmpeg") or "/usr/bin/ffmpeg"
TP_CEILING = -1.0          # dBTP hard ceiling after encoding
MUSIC_LUFS = -20.0         # integrated loudness target for the music loop
LN1000 = math.log(1000.0)  # exp(-LN1000 * t / T60) reaches -60 dB at T60

# =============================================================================
# Core DSP helpers (identical in both games' generators)
# =============================================================================


def n_of(sec: float) -> int:
    return max(0, int(round(sec * SR)))


def t_of(n: int) -> np.ndarray:
    return np.arange(n) / SR


def db2lin(d: float) -> float:
    return 10.0 ** (d / 20.0)


def lin2db(x: float) -> float:
    return 20.0 * math.log10(max(float(x), 1e-12))


def midi_hz(m: float) -> float:
    return 440.0 * 2.0 ** ((m - 69.0) / 12.0)


def rng_for(name: str) -> np.random.Generator:
    return np.random.default_rng(zlib.crc32(f"{GAME}:{name}".encode()))


def _bc(env: np.ndarray, x: np.ndarray) -> np.ndarray:
    return env[:, None] if x.ndim == 2 else env


def ramp(n: int) -> np.ndarray:
    """Raised-cosine 0 -> 1 over n samples."""
    if n <= 0:
        return np.zeros(0)
    return 0.5 - 0.5 * np.cos(np.pi * (np.arange(n) + 0.5) / n)


def fade(x: np.ndarray, fin: float = 0.0003, fout: float = 0.03) -> np.ndarray:
    y = np.array(x, dtype=np.float64, copy=True)
    ni, no = min(n_of(fin), len(y)), min(n_of(fout), len(y))
    if ni:
        y[:ni] *= _bc(ramp(ni), y)
    if no:
        y[-no:] *= _bc(ramp(no)[::-1], y)
    return y


def fit(x: np.ndarray, n: int) -> np.ndarray:
    """Truncate or zero-pad along time to exactly n samples."""
    if len(x) >= n:
        return x[:n]
    pad = [(0, n - len(x))] + [(0, 0)] * (x.ndim - 1)
    return np.pad(x, pad)


def normpk(x: np.ndarray) -> np.ndarray:
    p = float(np.max(np.abs(x))) if len(x) else 0.0
    return x / p if p > 0 else x


def pan_st(x: np.ndarray, pan: float = 0.0) -> np.ndarray:
    """Mono -> stereo, constant power, centre == dual mono at unity."""
    if x.ndim == 2:
        return x
    a = (np.clip(pan, -1, 1) + 1.0) * math.pi / 4.0
    return np.stack([x * math.cos(a), x * math.sin(a)], axis=1) * math.sqrt(2.0)


def mix(parts, dur: float | None = None, stereo: bool | None = None) -> np.ndarray:
    """parts: iterable of (signal, start_sec, gain[, pan])."""
    parts = list(parts)
    if stereo is None:
        stereo = any(p[0].ndim == 2 or (len(p) > 3 and p[3]) for p in parts)
    end = max(n_of(p[1]) + len(p[0]) for p in parts)
    n = n_of(dur) if dur else end
    out = np.zeros((n, 2) if stereo else n)
    for p in parts:
        s, at, g = p[0], p[1], p[2]
        if stereo:
            s = pan_st(s, p[3] if len(p) > 3 else 0.0)
        i = n_of(at)
        j = min(n, i + len(s))
        if j > i:
            out[i:j] += g * s[: j - i]
    return out


def _sos(kind: str, f, order: int):
    if np.ndim(f):
        f = [min(max(v, 5.0), 0.45 * SR) for v in f]
    else:
        f = min(max(f, 5.0), 0.45 * SR)
    return signal.butter(order, f, btype=kind, fs=SR, output="sos")


def lp(x, f, order=2):
    return signal.sosfilt(_sos("lowpass", f, order), x, axis=0)


def hp(x, f, order=2):
    return signal.sosfilt(_sos("highpass", f, order), x, axis=0)


def bp(x, lo, hi, order=2):
    return signal.sosfilt(_sos("bandpass", [lo, hi], order), x, axis=0)


def hann_pulse(width: float) -> np.ndarray:
    """Unit-area raised-cosine force pulse (contact of duration `width`)."""
    n = max(3, n_of(width))
    p = np.sin(np.pi * (np.arange(n) + 0.5) / n) ** 2
    return p / p.sum()


def modal_ir(freqs, t60s, amps, dur: float, phases=None) -> np.ndarray:
    """Impulse response of a bank of exponentially decaying sinusoidal modes."""
    n = n_of(dur)
    t = t_of(n)
    out = np.zeros(n)
    for k, (f, T, a) in enumerate(zip(freqs, t60s, amps)):
        if f <= 0 or f >= 0.46 * SR or a == 0:
            continue
        m = min(n, n_of(1.7 * T) + 1)
        ph = 0.0 if phases is None else phases[k]
        out[:m] += a * np.exp(-LN1000 * t[:m] / T) * np.sin(2 * np.pi * f * t[:m] + ph)
    return out


def conv(a: np.ndarray, b: np.ndarray) -> np.ndarray:
    return signal.fftconvolve(a, b)


def burst(rng, dur: float, attack: float, decay: float, lo: float, hi: float) -> np.ndarray:
    """Band-limited noise burst with exponential decay (decay = T60)."""
    n = n_of(dur)
    t = t_of(n)
    e = np.exp(-LN1000 * t / decay)
    na = n_of(attack)
    if na:
        e[:na] *= ramp(na)
    return normpk(bp(rng.standard_normal(n), lo, hi, 2) * e)


def swept_noise(rng, dur: float, f0: float, f1: float, bw_oct: float = 0.9) -> np.ndarray:
    """Noise with a gaussian (log-frequency) band sweeping f0 -> f1."""
    n = n_of(dur)
    x = rng.standard_normal(n + 1024)
    f, t, Z = signal.stft(x, SR, nperseg=512, noverlap=384)
    frac = np.clip(t / dur, 0.0, 1.0)
    fc = np.log2(f0) + (np.log2(f1) - np.log2(f0)) * frac
    lf = np.log2(np.maximum(f, 20.0))
    W = np.exp(-0.5 * ((lf[:, None] - fc[None, :]) / (bw_oct / 2.0)) ** 2)
    _, y = signal.istft(Z * W, SR, nperseg=512, noverlap=384)
    return normpk(fit(y, n))


# ---------------------------------------------------------------------------
# Physical-ish impact model
# ---------------------------------------------------------------------------

def wood_impact(rng, *, base: float, ratios, eta: float, contact: float,
                pulses=((0.0, 1.0),), piece_gain=1.0, piece_tilt=0.5,
                board_base=180.0, board_gain=0.5, board_t60=0.12, board_modes=9,
                thump_hz=110.0, thump_gain=0.5, thump_t60=0.06,
                grain_gain=0.0, grain_lo=2500.0, felt_gain=0.0,
                strike=None, dur=0.3) -> np.ndarray:
    """One object striking a wooden board.

    Contact pulses (hann, unit area -> equal momentum; wider = softer/felt)
    excite (a) the struck object's inharmonic modes (T60 from a loss factor
    eta: T60 = 2.2/(eta*f)), (b) a denser set of lower board/plate modes and
    (c) a low body 'thump' driven by a broader pulse.  Optional wood-grain
    crackle and felt 'puff' noise add surface realism.
    """
    n = n_of(dur)
    span = max(dt for dt, _ in pulses)
    exc = np.zeros(n_of(span + contact * 1.3) + 8)
    th_exc = np.zeros(n_of(span + contact * 3 + 0.004) + 8)
    for dt, g in pulses:
        p = hann_pulse(contact * rng.uniform(0.9, 1.1)) * g
        i = n_of(dt)
        exc[i:i + len(p)] += p
        q = hann_pulse(contact * 3 + 0.0022) * g
        th_exc[i:i + len(q)] += q
    r = np.asarray(ratios, float) * rng.uniform(0.97, 1.03, len(ratios))
    r[0] = 1.0
    f = base * r
    t60 = np.clip(2.2 / (eta * f), 0.008, 0.3)
    sp = rng.uniform(0.12, 0.42) if strike is None else strike
    w = 0.35 + 0.65 * np.abs(np.sin(np.pi * (np.arange(len(r)) + 1) * sp))
    a = w * r ** -piece_tilt * rng.uniform(0.8, 1.2, len(r))
    y = piece_gain * normpk(fit(conv(exc, modal_ir(f, t60, a, dur)), n))
    if board_gain:
        nb = board_modes
        bf = board_base * np.cumprod(np.r_[1.0, rng.uniform(1.16, 1.40, nb - 1)])
        bt = board_t60 * (bf[0] / bf) ** 0.45 * rng.uniform(0.85, 1.15, nb)
        ba = (bf[0] / bf) ** 0.7 * rng.uniform(0.5, 1.0, nb)
        y += board_gain * normpk(fit(conv(exc, modal_ir(bf, bt, ba, dur)), n))
    if thump_gain:
        th = modal_ir([thump_hz, thump_hz * rng.uniform(1.8, 2.1)],
                      [thump_t60, thump_t60 * 0.6], [1.0, 0.35], dur)
        y += thump_gain * normpk(fit(conv(th_exc, th), n))
    for dt, g in pulses:
        if grain_gain:
            gr = burst(rng, 0.012, 0.0001, 0.004, grain_lo, 12000.0)
            y += mix([(gr, dt, grain_gain * g)], dur=dur)
        if felt_gain:
            fe = burst(rng, 0.03, 0.0008, 0.018, 250.0, 1800.0)
            y += mix([(fe, dt, felt_gain * g)], dur=dur)
    return y


# ---------------------------------------------------------------------------
# Tonal instruments
# ---------------------------------------------------------------------------

# (ratio, amplitude, T60 scale) -- struck bars / bells
CELESTA = [(1.0, 1.0, 1.0), (2.0, 0.05, 0.5), (2.756, 0.20, 0.30),
           (5.404, 0.08, 0.12), (8.933, 0.035, 0.06)]
LOW_BELL = [(0.5, 0.45, 1.5), (1.0, 0.55, 1.0), (1.183, 0.42, 0.8),
            (1.506, 0.16, 0.55), (2.0, 0.60, 0.55), (2.514, 0.10, 0.32),
            (2.662, 0.08, 0.3), (3.011, 0.10, 0.22), (4.166, 0.05, 0.14),
            (5.433, 0.03, 0.1)]
MARIMBA = [(1.0, 1.0, 1.0), (3.93, 0.26, 0.28), (9.24, 0.06, 0.1)]
VIBES = [(1.0, 1.0, 1.0), (3.98, 0.22, 0.4), (9.8, 0.05, 0.14)]
HANDBELL = [(1.0, 1.0, 1.0), (2.42, 0.10, 0.4), (3.0, 0.42, 0.6),
            (4.53, 0.08, 0.3), (5.08, 0.10, 0.25), (6.72, 0.04, 0.15)]


def mallet(f: float, dur: float, partials, *, t60: float, vel: float = 0.7,
           bright: float = 4000.0, attack: float = 0.0015, doublet: float = 0.0006,
           click: float = 0.0, trem: tuple | None = None, rng=None) -> np.ndarray:
    """Additive struck-bar/bell tone.  Mallet hardness is a gaussian low-pass
    on the partial amplitudes; `doublet` adds a slightly detuned twin for each
    partial (natural beating/shimmer of real bars and bells)."""
    rng = rng if rng is not None else np.random.default_rng(int(f * 1000) & 0xFFFF)
    n = n_of(dur)
    t = t_of(n)
    y = np.zeros(n)
    B = bright * (0.45 + vel)
    for r, a, ts in partials:
        fr = f * r
        if fr > 0.44 * SR:
            continue
        amp = a * math.exp(-((fr / B) ** 2))
        env = np.exp(-LN1000 * t / max(0.02, t60 * ts))
        y += amp * env * np.sin(2 * np.pi * fr * t)
        if doublet:
            d = doublet * rng.uniform(0.6, 1.4)
            y += 0.35 * amp * env * np.sin(2 * np.pi * fr * (1 + d) * t + rng.uniform(0, 6.28))
    if trem:
        rate, depth = trem
        y *= 1.0 - depth * (0.5 - 0.5 * np.cos(2 * np.pi * rate * t))
    na = n_of(attack)
    y[:na] *= ramp(na)
    nf = min(n // 3, n_of(float(np.clip(dur * 0.1, 0.02, 0.15))))
    y[n - nf:] *= ramp(nf)[::-1]
    if click:
        y += click * mix([(burst(rng, 0.01, 0.0002, 0.004, 2500, 9000), 0, 1.0)], dur=dur)
    return y * vel


def celesta(m: float, dur: float, vel=0.6, rng=None, bright=4200.0) -> np.ndarray:
    f = midi_hz(m)
    t60 = float(np.clip(1.9 * (880.0 / f) ** 0.6, 0.6, 4.5))
    return mallet(f, dur, CELESTA, t60=t60, vel=vel, bright=bright, attack=0.0012,
                  click=0.015, rng=rng)


def low_bell(m: float, dur: float, vel=0.6, rng=None, bright=1600.0, t60=2.4) -> np.ndarray:
    """Church-bell partial set (hum, prime, minor tierce, quint, nominal...);
    `m` is the prime.  Soft felt mallet -> dark, round."""
    return mallet(midi_hz(m), dur, LOW_BELL, t60=t60, vel=vel, bright=bright,
                  attack=0.004, doublet=0.0009, rng=rng)


def felt_piano(m: float, dur: float, vel: float, rng, release: float = 0.6) -> np.ndarray:
    """Soft 'felt piano': stiff-string partials (inharmonicity B), two slightly
    detuned strings per note (beating), two-stage decay, steep felt-hammer
    spectral tilt, soft 4-6 ms attack, low hammer thump; damper at note-off."""
    f = midi_hz(m)
    total = dur + release * 2.2
    n = n_of(total)
    t = t_of(n)
    y = np.zeros(n)
    Bi = 1.4e-4 * (f / 261.6) ** 0.6
    T1 = float(np.clip(9.0 * (261.6 / f) ** 0.55, 1.5, 16.0))
    tilt = 1.7 - 0.8 * vel
    lpf = 1400.0 + 2600.0 * vel
    for k in range(1, 24):
        fk = k * f * math.sqrt(1.0 + Bi * k * k)
        if fk > 9000:
            break
        a = k ** -tilt * (0.3 + abs(math.sin(math.pi * k * 0.13))) * math.exp(-((fk / lpf) ** 2) * 0.7)
        Tk = T1 / (1.0 + 0.33 * (k - 1))
        env = 0.65 * np.exp(-LN1000 * t / (0.28 * Tk)) + 0.35 * np.exp(-LN1000 * t / (1.2 * Tk))
        det = 1.0 + rng.uniform(2.5e-4, 8e-4)
        ph = rng.uniform(0, 2 * np.pi)
        y += a * env * (np.sin(2 * np.pi * fk * t) + 0.85 * np.sin(2 * np.pi * fk * det * t + ph))
    na = n_of(0.006 - 0.003 * vel)
    y[:na] *= ramp(na)
    thump = mix([(burst(rng, 0.05, 0.001, 0.03, 60, 500), 0, 1.0)], dur=total)
    y = normpk(y)
    y = y * (0.35 / kw_rms(y)) + 0.06 * thump     # equal loudness across the keyboard
    off = n_of(dur)
    if off < n:
        y[off:] *= np.exp(-LN1000 * t[: n - off] / release)
    return y * vel ** 1.2


def pad_voice(f: float, dur: float, rng, *, attack=2.5, release=3.5, harm=7,
              cents=(-6.0, 0.0, 6.0), bright=(1.2, 2.6), period=(9.0, 16.0)) -> np.ndarray:
    """Warm additive pad voice (stereo).  Three detuned oscillators panned
    L/C/R; the brightness (harmonic roll-off) breathes on a slow random LFO."""
    total = dur + release
    n = n_of(total)
    t = t_of(n)
    P = rng.uniform(*period)
    b = bright[0] + (bright[1] - bright[0]) * (0.5 + 0.5 * np.sin(2 * np.pi * t / P + rng.uniform(0, 6.28)))
    out = np.zeros((n, 2))
    pans = np.linspace(-0.7, 0.7, len(cents))
    for c, pan in zip(cents, pans):
        fd = f * 2 ** ((c + rng.uniform(-1.5, 1.5)) / 1200.0)
        acc = np.zeros(n)
        for h in range(1, harm + 1):
            if fd * h > 6000:
                break
            amp = h ** -1.0 * np.exp(-(h - 1) / b)
            acc += amp * np.sin(2 * np.pi * fd * h * t + rng.uniform(0, 2 * np.pi))
        out += pan_st(acc, pan) / len(cents)
    env = np.ones(n)
    na, nd = n_of(attack), n_of(dur)
    env[:na] = ramp(na)
    nr = n - nd
    if nr > 0:
        env[nd:] *= ramp(nr)[::-1] ** 1.5
    return out * env[:, None]


# ---------------------------------------------------------------------------
# Rooms
# ---------------------------------------------------------------------------

def room_ir(name: str, rt60: float, *, hf_ratio=0.5, dur=None, stereo=False,
            lp_hz=8000.0, hp_hz=150.0, predelay=0.003, early=6, xover=1800.0,
            er_gain=0.5) -> np.ndarray:
    """Synthetic room: sparse early reflections + exponentially decaying
    two-band noise tail (highs decay faster), energy-normalised."""
    rng = rng_for("room:" + name)
    dur = dur or rt60 * 1.25
    n = n_of(dur)
    t = t_of(n)
    ch = 2 if stereo else 1
    nz = rng.standard_normal((n, ch))
    lo = lp(nz, xover, 4)
    hi = nz - lo
    late = lo * np.exp(-LN1000 * t / rt60)[:, None] + hi * np.exp(-LN1000 * t / (rt60 * hf_ratio))[:, None]
    late *= (1.0 - np.exp(-t / 0.01))[:, None]
    ir = late * 0.35
    for c in range(ch):
        for _ in range(early):
            d = rng.uniform(0.002, 0.03)
            g = er_gain * math.exp(-d / 0.03) * rng.choice([-1.0, 1.0]) * rng.uniform(0.5, 1.0)
            i = n_of(d)
            if i < n:
                ir[i, c] += g * 6.0 / math.sqrt(n_of(0.02))
    ir = hp(lp(ir, lp_hz, 2), hp_hz, 2)
    ir = np.concatenate([np.zeros((n_of(predelay), ch)), ir])
    ir /= math.sqrt(float(np.sum(ir ** 2)) / ch)
    return ir if stereo else ir[:, 0]


def reverb(x: np.ndarray, ir: np.ndarray, wet_db: float, dry: float = 1.0) -> np.ndarray:
    """Dry + wet convolution (output grows by len(ir)); mono x with stereo IR
    gives a stereo result."""
    if ir.ndim == 2 and x.ndim == 1:
        x = pan_st(x)
    if ir.ndim == 2:
        wet = np.stack([conv(x[:, c], ir[:, c]) for c in range(2)], axis=1)
    elif x.ndim == 2:
        wet = np.stack([conv(x[:, c], ir) for c in range(2)], axis=1)
    else:
        wet = conv(x, ir)
    return dry * fit(x, len(wet)) + db2lin(wet_db) * wet


# ---------------------------------------------------------------------------
# Loudness / peaks  (ITU-R BS.1770-4 K-weighting, gated integrated loudness)
# ---------------------------------------------------------------------------

def _kweight_sos(fs=SR):
    f0, G, Q = 1681.974450955533, 3.999843853973347, 0.7071752369554196
    K = math.tan(math.pi * f0 / fs)
    Vh, Vb = 10 ** (G / 20.0), 10 ** (G / 20.0) ** 0.4996667741545416
    a0 = 1.0 + K / Q + K * K
    b1 = [(Vh + Vb * K / Q + K * K) / a0, 2 * (K * K - Vh) / a0, (Vh - Vb * K / Q + K * K) / a0]
    a1 = [1.0, 2 * (K * K - 1) / a0, (1 - K / Q + K * K) / a0]
    f0, Q = 38.13547087602444, 0.5003270373238773
    K = math.tan(math.pi * f0 / fs)
    a0 = 1.0 + K / Q + K * K
    a2 = [1.0, 2 * (K * K - 1) / a0, (1 - K / Q + K * K) / a0]
    return np.array([b1 + a1, [1.0, -2.0, 1.0] + a2])


KSOS = _kweight_sos()


def loudness(x: np.ndarray) -> tuple[float, float]:
    """(integrated LUFS, max momentary LUFS).  Mono is measured as dual-mono
    (how Godot plays a mono stream on a stereo bus)."""
    y = x if x.ndim == 2 else np.stack([x, x], axis=1)
    k = signal.sosfilt(KSOS, y, axis=0)
    blk, hop = n_of(0.4), n_of(0.1)
    if len(k) < blk:
        k = np.pad(k, ((0, blk - len(k)), (0, 0)))
    cs = np.concatenate([np.zeros((1, k.shape[1])), np.cumsum(k * k, axis=0)])
    st = np.arange(0, len(k) - blk + 1, hop)
    z = ((cs[st + blk] - cs[st]) / blk).sum(axis=1)
    lk = -0.691 + 10 * np.log10(np.maximum(z, 1e-20))
    g = lk > -70.0
    if not g.any():
        return -math.inf, float(lk.max())
    rel = -0.691 + 10 * math.log10(z[g].mean()) - 10.0
    g2 = g & (lk > rel)
    return -0.691 + 10 * math.log10(z[g2].mean()), float(lk.max())


def kw_rms(x: np.ndarray, sec: float = 0.4) -> float:
    """K-weighted RMS of the first `sec` seconds (note-level loudness match)."""
    k = signal.sosfilt(KSOS, x[: n_of(sec)], axis=0)
    return float(np.sqrt(np.mean(k ** 2))) + 1e-12


def true_peak(x: np.ndarray) -> float:
    up = signal.resample_poly(x, 4, 1, axis=0)
    return max(float(np.max(np.abs(up))), float(np.max(np.abs(x))))


PREROLL = 0.004   # s of digital silence before the attack: keeps Vorbis pre-echo
POSTROLL = 0.012  # off sample 0; post-roll guards the tail against decoder trim


def prep_sfx(x: np.ndarray, fout: float = 0.03, fin: float = 0.0002,
             trim_db: float = -70.0) -> np.ndarray:
    """DC/subsonic high-pass, trim silent tail, raised-cosine edge fades."""
    x = hp(x, 20.0, 2)
    env = np.max(np.abs(x), axis=1) if x.ndim == 2 else np.abs(x)
    thr = env.max() * db2lin(trim_db)
    idx = np.nonzero(env > thr)[0]
    if len(idx):
        x = x[: min(len(x), idx[-1] + n_of(0.01))]
    return fade(x, fin, min(fout, len(x) / SR * 0.5))


def pad_edges(x: np.ndarray) -> np.ndarray:
    pre = np.zeros((n_of(PREROLL),) + x.shape[1:])
    post = np.zeros((n_of(POSTROLL),) + x.shape[1:])
    return np.concatenate([pre, x, post])


# =============================================================================
# Encoding / decoding
# =============================================================================

def encode_ogg(x: np.ndarray, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as td:
        wav = Path(td) / "in.wav"
        wavfile.write(wav, SR, np.ascontiguousarray(x, dtype=np.float32))
        tmp = Path(td) / "out.ogg"
        subprocess.run([FFMPEG, "-hide_banner", "-loglevel", "error", "-y", "-i", str(wav),
                        "-map_metadata", "-1", "-c:a", "libvorbis", "-q:a", "5",
                        "-ar", str(SR), "-fflags", "+bitexact", "-flags:a", "+bitexact",
                        str(tmp)], check=True)
        shutil.move(str(tmp), str(path))


def ogg_length(path: Path) -> int:
    """Stream length in samples = granule position of the last Ogg page (what
    Godot's libvorbis-based player uses)."""
    b = path.read_bytes()
    j = b.rfind(b"OggS")
    return int.from_bytes(b[j + 6:j + 14], "little", signed=True)


def decode_ogg(path: Path) -> np.ndarray:
    """Decode with ffmpeg and fit to the granule length.  (ffmpeg's decoders
    drop the final 128 samples of single-page files; our SFX end in >= 12 ms
    of digital silence, so zero-filling them is exact to within codec noise.)"""
    with tempfile.TemporaryDirectory() as td:
        wav = Path(td) / "dec.wav"
        subprocess.run([FFMPEG, "-hide_banner", "-loglevel", "error", "-y", "-i", str(path),
                        "-c:a", "pcm_f32le", str(wav)], check=True)
        _, x = wavfile.read(wav)
    return fit(x.astype(np.float64), ogg_length(path))


def write_checked(x: np.ndarray, path: Path) -> np.ndarray:
    """Encode; if the decoded Vorbis overshoots the true-peak ceiling, scale
    down and re-encode."""
    for _ in range(4):
        encode_ogg(x, path)
        d = decode_ogg(path)
        tp = lin2db(true_peak(d))
        if tp <= TP_CEILING - 0.05:
            return d
        x = x * db2lin(TP_CEILING - 0.3 - tp)
    return d


# =============================================================================
# Circular (loop-safe) rendering helpers for music
# =============================================================================

class LoopBuffer:
    """Stereo accumulation buffer for a loop of exactly `length` samples.
    Anything placed past the loop end (note tails, events at negative times)
    wraps around modulo the loop length -- exactly what continuous looped
    playback would produce -- so the loop point is seamless by construction."""

    def __init__(self, seconds: float, tail: float = 16.0):
        self.L = n_of(seconds)
        self.buf = np.zeros((self.L + n_of(tail), 2))

    def add(self, sig: np.ndarray, at: float, gain: float = 1.0, pan: float = 0.0):
        s = pan_st(sig, pan) * gain
        i = n_of(at) % self.L
        j = min(len(self.buf), i + len(s))
        self.buf[i:j] += s[: j - i]

    def folded(self) -> np.ndarray:
        y = self.buf[: self.L].copy()
        rest = self.buf[self.L:]
        k = 0
        while k < len(rest):
            seg = rest[k:k + self.L]
            y[: len(seg)] += seg
            k += self.L
        return y


def circ_convolve(x: np.ndarray, ir: np.ndarray) -> np.ndarray:
    """Circular convolution over the loop length (reverb tail wraps into head)."""
    L = len(x)
    H = np.fft.rfft(ir, n=L, axis=0)
    X = np.fft.rfft(x, axis=0)
    return np.fft.irfft(X * (H if H.ndim == 2 else H[:, None]), n=L, axis=0)


def circ_highpass(x: np.ndarray, fc: float = 22.0) -> np.ndarray:
    X = np.fft.rfft(x, axis=0)
    f = np.fft.rfftfreq(len(x), 1 / SR)
    g = 1.0 / np.sqrt(1.0 + (fc / np.maximum(f, 1e-3)) ** 8)
    g[0] = 0.0
    return np.fft.irfft(X * g[:, None], n=len(x), axis=0)


def periodic_noise(rng, n: int, lo: float, hi: float, tilt: float = 0.0) -> np.ndarray:
    """Band-limited noise that is exactly periodic over n samples."""
    X = np.fft.rfft(rng.standard_normal(n))
    f = np.fft.rfftfreq(n, 1 / SR)
    g = 1.0 / np.sqrt(1 + (lo / np.maximum(f, 1e-3)) ** 4) / np.sqrt(1 + (f / hi) ** 4)
    g *= (np.maximum(f, 1.0) / 1000.0) ** tilt
    return normpk(np.fft.irfft(X * g, n=n))


def at_lufs(x: np.ndarray, target: float) -> np.ndarray:
    """Scale a (long) bus to an integrated loudness -- used for mix balance."""
    return x * db2lin(target - loudness(x)[0])


def finalize_music(y: np.ndarray, lufs: float = MUSIC_LUFS) -> np.ndarray:
    y = circ_highpass(y - y.mean(axis=0))
    li, _ = loudness(y)
    y = y * db2lin(lufs - li)
    tp = lin2db(true_peak(y))
    if tp > TP_CEILING - 1.0:        # keep headroom for the codec
        y = y * db2lin(TP_CEILING - 1.0 - tp)
    return y


# =============================================================================
# Shadow Chess 3D sound design ("private salon": walnut board, felt-bottomed
# boxwood pieces, dark velvet room, celesta / low bell / felt piano palette)
# =============================================================================

PIECE_RATIOS = [1.0, 1.52, 2.11, 2.63, 3.34, 4.07, 4.95]


def salon_room(rt60=0.42, stereo=False):
    return room_ir(f"salon{rt60}{stereo}", rt60, hf_ratio=0.45, stereo=stereo,
                   lp_hz=6500, hp_hz=140, predelay=0.004)


def chess_piece(rng, *, size=1.0, force=1.0, felt=1.0, rock=None, dur=0.30) -> np.ndarray:
    """A felt-bottomed boxwood Staunton piece set down on a walnut board.
    size > 1 -> bigger piece (lower modes, more body); felt softens contact."""
    contact = (0.00030 + 0.00025 * felt) / force ** 0.35
    pulses = [(0.0, 1.0)]
    if rock:
        pulses.append(rock)
    return wood_impact(
        rng, base=rng.uniform(1050, 1250) / size, ratios=PIECE_RATIOS,
        eta=rng.uniform(0.020, 0.027), contact=contact, pulses=pulses,
        piece_gain=1.0, piece_tilt=0.55,
        board_base=rng.uniform(150, 180) / size ** 0.3, board_gain=0.5 * force ** 0.5,
        board_t60=rng.uniform(0.10, 0.14),
        thump_hz=rng.uniform(98, 124) / size ** 0.5, thump_gain=0.5 * force,
        thump_t60=rng.uniform(0.05, 0.07),
        grain_gain=0.05 * (1.25 - 0.8 * felt), felt_gain=0.07 * felt, dur=dur)


def piece_clack(rng, dur=0.2) -> np.ndarray:
    """Piece knocking piece: hard wood-on-wood contact, no board, bright."""
    a = wood_impact(rng, base=rng.uniform(950, 1100), ratios=PIECE_RATIOS, eta=0.03,
                    contact=0.00014, board_gain=0, thump_gain=0, grain_gain=0.12, dur=dur)
    b = wood_impact(rng, base=rng.uniform(1150, 1350), ratios=PIECE_RATIOS, eta=0.03,
                    contact=0.00014, board_gain=0, thump_gain=0, dur=dur)
    return a + 0.7 * b


def sfx_move(i: int):
    def render(rng):
        rock = None
        if i in (2, 4):  # piece rocks once onto its base
            rock = (rng.uniform(0.009, 0.016), rng.uniform(0.18, 0.28))
        y = chess_piece(rng, size=[1.0, 0.94, 1.07, 1.0][i - 1], force=rng.uniform(0.92, 1.05),
                        felt=rng.uniform(0.85, 1.0), rock=rock, dur=0.30)
        return reverb(y, salon_room(), -15.0)
    return render


def sfx_capture(i: int):
    def render(rng):
        # heavy knock of the capturing piece, then the displaced piece clacks
        knock = chess_piece(rng, size=rng.uniform(1.04, 1.12), force=1.35, felt=0.7,
                            rock=(rng.uniform(0.011, 0.02), 0.22) if i == 2 else None, dur=0.32)
        clack = piece_clack(rng)
        y = mix([(knock, 0.0, 1.0), (clack, rng.uniform(0.016, 0.026), rng.uniform(0.34, 0.42))])
        return reverb(y, salon_room(), -14.0)
    return render


def sfx_castle(rng):
    king = chess_piece(rng, size=1.18, force=1.05, dur=0.3)
    rook = chess_piece(rng, size=0.96, force=0.9, dur=0.3,
                       rock=(0.012, 0.2))
    y = mix([(king, 0.0, 1.0), (rook, 0.155, 0.85)])
    return reverb(y, salon_room(), -15.0)


def sfx_check(rng):
    place = chess_piece(rng, force=1.05, dur=0.3)
    chime = mix([(celesta(81, 1.5, 0.55, rng), 0.0, 1.0, -0.15),
                 (celesta(86, 1.5, 0.45, rng), 0.022, 0.8, 0.15)])
    y = mix([(pan_st(place), 0.0, 1.0), (chime, 0.05, 0.18)])
    return reverb(y, salon_room(0.9, True), -12.0)


def sfx_checkmate(rng):
    place = chess_piece(rng, size=1.12, force=1.45, felt=0.8, dur=0.35)
    bell = low_bell(50, 2.6, 0.75, rng, bright=1500, t60=2.3)       # prime D3
    chord = mix([(celesta(m, 2.4, v, rng, bright=3000), 0.03 * k, 1.0, p)
                 for k, (m, v, p) in enumerate([(57, 0.4, -0.3), (62, 0.42, 0.0),
                                                (65, 0.38, 0.25), (69, 0.3, 0.4)])])
    y = mix([(pan_st(place), 0.0, 1.0), (pan_st(bell), 0.05, 0.6), (chord, 0.07, 0.32)])
    return reverb(y, room_ir("mate", 1.7, hf_ratio=0.4, stereo=True, lp_hz=5500), -10.0)


def sfx_draw(rng):
    a = mix([(celesta(62, 1.2, 0.35, rng, 3000), 0.0, 1.0, -0.2),
             (celesta(67, 1.2, 0.32, rng, 3000), 0.012, 1.0, 0.2)])
    b = mix([(celesta(50, 1.8, 0.3, rng, 2500), 0.0, 0.8, -0.3),
             (celesta(62, 1.8, 0.35, rng, 3000), 0.01, 1.0, -0.1),
             (celesta(69, 1.8, 0.32, rng, 3000), 0.022, 1.0, 0.25)])
    y = mix([(a, 0.0, 0.8), (b, 0.34, 1.0)])
    return reverb(y, room_ir("draw", 1.3, hf_ratio=0.4, stereo=True, lp_hz=6000), -10.0)


def glass_grains(rng, count: int, t0: float, t1: float, dur: float, lo=3000.0, hi=7500.0) -> np.ndarray:
    parts = []
    for _ in range(count):
        f = math.exp(rng.uniform(math.log(lo), math.log(hi)))
        g = modal_ir([f, f * 1.0013], [rng.uniform(0.12, 0.4), 0.3], [1.0, 0.4], 0.6)
        g[: n_of(0.001)] *= ramp(n_of(0.001))
        parts.append((g, rng.uniform(t0, t1), rng.uniform(0.3, 1.0), rng.uniform(-0.8, 0.8)))
    return mix(parts, dur=dur, stereo=True)


def sfx_promote(rng):
    notes = [(81, 0.30), (83, 0.33), (86, 0.36), (88, 0.40), (93, 0.36)]
    arp = mix([(celesta(m, 1.4, v, rng, 5200), 0.036 * k, 1.0, -0.5 + 0.25 * k)
               for k, (m, v) in enumerate(notes)] +
              [(celesta(74, 1.6, 0.3, rng, 3000), 0.0, 0.8, 0.0)])
    y = mix([(arp, 0.0, 1.0), (glass_grains(rng, 16, 0.03, 0.5, 1.6), 0.0, 0.1)])
    return reverb(y, room_ir("promote", 1.2, hf_ratio=0.5, stereo=True, lp_hz=8000), -10.0)


def sfx_illegal(rng):
    def thud(r, size):
        return lp(wood_impact(r, base=420 / size, ratios=PIECE_RATIOS, eta=0.05, contact=0.0016,
                              piece_gain=0.35, board_base=140 / size, board_gain=0.8, board_t60=0.09,
                              thump_hz=102 / size, thump_gain=1.0, thump_t60=0.07,
                              felt_gain=0.15, dur=0.25), 900, 2)
    y = mix([(thud(rng, 1.0), 0.0, 1.0), (thud(rng, 1.06), 0.085, 0.42)])
    return reverb(y, salon_room(), -17.0)


def sfx_select(rng):
    tap = wood_impact(rng, base=1500, ratios=PIECE_RATIOS, eta=0.035, contact=0.00022,
                      board_gain=0.15, board_base=300, thump_gain=0.05, thump_hz=180,
                      grain_gain=0.05, dur=0.09)
    scuff = burst(rng, 0.04, 0.004, 0.025, 900, 4000)
    y = mix([(scuff, 0.0, 0.18), (tap, 0.006, 1.0)])
    return reverb(y, salon_room(0.3), -20.0)


def ui_tick(rng, modes, t60s, amps, body_hz=210.0, body=0.45, contact=0.00012, dur=0.08):
    hi = normpk(fit(conv(hann_pulse(contact), modal_ir(modes, t60s, amps, dur)), n_of(dur)))
    lo = normpk(fit(conv(hann_pulse(0.0007), modal_ir([body_hz], [0.025], [1.0], dur)), n_of(dur)))
    return hi + body * lo


def sfx_ui_click(rng):
    y = ui_tick(rng, [1650, 2890, 4120, 5600], [0.018, 0.012, 0.009, 0.006], [1.0, 0.6, 0.35, 0.18])
    return reverb(y, salon_room(0.3), -20.0)


def sfx_ui_hover(rng):
    y = ui_tick(rng, [2300, 4100], [0.007, 0.004], [1.0, 0.3], body_hz=260, body=0.2,
                contact=0.0002, dur=0.03)
    return lp(y, 5000, 2)


def sfx_ui_open(rng):
    air = swept_noise(rng, 0.16, 650, 2400, 0.9)
    air *= np.sin(np.linspace(0, np.pi, len(air))) ** 1.5
    tick = ui_tick(rng, [1900, 3050], [0.016, 0.01], [1.0, 0.4], body_hz=240, body=0.35)
    y = mix([(air, 0.0, 0.5), (tick, 0.125, 0.8)])
    return reverb(y, salon_room(0.3), -18.0)


def sfx_ui_close(rng):
    air = swept_noise(rng, 0.15, 2300, 600, 0.9)
    air *= np.sin(np.linspace(0, np.pi, len(air))) ** 1.5
    tick = ui_tick(rng, [1500, 2600], [0.016, 0.01], [1.0, 0.4], body_hz=200, body=0.45)
    y = mix([(tick, 0.0, 0.8), (air, 0.01, 0.45)])
    return reverb(y, salon_room(0.3), -18.0)


def sfx_game_start(rng):
    bell = low_bell(62, 2.0, 0.6, rng, bright=1700, t60=1.5)       # prime D4
    under = celesta(50, 2.0, 0.3, rng, 2000)                        # D3 body
    fifth = celesta(69, 1.6, 0.18, rng, 3000)
    y = mix([(bell, 0.0, 1.0, 0.0), (under, 0.0, 0.6, -0.2), (fifth, 0.02, 0.5, 0.25)])
    return reverb(y, room_ir("start", 1.5, hf_ratio=0.4, stereo=True, lp_hz=5500), -10.0)


def sfx_clock_tick(rng):
    metal = fit(conv(hann_pulse(0.00008), modal_ir([3150, 4700, 6900, 8800], [0.02, 0.014, 0.01, 0.006],
                                                   [1.0, 0.7, 0.4, 0.2], 0.1)), n_of(0.1))
    case = fit(conv(hann_pulse(0.0003), modal_ir([780, 1240, 1900, 180], [0.03, 0.025, 0.02, 0.03],
                                                 [0.6, 0.4, 0.3, 0.5], 0.1)), n_of(0.1))
    y = 0.55 * normpk(metal) + normpk(case)
    return reverb(y, salon_room(0.3), -20.0)


def sfx_clock_warning(rng):
    def ping(v):
        f = midi_hz(81)
        return mallet(f, 0.6, CELESTA, t60=0.45, vel=v, bright=3500, attack=0.001, click=0.01, rng=rng)
    tick = sfx_clock_tick(rng)
    y = mix([(ping(0.6), 0.0, 1.0), (ping(0.5), 0.17, 0.85), (tick, 0.0, 0.25)])
    return reverb(y, salon_room(0.6), -15.0)


def sfx_hint(rng):
    y = mix([(celesta(81, 1.3, 0.35, rng, 3800), 0.0, 1.0, -0.25),
             (celesta(88, 1.3, 0.32, rng, 3800), 0.085, 0.9, 0.25),
             (glass_grains(rng, 6, 0.08, 0.35, 1.3, 4000, 8000), 0.0, 0.08)])
    return reverb(y, room_ir("hint", 1.2, hf_ratio=0.5, stereo=True, lp_hz=8000), -11.0)


def sfx_puzzle_solved(rng):
    notes = [(74, 0.40, -0.3), (81, 0.38, -0.1), (83, 0.36, 0.1), (88, 0.42, 0.3)]
    y = mix([(celesta(m, 1.8 - 0.1 * k, v, rng, 4000), 0.095 * k, 1.0, p) for k, (m, v, p) in enumerate(notes)] +
            [(low_bell(62, 1.8, 0.35, rng, 1600, 1.4), 0.285, 0.35, 0.0)])
    return reverb(y, room_ir("solved", 1.3, hf_ratio=0.45, stereo=True, lp_hz=7000), -10.0)


def sfx_puzzle_wrong(rng):
    def wood(m, v):
        return mallet(midi_hz(m), 0.5, MARIMBA, t60=0.28, vel=v, bright=1400, attack=0.003, rng=rng)
    y = mix([(wood(57, 0.6), 0.0, 1.0), (wood(53, 0.5), 0.13, 0.9)])
    return reverb(y, salon_room(0.5), -15.0)


def sfx_victory(rng):
    c1 = [(43, 0.28), (55, 0.30), (59, 0.28), (62, 0.30), (69, 0.26)]            # Gadd9
    c2 = [(38, 0.30), (57, 0.32), (66, 0.34), (71, 0.30), (76, 0.30), (81, 0.24)]  # D6/9
    a = mix([(celesta(m, 1.2, v, rng, 3000), 0.018 * k, 1.0, -0.4 + 0.2 * k) for k, (m, v) in enumerate(c1)])
    b = mix([(celesta(m, 3.0, v, rng, 3600), 0.022 * k, 1.0, -0.5 + 0.2 * k) for k, (m, v) in enumerate(c2)])
    pad = mix([(pad_voice(midi_hz(m), 1.6, rng, attack=0.35, release=1.4, harm=5), 0.0, 1.0)
               for m in (50, 57, 62, 66)])
    bell = low_bell(50, 3.0, 0.5, rng, bright=1500, t60=2.4)
    y = mix([(a, 0.0, 0.8), (b, 0.52, 1.0), (pad, 0.48, 0.10), (pan_st(bell), 0.53, 0.5)])
    return reverb(y, room_ir("victory", 1.9, hf_ratio=0.45, stereo=True, lp_hz=6000), -9.0)


def sfx_defeat(rng):
    c1 = [(46, 0.35), (53, 0.30), (57, 0.30), (62, 0.30), (69, 0.26)]   # Bbmaj7(9) rolled
    c2 = [(38, 0.33), (57, 0.30), (64, 0.28), (65, 0.30), (74, 0.24)]   # Dm(add9)
    a = mix([(felt_piano(m, 0.9, v, rng, 0.5), 0.03 * k, 1.0, -0.3 + 0.15 * k) for k, (m, v) in enumerate(c1)])
    b = mix([(felt_piano(m, 2.2, v, rng, 0.8), 0.04 * k, 1.0, -0.3 + 0.15 * k) for k, (m, v) in enumerate(c2)])
    pad = mix([(pad_voice(midi_hz(m), 1.8, rng, attack=0.6, release=1.2, harm=4), 0.0, 1.0)
               for m in (50, 57, 65)])
    y = mix([(a, 0.0, 1.0), (b, 0.75, 1.0), (pad, 0.55, 0.12)])
    return reverb(y, room_ir("defeat", 1.9, hf_ratio=0.4, stereo=True, lp_hz=5000), -10.0)


# ---------------------------------------------------------------------------
# Music: "salon" -- D Dorian, slow evolving pad + sparse felt piano + sub.
# 64 BPM, 2 bars per chord, 16 chords = 120.0 s, rendered circularly.
# ---------------------------------------------------------------------------

MUSIC_SECONDS = {"music_salon": 120.0}
SALON_CHORDS = [  # (bass, pad voicing) MIDI
    (38, [53, 57, 60, 64]),   # Dm9
    (38, [55, 59, 62, 69]),   # G(add9)/D
    (38, [53, 57, 62, 64]),   # Dm(add9)
    (40, [55, 59, 62, 64]),   # Cmaj9/E
    (41, [57, 60, 64, 67]),   # Fmaj9
    (40, [55, 57, 62, 64]),   # Em7(11)
    (38, [53, 57, 60, 64]),   # Dm9
    (33, [55, 60, 62, 64]),   # Am7(11)
    (35, [57, 62, 65, 69]),   # Bm7b5
    (43, [59, 62, 64, 69]),   # G6/9
    (41, [57, 59, 60, 64]),   # Fmaj7#11
    (36, [55, 60, 62, 64]),   # Cadd9
    (38, [55, 60, 65, 69]),   # Dm11 (quartal)
    (40, [57, 62, 67, 71]),   # Em7(11) (quartal)
    (41, [55, 57, 60, 64]),   # Fmaj9
    (33, [55, 59, 62, 64]),   # A7sus4(9)  -> back to Dm9
]
SALON_MELODY = [  # per chord: (beat, midi, velocity)
    [(1.0, 69, .50), (3.5, 76, .42), (5.0, 74, .38)],
    [(0.5, 71, .45), (2.5, 74, .35), (4.0, 69, .40)],
    [(0.0, 65, .38), (1.5, 72, .36), (4.5, 76, .44), (6.5, 74, .30)],
    [(1.0, 71, .40), (3.0, 67, .34)],
    [(0.0, 72, .44), (2.0, 76, .40), (3.5, 79, .36), (6.0, 77, .30)],
    [(1.0, 74, .40), (4.0, 71, .34)],
    [(0.0, 69, .44), (2.0, 72, .34), (2.75, 74, .30), (5.0, 65, .30)],
    [(1.0, 76, .40), (4.0, 72, .34)],
    [(0.5, 74, .40), (2.0, 77, .40), (4.5, 81, .34), (6.5, 76, .30)],
    [(1.0, 74, .38), (3.0, 71, .34), (5.5, 69, .30)],
    [(0.0, 71, .40), (2.0, 72, .34), (4.0, 76, .40)],
    [(1.5, 74, .35), (4.0, 67, .30)],
    [(0.0, 81, .34), (1.0, 77, .38), (2.5, 76, .34), (4.5, 74, .40)],
    [(2.0, 71, .35), (5.0, 69, .30)],
    [(0.0, 72, .40), (3.0, 67, .30), (5.5, 69, .32)],
    [(1.0, 76, .38), (4.0, 74, .32), (6.5, 69, .28)],
]


def music_salon(rng):
    beat = 60.0 / 64.0
    slot = 8 * beat                       # 7.5 s per chord
    total = MUSIC_SECONDS["music_salon"]  # 16 chords * 7.5 s = 120 s
    pad_bus, pno_bus = LoopBuffer(total), LoopBuffer(total)
    for i, (bass, voicing) in enumerate(SALON_CHORDS):
        t0 = i * slot
        for m in voicing:
            v = pad_voice(midi_hz(m), slot + 1.2, rng, attack=2.8, release=4.0, harm=7,
                          bright=(1.0, 2.4))
            pad_bus.add(v, t0 - 0.9, 0.09)
        sub = pad_voice(midi_hz(bass), slot + 0.6, rng, attack=2.0, release=3.0, harm=2,
                        cents=(-2.0, 2.0), bright=(0.5, 0.8))
        pad_bus.add(sub, t0 - 0.5, 0.20)
        if i % 4 == 0:  # soft low piano root at each phrase start
            pno_bus.add(felt_piano(bass + 12, 6.0, 0.26, rng, 1.5), t0 + rng.uniform(0.0, 0.03), 1.0, -0.25)
        for bt, m, v in SALON_MELODY[i]:
            at = t0 + bt * beat + rng.uniform(-0.025, 0.025)
            note = felt_piano(m, rng.uniform(2.5, 4.0), v + rng.uniform(-0.04, 0.04), rng, 1.4)
            pno_bus.add(note, at, 1.0, float(np.clip((m - 70) / 20.0, -0.3, 0.3)))
    # bus balance (integrated, gated LUFS): the pad is a steady bed and the
    # sparse piano floats just above it (keeps momentary peaks gentle)
    pad, pno = at_lufs(pad_bus.folded(), -23.5), at_lufs(pno_bus.folded(), -23.0)
    ir = room_ir("salon_music", 3.2, hf_ratio=0.42, dur=5.5, stereo=True, lp_hz=5200,
                 hp_hz=120, predelay=0.022, er_gain=0.25)
    wet = circ_convolve(pad * 0.6 + pno, ir)
    return pad + pno + db2lin(-7.0) * wet


# =============================================================================
# Manifest
# =============================================================================
# name -> (render(rng), target loudness [max momentary LUFS, dual-mono] or None,
#          true-peak ceiling dBFS, max duration s, fade-out s, family or None)
# Families (variants) are loudness-matched to each other and the loudest one is
# set to the ceiling, which anchors the whole set: a plain move peaks at -3 dBFS
# (~ -21 LUFS momentary) and every other cue is balanced against it.
SOUNDS: dict = {}
for _i in range(1, 5):
    SOUNDS[f"move_{_i}"] = (sfx_move(_i), None, -3.0, 0.34, 0.06, "move")
for _i in range(1, 4):
    SOUNDS[f"capture_{_i}"] = (sfx_capture(_i), None, -3.0, 0.36, 0.06, "capture")
SOUNDS.update({
    "castle":        (sfx_castle,        -19.5, -3.0, 0.50, 0.06, None),
    "check":         (sfx_check,         -18.5, -3.0, 1.30, 0.30, None),
    "checkmate":     (sfx_checkmate,     -16.5, -3.0, 2.40, 0.50, None),
    "draw":          (sfx_draw,          -20.0, -4.0, 2.00, 0.40, None),
    "promote":       (sfx_promote,       -21.0, -5.0, 1.50, 0.40, None),
    "illegal":       (sfx_illegal,       -26.0, -8.0, 0.30, 0.05, None),
    "select":        (sfx_select,        -33.0, -14.0, 0.15, 0.03, None),
    "ui_click":      (sfx_ui_click,      -32.0, -12.0, 0.10, 0.02, None),
    "ui_hover":      (sfx_ui_hover,      -42.0, -20.0, 0.05, 0.01, None),
    "ui_open":       (sfx_ui_open,       -31.0, -12.0, 0.25, 0.04, None),
    "ui_close":      (sfx_ui_close,      -32.0, -12.0, 0.22, 0.04, None),
    "game_start":    (sfx_game_start,    -19.0, -5.0, 1.90, 0.40, None),
    "clock_tick":    (sfx_clock_tick,    -29.0, -10.0, 0.12, 0.02, None),
    "clock_warning": (sfx_clock_warning, -22.0, -6.0, 0.75, 0.10, None),
    "hint":          (sfx_hint,          -24.0, -8.0, 1.20, 0.30, None),
    "puzzle_solved": (sfx_puzzle_solved, -18.0, -4.0, 1.90, 0.40, None),
    "puzzle_wrong":  (sfx_puzzle_wrong,  -23.0, -8.0, 0.60, 0.10, None),
    "victory":       (sfx_victory,       -16.0, -3.0, 3.40, 0.60, None),
    "defeat":        (sfx_defeat,        -18.0, -4.0, 3.40, 0.60, None),
})
MUSIC = {"music_salon": music_salon}
PERCUSSIVE = ("move_", "capture_", "castle", "illegal", "select", "ui_click", "ui_close",
              "clock_tick")


def render_all(only: list[str] | None) -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    fams: dict[str, list[str]] = {}
    for name, spec in SOUNDS.items():
        if spec[5]:
            fams.setdefault(spec[5], []).append(name)
    todo = [n for n in list(SOUNDS) + list(MUSIC) if not only or n in only]
    done: set[str] = set()
    for name in todo:
        if name in done:
            continue
        t0 = time.time()
        if name in MUSIC:
            y = finalize_music(MUSIC[name](rng_for(name)))
            write_checked(y, OUT_DIR / f"{name}.ogg")
            done.add(name)
            print(f"  rendered {name:<24} {time.time() - t0:5.1f}s", flush=True)
            continue
        fam = SOUNDS[name][5]
        group = fams[fam] if fam else [name]   # whole family, for loudness matching
        outs = {}
        for g in group:
            fn, lufs, ceil, mdur, fout, _ = SOUNDS[g]
            x = prep_sfx(fit(fn(rng_for(g)), n_of(mdur)), fout)
            if lufs is not None:
                x = x * db2lin(lufs - loudness(x)[1])
                tp = lin2db(true_peak(x))
                if tp > ceil:
                    x = x * db2lin(ceil - tp)
            outs[g] = x
        if fam:  # equal momentary loudness across variants, loudest at the ceiling
            lm = {g: loudness(x)[1] for g, x in outs.items()}
            ref = float(np.mean(list(lm.values())))
            outs = {g: x * db2lin(ref - lm[g]) for g, x in outs.items()}
            k = db2lin(SOUNDS[name][2]) / max(true_peak(x) for x in outs.values())
            outs = {g: x * k for g, x in outs.items()}
        for g, x in outs.items():
            write_checked(pad_edges(x), OUT_DIR / f"{g}.ogg")
            done.add(g)
        print(f"  rendered {', '.join(group):<24} {time.time() - t0:5.1f}s", flush=True)


# =============================================================================
# QC
# =============================================================================

def attack_ms(x: np.ndarray) -> float:
    """Onset (-40 dB re peak) to the first envelope point within 6 dB of the
    overall peak, in ms (so a multi-hit sequence is judged by its first hit)."""
    e = np.max(np.abs(x), axis=1) if x.ndim == 2 else np.abs(x)
    w = n_of(0.0005)
    e = np.convolve(e, np.ones(w) / w, mode="same")
    pk = e.max()
    on = np.nonzero(e > pk * db2lin(-40))[0]
    top = np.nonzero(e > pk * db2lin(-6))[0]
    return (top[0] - on[0]) / SR * 1000.0 if len(on) else 0.0


def seam_metrics(x: np.ndarray) -> tuple[float, float, float]:
    """Loop-point checks on the decoded file (the pre-encode render is exactly
    periodic, so these only catch codec/length problems):
      jump  -- sample step across the seam / 99.9th pct of all sample steps
               (> 1 would be a real discontinuity);
      hf_db -- peak > 9 kHz click residue at the seam, dBFS;
      pct   -- percentile of that residue among all 4 ms windows of the file
               (~50 = indistinguishable from the rest of the music)."""
    d = np.abs(np.diff(x, axis=0)).max(axis=1)
    step = float(np.max(np.abs(x[0] - x[-1])))
    jump = step / (float(np.percentile(d, 99.9)) + 1e-12)
    w = n_of(0.004)
    mid = (len(x) // 2 // w) * w
    r = np.roll(x.mean(axis=1), mid)             # loop point now at `mid`
    h = np.abs(hp(r, 9000.0, 4))
    win = h[: len(h) // w * w].reshape(-1, w).max(axis=1)
    seam = float(h[mid - w // 2: mid + w // 2].max())
    pct = float(np.mean(win < seam) * 100.0)
    return jump, lin2db(seam), pct


def analyze(names: list[str], plots: Path | None) -> None:
    fam_l: dict[str, list[float]] = {}
    print()
    hdr = (f"{'file':<16}{'ch':>3}{'dur s':>7}{'KB':>7}{'peak':>7}{'TP':>7}{'LUFS-I':>8}"
           f"{'M-max':>7}{'RMS':>7}{'DC':>9}{'|x0|':>8}{'|xN|':>8}{'tail':>6}{'atk ms':>7}")
    print(hdr)
    print("-" * len(hdr))
    total = 0
    warn: list[str] = []
    decoded = {}
    for name in names:
        p = OUT_DIR / f"{name}.ogg"
        if not p.exists():
            print(f"{name:<16} MISSING")
            warn.append(f"{name}: missing")
            continue
        x = decode_ogg(p)
        decoded[name] = x
        kb = p.stat().st_size / 1024
        total += p.stat().st_size
        ch = 2 if x.ndim == 2 else 1
        pk = lin2db(np.max(np.abs(x)))
        tp = lin2db(true_peak(x))
        li, mm = loudness(x)
        rms = lin2db(np.sqrt(np.mean(x ** 2)))
        dc = float(np.max(np.abs(np.mean(x, axis=0))))
        x0 = float(np.max(np.abs(x[0])))
        xn = float(np.max(np.abs(x[-1])))
        tail = lin2db(np.sqrt(np.mean(x[-n_of(0.01):] ** 2)))
        atk = attack_ms(x)
        print(f"{name:<16}{ch:>3}{len(x) / SR:>7.2f}{kb:>7.1f}{pk:>7.1f}{tp:>7.1f}{li:>8.1f}"
              f"{mm:>7.1f}{rms:>7.1f}{dc:>9.1e}{x0:>8.1e}{xn:>8.1e}{tail:>6.0f}{atk:>7.1f}")
        fam = SOUNDS[name][5] if name in SOUNDS else None
        if fam:
            fam_l.setdefault(fam, []).append(mm)
        if tp > TP_CEILING + 0.01:
            warn.append(f"{name}: true peak {tp:.2f} dBTP > {TP_CEILING}")
        if dc > 1e-3:
            warn.append(f"{name}: DC offset {dc:.1e}")
        if name in SOUNDS:
            if x0 > 1e-4 or xn > 1e-4:
                warn.append(f"{name}: edge sample not ~0 (x0={x0:.1e}, xN={xn:.1e})")
            if name.startswith(PERCUSSIVE) and atk > 10.0:
                warn.append(f"{name}: attack {atk:.1f} ms > 10 ms")
            if SOUNDS[name][1] is not None and abs(mm - SOUNDS[name][1]) > 1.0 and tp < SOUNDS[name][2] - 0.5:
                warn.append(f"{name}: loudness {mm:.1f} off target {SOUNDS[name][1]}")
    print("-" * len(hdr))
    print(f"total size: {total / 1024 / 1024:.2f} MB in {len(decoded)} files   "
          f"(LUFS dual-mono for mono files; M-max = max momentary 400 ms)")
    for fam, ls in fam_l.items():
        print(f"family '{fam}': momentary-max spread {max(ls) - min(ls):.2f} LU "
              f"({min(ls):.1f} .. {max(ls):.1f} LUFS)")
    for name in MUSIC:
        if name in decoded:
            x = decoded[name]
            jump, hf_db, pct = seam_metrics(x)
            li, _ = loudness(x)
            glen = ogg_length(OUT_DIR / f"{name}.ogg")
            exp = n_of(MUSIC_SECONDS[name])
            print(f"{name}: {glen} samples ({glen / SR:.3f} s, expected {exp}), {li:.1f} LUFS-I; "
                  f"loop seam: step/p99.9 = {jump:.2f}, HF residue {hf_db:.0f} dBFS "
                  f"(percentile {pct:.0f} of all 4 ms windows)")
            if glen != exp:
                warn.append(f"{name}: stream length {glen} != loop length {exp}")
            if jump > 1.0 or (pct > 99.5 and hf_db > -55.0):   # codec edge noise below -55 dBFS is inaudible
                warn.append(f"{name}: loop seam may be audible")
    print("QC: OK" if not warn else "QC warnings:\n  " + "\n  ".join(warn))
    if plots:
        contact_sheets(decoded, plots)


def contact_sheets(decoded: dict, outdir: Path) -> None:
    try:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
    except Exception:  # pragma: no cover
        print("matplotlib not available -- skipping plots")
        return
    outdir.mkdir(parents=True, exist_ok=True)
    sfx = [n for n in decoded if n not in MUSIC]
    per = 12
    for page in range(0, len(sfx), per):
        names = sfx[page:page + per]
        fig, axes = plt.subplots(len(names), 2, figsize=(14, 1.55 * len(names)),
                                 gridspec_kw={"width_ratios": [1, 1.4]})
        axes = np.atleast_2d(axes)
        for r, name in enumerate(names):
            x = decoded[name]
            m = x.mean(axis=1) if x.ndim == 2 else x
            t = np.arange(len(m)) / SR * 1000
            ax = axes[r, 0]
            ax.plot(t, m, lw=0.5, color="#222")
            ax.set_xlim(0, t[-1])
            ax.set_ylim(-1, 1)
            ax.text(0.99, 0.9, name, transform=ax.transAxes, ha="right", va="top", fontsize=8)
            ax.tick_params(labelsize=6)
            ax = axes[r, 1]
            ax.specgram(m + 1e-9, NFFT=512, Fs=SR, noverlap=448, cmap="magma", vmin=-130, vmax=-30)
            ax.set_ylim(0, 12000)
            ax.tick_params(labelsize=6)
        axes[-1, 0].set_xlabel("ms", fontsize=7)
        fig.tight_layout()
        p = outdir / f"{GAME}_sfx_{page // per + 1}.png"
        fig.savefig(p, dpi=90)
        plt.close(fig)
        print(f"wrote {p}")
    for name in MUSIC:
        if name not in decoded:
            continue
        x = decoded[name]
        m = x.mean(axis=1)
        fig, axes = plt.subplots(3, 1, figsize=(14, 8))
        t = np.arange(len(m)) / SR
        axes[0].plot(t, x[:, 0], lw=0.3, color="#335")
        axes[0].plot(t, x[:, 1], lw=0.3, color="#a63", alpha=0.6)
        axes[0].set_title(f"{name} (L blue / R orange)", fontsize=9)
        axes[1].specgram(m + 1e-9, NFFT=4096, Fs=SR, noverlap=2048, cmap="magma", vmin=-140, vmax=-40)
        axes[1].set_ylim(0, 6000)
        k = n_of(0.03)
        seam = np.concatenate([x[-k:], x[:k]])
        ts = (np.arange(len(seam)) - k) / SR * 1000
        axes[2].plot(ts, seam[:, 0], lw=0.7)
        axes[2].plot(ts, seam[:, 1], lw=0.7, alpha=0.7)
        axes[2].axvline(0, color="r", lw=0.6)
        axes[2].set_title("loop seam: last 30 ms | first 30 ms", fontsize=9)
        fig.tight_layout()
        p = outdir / f"{GAME}_{name}.png"
        fig.savefig(p, dpi=80)
        plt.close(fig)
        print(f"wrote {p}")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--only", nargs="*", help="render only these sound names")
    ap.add_argument("--analyze-only", action="store_true", help="skip rendering, just run QC")
    ap.add_argument("--plots", type=Path, help="write PNG waveform/spectrogram contact sheets here")
    args = ap.parse_args()
    names = list(SOUNDS) + list(MUSIC)
    if args.only:
        bad = [n for n in args.only if n not in names]
        if bad:
            print(f"unknown sound(s): {bad}", file=sys.stderr)
            return 2
    if not args.analyze_only:
        print(f"Rendering {GAME} audio into {OUT_DIR}")
        render_all(args.only)
    if args.only:   # families are always rendered/checked as a whole
        fams = {SOUNDS[n][5] for n in args.only if n in SOUNDS and SOUNDS[n][5]}
        sel = [n for n in names if n in args.only or (n in SOUNDS and SOUNDS[n][5] in fams)]
    analyze(sel if args.only else names, args.plots)
    return 0


if __name__ == "__main__":
    sys.exit(main())
