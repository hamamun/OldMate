#!/usr/bin/env python3
"""
OldMate - reference implementation of every calculation the EA performs.

Python is used here only as the proving ground: each function below is written the
way the MQL5 must be written, and tools/selftest.py checks that it behaves.
Nothing here trades. It exists so the EA's arithmetic is verified before it is
translated, instead of being asserted in a comment.

Conventions that matter and are enforced here:
  * Wilder smoothing is weight 1/n with a simple-average seed. Not an EMA at 2/(n+1).
  * True range counts gaps.
  * Averages that feed a ratio are seeded so the first value is not a warm-up artefact.
  * Percentiles are empirical with linear interpolation and a minimum sample count.
  * Hurst is DFA primary, R/S secondary; disagreement is 'Unclear', never averaged.
"""

import math
import statistics as st


# ---------------------------------------------------------------- smoothing
def sma(x, n):
    return sum(x[:n]) / n if len(x) >= n else None


def ema_seeded(x, n):
    """EMA seeded by a simple average of the first n values."""
    if len(x) < n:
        return [None] * len(x)
    out = [None] * len(x)
    out[n - 1] = sma(x, n)
    a = 2.0 / (n + 1.0)
    for i in range(n, len(x)):
        out[i] = out[i - 1] + a * (x[i] - out[i - 1])
    return out


def wilder(x, n):
    """Wilder's smoothing (RMA): weight 1/n, simple-average seed."""
    if len(x) < n:
        return [None] * len(x)
    out = [None] * len(x)
    out[n - 1] = sma(x, n)
    for i in range(n, len(x)):
        out[i] = out[i - 1] + (x[i] - out[i - 1]) / n
    return out


def true_range(h, l, c):
    tr = [h[0] - l[0]]
    for i in range(1, len(c)):
        tr.append(max(h[i] - l[i], abs(h[i] - c[i - 1]), abs(l[i] - c[i - 1])))
    return tr


def atr_wilder(h, l, c, n=26):
    return wilder(true_range(h, l, c), n)


# ---------------------------------------------------------------- readings
def macd_v(c, h, l, fast=12, slow=26, sig=9):
    """
    MACD divided by ATR over the slow window, x100.  Dimensionless, so a reading
    means the same on gold, EURUSD and an index.  Spiroglou 2022.
    """
    ef, es = ema_seeded(c, fast), ema_seeded(c, slow)
    atr = atr_wilder(h, l, c, slow)
    line = [None] * len(c)
    for i in range(len(c)):
        if ef[i] is not None and es[i] is not None and atr[i]:
            line[i] = (ef[i] - es[i]) / atr[i] * 100.0
    valid = [v for v in line if v is not None]
    s_line = ema_seeded(valid, sig) if len(valid) >= sig else [None] * len(valid)
    out_sig = [None] * len(c)
    k = 0
    for i in range(len(c)):
        if line[i] is not None:
            out_sig[i] = s_line[k]
            k += 1
    return line, out_sig


def dmi_wilder(h, l, c, n=14):
    """+DI, -DI, ADX - Wilder's directional movement, Wilder-smoothed."""
    pdm, mdm, tr = [0.0], [0.0], [h[0] - l[0]]
    for i in range(1, len(c)):
        up, dn = h[i] - h[i - 1], l[i - 1] - l[i]
        pdm.append(up if (up > dn and up > 0) else 0.0)
        mdm.append(dn if (dn > up and dn > 0) else 0.0)
        tr.append(max(h[i] - l[i], abs(h[i] - c[i - 1]), abs(l[i] - c[i - 1])))
    sp, sm, st = wilder(pdm, n), wilder(mdm, n), wilder(tr, n)
    pdi = [None] * len(c)
    mdi = [None] * len(c)
    dx = [None] * len(c)
    for i in range(len(c)):
        if sp[i] is None or not st[i]:
            continue
        pdi[i] = 100.0 * sp[i] / st[i]
        mdi[i] = 100.0 * sm[i] / st[i]
        s = pdi[i] + mdi[i]
        if s:
            dx[i] = 100.0 * abs(pdi[i] - mdi[i]) / s
    vals = [v for v in dx if v is not None]
    adx_s = wilder(vals, n)
    adx = [None] * len(c)
    k = 0
    for i in range(len(c)):
        if dx[i] is not None:
            adx[i] = adx_s[k] if k < len(adx_s) else None
            k += 1
    return pdi, mdi, adx


def bollinger_position(c, n=20, k=2.0):
    """%B-like position around the middle, population sigma (Bollinger's convention)."""
    out = [None] * len(c)
    for i in range(n - 1, len(c)):
        w = c[i - n + 1:i + 1]
        m = sum(w) / n
        sd = math.sqrt(sum((v - m) ** 2 for v in w) / n)
        out[i] = 0.0 if sd == 0 else (c[i] - m) / (k * sd)
    return out


def envelope_width(c, n=20):
    out = [None] * len(c)
    for i in range(n - 1, len(c)):
        w = c[i - n + 1:i + 1]
        m = sum(w) / n
        out[i] = math.sqrt(sum((v - m) ** 2 for v in w) / n)
    return out


def efficiency_ratio(c, k):
    """|net move| / total path over k bars.  1 = clean, 0 = churn."""
    out = [None] * len(c)
    for i in range(k, len(c)):
        path = sum(abs(c[j] - c[j - 1]) for j in range(i - k + 1, i + 1))
        out[i] = 0.0 if path == 0 else abs(c[i] - c[i - k]) / path
    return out


def unit_size(c, n=20):
    """The measured unit: median absolute close-to-close change."""
    out = [None] * len(c)
    for i in range(n, len(c)):
        out[i] = st.median([abs(c[j] - c[j - 1]) for j in range(i - n + 1, i + 1)])
    return out


# ---------------------------------------------------------------- percentiles
def pct_rank(hist, value):
    """
    Percentile rank 0..100 of value within hist, linear interpolation.
    Returns None when hist is shorter than MIN_PCT samples - the EA shows
    CALIBRATING rather than falling back to a written-down threshold.
    """
    h = sorted(v for v in hist if v is not None)
    if len(h) < MIN_PCT:
        return None
    if len(h) == 1:
        return 50.0
    below = sum(1 for v in h if v < value)
    equal = sum(1 for v in h if v == value)
    pos = below + 0.5 * equal
    return 100.0 * pos / len(h)


MIN_PCT = 60


# ---------------------------------------------------------------- persistence
def diffs(x):
    """First differences.  DFA and R/S are computed on these for a price series.

    This is the correction the self-test forced: running DFA on prices themselves
    returns H+1 (a random walk scores 1.5, not 0.5), because the profile step
    integrates an already-integrated series.  For a price series the exponent is
    measured on its increments.
    """
    return [x[i] - x[i - 1] for i in range(1, len(x))]


def hurst_dfa(x, min_box=8):
    """Detrended fluctuation analysis.  Slope of log F(s) against log s.

    Expects the series whose memory you want: pass `diffs(prices)`, not prices.
    White noise ~0.5, persistent >0.5, anti-persistent <0.5.
    """
    n = len(x)
    boxes = []
    s = min_box
    while s * 2 <= n // 2:
        boxes.append(s)
        s *= 2
    if len(boxes) < 3:
        return None
    m = sum(x) / n
    prof, acc = [], 0.0
    for v in x:
        acc += v - m
        prof.append(acc)
    pts = []
    for s in boxes:
        nb = n // s
        if nb < 2:
            continue
        tot, cnt = 0.0, 0
        xs = list(range(s))
        xm = (s - 1) / 2.0
        den = sum((v - xm) ** 2 for v in xs) or 1.0
        for b in range(nb):
            seg = prof[b * s:(b + 1) * s]
            ym = sum(seg) / s
            num = sum((xs[j] - xm) * (seg[j] - ym) for j in range(s))
            slope = num / den
            icpt = ym - slope * xm
            tot += sum((seg[j] - (icpt + slope * j)) ** 2 for j in range(s))
            cnt += s
        if cnt:
            f = math.sqrt(tot / cnt)
            if f > 0:
                pts.append((math.log(s), math.log(f)))
    if len(pts) < 3:
        return None
    xs_ = [p[0] for p in pts]
    ys_ = [p[1] for p in pts]
    mx, my = sum(xs_) / len(xs_), sum(ys_) / len(ys_)
    num = sum((xs_[i] - mx) * (ys_[i] - my) for i in range(len(xs_)))
    den = sum((v - mx) ** 2 for v in xs_) or 1.0
    return num / den


def hurst_rs(x, min_box=8):
    """Classic rescaled range.  Secondary estimator, used as a cross-check.

    As with DFA, pass `diffs(prices)` for a price series.
    """
    n = len(x)
    boxes, s = [], min_box
    while s * 2 <= n // 2:
        boxes.append(s)
        s *= 2
    pts = []
    for s in boxes:
        nb = n // s
        if nb < 2:
            continue
        acc = []
        for b in range(nb):
            seg = x[b * s:(b + 1) * s]
            m = sum(seg) / s
            dev, run, lo, hi = 0.0, 0.0, 0.0, 0.0
            for v in seg:
                run += v - m
                lo, hi = min(lo, run), max(hi, run)
            sd = math.sqrt(sum((v - m) ** 2 for v in seg) / s)
            if sd > 0:
                acc.append((hi - lo) / sd)
        if acc:
            pts.append((math.log(s), math.log(sum(acc) / len(acc))))
    if len(pts) < 3:
        return None
    xs_ = [p[0] for p in pts]
    ys_ = [p[1] for p in pts]
    mx, my = sum(xs_) / len(xs_), sum(ys_) / len(ys_)
    num = sum((xs_[i] - mx) * (ys_[i] - my) for i in range(len(xs_)))
    den = sum((v - mx) ** 2 for v in xs_) or 1.0
    return num / den


def variance_ratio(x, q=4):
    """Var of q-step changes over q, divided by Var of 1-step changes. >1 persists."""
    if len(x) < q * 4:
        return None
    d1 = [x[i] - x[i - 1] for i in range(1, len(x))]
    dq = [x[i] - x[i - q] for i in range(q, len(x))]
    v1, vq = st.pvariance(d1), st.pvariance(dq)
    if v1 <= 0:
        return None
    return vq / (q * v1)


def memory_state(prices):
    """
    0 = trending, 1 = random, 2 = ranging, 3 = unclear.

    Takes a PRICE series and analyses its increments.  DFA is primary, R/S is a
    cross-check, the variance ratio is a second check.  Never an average.
    """
    x = diffs(prices)
    d, r, vr = hurst_dfa(x), hurst_rs(x), variance_ratio(prices, 4)
    if d is None:
        return 3, d, r, vr
    if r is not None and abs(d - r) > HURST_TOL:
        return 3, d, r, vr
    if d >= HURST_HI:
        if vr is not None and vr < 1.0:
            return 3, d, r, vr
        return 0, d, r, vr
    if d <= HURST_LO:
        if vr is not None and vr > 1.0:
            return 3, d, r, vr
        return 2, d, r, vr
    return 1, d, r, vr


HURST_HI = 0.55
HURST_LO = 0.45
HURST_TOL = 0.12


# ---------------------------------------------------------------- the votes
def vote_momentum(mv, mvsig, strength_pct):
    """Up when the reading is positive and strong for this symbol, down mirrored."""
    if mv is None or strength_pct is None or mvsig is None:
        return 0
    if mv > 0 and mv >= mvsig and strength_pct >= MOM_CUT:
        return 1
    if mv < 0 and mv <= mvsig and strength_pct >= MOM_CUT:
        return -1
    return 0


def vote_push(pdi, mdi, adx, adx_pct, deadband):
    if pdi is None or mdi is None or adx is None or adx_pct is None:
        return 0
    diff = pdi - mdi
    if abs(diff) <= deadband:
        return 0
    if adx_pct < PUSH_CUT:
        return 0
    return 1 if diff > 0 else -1


def vote_stretch(pos_pct):
    """
    The stretch reading is a REVERSION reading: stretched high fades bearish,
    stretched low fades bullish.

    Measured (combine_test.py), this family is the better decider only when
    market memory says the series is ranging; in a trend it is systematically
    wrong, which is why the EA lets it decide only there.
    """
    if pos_pct is None:
        return 0
    if pos_pct >= STRETCH_HI:
        return -1
    if pos_pct <= (100.0 - STRETCH_HI):
        return 1
    return 0


MOM_CUT = 60.0
PUSH_CUT = 55.0
STRETCH_HI = 85.0
