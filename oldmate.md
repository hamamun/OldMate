# OldMate — the plan, as built

**Status: built. `OldMate.mq5` exists, preflight-clean, 3 348 lines.** It has not yet been
compiled in MetaEditor or run on a demo account — that is the only step left, and section 17
says exactly how to judge it.

This document is the plan and the record of what the measurements changed on the way. Where
the plan and the file disagree, **the file is the truth and this document is the bug.**

OldMate is the conventional sibling of [Automate](https://github.com/hamamun/Automate). Same
family, same panel discipline, same refusal to print a number it cannot compute — built so the
two can be **run side by side and compared honestly.**

**Hard rules, unchanged and enforced:**

1. **No fallback.** A value that cannot be measured is reported as `CALIBRATING`, `DATA WAIT`
   or `Unclear`. There is no default threshold anywhere in the file.
2. **No fabricated claim.** Agreement is not a probability, and no forward number without a
   sample size beside it.
3. **Correct instrument for the correct job.** Wilder smoothing is Wilder's, true range counts
   gaps, percentiles are empirical with a minimum count, the target is measured not multiplied.
4. **The EA may do less than this document says. It may never do something this document does
   not say.**

---

## 0. The ten things you asked for, and where each is

| # | You asked for | Where it lives | State |
|---|---|---|---|
| 1 | understand what type of symbol it is | `ClassifySymbol`, `ApplyProfile` | built |
| 2 | say open or closed, and when it opens | `IsOpenNow`, `RefreshMarket` | built |
| 3 | say the session | `SessionLabel` | built |
| 4 | M5 / M15 / M30 only, else out of range | `TimeframeAllowed`, panel gate | built |
| 5 | set its own parameters from symbol and context | §5, `UnitAt`, `LaneRankWindow`, `PctRank` | built |
| 6 | M5 scalps, M15 short, M30 intraday | `LaneHorizon`, `LaneStructWindow`, per-lane windows | built |
| 7 | declare TREND / REGIME / SCORE / SIGNAL | `UpdateLane`, panel | built |
| 8 | on a call, show entry / TP / SL / lot, all calculated | `BuildPlan`, `MeasureTarget`, `CalcLot` | built |
| 9 | autotrade from the signal | `SendPlan`, `TradeOnBar`, `ManageSecond` | built |
| 10 | today and all-time score, and a record | `RecordLoad`, `GradePending`, panel | built |
| — | forward vision | §7 — four counted numbers | built |
| — | trailing stop, TP1/TP2, self-tweak | `ManageSecond`, `ApplyTweak` | built, not deferred |

---

## 0.1 What the measurements changed — the important part

Three candidate designs were tested before a line of MQL5 was written. The tools are in
`tools/` and every number below is reproducible by running them.

### Measurement 1 — the original trio was fake

The first design used MACD-V, directional movement and envelope position as three independent
readings. On a long series they agreed **99–100 % of the time whenever all three had an
opinion** (`tools/selftest.py`, section 6). Three names, one measurement. A "2 of 3" count over
them would have been a coin weighted by how the trio happened to be chosen.

### Measurement 2 — there are only two directional opinions in a price series

Tested seven conventional candidates (`tools/choose_readings.py`). The answer was structural:

- **Continuation family** — MACD-V, directional movement, break of structure, efficiency
  direction: they agree **95–100 %** with each other.
- **Reversion family** — RSI, Stochastic, envelope position: they agree **100 %** with each
  other.
- **Across the two families: 0 %.** They are opposites, not cousins.

### Measurement 3 — which rule survives four different markets

`tools/combine_test.py` scored combination rules against five kinds of market, including one
that genuinely mean-reverts:

| Rule | random | drift | momentum | mean-reverting | drift+pullbacks | worst case |
|---|---|---|---|---|---|---|
| MACD-V only | 51.3 % | 65.7 % | 54.9 % | **29.7 %** | 58.2 % | fails |
| reverse-fade only | 49.5 % | 48.9 % | 44.1 % | 69.5 % | **23.3 %** | fails |
| fixed trio, 2 of 3 | 50.3 % | 65.2 % | 57.1 % | **29.5 %** | 81.9 % | fails |
| **memory-conditional** | **51.5 %** | **66.5 %** | **55.8 %** | **51.3 %** | **80.8 %** | **never below a coin flip** |

**The decision this forced.** The regime word is not a veto — it is the **switch that chooses
which family to listen to**:

- memory says **Ranging** → listen to the reversion reading;
- memory says **Trending** or **Random** → listen to the continuation readings;
- memory **Unclear** → continuation, but only when both of them agree.

That is `DecideSignal` in the file, and it is the only rule that was not below 50 % in any
market tested.

### Measurement 4 — the arithmetic itself was checked, and two bugs were caught

`tools/selftest.py` found, before any MQL5 existed:

- **DFA and R/S were being run on prices instead of increments**, so every series scored a
  Hurst of about 1.4 and every memory label came out `Unclear`. Fixed, and now a random walk
  scores 0.548, a persistent series 0.696, a reverting one 0.412.
- **A percentile was being applied to a raw random walk**, which has no stationary
  distribution, and fired 12 % of the time instead of 5 %. That is why percentiles in this EA
  are only ever applied to a **bounded reading** — now measured at 5.29 % for the envelope
  position and 5.46 % for `|MACD-V|`, against a stated 5 %.

Both would have shipped silently as plausible-looking numbers. That is the entire argument for
building the proving ground first.

---

## 1. What it works out for itself

- **The symbol**: exact name with suffix, digits, tick size, contract size, volume min / max /
  step, stops and freeze levels, filling mode, trade mode. Never guessed from a name.
- **The account**: company, server, currency, equity, and whether it is **hedging** or
  **netting** — which decides whether two lanes may hold opposite positions.
- **The instrument's size**: the **median** absolute close-to-close change; and the median
  spread for this server hour, sampled live. Every threshold is expressed against these, which
  is why one file behaves sanely on gold at 3 500 and on EUR/USD at 1.08.
- **Its class**: metal, forex, index, energy, crypto, stock, or Other — from the broker's own
  metadata, with six letters and no other clue treated as a currency pair. **A class may raise
  a floor or set a gate. It never changes the strategy.**
- **Market state**: open, closed with the next opening time, disconnected, stale quote,
  trading unavailable, or unknown. Never "closed" for something that is not a closure.

## 2. Sessions and the timeframe gate

Session labels are Tokyo 09:00–18:00, London 08:00–17:00, New York 08:00–17:00 in their own
local hours, marked `(est.)` when the UTC offset cannot be independently verified — the
Strategy Tester always falls in that case, where `TimeGMT()` is simulated server time.

**Only M5, M15 and M30.** On any other chart the panel prints, in red:

```
 OUT OF RANGE - attach to M5, M15 or M30
 Nothing is read, planned or sent on this chart.
```

No readings, no plan, no order, no record line, and no touching of a resting order. Refusing is
one line of panel; scaling a fourth personality nobody measured would be a silent strategy
change.

## 3. The three readings

| Panel word | Built from | Votes |
|---|---|---|
| **TREND** | MACD divided by its own volatility (MACD-V), the momentum reading | up when the reading is positive, above its signal line, and stronger than 60 % of its own recent history |
| **PUSH** | directional movement, Wilder-correct | up when the plus line is above the minus line, and both the strength and the separation beat 55 % of their own history |
| **STRETCH** | position inside the volatility envelope, as a percentile | fades: stretched high votes down, stretched low votes up |

**STRETCH is deliberately a reversion reading.** It is the one that disagrees with the other
two, and measurement 3 is why it decides on its own when memory says the market is ranging, and
never decides when the market is trending.

Every one of them abstains sometimes — measured at 72 %, 59 % and 71 % of bars. Without
abstention the score would be a two-state guess.

## 4. REGIME, and why it is not a veto

`REGIME` is two measured words:

- **memory** — `Trending`, `Random`, `Ranging`, `Unclear`, from a detrended-fluctuation estimate
  of the Hurst exponent, cross-checked by rescaled range and by a variance ratio. Disagreement
  is `Unclear`, never an average.
- **volatility** — `Quiet`, `Normal`, `Wild`, the percentile of envelope width in its own
  history.

It does not block a trade. It **chooses the reading family** (§0.1, measurement 3), which is a
far better use of it than a veto, and it earned that role by measurement.

## 5. The self-configuration engine

This is point 5 of your list, and it is the part easiest to fake. Fake is: scan twenty settings
and keep whichever made the most money last month. Real is what is in the file.

| Kind of number | Examples | Adapts? | Why |
|---|---|---|---|
| **Identity** | MACD 12 / 26 / 9, volatility window 26, directional movement 14, envelope 20 | **no** | these lengths *are* the indicators on the owner's own chart. If the EA quietly used 9/19/7 the panel would describe a chart nobody can look at, and the comparison against Automate would be worthless |
| **Unit** | the size of an ordinary bar, one tick, this hour's spread | **yes**, from the symbol | the only reason one file works on gold and on EUR/USD |
| **Threshold** | what counts as stretched, strong, or agreeing | **yes**, as a percentile of the reading's own distribution | this is what removes every tuning input |
| **Calibration window** | 300 / 400 / 500 bars | **yes**, by lane role | a scalper must adapt within an hour; an intraday lane should reflect the session |
| **Gates** | spread gate, warm-up length, stop buffer | **yes**, by class and by live samples | |

**The one thing that does not adapt, and why.** Indicator lengths are canonical. Adapting them
would make the panel describe a chart the owner cannot reproduce, and the measurement showed it
is the *decision rule*, not the lengths, that carries the edge. That is a deliberate trade, not
an omission.

**When a percentile cannot be computed** — fewer than 60 samples — the reading votes neutral,
the cell says `CALIBRATING`, and because a silent reading cannot reach a decision, **an
uncalibrated lane cannot trade.** That is rule 1 applied literally.

## 6. What the panel says

```
 OLD MATE   XAUUSDm  |  Metal  |  Hedging  |  Equity 1000.00 USD
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

 RECORD  today  calls 2R/1W   trades 1W/0L
         all    calls 38R/31W trades 4W/3L
 Readings  MOM 55% (120)   PUSH 52% (141)   STRT 47% (96)
 Saved | Tweak: off | Last closed bar 14:35 server
```

| Word | Means exactly |
|---|---|
| `TREND` + a bar count | the momentum reading's direction and how long it has held |
| `REGIME` two words | memory, then volatility. Counted, never guessed |
| `SCORE` `2/2` | how many of the readings that spoke agree with the call. **Agreement, never a win rate.** `±3` is impossible by construction — the two families never agree |
| `SIGNAL` `64% (18)` | the call, and the share of replayed analogues that reached their measured target, with the sample size. Withheld under 24 cases |
| `HOLDS` | median remaining bars for this state from its own completed runs, with the middle range |
| `STATE` | `READY`, `WAIT: <reason>`, `NO SIGNAL`, `DATA WAIT` — what the *plan* is |

A second panel (switch `Diary details`) shows each lane's raw reading values, the two Hurst
estimates and the variance ratio, so a number can always be argued with.

## 7. Forward vision — the honest version

Four numbers, each **counted from recorded outcomes**, each with its sample size, each withheld
when the sample is too small:

1. **HOLDS** — how much longer this state lasts, from the lane's own completed runs
   conditioned on how far this one has already got.
2. **reach %** — among replayed analogues of the same direction, each judged with the same kind
   of structural stop this lane places, the share that reached the measured target before an
   equal-sized stop, within the lane's horizon.
3. **typical bars to the target** — from the same replay, shown in the details panel.
4. **the stop that decided it** — every analogue is judged with a stop of the same size the
   trade in front of you will carry, not an easier one.

What is **not** claimed: the bar a turn will happen, or a price at a time. A straight line
through the current move is not drawn anywhere in this file. That method was tested in Automate
and refused, and nothing here reintroduces it.

## 8. Entry, stop, target, size

- **Unanimous** (`score == spoke`, at least two spoke) → market order at a fresh quote.
- **Otherwise** → a resting limit at the nearest **already-confirmed** three-bar turn on the
  correct side, never a price the market has passed.
- **Stop** — behind a confirmed three-bar turn, plus a buffer of the larger of one tick and the
  live spread, snapped to the price grid, checked against the broker's minimum stop distance.
  No turn within the structure window → `WAIT`, never a wider stop.
- **Target** — replayed analogues, cut at 80 % of their median favourable run. Then capped
  before the nearest confirmed opposing turn, and required to clear the spread by 2×. A
  measured target of zero is `WAIT`, with the reason named.
  What the replay matches is **direction and the kind of stop**, not the reading grade:
  recomputing the historical grade at four hundred analogue bars would mean running the whole
  indicator stack four hundred times per bar, and claiming a filter that is not applied would be
  worse than not claiming it.
- **Size** — 0.50 % of equity, converted to lots by **`OrderCalcProfit`**, the terminal's own
  money calculation for this symbol and this stop. Never hand arithmetic, never an assumed pip
  value. Refused when the budget cannot buy the minimum lot, unless `Minimum lot` is ticked.
- **Total risk cap** — 1.50 % of equity across all lanes, counted against the stops actually
  resting at the broker.

## 9. Management, to the end

Built, not deferred:

- **TP1** — close 50 % at the halfway target, then protect the rest. If the broker's minimum
  volume cannot hold the remainder, the partial is skipped and the stop is protected instead —
  it is never pretended.
- **Trailing stop** — once TP1 is banked or the trade is one risk-unit in profit, the stop
  follows the best price at half a risk-unit behind, and after TP1 never goes back behind entry.
  Steps respect the stops level, the freeze level and the price grid.
- **Limit life** — three lane-periods (15 / 45 / 90 minutes) at the broker, plus a local
  watchdog, plus cancellation the moment the market walks through the resting price.
- **The idea latch** — one idea per signal, not one per bar. A **winning** close re-arms the
  lane; a losing close does not.
- **Netting accounts** — two lanes may not hold opposite positions; the slower lane yields and
  the panel says so.
- **Cold start** — the EA reconciles with the broker's positions and orders, never with its own
  memory.

## 10. The record

One CSV per account and symbol, appended, read back at attach so counts survive a restart.

| Line | Written | Contains |
|---|---|---|
| `CALL` | three bars after the call | lane, grade it was made at, right / wrong / flat, and each reading's own verdict |
| `TRADE` | when a filled trade closes | side, lot, and the **money** — profit + swap + commission on every deal |
| `TWEAK` | if the bounded tweak fires | which reading, its measured rate |

The panel shows today and all-time, and a **per-reading scoreboard**. That last line is the
thing Automate could not offer: it tells you *which of the three readings* is lying, not just
whether the lane was right.

**The one bounded self-tweak** (switch `Tweak`, off by default): if a reading has at least 100
graded calls and is right less than 45 % of the time, it stops counting toward agreement once.
It is marked with `*`, written to the record, and never re-promotes itself. It cannot promote
anything and cannot touch risk.

## 11. The ten switches

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
| `Bypass risk budget` | off | **the wider override**: a minimum lot larger than the budget is no longer refused, and the 1.50 % total cap is released. The panel shows `RISK BYPASS ON`, and every order still reports what it actually risks |

No period, band, threshold or session time is ever an input.

## 12. What will not be built

An indicator that repaints or reads future bars (the popular 2024–25 kernel-smoothing family
uses future candles by default) · a "probability of winning" · a predicted bar of the turn · a
machine-learning classifier nobody can audit · a per-indicator input · a live re-fitting of
parameters · an ATR-multiple target or stop · closing a position on a clock · trading on any
timeframe other than M5 / M15 / M30.

## 13. Validation

**Done:**

1. `python3 tools/preflight.py OldMate.mq5` — clean, 22 checks, 0 failures: delimiters
   balanced, no duplicate definitions, no calls to functions that do not exist, every call's
   argument count correct, **every struct field read exists on that struct**, no dead constants,
   every input read, guards present.
2. `python3 tools/selftest.py` — **ALL CHECKS PASSED**: Wilder seeding, true-range gaps,
   MACD-V scale-freedom (0.00 % spread between a 100-price and a 3 500-price series), percentile
   calibration (5.29 % and 5.46 % against a stated 5 %), memory separation (0.548 / 0.696 /
   0.412), reading independence, and a truncated-versus-full-series test proving no reading
   depends on a later bar.

**A second read-through found six real defects, all fixed.** They are worth naming, because
they are the argument for reading code after writing it:

| Defect | Consequence had it shipped |
|---|---|
| the record was read back with every field one place off | restored counts would have been wrong after every restart |
| a reading was graded on the calls where it abstained | a quiet reading would have looked better than it was, and the tweak would have demoted the wrong one |
| `g_lane[idx].ok` where the field is on `g_plan` | would not compile |
| TP1 was taken from the live plan instead of the trade | a rebuilt plan could have triggered the partial on the wrong side |
| a demoted reading still counted toward the decision | the tweak would have been decorative |
| no session table was reported as "Market closed" | a false report, which rule 1 forbids outright |

The checker was extended to catch the "field does not exist" class automatically — and caught
the compile error on its first run.

**The first real compile found ten errors, all fixed.** Reported from MetaEditor on
2026-11-01 and repaired the same day:

| Compiler said | Real cause | Fix |
|---|---|---|
| `'g_spr' - invalid array access`, `parameter passed as reference` | a row of a 2-D array cannot be passed by reference | the row is copied into a 1-D array first |
| `undeclared identifier 'SYMBOL_TRADE_DISABLED'` | that is the MQL4 name | `SYMBOL_TRADE_MODE_DISABLED` |
| `cannot convert enum` at the limit order | two `datetime` values were added; MQL5 will not | add in `long`, cast back once |
| `undeclared identifier 'SelectByTicket'` (×3) | `COrderInfo` has no `SelectByTicket` in this build | pending orders now read through the built-in `OrderSelect`/`OrderGet*` calls, with six small accessors of our own |

Two more of the same class were found by sweeping for the pattern rather than waiting for
the next compile: every `datetime` subtraction in the file (five of them) is now done in
`long`, and the enum ternary in `OnInit` is cast explicitly. The checker was also taught the
`ENUM_*` return type, which it had been misreading as an unknown function.

**Field question answered: why no trade on M30 with `2/3 BUY`.** There were two
independent blockers, and the panel was hiding both.

1. **`Market status unknown` stopped every send.** The broker publishes no session table for
   crypto symbols, so `g_sessCount` was zero and the state was reported as unknown — which
   `SendPlan` correctly refuses. The consequence was that no crypto symbol could ever trade.
   No published session table means the symbol is not session-restricted, not that the state is
   unknown, so it is now `Market open (no session table)` — with trade mode, connection and quote
   freshness still checked, so a genuinely closed or stale symbol still stops.
2. **A finished plan could read `READY` while nothing was sent.** `PlanStateText` now asks the
   same gate `SendPlan` asks, and prints `HOLD: <the blocker>` instead.

Every refusal now also carries its arithmetic, shown on hover: the spread against its hourly
median and gate, the open risk against the cap, the stop against the prime minimum, the measured
target against the spread, and — the one that most often bites a small account —
`budget $1.93 (0.50% of $385.19); one lot risks $300.00 at this stop; min lot 0.01 risks $3.00`.

**Field feedback on the panel, fixed.** The first screenshot from a live chart
showed four things wrong, all now corrected:

| What was seen | Cause | Fix |
|---|---|---|
| the word `Label` on blank lines | an empty string does not clear a label's text, so the object kept its default caption | a blank line is drawn as a single space |
| lines overlapping each other | 15 px spacing against a taller rendered font | line height is now `font size + 9`, and the box height is computed from the line count |
| text unreadable over candles | no background at all | every panel is drawn on an opaque rectangle, sized to its own longest line |
| **no panel at all when the market was closed, or on an unsupported timeframe** | `ChartRedraw()` was only called in `OnDeinit`. With no ticks there is no repaint, so the objects existed but were never shown | `ChartRedraw()` now runs after every draw, driven by the one-second timer, so a closed market still repaints |

The column widths also moved into one place (`C_TF`, `C_TREND`, `C_REGIME`, …) so the header
and the rows can never disagree again. The details panel now sits beside the main panel when
there is room and below it when there is not, instead of running off the edge.

**The second compile found one error, fixed the same way.** `CTrade::OrderOpen`
takes ten arguments; the file passed nine. The seventh is the stop-limit price, so leaving it
out slid the time-in-force enum into a `double` slot and the compiler reported
`cannot convert enum` rather than a missing argument. It is now passed as `0.0`, which is what a
plain limit order needs. `tools/preflight.py` gained an argument-count check for every library
method this file calls, so a wrong count is caught here rather than by MetaEditor.

**Still to do, and only this:**

3. Compile in MetaEditor — expect **0 errors, 0 warnings**. Any warning is a defect, not
   noise.
4. Attach to a demo chart of M5, M15 and M30. Confirm: the header is true; `OUT OF RANGE` on
   H1; `DATA WAIT` with shallow history; every panel number reproducible by hand from exported
   bars; a reading that does not change when the chart is re-read an hour later.
5. One week on demo, then a small live size. If the record's per-reading scoreboard shows a
   reading below a coin flip, the measurement above says which family it belongs to and what to
   do about it.

## 14. Open questions for you

| # | Question | Default if unanswered |
|---|---|---|
| Q1 | Risk per idea: 0.50 % of equity, cap 1.50 % across lanes | as built |
| Q2 | On a netting account, the slower lane always yields | as built |
| Q3 | Should the forward `reach %` appear on the panel or only in the details panel? | on the panel, as built |
| Q4 | Is a `±3` score being impossible acceptable, or do you want a fourth reading that can agree with both families? | acceptable — it is the measured structure, not a limitation |

## 15. References

- **MACD-V** — Alex Spiroglou, 2022. Charles H. Dow Award, NAAIM Founders Award.
- **Wilder's smoothing** — *New Concepts in Technical Trading Systems*, 1978. The correct
  seeding of RSI, ATR and ADX, which platform copies get subtly wrong.
- **Hurst exponent and variance ratio** — persistence measures; detrended fluctuation analysis
  is the more robust estimator of the two.
- **Percentile-based thresholds** — current practice replacing fixed 70/30 and 25-type levels.

Formulas, the reject pile and the source links: [indicators.md](indicators.md).
