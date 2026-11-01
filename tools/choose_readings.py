#!/usr/bin/env python3
"""
OldMate - choose the three readings from measurement, not from taste.

The first trio (MACD-V, directional movement, envelope position) agreed 99-100% of
the time whenever all three had an opinion. Three names, one measurement. That is
useless: a 2-of-3 count needs readings that can genuinely disagree.

This script scores a wider set of conventional candidates on two things that
actually matter:
  1. does its vote point the right way (against forward price)?
  2. is it a copy of another candidate (pairwise agreement when both vote)?

Run:  python3 tools/choose_readings.py
"""

import itertools
import statistics as st

import reference as R

FWD = 4          # how far ahead the direction is judged, M15-ish
BAND_UNITS = 1.0  # deadband in units of an ordinary bar


# ---------------------------------------------------------------- candidates
def v_macdv(c, h, l, i, ctx):
    mv, ms = ctx["mv"], ctx["ms"]
    if mv[i] is None or ms[i] is None:
        return 0
    p = R.pct_rank([abs(v) for v in mv[max(0, i - 400):i] if v is not None], abs(mv[i]))
    if p is None or p < 60.0:
        return 0
    if mv[i] > 0 and mv[i] >= ms[i]:
        return 1
    if mv[i] < 0 and mv[i] <= ms[i]:
        return -1
    return 0


def v_dmi(c, h, l, i, ctx):
    pdi, mdi, adx = ctx["pdi"], ctx["mdi"], ctx["adx"]
    unit = ctx["unit"]
    if pdi[i] is None or mdi[i] is None or adx[i] is None or unit[i] is None:
        return 0
    band = BAND_UNITS * unit[i] * (R.math.sqrt(FWD) if False else 2.0)
    diff = pdi[i] - mdi[i]
    ap = R.pct_rank([v for v in adx[max(0, i - 400):i] if v is not None], adx[i])
    if ap is None or ap < 55.0 or abs(diff) <= 0.15 * band:
        return 0
    return 1 if diff > 0 else -1


def v_rsi_rev(c, h, l, i, ctx):
    """Conventional RSI, used the way it was designed: fade the extremes."""
    rsi = ctx["rsi"]
    if rsi[i] is None:
        return 0
    p = R.pct_rank([v for v in rsi[max(0, i - 400):i] if v is not None], rsi[i])
    if p is None:
        return 0
    if p >= 85.0:
        return -1
    if p <= 15.0:
        return 1
    return 0


def v_stoch_rev(c, h, l, i, ctx):
    k = ctx["stoch"]
    if k[i] is None:
        return 0
    p = R.pct_rank([v for v in k[max(0, i - 400):i] if v is not None], k[i])
    if p is None:
        return 0
    if p >= 88.0:
        return -1
    if p <= 12.0:
        return 1
    return 0


def v_bb_rev(c, h, l, i, ctx):
    if ctx["pos"][i] is None:
        return 0
    p = R.pct_rank([v for v in ctx["pos"][max(0, i - 400):i] if v is not None], ctx["pos"][i])
    if p is None:
        return 0
    if p >= 85.0:
        return -1
    if p <= 15.0:
        return 1
    return 0


def v_break(c, h, l, i, ctx):
    """Structure: only speaks at a fresh confirmed extreme."""
    w = 20
    unit = ctx["unit"][i]
    if i < w + 2 or unit is None:
        return 0
    hi = max(h[i - w:i])
    lo = min(l[i - w:i])
    band = 0.5 * unit
    if c[i] > hi + band:
        return 1
    if c[i] < lo - band:
        return -1
    return 0


def v_eff(c, h, l, i, ctx):
    er = ctx["er"][i]
    if er is None or ctx["unit"][i] is None:
        return 0
    net = c[i] - c[i - 10]
    if abs(net) <= 3.0 * ctx["unit"][i]:
        return 0
    return 1 if net > 0 else -1


CANDS = [
    ("MACD-V direction", v_macdv, "continuation"),
    ("DMI direction", v_dmi, "continuation"),
    ("RSI (fade extremes)", v_rsi_rev, "reversion"),
    ("Stochastic (fade)", v_stoch_rev, "reversion"),
    ("Envelope %B (fade)", v_bb_rev, "reversion"),
    ("Break of structure", v_break, "structure"),
    ("Efficiency direction", v_eff, "continuation"),
]


# ---------------------------------------------------------------- context
def wilder_rsi(c, n=14):
    up, dn = [0.0], [0.0]
    for i in range(1, len(c)):
        d = c[i] - c[i - 1]
        up.append(max(d, 0.0))
        dn.append(max(-d, 0.0))
    su, sd = R.wilder(up, n), R.wilder(dn, n)
    out = [None] * len(c)
    for i in range(len(c)):
        if su[i] is None or sd[i] is None:
            continue
        out[i] = 100.0 if su[i] + sd[i] == 0 else 100.0 * su[i] / (su[i] + sd[i])
    return out


def stoch_k(h, l, c, n=14, smooth=3):
    raw = [None] * len(c)
    for i in range(n - 1, len(c)):
        hi, lo = max(h[i - n + 1:i + 1]), min(l[i - n + 1:i + 1])
        raw[i] = 50.0 if hi == lo else 100.0 * (c[i] - lo) / (hi - lo)
    vals = [v for v in raw if v is not None]
    sm = R.ema_seeded(vals, smooth)
    out, k = [None] * len(c), 0
    for i in range(len(c)):
        if raw[i] is not None:
            out[i] = sm[k] if k < len(sm) else None
            k += 1
    return out


def build_context(c):
    h, l = [v + 0.02 for v in c], [v - 0.02 for v in c]
    mv, ms = R.macd_v(c, h, l)
    pdi, mdi, adx = R.dmi_wilder(h, l, c)
    return {
        "mv": mv, "ms": ms, "pdi": pdi, "mdi": mdi, "adx": adx,
        "pos": R.bollinger_position(c), "unit": R.unit_size(c),
        "rsi": wilder_rsi(c), "stoch": stoch_k(h, l, c),
        "er": R.efficiency_ratio(c, 10),
    }


def series_mix():
    """Several kinds of market, so nothing is chosen on one lucky sample."""
    out = []
    for seed, drift in [(101, 0.0), (102, 0.20), (103, -0.20), (104, 0.0)]:
        import random
        random.seed(seed)
        p, s = 100.0, []
        v = 0.0
        for _ in range(1400):
            v = 0.35 * v + random.gauss(0, 1.0)
            p += drift + v
            s.append(p)
        out.append(s)
    return out


def collect(series):
    allv = {name: [] for name, _, _ in CANDS}
    allfwd = []
    for s in series:
        ctx = build_context(s)
        start = 400
        for i in range(start, len(s) - FWD):
            for name, fn, _ in CANDS:
                allv[name].append(fn(s, [v + 0.02 for v in s], [v - 0.02 for v in s], i, ctx))
            allfwd.append(s[i + FWD] - s[i])
    return allv, allfwd


def main():
    data = collect(series_mix())
    votes, fwd = data
    print("=" * 78)
    print("HOW OFTEN DOES EACH CANDIDATE ACTUALLY SPEAK?")
    print("=" * 78)
    for name, _, fam in CANDS:
        v = votes[name]
        up = 100.0 * sum(1 for x in v if x > 0) / len(v)
        dn = 100.0 * sum(1 for x in v if x < 0) / len(v)
        ab = 100.0 * sum(1 for x in v if x == 0) / len(v)
        print(f"  {name:22s} {fam:12s} up {up:5.1f}%  down {dn:5.1f}%  abstain {ab:5.1f}%")

    print()
    print("=" * 78)
    print("DOES EACH POINT THE RIGHT WAY AT +" + str(FWD) + " BARS?")
    print("=" * 78)
    hits = {}
    for name, _, fam in CANDS:
        v, h_, t_ = votes[name], 0, 0
        for i in range(len(v)):
            if v[i] == 0 or fwd[i] == 0:
                continue
            t_ += 1
            if (v[i] > 0 and fwd[i] > 0) or (v[i] < 0 and fwd[i] < 0):
                h_ += 1
        hits[name] = 100.0 * h_ / t_ if t_ else 0.0
        print(f"  {name:22s} right {hits[name]:5.1f}% of {t_} calls")

    print()
    print("=" * 78)
    print("ARE THEY COPIES?  (agreement on the bars where both vote)")
    print("=" * 78)
    names = [n for n, _, _ in CANDS]
    print(f"  {'':22s}" + "".join(f"{n[:11]:>13s}" for n in names))
    agree = {}
    for a in names:
        row = f"  {a:22s}"
        for b in names:
            if a == b:
                row += f"{'--':>13s}"
                continue
            nz = [(u, w) for u, w in zip(votes[a], votes[b]) if u != 0 and w != 0]
            pct = 100.0 * sum(1 for u, w in nz if u == w) / len(nz) if nz else 0.0
            agree[(a, b)] = (pct, len(nz))
            row += f"{pct:5.1f}%({len(nz)//1000}k)" .rjust(13)
        print(row)

    print()
    print("=" * 78)
    print("THE CHOICE")
    print("=" * 78)
    fam = {n: f for n, _, f in CANDS}
    best, best_score = None, -1e9
    for trio in itertools.combinations(names, 3):
        fams = {fam[n] for n in trio}
        if len(fams) < 3:
            continue
        max_agree = max(agree[(a, b)][0] for a, b in itertools.combinations(trio, 2))
        min_agree = min(agree[(a, b)][0] for a, b in itertools.combinations(trio, 2))
        hit = st.mean(hits[n] for n in trio)
        # want: decent hit rate, genuine disagreement, and not pure noise
        score = hit - 0.35 * max(0.0, max_agree - 75.0) + 0.02 * (100.0 - min_agree)
        if score > best_score:
            best_score, best = score, (trio, hit, max_agree, min_agree)
    trio, hit, mx, mn = best
    print(f"  chosen: {', '.join(trio)}")
    print(f"  mean hit rate at +{FWD} bars: {hit:.1f}%")
    print(f"  worst pair agreement: {mx:.1f}%   (a copy would be ~100%)")
    print(f"  best pair agreement:  {mn:.1f}%   (genuinely different reads)")
    print()
    print("  every trio with one reading from each family, for the record:")
    for t in itertools.combinations(names, 3):
        if len({fam[n] for n in t}) < 3:
            continue
        ma = max(agree[(a, b)][0] for a, b in itertools.combinations(t, 2))
        hh = st.mean(hits[n] for n in t)
        mark = "  <- chosen" if set(t) == set(trio) else ""
        print(f"    {hh:5.1f}% hit, worst pair {ma:5.1f}%   {', '.join(t)}{mark}")


if __name__ == "__main__":
    main()
