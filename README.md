# OldMate — conventional autotrading for MT5

**Status: plan only. No EA file exists yet.** Nothing here can be compiled or attached, and
nothing here should go near a live account until it is built and has passed the checks in
[oldmate.md](oldmate.md) section 17.

OldMate is the conventional sibling of [Automate](https://github.com/hamamun/Automate) — same
family, same discipline, same refusal to print a number it cannot compute — built so the two can
be **run side by side and compared honestly.** That comparison is the reason it exists. The
differences are deliberate and few: the readings, and how they are calibrated.

## The documents

| File | What it is |
|---|---|
| [oldmate.md](oldmate.md) | the plan: the ten promises and where each is answered, the lanes, the self-configuration engine, the forward view, the rules, the panel, the stages, the validation |
| [indicators.md](indicators.md) | the indicator record: each classic in its modern form, formula-level procedures, the spares, the reject pile, and the tests that must pass first |

## Ten promises

1. It works out **what kind of symbol** it is on, from the broker's own data.
2. It says whether the market is **open or closed**, and when it next opens.
3. It says the **session**, marked as an estimate when it cannot be verified.
4. It runs on **M5, M15 and M30** only — on any other chart it says `OUT OF RANGE` and trades nothing.
5. It **sets its own parameters** from the symbol and the context: units from the instrument,
   thresholds from each reading's own distribution, speed from how clean the move is.
6. **M5 scalps, M15 is short-term, M30 is intraday** — real differences in horizon, structure
   window, deadband, spread gate and patience, not just labels.
7. It declares **TREND, REGIME, SCORE and SIGNAL**, as Automate does.
8. On a call it plans **entry, target, stop and lot** — all calculated, and refused by name when
   they cannot be.
9. It **autotrades** from that plan when the switches and the terminal both allow it.
10. It keeps **today's and the all-time record**, and a diary, per lane and per reading.

## The panel, as planned

```text
 TF    TREND        REGIME           SCORE  SIGNAL              HOLDS
 M5    UP 12        Trending Wild    3/3    BUY 64% (18)        2 bars (1-4)
 M15   FLAT 4       Random Normal    2/3    NO SIGNAL           --
 M30   DOWN 7       Ranging Quiet    1/3    NO SIGNAL           --
```

`SCORE` is **agreement, never a win rate.** REGIME describes the weather and never vetoes a call.
Nothing is a tuning knob.

## The three readings

| Reading | Classic name | Modern form |
|---|---|---|
| Momentum | MACD | divided by the instrument's own volatility, so one reading means the same on every symbol |
| Push | ADX / DMI | Wilder's own smoothing, and strength judged against its own history instead of a written-down 25 |
| Position | Bollinger | position inside the band ranked as a percentile, with the squeeze read from band width |

Everything else — units, thresholds, speed, warm-up, gates — is measured, not typed. How that
works, and what each part says when it cannot be measured, is [oldmate.md](oldmate.md) section 5.

## The eight inputs, all on/off

`Autotrading (master switch)`, `Allow M5 autotrade`, `Allow M15 autotrade`,
`Allow M30 autotrade`, `Trailstop enable`, `Diary details`, `Tweak`, `Minimum lot`.

No period, band, threshold or session time is ever an input. That is not laziness — it is the
property that a new user cannot get wrong.

## Stages

| Stage | Adds | State |
|---|---|---|
| 0 | these documents, the measurement tools, the candidate comparison | **in progress** |
| 1 | discovery, classification, market state, next open, sessions, the timeframe gate, panel skeleton | not started |
| 2 | self-configuration, the three readings, TREND / REGIME / SCORE / SIGNAL, the per-reading record | not started |
| 3 | the plan: entry, stop, target, size, and its refusals | not started |
| 4 | sending, repricing, cancelling, the broker table, grading, today/all record | not started |
| 5 | trailing stop, TP1/TP2 | not started |

## The two rules that beat all the others

The EA is allowed to do **less** than the plan says, and never more. And it is never allowed to
print a number it cannot compute honestly — `CALIBRATING`, `DATA WAIT` and `Unclear` are real
states, not embarrassments.
