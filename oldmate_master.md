# OldMate — the complete record

**One document: what the EA is, what it does, which indicators it uses and why, what was
measured, and what was rejected.**

`OldMate.mq5` — 3 438 lines, build `1.08`, preflight-clean (25 checks), arithmetic verified by a
Python mirror, and compiled twice in MetaEditor with every reported error fixed. What is still
missing is a clean compile and a week on demo — Part I §16 lists exactly what to look at.

OldMate is the conventional sibling of [Automate](https://github.com/hamamun/Automate). Same
family, same panel discipline, same refusal to print a number it cannot compute — built so the
two can be **run side by side and compared honestly.**

## How to read this

| Part | Answers |
|---|---|
| **Part I** | what the EA is, what it works out for itself, what it declares, how it trades and manages, what the panel says, and everything the checks caught |
| **Part II** | which conventional instruments it uses, in what modern form, the exact formulas, the spares that were measured and dropped, the reject pile, and the measurement record |

Sections number continuously from 1 to 26, so a cross-reference like "§24.3" means the same thing
wherever it appears.

Every number in this document is either produced by a script in `tools/` or was reported by the
compiler or by a live chart. Where the document and the file disagree, **the file is the truth and
this document is the bug** — Part I §16 records every occasion that has happened so far.

## Files and tools

| File | What it is |
|---|---|
| `OldMate.mq5` | the EA. Copy to `MQL5/Experts/`, compile with F7, attach to M5, M15 or M30 |
| `tools/reference.py` | the Python mirror of every calculation in the EA |
| `tools/selftest.py` | proves the arithmetic — Wilder seeding, gaps, scale-freedom, percentile calibration, memory separation, no repaint |
| `tools/choose_readings.py` | which conventional indicators are actually different from each other |
| `tools/combine_test.py` | which combination rule survives five kinds of market |
| `tools/preflight.py` | 25 static checks the compiler would otherwise catch |

```
python3 tools/preflight.py OldMate.mq5     # PREFLIGHT CLEAN
python3 tools/selftest.py                  # ALL CHECKS PASSED
```

## The two rules that beat all the others

The EA may do **less** than this document says, never more. And it may never print a number it
cannot compute honestly — `DATA WAIT`, `--` and `Unclear` are real states, not embarrassments.

---

# Part I — what OldMate is, and what it does
This part is the specification of the file as it stands, and the record of what the checks
changed on the way. Section 16 is the validation log; section 17 is the list of questions still
open with you.

OldMate is the conventional sibling of [Automate](https://github.com/hamamun/Automate). Same
family, same panel discipline, same refusal to print a number it cannot compute — built so the
two can be **run side by side and compared honestly.**

**Hard rules, unchanged and enforced:**

1. **No fallback.** A value that cannot be measured is reported as `DATA WAIT`, `--` or
   `Unclear`. No reading substitutes a written-down level for a missing one.
2. **No fabricated claim.** Agreement is not a probability. No forward number appears without
   its sample size.
3. **Correct instrument for the correct job.** Wilder smoothing is Wilder's, true range counts
   gaps, percentiles are empirical with a minimum count, the target is measured from outcomes
   rather than multiplied out of a range.
4. **The EA may do less than this document says. It may never do something this document does
   not say.**

Where this document and the file disagree, **the file is the truth and this document is the
bug** — and section 16 records every occasion that has happened so far.

---

## 1. The ten things you asked for, and where each is

| # | You asked for | Where it lives | State |
|---|---|---|---|
| 1 | understand what type of symbol it is | `ClassifySymbol`, `ApplyProfile` | built |
| 2 | say open or closed, and when it opens | `ReadSessions`, `IsOpenNow`, `RefreshMarket` | built |
| 3 | say the session | `SessionLabel` | built |
| 4 | M5 / M15 / M30 only, else out of range | `TimeframeAllowed`, panel gate | built |
| 5 | set its own parameters from symbol and context | §7, `UnitAt`, `LaneRankWindow`, `PctRank` | built |
| 6 | M5 scalps, M15 short, M30 intraday | `LaneHorizon`, `LaneStructWindow`, per-lane windows | built |
| 7 | declare TREND / REGIME / SCORE / SIGNAL | `UpdateLane`, panel | built |
| 8 | on a call, show entry / TP / SL / lot, all calculated | `BuildPlan`, `MeasureTarget`, `CalcLot` | built |
| 9 | autotrade from the signal | `SendPlan`, `TradeOnBar`, `ManageSecond` | built |
| 10 | today and all-time score, and a record | `RecordLoad`, `GradePending`, panel | built |
| — | forward vision | §12 — four counted numbers, each with a sample size | built |
| — | trailing stop, TP1/TP2, self-tweak | `ManageSecond`, `ApplyTweak` | built, not deferred |

## 2. What it works out for itself

- **The symbol**: exact name with suffix, digits, point, tick size, contract size, volume
  min / max / step, stops and freeze levels, filling mode, trade mode. Never guessed from a name.
- **The account**: company, server, currency, equity, and whether it is **hedging** or
  **netting** — which decides whether two lanes may hold opposite positions.
- **The instrument's size**: the **median** absolute close-to-close change over 20 bars,
  floored at one tick. This is the only "size of a normal move" the EA uses, and it divides the
  envelope width before that width is ranked, which is why one file behaves sanely on gold at
  3 500 and on EUR/USD at 1.08.
- **Its class**: metal, forex, index, energy, crypto, stock, or Other — from the broker's own
  metadata. **A class may set one gate or raise a floor. It never changes the strategy.**
- **Market state**: open, closed with the next opening time, disconnected, stale quote, trading
  window shut, or trading unavailable. See §3 — there is no longer an "unknown" state, because
  there is no longer an excuse for one.

## 3. Sessions, market status, and the timeframe gate

**MT5 publishes two session tables per symbol, and they answer different questions:**

| Table | Question it answers | Used for |
|---|---|---|
| `SymbolInfoSessionQuote` | when the broker is quoting | is the market **open** |
| `SymbolInfoSessionTrade` | when orders are accepted | may an order be **sent** |

Both are read and kept apart. They are frequently not the same, and either may be empty. That
distinction matters:

- no quote table and no trade table → the symbol is **not session-restricted** (crypto, for
  example) → `Market open (no session table)`, with connection, trade mode and quote freshness
  still gating every send;
- quotes flowing but the trade clock shut (gold after 23:00, for instance) →
  `Trading window shut (quote only)`, reported *before* an order is attempted;
- a broker that allows only one direction → `broker allows buys only` / `sells only`, and
  close-only is named the same way.

Closed markets carry the next opening time and how far away it is: a session table exists, so
"opens Monday 01:00 (in 2d 12h)" is counted, not guessed.

Session *labels* are Tokyo 09:00–18:00, London 08:00–17:00, New York 08:00–17:00 in their own
local hours, marked `(est.)` when the UTC offset cannot be independently verified. The label is
a convenience; **availability always comes from the broker's session table**, never from the
label.

**Only M5, M15 and M30.** On any other chart the panel prints, in red:

```
 OUT OF RANGE - attach to M5, M15 or M30
 Nothing is read, planned or sent on this chart.
 This chart: PERIOD_H1
```

No readings, no plan, no order, no record line, and no touching of a resting order. Refusing is
one line of panel; scaling a fourth personality nobody measured would be a silent strategy
change.

## 4. The three readings

| Panel word | Built from | Votes (exact rule) |
|---|---|---|
| **TREND** | MACD divided by its own volatility (MACD-V) | up when `MACD-V > 0` **and** `MACD-V ≥ its 9-signal` **and** `\|MACD-V\|` sits at or above the 60th percentile of its own last 300/400/500 readings; down mirrored |
| **PUSH** | directional movement, Wilder-correct | up when `+DI > −DI` **and** `ADX` is at or above its 55th percentile **and** the `+DI − −DI` separation is at or above its 55th percentile; down mirrored |
| **STRETCH** | position inside the volatility envelope | **fades**: at or above the 85th percentile of its own positional history votes **down**; at or below the 15th votes **up** |

Every one of them abstains most of the time — measured at **72.3 %**, **58.9 %** and **71.2 %**
of bars. Without abstention the score would be a two-state guess, and `2/3` could never occur.

**STRETCH is deliberately a reversion reading.** It is the one that disagrees with the other
two, and §6 is why it decides on its own when memory says the market is ranging and never
decides when the market is trending.

## 5. REGIME, and why it is not a veto

`REGIME` is two measured words, on every lane:

- **memory** — `Trending`, `Random`, `Ranging`, `Unclear`. A detrended-fluctuation estimate of
  the Hurst exponent on the lane's 320-bar window, cross-checked by rescaled range. If the two
  disagree by more than **0.12** the word is `Unclear` — never an average. The variance ratio
  over the same window is shown beside them in the details panel.
- **volatility** — `Quiet`, `Normal`, `Wild`: where the current envelope width sits in its own
  recent distribution, after the width has been divided by the measured unit.

It does not block a trade. It **chooses the reading family** (§6) — a far better use of it than
a veto, and one that earned the role by measurement rather than by preference.

## 6. The decision rule, and the measurement that forced it

Seven conventional indicators collapse into exactly **two** opinions: continuation and
reversion. Within each family they agree **95–100 %**; between the families, **0 %**. So a fixed
"2 of 3" is a coin weighted by how the trio happened to be chosen.

Across five kinds of market, the only rule never below a coin flip was the one that lets
**market memory choose which family listens**:

| Market | fixed trio, 2 of 3 | reversion only | **memory-conditional** |
|---|---|---|---|
| random walk | 50.3 % | 49.5 % | **51.5 %** |
| steady drift | 65.2 % | 48.9 % | **66.5 %** |
| momentum | 57.1 % | 44.1 % | **55.8 %** |
| mean-reverting | **29.5 %** | 69.5 % | **51.3 %** |
| drift + pullbacks | 81.9 % | **23.3 %** | **80.8 %** |

That is `DecideSignal`, exactly:

| Memory | Who decides | Entry type |
|---|---|---|
| `Ranging` | STRETCH alone — the fading reading | limit |
| `Trending`, `Random` | TREND and PUSH. Both agree → that way; one speaks → that way; they disagree → no signal | limit unless they agree |
| `Unclear` | TREND **and** PUSH, both speaking, in the same direction — nothing less | market if unanimous |

**A market order is sent only when `score == spoke` and at least two readings spoke** (`2/2` or
`3/3`). Everything else that has a direction rests at a limit. The honest consequence, stated
plainly: **one reading can open a trade** — in a trending market TREND alone at `1/1` is enough,
as a limit. That follows from the table above: requiring agreement is what scored 29.5 % on
mean-reverting markets.

`SCORE` is **agreement, never a win rate**. `±3` is impossible by construction — the two
families never agree — and the self-test asserts that it stays impossible.

## 7. The self-configuration engine

This is point 5 of your list, and the part easiest to fake. Fake is: scan twenty settings and
keep whichever made the most money last month. Real is this table.

| Kind of number | Examples | Adapts? | Why |
|---|---|---|---|
| **Identity** | MACD 12 / 26 / 9, ATR 26, directional movement 14, envelope 20 / 2σ | **no** | these lengths *are* the indicators on the owner's own chart. A quietly different set would describe a chart nobody can look at, and the comparison with Automate would be worthless |
| **Unit** | median 20-bar close-to-close move, one tick, this hour's median spread | **yes**, from the symbol and from live samples | the only reason one file works on gold and on EUR/USD |
| **Threshold** | what counts as strong, absorbing, or stretched | **yes**, as a percentile of the reading's own distribution | this is what removes every tuning input |
| **Calibration window** | 300 / 400 / 500 bars | **yes**, by lane role | a scalper must adapt within an hour; an intraday lane should reflect the session |
| **Gates** | spread gate, stop buffer | **yes**, by asset class | gold's spread is not forex's |
| **Speed** | smoothing constants | **no**, deliberately | adapting speed would change what the indicator *is*. The adaptivity lives in the thresholds, not in the smoothing |

When a percentile cannot be computed — fewer than **60** samples — the reading votes neutral,
the lane is not `ready`, and the panel says **`DATA WAIT`**. Because a silent reading cannot
reach a decision, **an uncalibrated lane cannot trade.** That is rule 1 applied literally.

There are **no deadbands** anywhere in this EA, and no hidden fallback level: every threshold in
the table above is a percentile of that reading's own recent distribution, and the only
written-down numbers are the four percentile cuts (60, 55, 85, 15), which say *where in the
distribution* to look, not what the indicator should be worth.

## 8. Entry, stop, target, size

- **Entry** — unanimous (`score == spoke`, at least two spoke) → market order at a fresh quote.
  Otherwise a resting **limit at the nearest already-confirmed three-bar turn** on the correct
  side, never at a price the market has already passed.
- **Stop** — behind a confirmed three-bar turn, plus a buffer of the larger of one tick and the
  live spread (raised to 1.5 ticks on metals), snapped to the price grid, and checked against
  the broker's minimum stop distance. No turn inside the structure window → `WAIT`, never a
  wider stop.
- **Target** — replayed analogues of the same direction over the last **400** bars, each judged
  with a stop of the same size this trade will carry. The target is the **median** favourable
  run times **0.80**, then capped before the nearest confirmed opposing turn, and required to
  clear the spread by **2×**. Below **24** analogue cases the number is withheld and the cell
  reads `--`.
- **Size** — **0.50 %** of equity, converted to lots by `OrderCalcProfit` — the terminal's own
  money calculation for this symbol and this stop. Never hand arithmetic, never an assumed pip
  value. Refused when the budget cannot buy the minimum lot, unless `Minimum lot` or
  `Bypass risk budget` is on.
- **Total risk cap** — **1.50 %** of equity across all lanes, counted against the stops actually
  resting at the broker plus anything already open.

## 9. Management, to the end

Built, not deferred:

- **TP1** — close 50 % at the halfway target, then protect the rest. If the broker's minimum
  volume cannot hold the remainder, the partial is skipped and the stop is protected instead —
  never pretended.
- **Trailing stop** — once TP1 is banked or the trade is one risk-unit in profit, the stop
  follows the best price at half a risk-unit behind, and after TP1 never goes back behind entry.
  Steps respect the stops level, the freeze level and the price grid.
- **Limit life** — three lane-periods at the broker (15 / 45 / 90 minutes), plus a local
  watchdog, plus cancellation the moment the market walks through the resting price.
- **The idea latch** — one idea per signal, not one per bar. A **winning** close re-arms the
  lane; a losing close does not.
- **Netting accounts** — two lanes may not hold opposite positions; the slower lane yields and
  the panel says so.
- **Cold start** — the EA reconciles with the broker's positions and orders, never with its own
  memory. A restart cannot double a position or forget a stop.

## 10. The record

One CSV per account and symbol, appended, read back at attach so counts survive a restart.

| Line | Written | Contains |
|---|---|---|
| `CALL` | three bars after the call | lane, the grade it was made at, right / wrong / flat, and **each reading's own verdict** |
| `TRADE` | when a filled trade closes | side, lot, and the **money** — profit + swap + commission on every deal |
| `TWEAK` | if the bounded tweak fires | which reading, its measured rate |

The panel shows today and all-time, plus a **per-reading scoreboard**:

```
 READINGS  MOM 55% (120)   PUSH 52% (141)   STRT 47% (96)
```

That line is the thing Automate could not offer: it says *which of the three readings* is lying,
not merely whether the lane was right. A reading is **graded only on the calls where it actually
spoke** — scoring a reading on the calls it abstained from would make silence look like skill.

**The one bounded self-tweak** (switch `Tweak`, off by default): a reading with at least **100**
graded calls that has been right **less than 45 %** of the time stops counting toward agreement.
It is marked with `*`, written to the record, and never re-promotes itself. It cannot promote
anything and it cannot touch risk.

## 11. The panel

Two tables, because the first answers *what is the chart doing* and the second answers *what is
the EA doing about it*.

```text
 OLD MATE   XAUUSDm  |  Metal  |  Hedging  |  Equity 385.19 USD
 Market open  |  London (est.)  |  Spread 24 pts (normal)
 Autotrading: ON

 TF    TREND      REGIME           SCORE  SIGNAL          HOLDS
 M5    UP 12      Trending Wild    2/2    BUY 64% (18)    2 bars (1-4)
 M15   FLAT 4     Random Normal    1/1    NO SIGNAL       --
 M30   DOWN 7     Ranging Quiet    1/1    SELL 51% (30)   --

 TF    SIDE  ENTRY     LOT   TARGET             STOP               STATE
 M5    BUY   2461.35   0.02  2467.10 (575)      2458.90 (245)      READY
 M15   --    --        --    --                 --                 WAIT: spread too wide
 M30   --    --        --    --                 --                 NO SIGNAL

 AT THE BROKER (USD)
 M5    Open BUY   Entry 2461.35   Lot 0.02   P/L +2.14
       Bid 2461.10  Ask 2461.30   To target 575 pts
       Target 2467.10   Stop 2458.90   TP1 done
 M15   none
 M30   none

 RECORD   today  calls 2R/1W   trades 1W/0L
          all    calls 38R/31W  trades 4W/3L
 READINGS  MOM 55% (120)   PUSH 52% (141)   STRT 47% (96)
 saved  |  Tweak: off  |  Last bar 14:35 server  |  build 1.08
```

| Cell | Means exactly |
|---|---|
| `TREND` + a bar count | the momentum reading's direction and how long it has held |
| `REGIME` two words | memory, then volatility. Counted, never guessed |
| `SCORE` `2/2` | how many of the readings that spoke agree with the call. **Agreement, never a win rate.** `±3` is impossible by construction |
| `SIGNAL` `64% (18)` | the call, and the share of replayed analogues that reached their measured target before an equal stop, with the sample size. Withheld below 24 cases, shown as `BUY --` |
| `HOLDS` | median remaining bars for this state, with the middle range; `--` below 12 usable runs |
| `STATE` | `READY`, `HOLD: <blocker>`, `WAIT: <reason>`, `NO SIGNAL`, `DATA WAIT` |

`READY` is only printed when the plan **could actually be sent right now** — the panel asks the
same gate `SendPlan` asks, so it can never claim readiness the sender would refuse. Every refusal
carries its arithmetic in the **hover text**: the spread against this hour's median and gate, the
open risk against the cap, the stop against the broker minimum, the target against the spread,
and the sizing numbers — budget, risk per lot, and `OVER BUDGET by $x (y% of equity)` when
`Bypass risk budget` is armed.

A second panel (switch `Diary details`) shows, for each lane: the raw reading values, how each
reading voted, the memory word, both Hurst estimates, the variance ratio, the analogue reach with
its sample count, and the median bars the analogues took to reach their target.

The panel is drawn on an opaque box, redrawn on a one-second timer so a closed market still
repaints, and it carries the **build stamp** in the footer so a report can always be matched to
the code that produced it.

## 12. Forward vision — the honest version

Four numbers, each **counted from recorded outcomes**, each with its sample size, each withheld
when the sample is too small:

1. **HOLDS** — how much longer this state lasts, from the lane's own completed runs, conditioned
   on how far this one has already got. Median plus the middle range.
2. **reach %** — among replayed analogues of the same direction, each judged with the same kind
   of structural stop this lane places, the share that reached the measured target before an
   equal-sized stop, inside the lane's horizon.
3. **bars to target** — the median the successful analogues took, in the details panel.
4. **the stop that decided it** — every analogue is judged with a stop of the size the trade in
   front of you will carry, not an easier one.

What is **not** claimed: the bar a turn will happen, or a price at a time. No straight line
through the current move is drawn anywhere in this file. Automate tested that method and refused
it; nothing here re-introduces it.

## 13. The ten switches

| Input | Default | What it does |
|---|---|---|
| `Autotrading (master switch)` | on | must be on for any order to be sent |
| `Allow M5 autotrade` | on | that lane may place, reprice and cancel |
| `Allow M15 autotrade` | on | same, M15 |
| `Allow M30 autotrade` | on | same, M30 |
| `Trailstop enable` | on | the trailing engine |
| `TP1 partial + TP2` | on | the partial close at TP1 |
| `Diary details` | on | the second panel |
| `Tweak` | off | arms the bounded demotion |
| `Minimum lot` | off | clamp a size up to the broker minimum instead of refusing |
| `Bypass risk budget` | off | the wider override: a minimum lot larger than the budget is no longer refused **and** the 1.50 % total cap is released. The panel prints `RISK BYPASS ON`, and every plan still reports what it actually risks |

No period, band, threshold or session time is ever an input. Ten switches, all on/off, all safe
at their default.

## 14. What will not be built

An indicator that repaints or reads future bars (the popular 2024–25 kernel-smoothing family uses
future candles by default) · a "probability of winning" · a predicted bar of the turn · a
machine-learning classifier nobody can audit · a per-indicator input · a live re-fitting of
parameters · an ATR-multiple target or stop · closing a position on a clock · trading on any
timeframe other than M5 / M15 / M30.

## 15. The four measurements that shaped the design

Every number below is printed by a script in `tools/` and can be re-run.

### 15.1 The original trio was fake

The first design used MACD-V, directional movement and envelope position as three independent
readings. Whenever all three had an opinion they agreed **99–100 %** of the time. Three names,
one measurement — a "2 of 3" count over them would have been a coin weighted by how the trio
happened to be chosen.

### 15.2 There are only two directional opinions in a price series

Measured on seven conventional candidates: continuation (MACD-V, directional movement, structure
break, efficiency direction) agree **95–100 %** with each other; reversion (RSI, Stochastic,
envelope position) agree **100 %** with each other; **across the families, 0 %**. They are
opposites, not cousins.

### 15.3 Which rule survives five kinds of market

The table in §6. Only the memory-conditional rule was never below a coin flip.

### 15.4 The arithmetic itself was checked, and two real bugs were caught

- **DFA and rescaled range were being run on prices instead of increments**, so every series
  scored a Hurst near 1.4 and every memory label came out `Unclear`. Now a random walk scores
  **0.548**, a persistent series **0.696**, a reverting one **0.412**.
- **A percentile was being applied to a raw random walk**, which has no stationary distribution,
  and fired 12 % of the time instead of 5 %. That is why percentiles here are only ever applied
  to a **bounded reading** — now measured at **5.29 %** (envelope position) and **5.46 %**
  (`|MACD-V|`) against a stated 5 %.

Both would have shipped silently as plausible-looking numbers. That is the entire argument for
building the proving ground first.

## 16. Validation, and everything the checks caught

**Static checks — `python3 tools/preflight.py OldMate.mq5`, 25 checks, all passing:**

Five structural checks (`{}` / `()` / `[]` balance, final newline, no stray `;;`) · four that
each event handler is defined exactly once · no duplicate function definitions, and a plausible
function count (120) · **every call to our own functions has the right number of arguments** ·
no calls to functions that do not exist · **every struct field read exists on that struct** ·
**every struct field is also read, not only written** · **every global is read, not only
written** · no `#define` declared and never used · **every library call (`PositionOpen`,
`OrderOpen`, `OrderModify`, …) has a legal argument count** · every input is read · and six
guards that encode the hard rules: **no trading on an unsupported timeframe**, **a percentile
needs its minimum sample count**, **no ATR-multiple target or stop**, **the forming bar is never
read by a reading** (`start_pos` 1, checked in the source), **trading is gated by the
terminal**, and **fills are graded in money**.

**Arithmetic — `python3 tools/selftest.py`, ALL CHECKS PASSED (8 groups):**

| Check | Result |
|---|---|
| Wilder seed is the simple average, step is 1/n | verified against hand arithmetic |
| Wilder is slower than an EMA of the same length | 3.1250 vs 3.5000 after the first step |
| True range counts a gap | 10.5 where high-minus-low says 1.0 |
| MACD-V is scale-free | 0.00 % spread between a 100-price series and the same shape at 3 500 |
| a raw MACD is not | 35× apart on the same two series — the problem MACD-V fixes |
| a 5 % threshold fires 5 % of the time | 5.29 % (position), 5.46 % (`|MACD-V|`) |
| memory separates the three series | 0.548 random / 0.696 persistent / 0.412 reverting |
| reading independence | momentum/push 100.0 %, momentum/stretch 0.0 %, push/stretch 0.7 % |
| abstention is real | momentum 72.3 %, push 58.9 %, stretch 71.2 % neutral |
| `±3` is unreachable and not faked | 0.0 % of 5 921 bars |
| no reading depends on a later bar | 1 375 votes identical on truncated and full series |

**A second read-through found six real defects, all fixed.** They are the argument for reading
code after writing it:

| Defect | Consequence had it shipped |
|---|---|
| the record was read back with every field one place off | restored counts would have been wrong after every restart |
| a reading was graded on the calls where it abstained | a quiet reading would have looked better than it was, and the tweak would have demoted the wrong one |
| `g_lane[idx].ok` where the field is on `g_plan` | would not compile |
| TP1 was taken from the live plan instead of the trade | a rebuilt plan could have triggered the partial on the wrong side |
| a demoted reading still counted toward the decision | the tweak would have been decorative |
| no session table was reported as "Market closed" | a false report, which rule 1 forbids outright |

The checker was extended to catch the "field does not exist" class automatically, and caught the
compile error on its first run.

**First compile — ten errors, all fixed the same day:**

| Compiler said | Real cause | Fix |
|---|---|---|
| `'g_spr' - invalid array access`, `parameter passed as reference` | a row of a 2-D array cannot be passed by reference | the row is copied into a 1-D array first |
| `undeclared identifier 'SYMBOL_TRADE_DISABLED'` | that is the MQL4 name | `SYMBOL_TRADE_MODE_DISABLED` |
| `cannot convert enum` at the limit order | two `datetime` values were added; MQL5 will not | add in `long`, cast back once |
| `undeclared identifier 'SelectByTicket'` (×3) | `COrderInfo` has no `SelectByTicket` in this build | pending orders read through the built-in `OrderSelect` / `OrderGet*` |

Two more of the same class were found by sweeping for the pattern rather than waiting for the
next compile: every `datetime` subtraction in the file is now done in `long`, and the enum
ternary in `OnInit` is cast explicitly.

**Second compile — one error, same class of trap:** `CTrade::OrderOpen` takes **ten** arguments
and the file passed nine. The seventh is the stop-limit price, so omitting it slid the
time-in-force enum into a `double` slot and the compiler reported `cannot convert enum` instead
of a missing argument. It is now `0.0`, which is what a plain limit order needs. The checker
gained an argument-count check for every library method this file calls.

**Field report: `Market status unknown` on every chart.** The reader only ever asked for the
**trade** session table. Plenty of brokers publish quote sessions and leave the trade table
empty, so the count was zero on every symbol, the status fell through to "unknown", and
`SendPlan` refused everything. It was never crypto-specific. Both tables are now read and kept
apart, as described in §3.

**Field report: a panel row said `READY` and no trade was sent.** `PlanStateText` and `SendPlan`
were asking different questions. The panel now asks the send gate and prints `HOLD: <blocker>`,
and every refusal carries its arithmetic in the hover text.

**Field report: the panel was unreadable, and absent on a closed market.**

| What was seen | Cause | Fix |
|---|---|---|
| the word `Label` on blank lines | an empty string does not clear a label's caption | a blank line is drawn as a single space |
| lines overlapping | 15 px spacing against a taller rendered font | line height is `font size + 9`, box height from the line count |
| text unreadable over candles | there was no background at all | every panel sits on an opaque box, sized to its longest line |
| no panel on a closed market or an unsupported timeframe | `ChartRedraw()` was only called in `OnDeinit`; with no ticks there is no repaint | redraw on the one-second timer, so a quiet chart still paints |

**Field report: a box left on the chart, and `Abnormal termination` in the log.** The log line
means `OnDeinit` never finished — and the boxes are deleted last, which is exactly why the text
vanished and the boxes stayed. One event, not two. Cleanup is now a **name-prefix sweep over
every chart object**, so it is idempotent and self-healing: `OnDeinit` sweeps first and logs the
reason code and how many objects it removed, and `OnInit` sweeps *before* drawing, so a panel
left by an earlier run is cleared at attach instead of drawn over.

**A dead-code audit, run while preparing this document.** The static checker gained two mirrors
("read, not only written") and immediately found five real instances:

| Dead thing | What it means |
|---|---|
| `g_unit[]` | the measured unit was stored on every bar under a name nothing read — the arithmetic that mattered was the local copy, which does divide the band width before ranking |
| `g_currency` | assigned at attach, read by nobody; the panel uses the symbol record directly |
| `g_pendTF[]` | written when a call was recorded, never read |
| `momOk`, `pushOk`, `stretchOk`, `volPct` | per-bar calibration flags and the vol percentile, stored and never displayed |
| `durabOk` / `durabPct` | **contained a documented number that did not exist**: "bars to target" was computed from the replay and never shown. It is now displayed in the details panel |

That last one is the reason the audit was worth doing: a number the document promised was being
computed correctly and then thrown away.

**Still to do, and only this:**

1. Compile in MetaEditor — expect **0 errors, 0 warnings**. Any warning is a defect, not noise.
2. Attach to a demo chart on M5, M15 and M30. Confirm: the header is true; `OUT OF RANGE` on H1;
   `DATA WAIT` with shallow history; every panel number reproducible by hand from exported bars;
   a reading that does not change when the chart is re-read an hour later.
3. One week on demo, then a small live size. If the record's per-reading scoreboard shows a
   reading below a coin flip, §6 says which family it belongs to and what follows from that.

## 17. Open questions for you

| # | Question | Default if unanswered |
|---|---|---|
| Q1 | Risk per idea: 0.50 % of equity, cap 1.50 % across lanes | as built |
| Q2 | On a netting account, the slower lane always yields | as built |
| Q3 | Should the forward `reach %` appear on the main panel or only in the details panel? | on the main panel, as built |
| Q4 | Is a `±3` score being impossible acceptable, or do you want a fourth reading that can agree with both families? | acceptable — it is the measured structure, not a limitation |



---

# Part II — the indicator record

Part I says what the EA does. Part II says **which conventional instruments it uses, in what
modern form, why, and what was rejected** — so the choices can be argued with, and so nothing has
to be taken on trust later.

Rule for this part: every claim is either a published source or a measurement we can run and
print. Where a number is not known, it says so rather than guessing.

---

## 18. Why "conventional name, modern arithmetic"

A trader looking at a chart already knows what MACD, ADX and Bollinger bands are for. Throwing
those names away means the panel has to be learned from scratch, and an unexplainable panel is a
panel that gets switched off during its first losing week.

But the *bare* conventional versions have four well-known faults. Three are fixable without
changing the name; the fourth was considered and **refused**, which is recorded here because
refusing it is a design decision, not an oversight.

| Fault in the bare version | What it does to a real account | What this EA does |
|---|---|---|
| **Scale depends on the symbol** — a raw MACD of 2.5 means nothing until you know the instrument and the decade | the same rule cannot be used on gold and on EUR/USD; every symbol needs its own settings | divide by the instrument's own volatility (MACD-V) |
| **Fixed thresholds** — RSI 70/30, ADX 25 | levels that were sensible for one market in one era, applied forever to everything | compare each reading to its **own rolling percentile** |
| **Fixed speed** — always 14 bars | too slow in a clean move, too fast in chop | **kept fixed, deliberately.** Adapting the smoothing would change what the indicator *is*, and the panel would stop describing the chart on the owner's screen. The whiplash problem is answered by letting a reading **abstain** inside the middle of its own distribution instead |
| **No way to know if it is helping** | three plausible readings, no evidence any of them earns its place | a **per-reading scoreboard**, graded on outcomes |

The fourth row is the one that sounds like a compromise and is not. An adaptive RSI built on
Kaufman's efficiency ratio was specified, measured in principle, and then dropped: it changes the
identity of the instrument, it re-tunes itself on the same bars it is judged on, and the
measurement in §22 says the *rule choosing between families* is what carries the edge, not the
speed of any one smoother.

None of the accepted fixes changes what the panel *says*. `TREND`, `PUSH`, `STRETCH` are familiar
ideas. What changed is that the numbers behind them no longer need a human to tune them.

---

## 19. The two families, and why the panel keeps three readings

> This section is the foundation of the whole design. It began as three readings assumed to be
> independent voters. `tools/selftest.py` showed they agreed **99–100 %** whenever all three
> spoke — three names for one measurement. `tools/choose_readings.py` then found that seven
> conventional candidates collapse into exactly **two** families: continuation (MACD-V,
> directional movement, structure break, efficiency direction — mutually 95–100 %) and reversion
> (RSI, Stochastic, envelope position — mutually 100 %), with **0 % agreement between the
> families**.
>
> `tools/combine_test.py` showed the consequence across five kinds of market: every fixed
> combination fails somewhere (a fixed trio scored 29.5 % on a mean-reverting market;
> reversion-only scored 23.3 % on drift-with-pullbacks), while a **memory-conditional** rule was
> the only one never below a coin flip anywhere — 51.3 % to 80.8 % across the five markets.
>
> So the three readings are kept, but they are not three equal votes: one continuation reading,
> one participation reading and one reversion reading, with **market memory choosing which family
> decides**. That is `DecideSignal` in the file, described in Part I §6.
>
> A consequence worth stating: a unanimous `3/3` score is **impossible by construction**, and the
> self-test asserts that it stays impossible rather than letting a faked one appear.

### 19.1 Momentum — MACD, in its volatility-normalised form (MACD-V)

**What it is.** Gerald Appel's MACD — the gap between a fast and a slow exponential average —
divided by the instrument's own average true range, times 100. The 12 / 26 / 9 shape is
unchanged, and the volatility window matches the slow average by design.

**Who and when.** Alex Spiroglou, "MACD-V: Volatility Normalised Momentum", 2022. It received the
CMT Association's **Charles H. Dow Award** and the NAAIM **Founders Award**, and now exists as an
MT4/MT5 indicator in the MQL5 code base and as standard scripts on TradingView and StockCharts.

**Why it earns the momentum slot.**

- A reading of `+100` means "momentum equal to one unit of this instrument's own volatility" —
  the same statement on gold, on EUR/USD and on an index. That property is what makes a
  zero-input panel possible.
- It keeps the parent's signal line, zero line and histogram behaviour, so nothing has to be
  relearned.
- Its published zones are a genuine scale rather than folklore: roughly −50 to +50 neutral,
  ±50 to ±150 real momentum, beyond ±150 stretched relative to volatility.

**What is done with it, honestly.** The published zones are a **human-readable label only** and
are never the trigger. The vote uses the reading's position in its own recent distribution, in
the exact form given in Part I §4. If the two ever disagree systematically on this broker's data,
the record will show it.

**What it will not do.** It will not be treated as "overbought means sell". In a strong move,
stretched momentum is a sign of strength; this reading votes direction, and the stretch reading
handles stretch.

Sources:
- Concept and formula: <https://www.luxalgo.com/library/concept/macd-v/>
- Author's own summary and award citation: <https://www.benzinga.com/pressreleases/22/05/p27046755/>
- Independent implementations (scale, bands): <https://www.tradingview.com/script/99lPD1fh-Case-s-MACD-V-Volatility-Normalized-Momentum/>,
  <https://www.mql5.com/en/code/66221>

### 19.2 Push — directional movement (ADX / DMI), Wilder-correct

**What it is.** Wilder's directional movement: how much of the recent range was made on the up
side versus the down side, smoothed, with an index of how directional the whole thing is.

**Why it earns the push slot.** It is the only classic that answers "is anybody actually in
control here", and it is built from highs and lows rather than closes, so it is not a copy of the
momentum reading.

**The modern parts.**

1. **Correct arithmetic.** Wilder's smoothing is an average with weight `1/n`, seeded from a
   simple average — not an ordinary exponential average with weight `2/(n+1)`. Most retail code
   muddles the two, and MT5 itself ships two variants (`Average Directional Movement Index` and
   `Average Directional Movement Index Wilder`) whose lines genuinely differ. OldMate computes
   both directional lines from the correct seed and does not depend on a platform handle, so the
   number on the panel is the number the file computes.
2. **Percentile strength, not 25.** The written-down `25` is a convention from a 1978 book about
   commodity markets. Here, "strong enough to vote" is where the reading sits against this
   symbol's own recent distribution — the 55th percentile, in both the trend strength and the
   separation between the two directional lines.
3. **Abstention is the default.** Inside the middle of its own distribution the reading votes
   neutral instead of picking a side. Without that, `2/3` could never occur and the score would
   collapse to a two-state guess.

Sources:
- Wilder's smoothing explained, and the seeding problem: <https://chartschool.stockcharts.com/table-of-contents/technical-indicators-and-overlays/technical-indicators/average-directional-index-adx>
- The two MT5 ADX variants: <https://admiralmarkets.com/education/articles/forex-indicators/how-to-use-adx-indicator-in-mt4>
- RMA definition as Wilder intended: <https://github.com/TA-Lib/ta-lib/issues/348>

### 19.3 Stretch — where price sits inside its own volatility envelope

**What it is.** The Bollinger idea: a middle average with a band whose width is the instrument's
own recent dispersion. Read as **position** — top, middle, bottom of the band — and as **width** —
squeeze or expansion.

**Why it earns the stretch slot.** Position is the one measurement that is genuinely about
*stretch* rather than *speed*, so it is not a third copy of momentum. It also carries the squeeze,
which is the best-understood thing this family measures.

**The modern parts.**

1. **Percentile position, not raw percentage.** Instead of "80 % of the way up the band", the
   reading is "where this position sits in its own recent distribution". Same information,
   comparable across symbols and eras.
2. **Width as a percentile too.** Band width is divided by the measured unit and then ranked; the
   5th percentile is genuine compression, the 95th genuine expansion, rather than an arbitrary
   "narrow" or "wide".
3. **Volatility is a state, not a signal.** A wide band in a wild market means something different
   from a wide band in a quiet one; the REGIME cell keeps that distinction visible instead of
   folding it into the vote.
4. **This reading fades, and only fades.** At or above the 85th percentile it votes down; at or
   below the 15th it votes up. It is the only reading that disagrees with the other two, and the
   measurement says that is exactly what makes it worth having — but only when market memory says
   the series is ranging.

Sources:
- Percentile-based band-width regimes and normalisation: <https://www.tradingview.com/script/23tnzSdb/>
- Bollinger bands as a volatility-relative measure, and why a fixed-threshold oscillator is not
  the same statement: <https://www.tradingview.com/chart/ES1!/FwfqO55g-Buy-the-Panic-What-20-Million-Bollinger-Tests-Found/>

---

## 20. The two context measures, shown as one REGIME cell

Neither votes. Both are shown because they change how a reading should be read by a human. On the
panel they sit together as one `REGIME` cell with two words — `Trending Wild`, `Random Normal`,
`Ranging Quiet` — because they are two halves of one description: what kind of series this is,
and how loud it currently is.

### 20.1 Volatility — against its own range

`Quiet`, `Normal`, `Wild`, from the percentile of the current envelope width in the instrument's
own recent history, after that width has been divided by the measured unit. Volatility clusters:
high follows high, low follows low. The column exists so that "the target is 575 points" is read
in context, and so a wide-spread hour is visible before it becomes a refusal.

### 20.2 Memory — does this market push, wander, or snap back

`Trending`, `Random`, `Ranging`, from a rolling estimate of long-range dependence — the Hurst
exponent, cross-checked by a variance ratio. Conventionally: above about **0.55** the series
persists, below about **0.45** it reverts, near 0.5 it is a random walk and neither momentum nor
mean reversion has structural support.

**Why this instead of a moving-average band.** A band tells you where price is relative to an
average. Memory tells you what kind of series you are in — which is the question a strategy
actually needs answered, and the reason it is now the standard regime core in quantitative
practice.

**The honest limits, stated up front.**

- The Hurst exponent is an **estimate**, and on short windows a noisy one. Two estimators
  (rescaled range and detrended fluctuation analysis) give different answers; DFA is the more
  robust and is the primary, with rescaled range as the cross-check.
- **When the two disagree by more than 0.12 the word is `Unclear`** — never an average, because an
  average of two disagreeing estimates is a number nobody measured.
- It is a **context label, not a veto**. Whole profitable days happen at a Hurst near 0.5, and
  blocking them on a noisy estimate would be a silent strategy change.

Sources:
- Hurst as regime core, with the 0.55 / 0.45 conventions: <https://fractalcycles.com/guides/market-regime-detection>
- Peer-reviewed comparison of estimators, and regime-conditional performance: <https://apjm.apacific.org/PDFs/12-109.pdf>
- Practical three-number regime checklist (ADX + volatility percentile + Hurst): <https://fortraders.com/blog/momentum-vs-mean-reversion-strategies-for-challenges>

---

## 21. The spares that were measured and not used

Both were candidates for a slot, both are conventional, and both were **measured and rejected** —
not on taste, but because they landed inside a family that was already represented.

| Spare | Modern form that was specified | Measurement verdict |
|---|---|---|
| **RSI** | Wilder's RSI whose smoothing speed adapts to how clean the move is (Kaufman's efficiency ratio, bounded by the classic fast/slow constants), with percentile thresholds | it is the reversion family. `choose_readings.py` measured RSI against envelope position at **100 % agreement**, so adding it would have been a fourth name for one opinion |
| **Stochastic** | same adaptive treatment, plus percentile thresholds, plus the velocity of the two lines rather than only their cross | identical result: **100 % agreement** with the position reading. It measures the same stretch |

They are recorded here because "not used" is a decision that deserves its evidence, and because if
the record later shows the stretch reading misbehaving, the replacement is already specified.

Sources:
- Adaptive RSI via efficiency ratio, with bounded smoothing: <https://docs.wickra.org/Indicators/Indicator-AdaptiveRsi>
- Efficiency ratio as the general adaptive mechanism (KAMA lineage): <https://www.luxalgo.com/library/concept/adaptive-parameterization/>
- Percentile-adaptive thresholds in practice: <https://www.tradingview.com/script/a6c7sYp1-Adaptive-RSI-BOSWaves/>

---

## 22. The reject pile, and why

| Rejected | Reason |
|---|---|
| **Nadaraya-Watson envelope / kernel smoothing** (the popular 2024–25 indicator) | in its default mode it fits each bar using bars on both sides, so the historical chart shows a curve that did not exist in real time. It repaints. A non-repainting mode exists, but a repainting *default* is exactly the trap a real-money EA must not carry: <https://www.quantum-algo.com/blog/guides/nadaraya-watson-envelope-complete-guide/>, <https://www.mql5.com/en/blogs/post/766072> |
| **KNN / "machine learning" classification indicators** | no auditable arithmetic; a closed trade could not be explained to its owner. Refused on that ground, not because it is new |
| **Ehlers cycle / bandpass filters** | built and measured in `Automate`: the sign was a coin flip against direction on every test, because the filter removes the slow drift a trend reading is supposed to report. Kept there only as a printed comparison. Not carried into OldMate |
| **Kalman-filter slope** | measured against the simpler alternatives in `Automate`, not reachable; nothing to gain by re-running it here |
| **Laguerre RSI, Jurik-style smoothing** | closed-form or opaque smoothing whose properties cannot be verified from source; a reading must be reproducible by hand from exported bars |
| **Adaptive speed (Kaufman ER applied to RSI smoothing)** | see §18 — it changes the identity of the indicator the owner can see, and the measurement says the family rule carries the edge, not the smoother's speed |
| **Renko / Heikin-Ashi charts as a basis** | invented prices. Everything here is built from the real bars the broker delivers |
| **Volume and order-flow families** | symbol-dependent and unreliable across the brokers this EA will actually meet; not refused forever, but out of version 1 |
| **A "confidence %" from a fitted model** | tried in `Automate`: a logistic model on nine indicators helped in one era and hurt when the eras were swapped, and was badly calibrated out of sample. The record keeps a counted scoreboard instead of a fitted percentage |

---

## 23. Lane personalities — the numbers that actually change

The three lanes are the same method at three working speeds. These are the quantities that
differ, each with its reason. Everything else — indicator lengths, vote thresholds, risk per idea
— is identical across lanes by design.

| Quantity | M5 — scalping | M15 — short-term | M30 — intraday | Why |
|---|---|---|---|---|
| Planning horizon | 4 bars | 6 bars | 8 bars | how far ahead the lane may claim a target |
| Structure window | 36 bars | 48 bars | 72 bars | a scalper's valid turning point is recent; an intraday one is not |
| Percentile lookback | 300 bars | 400 bars | 500 bars | M5 must adapt within an hour; M30 should reflect the session |
| Limit patience | 15 min | 45 min | 90 min | three lane-periods, so the clock is the lane's own unit |
| Risk per idea | 0.50 % | 0.50 % | 0.50 % | deliberately equal: the lanes differ in speed, not in what the owner can lose |
| History loaded per lane | 900 bars | 900 bars | 900 bars | enough for Wilder to converge and for 500-bar percentiles |

Equal risk is a decision, not an oversight. Sizing the scalper smaller "because it trades more"
would mean the three lanes can no longer be compared on the record, which is the purpose of the
whole exercise.

**What does not vary by lane, and does vary by instrument — the spread gate.** The gate is a
multiple of this server-hour's median spread for this symbol, and it is set by **asset class**,
because a scalper and an intraday trader face the same spread on the same symbol:

| Class | Gate (× this hour's median spread) |
|---|---|
| Forex | 3.0 |
| Metal | 3.5 |
| Index | 4.0 |
| Energy | 4.5 |
| Crypto | 6.0 |
| Stock | 5.0 |
| Other | 3.0 |

The baseline needs 20 samples in the hour before it is trusted; below that the gate does not fire
and the panel says so. Stop buffers also vary by class: metals get 1.5 ticks, everything else 1.0.

---

## 24. Exact procedures

Written at formula level, so each can be checked by hand against exported bars. In the code, each
sits beside a comment naming the procedure.

### 24.1 The measured unit

`unit = median( |close[i] − close[i−1]| )` over 20 bars, floored at one tick.

Median, not mean: a single news candle must not redefine the instrument. **The unit has exactly
one job** — it divides the envelope width before that width is ranked, so `Quiet / Normal / Wild`
means the same thing on gold at 3 500 and on EUR/USD at 1.08.

There are **no deadbands** in this EA. An earlier design scaled abstention zones as
`unit × √horizon`; that was replaced by percentiles of each reading's own distribution, because a
zone expressed in price units still needs a written-down multiplier, and a written-down
multiplier is the setting this EA exists to avoid.

### 24.2 Momentum — MACD-V

1. `EMA_fast`, `EMA_slow` over 12 and 26, **seeded by a simple average** of their first values, so
   the first printed value is not a warm-up artefact.
2. `ATR_26` by **Wilder's smoothing**: the first value is the simple average of 26 true ranges,
   then `ATR = ATR_prev + (TR − ATR_prev)/26`. True range is `max(H−L, |H−C_prev|, |L−C_prev|)` —
   gaps count.
3. `MACD-V = (EMA_fast − EMA_slow) / ATR_26 × 100`. The denominator's window matches the slow
   average, which is why the ratio is dimensionless.
4. Signal line: a 9-period EMA of `MACD-V`, seeded the same way.
5. **Vote:** up when `MACD-V > 0`, `MACD-V ≥ signal`, **and** `|MACD-V|` is at or above the 60th
   percentile of its own last 300 / 400 / 500 closed readings. Down mirrored. Otherwise neutral.
6. The published ±50 / ±150 zones are used as a **label only**, never as the trigger.

### 24.3 Push — directional movement, Wilder-correct

1. `+DM = max(H − H_prev, 0)` when it exceeds `L_prev − L`, else 0; `−DM` mirrored. Inside bars
   produce zero for both, which is correct.
2. Smooth `+DM`, `−DM` and `TR` with **Wilder's 1/n smoothing**, simple-average seed.
3. `+DI = 100 × smoothed(+DM) / smoothed(TR)`, `−DI` mirrored.
4. `DX = 100 × |+DI − −DI| / (+DI + −DI)`; `ADX` = Wilder-smoothed `DX`.
5. **Vote:** up when `+DI > −DI`, `ADX` is at or above its **55th** percentile, **and** the
   `|+DI − −DI|` separation is at or above its **55th** percentile. Down mirrored. Neutral
   otherwise — abstention is deliberate, because without it `2/3` cannot occur.
6. **Warm-up:** Wilder's smoothing converges slowly — roughly 150 bars for a 14-period ADX to
   match the converged value, verified in the self-test. The lane says `DATA WAIT` until the
   warm-up is met; it never trades on an unconverged value.

### 24.4 Stretch — the envelope

1. Middle = 20-period simple average. Width = 2 × **population** standard deviation over the same
   20 bars (Bollinger's own convention, `n`, not `n−1`).
2. `position = (close − middle) / (2 × SD)` — %B expressed around the middle.
3. **Rank `position`** in its own recent history. The vote is on that rank: "top of the top decile
   of this symbol's own positional readings", not "0.9".
4. `width` is likewise divided by the unit and ranked, giving the volatility state used by REGIME:
   bottom of the distribution `Quiet`, middle `Normal`, top `Wild`.
5. **Vote:** at or above the 85th percentile → **down**; at or below the 15th → **up**; otherwise
   neutral. It fades, and it does nothing else. Whether a fade is allowed to decide is settled in
   `DecideSignal` (Part I §6), not hidden inside this function.

### 24.5 REGIME — memory and volatility

1. **Memory.** Detrended fluctuation analysis gives the Hurst estimate on the lane's 320-bar
   window; rescaled range gives a second estimate. If the two differ by **more than 0.12**, the
   word is `Unclear`. Otherwise: above 0.55 `Trending`, below 0.45 `Ranging`, between `Random`.
   **Never an average of the two estimates.**
2. **Variance ratio** on the same window: long-horizon variance over short-horizon variance. Above
   one supports persistence, below one supports reversion. It is shown beside the estimates as a
   cross-check; a contradiction is visible to the owner rather than silently resolved.
3. **Volatility.** The percentile of current envelope width in its own recent history, after the
   width is divided by the measured unit.
4. There is **no neighbouring-window search**. `Automate` learned that a regime span which cannot
   resolve a label produces constant flip-flop; the answer adopted here is a fixed window per lane
   plus an explicit `Unclear` when the two estimators disagree — not a search for a window that
   happens to agree today.

### 24.6 The forward numbers — counted, not predicted

All of them come from **recorded or replayed outcomes on this lane**, never from a formula applied
to a trend line.

| Number | Procedure | Where shown |
|---|---|---|
| **HOLDS** (bars remaining) | take this lane's completed runs of the same state, keep those that outlived the current age, take the median of their residuals, with the interquartile range | main panel; `--` below 12 survivors |
| **share that reach target** | replay analogues of the same direction over 400 bars, each judged with a stop of the size this trade will carry; count those that reached the measured target before an equal-sized stop inside the horizon | main panel as `64% (18)`; withheld below 24 cases |
| **bars to target** | among the analogues that *did* reach it, the median number of bars taken | details panel, `N bars to target, on average` |
| **the stop that decided it** | not a separate number: it is the rule applied to every analogue, so the share is never flattered by an easier stop | — |

A straight-line extrapolation of the current move is **not** used anywhere. That is the one
forecast method `Automate` tested and refused, and nothing here re-introduces it.

---

## 25. The measurement record

Every number below is printed by a script in `tools/` and can be reproduced by running it.

### 25.1 The families (`tools/choose_readings.py`)

| Pair | Agreement when both vote | Reading |
|---|---|---|
| MACD-V / directional movement | 100.0 % | one family |
| MACD-V / efficiency direction | 100.0 % | one family |
| RSI / Stochastic | 100.0 % | one family |
| RSI / envelope position | 100.0 % | one family |
| continuation / reversion | 0.0 % | opposites |

### 25.2 The rule (`tools/combine_test.py`)

| Market | fixed trio, 2 of 3 | reversion only | **memory-conditional** |
|---|---|---|---|
| random walk | 50.3 % | 49.5 % | **51.5 %** |
| steady drift | 65.2 % | 48.9 % | **66.5 %** |
| momentum | 57.1 % | 44.1 % | **55.8 %** |
| mean-reverting | 29.5 % | 69.5 % | **51.3 %** |
| drift + pullbacks | 81.9 % | 23.3 % | **80.8 %** |

50 % is a coin flip. Only the last column never goes below it.

### 25.3 The arithmetic, on the final file (`tools/selftest.py`, ALL CHECKS PASSED)

| Check | Result |
|---|---|
| Wilder seed is the simple average | 2.500000, then a step of 3.125000 on a 4-period example |
| Wilder is slower than an EMA of the same length | 3.1250 vs 3.5000 |
| 26-period Wilder converges | seeded at bar 400, 0.000 % from the converged value |
| true range counts a gap | 10.5000 where high-minus-low says 1.0 |
| MACD-V is scale-free | 0.0000 spread between a 100-price and a 3 500-price series (0.00 % of its own size) |
| a raw MACD is not | 0.5675 vs 19.8618 — 35.0× apart |
| a 5 % threshold fires 5 % of the time | 5.29 % for position, 5.46 % for `|MACD-V|` |
| memory separates three series | random 0.548 / persistent 0.696 / reverting 0.412 |
| the readings are two families | momentum/push 100.0 %, momentum/stretch 0.0 %, push/stretch 0.7 % |
| each reading abstains | 72.3 %, 58.9 %, 71.2 % neutral |
| reachable scores all occur | −2 7.3 %, −1 22.7 %, 0 46.6 %, +1 16.5 %, +2 6.8 % |
| `±3` is unreachable and not faked | 0.0 % / 0.0 % of 5 921 bars |
| no future bar is read | 1 375 votes identical on a truncated and a full series |

**Two real bugs were caught before any MQL5 existed:** DFA and rescaled range were being run on
prices instead of increments (every series scored H≈1.4 and every memory label read `Unclear`),
and a percentile was being applied to a raw random walk (firing 12 % instead of 5 %). Both would
have shipped as convincing-looking numbers.

---

## 26. Sources

- Spiroglou, A. — *MACD-V: Volatility Normalised Momentum* (2022). Dow Award, NAAIM Founders
  Award. <https://www.benzinga.com/pressreleases/22/05/p27046755/>
- Wilder, J. W. — *New Concepts in Technical Trading Systems* (1978): RSI, ATR, ADX, and the
  smoothing used throughout. <https://github.com/TA-Lib/ta-lib/issues/348>
- Kaufman, P. J. — efficiency ratio and the adaptive moving average (1995).
  <https://chartschool.stockcharts.com/table-of-contents/technical-indicators-and-overlays/technical-overlays/kaufmans-adaptive-moving-average-kama>
- Percentile-based thresholds instead of fixed levels.
  <https://www.tradingview.com/script/23tnzSdb/>
- Hurst exponent as a regime core, with the standard conventions.
  <https://fractalcycles.com/guides/market-regime-detection>
- Detrended fluctuation analysis versus rescaled range (peer reviewed).
  <https://apjm.apacific.org/PDFs/12-109.pdf>
- The repainting warning, stated by the indicator family's own users.
  <https://www.quantum-algo.com/blog/guides/nadaraya-watson-envelope-complete-guide/>
