# OldMate — the plan

**Status: plan. No EA file exists, no code written.** This is the whole EA, not one part.

OldMate is the conventional sibling of [Automate](https://github.com/hamamun/Automate). Same
family, same panel discipline, same refusal to invent a number — but it reads the chart with the
instruments traders already trust, calculated correctly and calibrated the modern way, so that
the two can be **run side by side and compared honestly.** That comparison is the reason
OldMate exists.

**Hard rules:**

1. **No fallback.** If a number cannot be measured honestly, the lane says so and waits. Nothing
   is defaulted, borrowed from another context, or quietly guessed.
2. **No fabrication.** Every value is either computed from closed bars, read from the terminal,
   or counted from a recorded history. Nothing is asserted as a probability that is really an
   agreement count.
3. **Correct instrument for the correct job.** No invented formulas, no "just multiply and
   divide until it looks plausible". Each calculation uses the accepted definition, stated in
   section 12, and is reproducible by hand from exported bars.
4. Real money will run on this. Refusing a trade costs nothing. Pretending costs the account.

---

## 0. Your ten points, and where each is answered

| # | What you asked for | Where |
|---|---|---|
| 1 | Understands what type of symbol it is | §2.1 |
| 2 | Says market open or closed, and when it opens | §2.2 |
| 3 | Says the session | §2.3 |
| 4 | Only M5 / M15 / M30; anything else says out of range | §3 |
| 5 | Sets its own indicator parameters from symbol and context | §5 |
| 6 | M5 scalps, M15 short-term, M30 longer | §4 |
| 7 | Declares TREND / REGIME / SCORE / SIGNAL | §6 |
| 8 | On a signal, shows entry / TP / SL / lot, all calculated | §8 |
| 9 | Autotrading from the signal | §9 |
| 10 | Today and all-time score, and a diary | §11 |
| — | "Must be able to see forward vision" | §7, answered honestly |

---

## 1. The idea in one paragraph

Attach it to a chart of any symbol on M5, M15 or M30. It works out the symbol, the broker's
rules, the account type, whether the market is open and when it opens, which session it is, and
how this particular instrument behaves — by itself. Then, on three lanes, it reads momentum,
push and position with the classics, shows all three separately, adds them into a score, and
calls BUY or SELL only when two or three agree. Per lane it plans one trade: a structural stop,
a target measured from what that lane has actually delivered before, and a size a fixed small
share of equity can afford. It sends the plan only when the switches and the terminal both allow
it, cancels it when it dies, and grades every call and every closed trade into a file so that
each of its three readings can be kept honest.

## 1.1 What is kept from Automate, deliberately

The comparison is only meaningful if the two EAs differ in one place — the **readings and their
calibration** — and not in twenty. So these are identical by design:

- three independent lanes, one idea per lane, one target and one stop, no partials in v1
- discovery of symbol, broker rules, account, market state, sessions
- everything computed on **closed bars only**
- a reading is never a permission: `WAIT: spread` never cancels a valid BUY
- plan and order are separate records, shown in separate tables
- context never vetoes a signal
- a diary that only ever watches, one file per account and symbol
- the panel sizes itself to its own text; no X/Y/width/font inputs
- the same refusal vocabulary, so the two panels can be read next to each other

## 1.2 What differs, and why

| | Automate | OldMate |
|---|---|---|
| The readings | regression slope, 2-bar move, swing structure | MACD-V, directional movement (Wilder), envelope position |
| Thresholds | none — all in units of a typical bar | none — all as percentiles of the reading's own history |
| Speed | fixed windows | adapts to how clean the move is, inside fixed bounds |
| REGIME | standardised drift over an equalised span | market persistence (Hurst family) cross-checked by a variance ratio, plus a volatility percentile |
| Target | replayed analogues | replayed analogues **of the same grade**, plus the counted share that reached it in time |
| Graded | the lane, and the trade | the lane, the trade, **and each reading separately** |
| Chart timeframe | any | **only M5, M15, M30** — anything else is out of range |

The last two rows are the substance. Automate can tell you a lane has been right twice today.
OldMate can tell you *which of its three readings* has been lying to it — and it refuses a
timeframe it was not designed for.

---

## 2. What it works out for itself

### 2.1 The symbol, and what kind of thing it is

Read from the terminal, never guessed from a name:

- exact symbol including any suffix, digits, tick size, contract size, volume minimum / maximum
  / step, stops level, freeze level, permitted order types and expiry modes, calculation mode
- broker and server, account currency, equity, free margin, permission to trade, and whether the
  account is **hedging** or **netting** — which decides whether two lanes may hold opposite
  positions at once
- the instrument's own size: the **median** size of an ordinary bar (median, not mean — one news
  candle must not redefine the instrument), and the median spread for the current hour of the
  server's day, sampled live
- a best-effort class: metal, forex, index, energy, crypto, stock, or `Other/Unknown`, from the
  broker's own metadata and description. If it is unclear it says `Other/Unknown` — it does not
  block, and it does not guess.

**What the class may and may not do.** It may raise a **floor** (a minimum deadband, a wider
default spread gate on a crypto weekend) and it may set a **gate** (this class refuses when the
quote is stale). It may never choose a different strategy, a different reading, or a different
threshold logic. Automate's decision, kept: otherwise forex and gold become two EAs sharing a
file and the comparison is worthless.

### 2.2 Market open, closed, and when it opens

- Uses the broker's own published trade sessions for that symbol, plus trade mode, server time,
  tick freshness and the terminal's trade permission. Handles multiple sessions per day, daily
  breaks, and sessions crossing midnight.
- States one of, by name: **Market open**, **Market closed until 20:59 (in 1h 24m)**,
  **Disconnected**, **Stale quote**, **Trading unavailable**, **Market status unknown**.
- **Never** reports "closed" for a problem that is not a closure. A dead connection is a dead
  connection; an unclear state is `unknown` and holds new entries with the reason visible.
- A timer repaints the panel even when no tick arrives, so a closed market still shows a live
  clock rather than a frozen panel.
- `Trading unavailable` covers the terminal's Algo Trading button being off: shown in red, not
  swallowed.

### 2.3 Session

Asia/Tokyo 09:00–18:00, Europe/London 08:00–17:00, America/New York 08:00–17:00, each in its
own local time, with overlaps named. The label is **informative, not a filter** — the broker's
schedule decides availability, not a city's office hours.

Where the UTC offset cannot be independently verified (the Strategy Tester is the common case,
where `TimeGMT()` is simulated server time), the label is marked `(est.)` or shown as
`Session: unknown`. It is never invented. An unknown session never blocks a valid call.

---

## 3. The timeframe gate

OldMate is designed for three timeframes. It **refuses** the others rather than pretending.

| Chart timeframe | Behaviour |
|---|---|
| **M5, M15, M30** | normal: all three lanes run, whichever of the three the chart is on |
| anything else (M1, M10, H1, D1, Renko, ticks…) | panel shows `OUT OF RANGE — attach to M5, M15 or M30`, in red |

Out of range means: no readings are claimed, no plan is built, **no order is sent or modified**,
no resting order of this EA is touched (it is not ours to judge from a timeframe it was not built
for), and nothing is written to the record. The one thing it does is keep offering to show the
market status, so the panel is never blank.

Why refuse instead of scaling to the chart: the lane personalities in section 4 are not a
formality — a scalping lane and an intraday lane differ in horizon, structure window, deadband
and speed. Running the same logic on an H1 chart would silently produce a fourth personality
nobody designed or measured. Refusing is the honest option and it is one line of the panel.

---

## 4. The three lanes and their personalities

All three lanes run at once regardless of which of the three timeframes the chart is on. Each
lane has its own role, and the role changes real numbers, not just labels.

| | **M5 — scalping** | **M15 — short-term** | **M30 — intraday** |
|---|---|---|---|
| Planning horizon | 4 bars ≈ 20 min | 6 bars ≈ 90 min | 8 bars ≈ 4 h |
| Structure window (for stops and levels) | 36 bars | 48 bars | 72 bars |
| Deadband width | tightest — small moves are the trade | middle | widest — noise is not the trade |
| Percentile lookback | shortest, so it adapts in minutes-to-hours | middle | longest, so it reflects the session's character |
| Speed of the adaptive smoothing | fastest allowed | middle | slowest allowed |
| Spread gate | strictest — the spread is a large share of a scalper's target | middle | most forgiving |
| Typical target | smaller, achieved sooner | middle | larger, given more time |
| Patience for a limit | 15 min (3 × 5) | 45 min | 90 min |
| Risk per idea | 0.50 % equity | 0.50 % | 0.50 % |

What is the same on every lane, on purpose: the three readings, the score rule, the stop logic,
the target measurement, the sizing rule. A lane is a **different working window on the same
method**, not a different method. Automate's D1 decision, kept and re-justified here.

**Portfolio limit.** Three lanes at 0.50 % each is 1.50 % of equity at risk if all three are
wrong at once. That is the cap: total open risk across lanes may not exceed 1.50 % of equity. A
fourth idea waits. The cap is checked against the **stops actually resting at the broker**, not
against the plan, because the broker's stop is the only one that executes.

---

## 5. The self-configuration engine

This is requirement 5, and it is the part most easily faked. Fake would be: scan twenty period
values, keep whichever made the most money last month. That is curve-fitting and it dies in the
next month. Real, and what is built here, is three separate mechanisms:

### 5.1 Three kinds of number, and which kind adapts

| Kind | Examples | Adapts? | Why |
|---|---|---|---|
| **Identity** | MACD 12 / 26 / 9, ATR window 26, directional-movement 14 | **no** — canonical, documented | these lengths *are* the indicator. A chart the owner looks at uses 12/26/9. If the EA quietly used 9/19/7, the panel would describe a chart nobody can see, and the comparison with Automate would be meaningless |
| **Measurement unit** | the size of an ordinary bar, the tick, the spread baseline | **yes** — always, from this symbol | this is what makes one file work on gold and on EUR/USD |
| **Threshold** | what counts as "stretched", "strong", "quiet", "agreeing" | **yes** — from the reading's own distribution | this is what removes every tuning input |

### 5.2 The measured unit

`unit` = the median absolute close-to-close change over the calibration window, floored at one
tick. Median, because one news candle must not redefine the instrument. Every deadband in the
file is a fraction of `unit` times the square root of the horizon (a move over four bars is
bigger than over one, and the square root is the honest scaling for a wandering series), with a
floor of one tick. No threshold is ever a bare number.

### 5.3 The percentile thresholds, and the honesty condition

A reading is not compared to a written-down level. It is compared to **where it sits in its own
recent distribution** on this symbol, this timeframe, this session.

Two conditions make that honest rather than decorative:

1. **Enough samples.** A 5 % threshold needs a distribution large enough for a 5 % cut to mean
   anything. The window is computed per lane from the horizon and the lane's role, and the
   sample count is displayed on hover next to every percentile.
2. **Too few samples is not a small threshold.** If the history is shorter than the minimum, the
   reading votes **neutral** and the cell says `CALIBRATING`. It does not fall back to 70/30. A
   lane with an uncalibrated reading cannot reach `2/3` and therefore cannot trade. This is rule
   1 applied literally.

### 5.4 The adaptive speed

The one thing that genuinely should change with the market is how fast an indicator reacts. That
is measured, not fitted: the **efficiency ratio** — net move divided by the total ground covered
— says how clean the current move is, and it sets the smoothing speed between two **fixed,
documented bounds** (Kaufman's classic fast/slow constants). Clean move: react quickly. Chop:
smooth heavily. The name, the levels and the reading of the indicator do not change; only its
responsiveness does.

A caveat recorded rather than hidden: on a pure random series the efficiency ratio sits low, so
the adaptive version behaves like a slow fixed one. That is the intended behaviour, and it is
one of the stage-0 measurements.

### 5.5 The full derivation table

| Parameter | Comes from | If it cannot be measured |
|---|---|---|
| indicator identity lengths | canonical: 12 / 26 / 9, 26, 14 | never — they are constants |
| effective speed | efficiency ratio over the lane's structure window, inside fixed bounds | votes neutral, `CALIBRATING` |
| measurement unit | median absolute change over the calibration window | lane `DATA WAIT`, no plan |
| deadbands | unit × √horizon, floor one tick | lane `DATA WAIT` |
| percentile thresholds | the reading's own distribution, per lane | reading votes neutral, `CALIBRATING` |
| volatility state | percentile of current volatility in its own history | cell shows `--` |
| persistence state | DFA Hurst with an R/S cross-check | `Unclear` when the two disagree |
| structure window | lane role: 36 / 48 / 72 bars | lane `DATA WAIT` |
| stop buffer | larger of one tick and the live spread | no quote, no plan |
| spread gate | multiple of this hour's median spread, live-sampled | gate inactive until enough samples, and the cell says `spread: no baseline` |
| target distance | replayed analogues of the same grade and direction | `WAIT: too few like this to measure` |
| size | 0.50 % of equity, converted by MT5's own money calculation | `WAIT: cannot size` |
| warm-up | computed from the longest window in use, plus the smoothing seeds | lane `DATA WAIT`, and the panel says how many bars are still needed |
| sessions | the broker's own trade table | `Session: unknown` |

**Every row's failure mode is a state on the panel, not a number.** That is the whole of rule 1.

### 5.6 Offline calibration is allowed; online fitting is not

Stage 0 will scan a modest grid of settings **on recorded data, once**, and report whether any
non-canonical setting is genuinely better. If one is, it becomes a **documented constant with the
measurement beside it** — not a live knob, and not a hidden search running on the owner's
account. A search that re-fits every week would make OldMate unfalsifiable, and the comparison
against Automate would be worthless within a month.

---

## 6. The four declared facts: TREND, REGIME, SCORE, SIGNAL

Requirement 7. Three readings produce four declarations, exactly as Automate's panel does, so
the two can be read side by side.

### 6.1 The three readings, each voting up / down / neutral

| Reading | Built from | Votes up when |
|---|---|---|
| **Momentum** | MACD in its volatility-normalised form (MACD-V) | the reading is above zero by more than its own neutral band, and its signal line agrees |
| **Push** | directional movement (ADX / DMI), Wilder-correct | the plus and minus directional lines are meaningfully apart, and the index says the separation is worth something *for this symbol* |
| **Position** | the volatility envelope, read as a percentile position | price is in the upper part of its own recent positional distribution in a market that is not reverting, or the lower part mirror-wise |

They are shown separately and **never multiplied**. A product hides which one disagreed, and
which one disagreed is the only diagnostic a trader can act on.

Abstention is a real state. Without it, `2/3` could never occur and the score would collapse into
a two-state guess.

### 6.2 SCORE

The sum of the three votes, −3 … +3, displayed as `3/3`, `2/3`, `1/3`, `0/3` and their negative
mirrors. It is **agreement, never a win rate.** Two or more in one direction is a call.

### 6.3 SIGNAL

`BUY` or `SELL` when the score is ±2 or ±3, otherwise `NO SIGNAL`. The cell also carries the one
honest forward number available: the counted share of historical situations of the same grade, on
this lane, that reached the measured target before an equal-sized stop within the horizon — with
the sample count beside it, withheld below the minimum. See section 7.

An optional `EARLY` preview may show what the forming bar would say. It is dimmed, marked
`EARLY`, and can never send an order.

### 6.4 TREND

The direction the score points, with a deadband so that `FLAT` is a real state, plus **how long
it has held**: `UP 12 bars`, `FLAT 4 bars`, `DOWN 7 bars`. The deadband is in units of the
measured bar size, so `FLAT` means the same thing on gold and on a currency.

### 6.5 REGIME

Two measured words, side by side, because two different things are being described:

`Trending Wild` · `Random Normal` · `Ranging Quiet`

- the **first** word is market memory: does this series push, wander, or snap back, from a
  detrended-fluctuation estimate of the Hurst exponent, cross-checked by a variance ratio
  (`Trending` above the upper band, `Ranging` below the lower, `Random` between, `Unclear` when
  the two estimators disagree)
- the **second** word is volatility against its own history: `Quiet`, `Normal`, `Wild`

REGIME describes the weather. It never vetoes a call. If it ever gains teeth, that is a separate
decision with its own measurement.

### 6.6 What each cell must be able to say when it cannot answer

`CALIBRATING`, `DATA WAIT`, `Unclear`, or `--`. Never a plausible-looking number. There is no
fifth option in this EA.

---

## 7. The forward view — "seeing ahead" without inventing anything

You asked for forward vision. It deserves a straight answer rather than a promise.

**What cannot be done, by anyone:** naming the bar a turn will happen, or the price at 15:00.
Automate refused this in writing and was right to. A panel that prints `target will be hit at
14:22` is lying, because the number came from a straight line drawn through noise.

**What can be done, and is what "forward vision" means in this EA** — four numbers, each counted
from this lane's own recorded history, each with its sample size, each withheld when the sample
is too small:

| # | The question it answers | How it is produced | Shown as |
|---|---|---|---|
| 1 | **How much longer does this state last?** | the lane's own completed runs of the same state, conditioned on how long the current one has already run — median bars remaining plus the interquartile range | `HOLDS 2 bars` in SIGNAL/TREND, `(1–4)` in hover, `--` when too few runs outlived this age |
| 2 | **Will it reach the target in time?** | among historical analogues of the same grade, direction and stop size, the counted share that reached the measured target before the stop within the horizon | `64% (18)` beside SIGNAL, withheld under the minimum count |
| 3 | **How long until the target, if it goes?** | the same analogue set, the distribution of bars taken by those that did reach it; offered only when the lane's measured travel per bar points toward the target | `est. 3–5 bars`, or `unclear` |
| 4 | **How far does a bar travel in this state?** | median favourable and adverse travel per bar, in this state, on this lane | hover on TREND |

Every one of them is labelled an estimate where it is one, every one carries its sample size, and
any of them being unavailable never blocks a valid trade — it just says `unclear`, which is the
truth.

This is the honest version of "predict accordingly": the EA reports what has **actually happened**
in situations it judges to be the same, and it refuses to extrapolate a line. If in the future we
add a proper model with out-of-sample calibration, it must beat this simple counted version on
its own data before it replaces it.

---

## 8. The plan: entry, stop, target, size

Requirement 8. Shown as a plan first; the plan is what the EA *would* do, the order is what the
broker *has*.

### 8.1 Entry

| Score | Entry |
|---|---|
| **3/3** | market order at a fresh quote — Ask to buy, Bid to sell |
| **2/3** | resting limit at a confirmed pullback: the nearest **already-confirmed** turning point on the correct side, snapped to the price grid, never a price the market has already passed |
| 1/3 or less | no plan |

### 8.2 Stop

Behind a **confirmed** three-bar turn on the correct side — the confirming bar already closed —
plus a buffer of the larger of one tick and the live spread. The level used for a limit entry
cannot also be the invalidation level; the stop goes beyond it.

No turning point within the structure window means `WAIT: no swing to hide the stop behind`. A
stop is never widened to make a trade fit, and the broker's minimum distance is checked against
the actual ticks, not assumed.

### 8.3 Target

Measured, never a volatility multiple. The lane replays several hundred past moments, keeps the
ones that looked the same **as of that bar** — same grade, same direction, a stop of the same
size behind them — and records how far price actually ran in the trade's favour before an
equal-sized stop took it out. The target is a conservative cut of that distribution, not its
average, so it is a distance this lane has repeatedly delivered.

Two caps, in order: a confirmed opposing turn closer than the measurement caps it just before
that turn; and the entry-to-target distance must clear the current spread by a set multiple, or
the panel says `WAIT: target does not clear spread`.

A measurement of **zero** is not a small target — it means the typical case was stopped before it
moved this way at all. `WAIT`, with that reason named.

### 8.4 Size

0.50 % of current equity per idea, converted to lots by **MT5's own money calculation** for this
symbol and this stop distance — never by hand arithmetic, never by an assumed pip value. Rounded
**down** to the broker's lot step. If the budget cannot buy the minimum lot, the idea is refused
and the panel says so, unless the owner ticked **Minimum lot**, which is the single place a plan
may exceed the risk budget and it is visible on the panel when it happens.

### 8.5 When it gives up

| Reason | Checked |
|---|---|
| the plan died — `WAIT`, opposite call, or no call | closed bar |
| the plan upgraded to 3/3 and now wants a market entry | closed bar (cancel only; the market entry waits for a later bar, because a partial fill can race a delete) |
| switches turned off, or the terminal withdrew permission | every second |
| three lane-periods old (15 / 45 / 90 minutes) | every second |
| the market walked through the price it rests at | every second |

Nothing is called cancelled until the broker confirms. An open position is never touched: its
stop and target sit at the broker.

---

## 9. Autotrading

Requirement 9. The chain is: **signal → plan → permission → order**, and each link can stop it
and say why.

- **Master switch** off: nothing is sent by any lane. **Lane switch** off: that lane places
  nothing and its resting limit is cancelled; its open position is untouched.
- **Terminal veto**: with MT5's Algo Trading off, nothing can be sent, and the panel says
  `Autotrading: ON — terminal is blocking it` in red. It never fails quietly.
- **Attaching sends nothing.** The first order on a lane waits for one closed bar with the EA
  running, so attaching a chart is never itself an instruction to trade.
- **One idea per lane**, held by a latch on the grade and direction, so a valid signal does not
  re-enter on every bar. The latch releases when the idea changes, when a lane is switched off
  and back on, and **when a trade closes in profit**. A losing close does not re-arm: buying back
  the level that was just wrong on the same evidence is how one bad bar becomes five.
- **Netting vs hedging**: on a netting account two lanes cannot hold opposite positions. The
  slower lane yields to the faster one and the panel says which lane yielded and why.
- **Never**: opening a second idea in a lane, converting a limit into a market order, chasing
  price by repeated modification, or touching a position's stop or target.

---

## 10. The panel

Requirement 7–10 visible in one place. Every line starts with one space; the panel sizes itself
to the text it draws; no X/Y/width/font inputs. Exact character anchors are locked in stage 1 and
written into the README then.

```text
 OLD MATE   XAUUSDm  |  Metal  |  Hedging  |  Equity 1000.00 USD
 MARKET OPEN | London (est.) | Spread 24 pts (normal) | Closes 20:59 (1h24m)     Autotrading: ON

 TF    TREND        REGIME           SCORE  SIGNAL              HOLDS
 M5    UP 12        Trending Wild    3/3    BUY 64% (18)        2 bars (1-4)
 M15   FLAT 4       Random Normal    2/3    NO SIGNAL           --
 M30   DOWN 7       Ranging Quiet    1/3    NO SIGNAL           --

 TF   SIDE  ENTRY     LOT   TARGET               STOP                 STATE
 M5   BUY   2461.35   0.02  2467.10  (575)       2458.90  (245)       READY
 M15  --    --        --    --                   --                   WAIT: spread
 M30  --    --        --    --                   --                   NO SIGNAL

 AT THE BROKER (USD)                                              Autotrading: ON
 M5   LONG  Entry 2461.35    Lot 0.02    P/L +2.14
      Bid 2461.10   Ask 2461.30   To target 575 pts   est. 3-5 bars
      Target 2467.10 (+11.50)   Stop 2458.90 (-4.90)   TP1 --  TP2 --
 M15  none
 M30  none

 RECORD  today   calls 2R/1W   trades 1W/0L        M5 1R/0W   M15 1R/1W   M30 0R/0W
         all     calls 38R/31W trades 4W/3L        M5 12R/9W  M15 14R/11W  M30 12R/11W
 Saved | Tweak: off | Last closed bar 14:35 server
```

| Word | Means exactly |
|---|---|
| `TREND` with a bar count | the aggregate direction and how long it has held |
| `REGIME` two words | memory (Trending / Random / Ranging / Unclear) and volatility (Quiet / Normal / Wild) |
| `SCORE` | how many readings agree — **agreement, never a win rate** |
| `SIGNAL` with `%` and `(n)` | the call, and the counted share of same-grade analogues that reached the target in time, with its sample size |
| `HOLDS` | how much longer this state typically lasts, from its own runs, with the middle range |
| `STATE` | READY, WAIT (with the reason), or NO SIGNAL — what the *plan* is |
| `P/L` | the broker's profit plus swap, in the account's own currency |

Hover text explains every cell in words: which reading disagreed, why a lane is waiting, the
sample count behind a percentage, and what the measurement refused.

---

## 11. The record

Requirement 10. One file per account and symbol. It **only ever watches** — it sends nothing, and
nothing it stores is read back to change a reading (the one bounded exception is the `Tweak`
switch, which is declared and does nothing in version 1).

### 11.1 What is counted

| Line | Written when | Contains |
|---|---|---|
| **a call** | three bars after it was made | lane, grade, direction, and whether the direction actually happened |
| **a reading** | with the call above | which of the three was right, which abstained — this is what keeps each reading honest |
| **a state run** | when a TREND or REGIME run ends | its length, so durations can be estimated |
| **a trade** | when a filled trade closes | side, lot, and the **money** actually gained or lost — profit + swap + commission on every deal of that position |

### 11.2 How it appears

```
 Diary   today   S2/S1/S0       W1/W0/W0       L0/W1/W0
         all     S38/S31/S12    W4/W2/W1       L1/W3/W0
 Health: saved | Tweak: off
```

`S` = calls checked (right / wrong / flat), `W` = trades closed in profit, `L` = trades closed at
a loss, each after costs. Counts are per lane, are read back from the file at attach, and survive
a restart. A trade closed exactly flat is written down and counted as neither.

Two records, not one, exactly as Automate: **the plan**, rebuilt every closed bar, and **the
trade**, which is what the broker has. That is what lets the panel say `WAIT` while an old
position is still running.

---

## 12. Correct process — the rules behind every number

Requirement: no "just multiply and divide". Each of these is a fixed procedure, and each will be
listed in the file next to the code that does it, so a reader can check it against the source.

| Calculation | The correct procedure, and what is refused |
|---|---|
| **True range** | max(high − low, │high − previous close│, │low − previous close│). Gaps count. `high − low` alone is wrong and is not used |
| **Wilder smoothing** (RSI, ATR, DMI) | weight 1/n with a simple-average seed, not an exponential average with weight 2/(n+1). The warm-up needed for convergence is computed and enforced, not wished away |
| **EMA seeding** (MACD) | seeded by a simple average of the first n values, so the first printed value is not an artefact |
| **MACD-V** | (fast EMA − slow EMA) ÷ ATR over the slow window × 100. The ATR uses Wilder smoothing, so the denominator and the numerator describe the same window |
| **Envelope position** | position inside the band using the population standard deviation, Bollinger's own convention; then **ranked as a percentile** before it is compared to anything |
| **Percentiles** | empirical quantile with linear interpolation, a stated minimum sample count, and no interpolation across a state boundary. The count is visible on hover |
| **Robust centre and spread** | median and median absolute deviation, not mean and standard deviation, for bar sizes and spreads — fat tails must not move a threshold |
| **Efficiency ratio** | │net move│ ÷ Σ│step│ over the lane's window, bounded 0–1. Used only to set speed |
| **Hurst exponent** | detrended fluctuation analysis as the primary estimator with rescaled range as a cross-check; disagreement beyond a stated tolerance reads `Unclear`, never an average |
| **Variance ratio** | long-horizon variance ÷ short-horizon variance, on the same window, as the check on the Hurst word |
| **Lot size** | MT5's own money calculation for this symbol and this stop. Refused, never estimated by hand |
| **Price levels** | snapped to the tick grid and digits, checked against the broker's minimum stop distance and freeze level |
| **Quote sides** | Ask for a buy entry and a sell exit, Bid for a sell entry and a buy exit. One side is never used for both |
| **Grading money** | profit + swap + commission, summed over every deal of that position |
| **History** | only bars with index ≥ 1 (the forming bar is never read by the vote path), and only values available at that bar in any replay |
| **Warm-up** | computed from the longest window in use plus the smoothing seeds; the lane reports how many bars it still needs |

**On volatility, a decision I am making explicit** because Automate banned it outright: volatility
is used here as a **unit** — the denominator of MACD-V, the width of the envelope, the size of the
true range. It is **never** used as a target or a stop multiplier. The target is a measured
distance; the stop is a structure plus a buffer. That distinction is the difference between
normalising a measurement and inventing a trade.

---

## 13. The switches

Eight, all on/off, all safe at their default forever. No period, band, threshold or session time
is ever an input — section 5 explains what replaces them.

| Input | Default | What it does |
|---|---|---|
| `Autotrading (master switch)` | on | the one switch that must be on for any order to be sent |
| `Allow M5 autotrade` | on | that lane may place, reprice and cancel |
| `Allow M15 autotrade` | on | same, M15 |
| `Allow M30 autotrade` | on | same, M30 |
| `Trailstop enable` | on | declared now; the engine arrives in stage 5 |
| `Diary details` | on | opens the second panel; the record is written either way |
| `Tweak` | off | arms one bounded self-adjustment; **declared and inert in version 1** |
| `Minimum lot` | off | clamp a size up to the broker's minimum instead of refusing the idea |

Changing any of them restarts the EA, which costs the in-memory run history for the first few
minutes — another reason the count stays at eight.

---

## 14. Decisions I am making on your behalf

You said these are mine to make. Here they are, with the reason, so they can be overturned
deliberately rather than by accident.

| # | Decision | Reason |
|---|---|---|
| A1 | **The three readings are MACD-V, directional movement, envelope position.** Adaptive RSI and adaptive Stochastic are measured spares that may take a slot if stage 0 shows they do better | three instruments that measure speed, push and stretch; the spares are the two most credible alternatives and testing them costs a day, not a month |
| A2 | **Volatility is a unit, never a target or stop multiplier** | otherwise the target becomes a guess wearing a number, and the Automate comparison stops being like-for-like |
| A3 | **Identity lengths stay canonical (12/26/9, 26, 14)** while units, thresholds and speed self-configure | the panel must describe the chart the owner is looking at; fitting lengths to history is curve-fitting and dies out of sample |
| A4 | **`Tweak` is inert in version 1.** The record observes and displays | a self-adjusting reading with one week of data is a coin being re-weighted by noise |
| A5 | **Out of range refuses, it does not scale** | a fourth personality nobody measured is worse than an honest refusal |
| A6 | **Total open risk capped at 1.50 %** across the three lanes | three lanes are three correlated bets on the same symbol, not three independent ones |
| A7 | **REGIME never vetoes, and no input ever exists for it** | an unmeasured veto deletes whole trading days silently |
| A8 | **Forward vision is counted, not predicted** | naming a turn bar is not possible; a counted share with a sample size is |

---

## 15. What will not be built

| Refused | Reason |
|---|---|
| anything that repaints or reads future bars | the popular 2024–25 kernel-smoothing family does this by default: history looks perfect, live trading does not |
| a "probability of winning" | agreement between correlated readings is not a probability |
| a predicted bar of the turn | section 7; a duration-so-far and a counted share is what can honestly be shown |
| machine-learning classification of the chart | unauditable; a closed trade could not be explained to its owner |
| a per-indicator input, or an input per timeframe | section 5; the whole point is that a new user cannot get it wrong |
| thirty indicators on a panel | three readable ones, and a record that proves each earns its place |
| a REGIME veto, or any unmeasured filter | section 6.5 |
| live re-fitting of parameters | section 5.6; it would make the EA unfalsifiable and the comparison worthless |
| ATR-multiple targets and stops | section 12 |
| closing a position on a clock, partial closes, trailing in v1 | one target, one stop, decided up front |
| trading on a timeframe other than M5 / M15 / M30 | section 3 |

---

## 16. Stages

| Stage | What it adds | Done when |
|---|---|---|
| **0** | these documents; the measurement tools; the candidate comparison | plan agreed, readings measured, spares decided |
| **1** | discovery, classification, market state, next open time, sessions, the timeframe gate, panel skeleton | the header is true on a live chart, on a closed market, on H1 (`OUT OF RANGE`), and with the terminal blocking trade |
| **2** | the self-configuration engine, the three readings, TREND / REGIME / SCORE / SIGNAL, `HOLDS`, and the per-reading record | every value reproducible by hand from exported bars; no value changes on a re-read; `CALIBRATING` appears when it should |
| **3** | the plan — entry, stop, target, size — and every named refusal | a plan appears, and is refused for the right named reason, on demand |
| **4** | sending, repricing, cancelling, the broker table, trade grading, today/all record | a limit is placed, repriced, cancelled and graded on a demo account |
| **5** | trailing stop, TP1/TP2 | designed only after stages 1–4 have been silent for a week |

Standing rule: **the EA may do less than this plan says. It may never do something this plan does
not say.**

---

## 17. Validation

Run before the EA goes near a live account. Every result is printed, including the unflattering
ones.

1. **Preflight** — static checker clean; **0 errors, 0 warnings** in MetaEditor.
2. **No repaint** — every reading recorded at bar close, then recomputed from a cold start ten
   bars later; identical, bar for bar.
3. **Are the three readings actually three?** An agreement matrix over long histories on several
   symbols. No pair may agree more than roughly nine times in ten; a redundant reading is
   replaced by a spare.
4. **Direction test** — sign at bar *t* against the next 4 / 6 / 8 bars, on real and synthetic
   series. Coin-flip gets recorded as coin-flip.
5. **Swap of eras** — any calibration fitted on one period and tested on another, in both
   directions. A gain that reverses is noise and is deleted.
6. **Threshold calibration** — a 5 % threshold must fire about 5 % of the time; a check that has
   never been done on most commercial indicators, and the reason most of them mislead.
7. **Lane separation** — three lanes on one series must agree on the regime word and differ
   sensibly on the readings; persistent disagreement is a bug, not a market condition.
8. **Refusal test** — shallow history, closed market, stale quote, wide spread, minimum lot too
   large, terminal blocking, wrong timeframe: each produces its own named refusal, never a
   silent nothing and never a fake number.
9. **Cold start** — delete the record, restart mid-position, restart mid-limit: the EA reconciles
   with the broker, not with its own memory.
10. **Demo week**, then small live size, before anything larger.

---

## 18. Open questions for you

| # | Question | Default if unanswered |
|---|---|---|
| Q1 | Risk per idea: keep 0.50 % of equity, or a different fixed figure? (Still internal, not an input) | 0.50 %, cap 1.50 % |
| Q2 | `Diary details` default on or off? It opens a second panel on the chart | on, since you want the record visible |
| Q3 | On a netting account, does the slower lane always yield? | yes, and the panel names the lane that yielded |
| Q4 | Trailing stop and TP1/TP2 — wanted at all, or is one target and one stop the whole product? | designed in stage 5 only |
| Q5 | Do you want the `EARLY` (forming bar) preview shown, dimmed, or left out entirely? | shown dimmed, never tradable |

---

## 19. References

- **MACD-V, volatility-normalised momentum** — Alex Spiroglou, 2022. Charles H. Dow Award, NAAIM
  Founders Award. The fixed scale that makes a zero-input panel possible.
- **Efficiency ratio / adaptive parameterisation** — Perry Kaufman (KAMA, 1995), Chande's VIDYA.
  The correct way to let speed adapt without letting the identity drift.
- **Percentile-based thresholds** — current practice replacing fixed 70/30 and 25-type levels.
- **Hurst exponent and variance ratio** — long-established persistence measures, now the standard
  regime core; detrended fluctuation analysis is the more robust estimator.
- **Wilder's smoothing** — *New Concepts in Technical Trading Systems*, 1978. The correct seeding
  of RSI, ATR and ADX, which platform copies get subtly wrong; MT5 ships two ADX variants.
- **The repainting trap** — the Nadaraya-Watson / kernel-smoothing family uses future candles in
  its default mode. Refused here for that reason alone.

Exact formulas, the rejected candidates, the spares and the source links: [indicators.md](indicators.md).
