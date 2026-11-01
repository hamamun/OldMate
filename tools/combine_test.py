#!/usr/bin/env python3
"""
OldMate - which combination rule earns the CALL?

choose_readings.py showed there are only two genuinely different directional
opinions in a price series: continuation and reversion. Within each family the
members are near-copies (95-100% agreement); between the families they are exact
opposites (0% agreement).

So a naive "2 of 3 agree" over an arbitrary trio is not a measurement, it is a
coin weighted by which family contributed two members.

This script tests real combination rules against four kinds of market, including
one that genuinely mean-reverts, so the answer is not fitted to trending data.

Run:  python3 tools/combine_test.py
"""

import random

import reference as R
from choose_readings import (CANDS, build_context, v_break, v_eff, v_macdv,
                             v_rsi_rev, v_dmi, v_bb_rev, wilder_rsi)

FWD = 4


# ---------------------------------------------------------------- markets
def m_walk(n, seed, drift=0.0):
    random.seed(seed)
    p, out = 100.0, []
    for _ in range(n):
        p += drift + random.gauss(0, 1.0)
        out.append(p)
    return out


def m_momentum(n, seed, phi=0.35, drift=0.0):
    random.seed(seed)
    p, v, out = 100.0, 0.0, []
    for _ in range(n):
        v = phi * v + random.gauss(0, 1.0)
        p += drift + v
        out.append(p)
    return out


def m_ou(n, seed, theta=0.15, sigma=1.0):
    """Ornstein-Uhlenbeck: the market really does snap back to a mean."""
    random.seed(seed)
    p, out = 100.0, []
    for _ in range(n):
        p += theta * (100.0 - p) + random.gauss(0, sigma)
        out.append(p)
    return out


def m_trend_with_pullbacks(n, seed):
    """Drift with regular retracements - the pattern most retail systems meet."""
    random.seed(seed)
    p, out, phase = 100.0, [], 0.0
    for i in range(n):
        phase += 0.09
        cycle = -6.0 * float(__import__("math").sin(phase))
        p += 0.12 + cycle * 0.25 + random.gauss(0, 0.6)
        out.append(p)
    return out


MARKETS = [
    ("random walk", m_walk(1500, 201)),
    ("steady drift", m_walk(1500, 202, drift=0.20)),
    ("momentum", m_momentum(1500, 203)),
    ("mean-reverting", m_ou(1500, 204)),
    ("drift + pullbacks", m_trend_with_pullbacks(1500, 205)),
]


# ---------------------------------------------------------------- rules
def clamp(x):
    return 0 if x == 0 else (1 if x > 0 else -1)


def rules_for(c, ctx):
    h = [v + 0.02 for v in c]
    l = [v - 0.02 for v in c]
    n = len(c)
    vec = {k: [] for k in ("macdv", "rsi", "bb", "brk", "eff", "dmi")}
    for i in range(400, n):
        vec["macdv"].append(v_macdv(c, h, l, i, ctx))
        vec["rsi"].append(v_rsi_rev(c, h, l, i, ctx))
        vec["bb"].append(v_bb_rev(c, h, l, i, ctx))
        vec["brk"].append(v_break(c, h, l, i, ctx))
        vec["eff"].append(v_eff(c, h, l, i, ctx))
        vec["dmi"].append(v_dmi(c, h, l, i, ctx))
    return vec


def sign_sum(vals):
    s = sum(vals)
    return 0 if s == 0 else (1 if s > 0 else -1)


def main():
    print("=" * 92)
    print("WHICH COMBINATION RULE EARNS THE CALL?   (hit rate at +%d bars)" % FWD)
    print("=" * 92)

    header = f"{'market':20s}"
    rule_names = [
        "MACD-V only",
        "break only",
        "MACD-V+break (both)",
        "MACD-V+break (sum)",
        "RSI fade only",
        "%B fade only",
        "trend-follow trio 2/3",
        "regime-conditional",
        "MACD-V+break+RSI 2/3",
    ]
    for r in rule_names:
        header += f"{r[:13]:>15s}"
    print(header)
    print("-" * 92)

    totals = {r: [0, 0] for r in rule_names}

    for label, c in MARKETS:
        ctx = build_context(c)
        v = rules_for(c, ctx)
        fwd = [c[i + FWD] - c[i] for i in range(400, len(c) - FWD)]
        mem = []
        for i in range(400, len(c) - FWD):
            mem.append(R.memory_state(c[max(0, i - 320):i + 1])[0])

        row = f"{label:20s}"
        for rname in rule_names:
            hits = tot = 0
            for k in range(len(fwd)):
                m, br, rs, bb, ef, dm = (v["macdv"][k], v["brk"][k], v["rsi"][k],
                                        v["bb"][k], v["eff"][k], v["dmi"][k])
                if rname == "MACD-V only":
                    call = m
                elif rname == "break only":
                    call = br
                elif rname == "MACD-V+break (both)":
                    call = m if (m != 0 and m == br) else 0
                elif rname == "MACD-V+break (sum)":
                    call = sign_sum([m, br]) if 0 not in (m, br) else 0
                elif rname == "RSI fade only":
                    call = rs
                elif rname == "%B fade only":
                    call = bb
                elif rname == "trend-follow trio 2/3":
                    s = m + br + ef
                    call = 0 if abs(s) < 2 else clamp(s)
                elif rname == "regime-conditional":
                    # persisting or random -> continuation; ranging -> reversion
                    if mem[k] == 2:
                        call = rs if rs != 0 else bb
                    else:
                        call = m if (m != 0 and m == br) else (m or br)
                elif rname == "MACD-V+break+RSI 2/3":
                    s = m + br + rs
                    call = 0 if abs(s) < 2 else clamp(s)
                if call == 0 or fwd[k] == 0:
                    continue
                tot += 1
                if (call > 0 and fwd[k] > 0) or (call < 0 and fwd[k] < 0):
                    hits += 1
            pct = 100.0 * hits / tot if tot else 0.0
            totals[rname][0] += hits
            totals[rname][1] += tot
            row += f"{pct:5.1f}%({tot//100:>3d})".rjust(15)
        print(row)

    print("-" * 92)
    row = f"{'ALL MARKETS':20s}"
    for rname in rule_names:
        h, t = totals[rname]
        row += f"{100.0*h/t:5.1f}%({t//100:>3d})".rjust(15)
    print(row)
    print()
    print("Read this honestly: 50% is a coin flip. A rule that scores 52% on one")
    print("market and 44% on another has no edge, it has a market bias. The rule")
    print("that survives is the one that is not below a coin flip anywhere.")


if __name__ == "__main__":
    main()
