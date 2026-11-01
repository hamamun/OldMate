# OldMate — conventional autotrading for MT5

**Status: built.** `OldMate.mq5` — 3 297 lines, preflight-clean, arithmetic verified by a
Python reference. **Not yet compiled in MetaEditor and not yet run on a demo account.** That is
the only step left, and [oldmate.md](oldmate.md) section 13 says exactly how to judge it.

OldMate is the conventional sibling of [Automate](https://github.com/hamamun/Automate) — same
family, same discipline, same refusal to print a number it cannot compute — built so the two can
be **run side by side and compared honestly.**

## Files

| File | What it is |
|---|---|
| `OldMate.mq5` | the EA. Copy to `MQL5/Experts/`, compile with F7, attach to M5, M15 or M30 |
| [oldmate.md](oldmate.md) | the plan and the record of what the measurements changed |
| [indicators.md](indicators.md) | the indicator record: formulas, the reject pile, the full measurement log |
| `tools/selftest.py` | proves the arithmetic — Wilder seeding, gaps, scale-freedom, percentile calibration, memory separation, no repaint |
| `tools/choose_readings.py` | which conventional indicators are actually different from each other |
| `tools/combine_test.py` | which combination rule survives four kinds of market |
| `tools/preflight.py` | static checks the compiler would otherwise catch |
| `tools/reference.py` | the Python mirror of every calculation in the EA |

```
python3 tools/preflight.py OldMate.mq5     # PREFLIGHT CLEAN
python3 tools/selftest.py                  # ALL CHECKS PASSED
```

## What it does

Attach it to a chart. It works out the symbol, the broker's rules, the account type, whether
the market is open and when it opens, which session it is, and how this instrument behaves — by
itself. On three lanes (M5 scalping, M15 short-term, M30 intraday) it reads the chart three
ways, shows each reading separately, and calls BUY or SELL using the rule that measurement
picked. It plans one trade per lane — structural stop, a target measured from what that lane
has actually delivered, size from the terminal's own money calculation — sends it only when the
switches and the terminal both allow it, then manages it to the end: TP1 partial, trailing
stop, TP2, graded in money.

## The finding that shaped it

Seven conventional indicators collapse into exactly **two** opinions: continuation and
reversion. Within each family they agree 95–100 %; between the families, 0 %. So a fixed
"2 of 3" is a coin weighted by how the trio was chosen. Across five kinds of market, the only
rule never below a coin flip was the one that lets **market memory choose the family**:

| Market | fixed trio | memory-conditional |
|---|---|---|
| mean-reverting | 29.5 % | **51.3 %** |
| drift + pullbacks | 81.9 % | **80.8 %** |
| steady drift | 65.2 % | **66.5 %** |

## The panel

```text
 TF    TREND      REGIME           SCORE  SIGNAL          HOLDS
 M5    UP 12      Trending Wild    2/2    BUY 64% (18)    2 bars (1-4)
 M15   FLAT 4     Random Normal    1/1    NO SIGNAL       --
 M30   DOWN 7     Ranging Quiet    1/1    SELL 51% (30)   --
```

`SCORE` is **agreement, never a win rate**. The percentage beside a call is the share of
replayed past situations that reached their measured target, with its sample size.

## The nine switches, all on/off

`Autotrading (master switch)`, `Allow M5 autotrade`, `Allow M15 autotrade`,
`Allow M30 autotrade`, `Trailstop enable`, `TP1 partial + TP2`, `Diary details`, `Tweak`,
`Minimum lot`.

No period, band, threshold or session time is ever an input.

## Only three timeframes

M5, M15 and M30. On any other chart the panel says `OUT OF RANGE` in red, reads nothing, plans
nothing, sends nothing and writes nothing.

## The two rules that beat all the others

The EA may do **less** than the plan says, never more. And it may never print a number it cannot
compute honestly — `CALIBRATING`, `DATA WAIT` and `Unclear` are real states, not embarrassments.
