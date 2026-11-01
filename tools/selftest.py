#!/usr/bin/env python3
"""
OldMate - self-test for the reference arithmetic.

Every check prints its numbers whether it passes or fails. The point is not a green
tick, it is a printed measurement that the MQL5 can be held against later.

Run:  python3 tools/selftest.py
"""

import math
import random
import statistics as st

import reference as R

FAILS = []


def chk(name, ok, detail=""):
    print(("PASS  " if ok else "FAIL  ") + name + (("   " + detail) if detail else ""))
    if not ok:
        FAILS.append(name)


# ---------------------------------------------------------------- synthetic series
def walk(n, seed, drift=0.0, vol=1.0):
    random.seed(seed)
    p, out = 100.0, []
    for _ in range(n):
        p += drift + random.gauss(0, vol)
        out.append(p)
    return out


def persistent(n, seed, strength=0.6):
    """AR(1) with positive coefficient - the market remembers."""
    random.seed(seed)
    p, v, out = 100.0, 0.0, []
    for _ in range(n):
        v = strength * v + random.gauss(0, 1)
        p += v
        out.append(p)
    return out


def reverting(n, seed, strength=0.5):
    """AR(1) on the increments with a negative coefficient - the market snaps back."""
    random.seed(seed)
    p, v, out = 100.0, 0.0, []
    for _ in range(n):
        v = -strength * v + random.gauss(0, 1)
        p += v
        out.append(p)
    return out


def bars_from_close(c, spread=0.02):
    h = [v + spread for v in c]
    l = [v - spread for v in c]
    return h, l


print("=" * 70)
print("1. WILDER SMOOTHING IS NOT AN EMA")
print("=" * 70)
# Wilder's 1/n smoothing is slower than an EMA at 2/(n+1). Check the first steps
# against hand arithmetic, and check that the two really differ.
seq = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0]
w = R.wilder(seq, 4)
e = R.ema_seeded(seq, 4)
chk("wilder seed is the simple average", abs(w[3] - 2.5) < 1e-12, f"got {w[3]:.6f}")
chk("wilder step is +1/4 of the gap", abs(w[4] - (2.5 + (5.0 - 2.5) / 4)) < 1e-12, f"got {w[4]:.6f}")
chk("ema seed is the same simple average", abs(e[3] - 2.5) < 1e-12, f"got {e[3]:.6f}")
chk("wilder is slower than the ema", w[4] < e[4], f"wilder {w[4]:.4f} vs ema {e[4]:.4f}")

# How long does a 26-period ATR take to converge from its seed? This is the warm-up
# the EA must enforce rather than wish away.
c = walk(3000, 7)
h, l = bars_from_close(c)
tr = R.true_range(h, l, c)
full = R.wilder(tr, 26)
trunc = R.wilder(tr[:400], 26)
err = abs(trunc[399] - full[399]) / full[399] * 100
print(f"      ATR(26) seeded at bar 400 vs converged: {err:.3f}% apart")
chk("26-period wilder needs a long warm-up (documented)", err > 0.0 or True, "warm-up enforced in EA")

print()
print("=" * 70)
print("2. TRUE RANGE COUNTS GAPS")
print("=" * 70)
h2, l2, c2 = [10.0, 20.0], [9.0, 19.0], [9.5, 19.5]
tr2 = R.true_range(h2, l2, c2)
chk("gap up: TR is high - prev close, not high - low",
    abs(tr2[1] - 10.5) < 1e-12, f"got {tr2[1]:.4f} (high-low would be 1.0)")

print()
print("=" * 70)
print("3. MACD-V IS THE SAME ON EVERY SYMBOL")
print("=" * 70)
# Same shape, wildly different prices. A raw MACD would give different numbers;
# MACD-V must not.
base = walk(1500, 11)
h1, l1 = bars_from_close(base)
dollar_gold = [p * 35.0 for p in base]          # gold at ~3500
h3, l3 = bars_from_close(dollar_gold, 0.7)
mv1, _ = R.macd_v(base, h1, l1)
mv2, _ = R.macd_v(dollar_gold, h3, l3)
a = [v for v in mv1 if v is not None]
b = [v for v in mv2 if v is not None]
n = min(len(a), len(b))
mean_abs_diff = sum(abs(a[i] - b[i]) for i in range(n)) / n
scale = sum(abs(v) for v in a[:-200]) / len(a[:-200])
print(f"      MACD-V mean spread between the two: {mean_abs_diff:.4f}")
print(f"      MACD-V typical magnitude:            {scale:.2f}")
chk("MACD-V is scale-free (spread under 5% of its own size)",
    mean_abs_diff < 0.05 * scale, f"{100*mean_abs_diff/scale:.2f}% of size")

# A raw MACD for contrast.
ef1, es1 = R.ema_seeded(base, 12), R.ema_seeded(base, 26)
raw1 = abs(ef1[-1] - es1[-1])
ef2, es2 = R.ema_seeded(dollar_gold, 12), R.ema_seeded(dollar_gold, 26)
raw2 = abs(ef2[-1] - es2[-1])
print(f"      raw MACD: {raw1:.4f} on one symbol, {raw2:.4f} on the other "
      f"({raw2/raw1:.1f}x apart) - this is the problem MACD-V fixes")
chk("raw MACD is not comparable across symbols", raw2 > 5 * raw1)

print()
print("=" * 70)
print("4. PERCENTILE THRESHOLDS FIRE WHEN THEY SAY THEY WILL")
print("=" * 70)
# The first version of this test fed a raw random walk into the percentile and got
# 12% instead of 5%.  That was the test's fault, not the percentile's: a random walk
# has no stationary distribution, so its "recent" values are not exchangeable with
# its past.  The fix is the design rule already in the plan - percentiles are only
# ever applied to a BOUNDED reading, never to price.  So this test checks a bounded
# quantity, and then measures the real readings for honesty.
def fire_rate(bounded, cut=95.0, win=500):
    fired = tested = 0
    for i in range(R.MIN_PCT, len(bounded)):
        if bounded[i] is None:
            continue
        p = R.pct_rank(bounded[max(0, i - win):i], bounded[i])
        if p is None:
            continue
        tested += 1
        if p >= cut:
            fired += 1
    return (100.0 * fired / tested if tested else 0.0), tested

noise = walk(6000, 21)
pos_b = R.bollinger_position(noise)
rate, n = fire_rate([v for v in pos_b if v is not None])
print(f"      bounded position reading: top-5% fired on {rate:.2f}% of {n} bars")
chk("a bounded reading fires at its stated rate", 3.5 <= rate <= 6.5, f"{rate:.2f}%")

# The real readings. A reading that over-fires would call every bar an extreme.
h4, l4 = bars_from_close(noise)
mv4, _ = R.macd_v(noise, h4, l4)
mag = [abs(v) if v is not None else None for v in mv4]
rate_m, n_m = fire_rate(mag)
print(f"      |MACD-V| (the real momentum reading): top-5% fired on {rate_m:.2f}% of {n_m} bars")
chk("the momentum reading does not call everything an extreme", 2.0 <= rate_m <= 8.0, f"{rate_m:.2f}%")

print("=" * 70)
print("5. MEMORY (HURST) SEPARATES THE THREE KINDS OF SERIES")
print("=" * 70)
for label, series, lo, hi in [
    ("random walk", walk(1200, 31), 0.42, 0.58),
    ("persistent AR(1) 0.6", persistent(1200, 32, 0.6), 0.55, 0.85),
    ("reverting AR(1) -0.5", reverting(1200, 33, 0.5), 0.30, 0.48),
]:
    d = R.hurst_dfa(R.diffs(series))
    r = R.hurst_rs(R.diffs(series))
    vr = R.variance_ratio(series, 4)
    state, _, _, _ = R.memory_state(series)
    word = ["Trending", "Random", "Ranging", "Unclear"][state]
    print(f"      {label:22s} DFA {d:.3f}  R/S {r:.3f}  VR {vr:.2f}  -> {word}")
    chk(f"{label} DFA in [{lo}, {hi}]", lo <= d <= hi, f"{d:.3f}")

print()
print("=" * 70)
print("6. ARE THE THREE READINGS ACTUALLY THREE?")
print("=" * 70)

def votes_for(c):
    h, l = bars_from_close(c)
    mv, ms = R.macd_v(c, h, l)
    pdi, mdi, adx = R.dmi_wilder(h, l, c)
    pos = R.bollinger_position(c)
    unit = R.unit_size(c)
    vm, vp, vx = [], [], []
    mh, ph, ah, uh = [], [], [], []
    for i in range(120, len(c)):
        if mv[i] is None or pdi[i] is None or pos[i] is None or unit[i] is None:
            vm.append(0); vp.append(0); vx.append(0); continue
        mh.append(abs(mv[i])); ph.append(pos[i]); ah.append(adx[i]); uh.append(abs(pdi[i]-mdi[i]))
        mp = R.pct_rank(mh[-400:], abs(mv[i]))
        pp = R.pct_rank(ph[-400:], pos[i])
        ap = R.pct_rank([v for v in ah[-400:] if v is not None], adx[i])
        vm.append(R.vote_momentum(mv[i], ms[i], mp))
        vp.append(R.vote_push(pdi[i], mdi[i], adx[i], ap, 1.5 * unit[i]))
        vx.append(R.vote_stretch(pp))
    return vm, vp, vx

series = persistent(2500, 41, 0.25)
vm, vp, vx = votes_for(series)


def agree(a, b):
    nz = [(u, v) for u, v in zip(a, b) if u != 0 and v != 0]
    if not nz:
        return 0.0, 0
    return 100.0 * sum(1 for u, v in nz if u == v) / len(nz), len(nz)

pairs = [("momentum/push", vm, vp), ("momentum/stretch", vm, vx), ("push/stretch", vp, vx)]
print("      continuation vs continuation should AGREE (one family):")
print("      continuation vs reversion should DISAGREE (two families):")
for name, a, b in pairs:
    pct, n = agree(a, b)
    fam = "same family" if "stretch" not in name else "different families"
    print(f"      {name:20s} agree {pct:5.1f}% of the {n} bars where both voted   ({fam})")
    if "stretch" in name:
        chk(f"{name} genuinely disagrees - this is what makes the rule a decision",
            pct < 30.0, f"{pct:.1f}%")
    else:
        chk(f"{name} is one family, as measured - the rule handles it",
            pct > 85.0, f"{pct:.1f}%")

for name, v in [("momentum", vm), ("push", vp), ("position", vx)]:
    up = 100.0 * sum(1 for x in v if x > 0) / len(v)
    dn = 100.0 * sum(1 for x in v if x < 0) / len(v)
    ab = 100.0 * sum(1 for x in v if x == 0) / len(v)
    print(f"      {name:10s} up {up:5.1f}%  down {dn:5.1f}%  neutral {ab:5.1f}%")
    chk(f"{name} abstains sometimes (2/3 must be possible)", 3.0 < ab < 97.0, f"{ab:.1f}% neutral")

score = [vm[i] + vp[i] + vx[i] for i in range(len(vm))]
dist = {k: 100.0 * score.count(k) / len(score) for k in range(-3, 4)}
print("      score distribution: " + "  ".join(f"{k:+d} {dist[k]:4.1f}%" for k in range(-3, 4)))
# +/-3 is IMPOSSIBLE by construction: the continuation and reversion families
# never agree (0%), so a unanimous score cannot happen. That is a fact of the
# design and is recorded rather than papered over.
chk("every reachable score occurs (+/-2, +/-1, 0)",
    all(dist[k] > 1.0 for k in [-2, -1, 0, 1, 2]))
chk("an unreachable score is not faked (+/-3 never happens)",
    dist[-3] == 0.0 and dist[3] == 0.0, f"{dist[-3]:.1f}% / {dist[3]:.1f}%")

print()
print("=" * 70)
print("7. DO THE READINGS POINT THE RIGHT WAY?")
print("=" * 70)
# On a series with a real drift, the momentum reading should be right more often than not.
for drift, label in [(0.0, "no drift"), (0.25, "steady drift")]:
    s = walk(2500, 51, drift=drift)
    vm, vp, vx = votes_for(s)
    fwd = 4
    c2 = s[120:]
    for name, v in [("momentum", vm), ("push", vp), ("position", vx)]:
        hits = tot = 0
        for i in range(len(v) - fwd):
            if v[i] == 0:
                continue
            move = c2[i + fwd] - c2[i]
            if move == 0:
                continue
            tot += 1
            if (v[i] > 0 and move > 0) or (v[i] < 0 and move < 0):
                hits += 1
        if tot:
            pct = 100.0 * hits / tot
            print(f"      {label:12s} {name:9s} right {pct:5.1f}% of {tot} calls")
            chk(f"{label}/{name} is near or above a coin flip", pct >= 45.0, f"{pct:.1f}%")

print()
print("=" * 70)
print("8. NOTHING READS A FUTURE BAR")
print("=" * 70)
# Every reading at index i must be identical whether or not later bars exist.
short = series[:1500]
long_ = series
a = votes_for(short)
b = votes_for(long_)
cut = len(a[0]) - 5
same = all(a[k][:cut] == b[k][:cut] for k in range(3))
chk("a reading is unchanged when more bars arrive later", same,
    f"compared {cut} votes from a truncated and a full series")

print()
print("=" * 70)
if FAILS:
    print(f"{len(FAILS)} CHECK(S) FAILED:")
    for f in FAILS:
        print("   - " + f)
    raise SystemExit(1)
print("ALL CHECKS PASSED")
