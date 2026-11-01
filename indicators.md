# OldMate — indicator design record

Companion to [oldmate.md](oldmate.md). That file says what the EA does. This file says **which
conventional instruments it uses, in what modern form, why, and what was rejected** — so the
choices can be argued with and so nothing here has to be taken on trust later.

Rule for this document: every claim is either a published source or a measurement we will run
and print. Where a number is not yet known, it says *to be measured* rather than guessing.

---

## 1. Why "conventional name, modern arithmetic"

A trader looking at a chart already knows what MACD, ADX and Bollinger bands are for. Throwing
those away means the panel has to be learned from scratch, and an unexplainable panel is a panel
that gets switched off during its first losing week.

But the *bare* conventional versions have four well-known faults, and all four are fixable
without changing the name:

| Fault in the bare version | What it does to a real account | Modern fix used here |
|---|---|---|
| **Scale depends on the symbol** — a raw MACD of 2.5 means nothing until you know the instrument and the decade | the same rule cannot be used on gold and on EUR/USD; every symbol needs its own settings | divide by the instrument's own volatility (MACD-V) |
| **Fixed thresholds** — RSI 70/30, ADX 25 | thresholds that were sensible for one market in one era, applied forever to everything | compare each reading to its **own rolling percentile** |
| **Fixed speed** — always 14 bars | too slow in a clean move, too fast in chop; the indicator whipsaws exactly when it should stay quiet | let measured cleanliness set the **speed** |
| **No way to know if it is helping** | three plausible readings, no evidence any of them earns its place | a **per-reading scoreboard**, graded on outcomes |

None of these fixes changes what the panel *says*. `TREND`, `PUSH`, `POSITION` are still
familiar ideas. What changed is that the numbers behind them no longer need a human to tune them.

---

## 2. The three chosen readings

### 2.1 Momentum — MACD, in its volatility-normalised form (MACD-V)

**What it is.** Gerald Appel's MACD — the gap between a fast and a slow exponential average —
divided by the instrument's own average true range, times 100. The 12 / 26 / 9 shape is
unchanged, and the volatility window matches the slow average by design.

**Who and when.** Alex Spiroglou, "MACD-V: Volatility Normalised Momentum", 2022. It received
the CMT Association's **Charles H. Dow Award** and the NAAIM **Founders Award**, and it now
exists as an MT4/MT5 indicator in the MQL5 code base and as standard scripts on TradingView and
StockCharts.

**Why it earns the momentum slot.**

- A reading of `+100` means "momentum equal to one unit of this instrument's own volatility" —
  the same statement on gold, on EUR/USD and on an index. That is the property that makes a
  zero-input panel possible.
- It keeps the parent's signal line, zero line and histogram behaviour, so nothing has to be
  relearned.
- Its published reading zones are a genuine scale, not folklore: roughly −50 to +50 is a
  neutral zone where crosses are least reliable, ±50 to ±150 is real momentum, beyond ±150 is
  stretched relative to volatility.

**What we will do with it honestly.** The published zone boundaries are a starting reference,
**not** a law. Because the panel is percentile-driven, the EA will use the reading's position in
its own recent distribution for the vote, and keep the published zones only as a human-readable
label. If the two ever disagree systematically on this broker's data, the record will show it.

**What it will not do.** It will not be treated as "overbought means sell". In a strong move,
stretched momentum is a sign of strength; the reading votes direction, and the position reading
handles stretch.

Sources:
- Concept and formula: <https://www.luxalgo.com/library/concept/macd-v/>
- Author's own summary and award citation: <https://www.benzinga.com/pressreleases/22/05/p27046755/>
- Independent implementations (scale, bands): <https://www.tradingview.com/script/99lPD1fh-Case-s-MACD-V-Volatility-Normalized-Momentum/>,
  <https://www.mql5.com/en/code/66221>

### 2.2 Push — directional movement (ADX / DMI), Wilder-correct

**What it is.** Wilder's directional movement: how much of the recent range was made on the up
side versus the down side, smoothed, with an index of how directional the whole thing is.

**Why it earns the push slot.** It is the only classic that answers "is anybody actually in
control here", and it is built from highs and lows rather than closes, so it is not a copy of
the momentum reading.

**The modern parts.**

1. **Correct arithmetic.** Wilder's smoothing is an average with weight `1/n`, seeded from a
   simple average — not an ordinary exponential average with weight `2/(n+1)`. Most retail code
   muddles the two, and MT5 itself ships two variants (`Average Directional Movement Index` and
   `Average Directional Movement Index Wilder`) whose lines genuinely differ. OldMate computes
   both directional lines from the correct seed and does not depend on a platform indicator
   handle, so the number on the panel is the number the file computes.
2. **Percentile strength, not 25.** The written-down `25` is a convention from a 1978 book
   about commodity markets. Here, "strong enough to vote" is where the current reading sits
   against this symbol's own recent distribution.
3. **Abstention is allowed.** When the two directional lines are within a deadband expressed in
   units of an ordinary bar, the reading votes neutral instead of picking a side. Without this,
   `2/3` could never happen and the score would collapse to a two-state guess.

Sources:
- Wilder's smoothing explained (and the seeding problem): <https://chartschool.stockcharts.com/table-of-contents/technical-indicators-and-overlays/technical-indicators/average-directional-index-adx>
- The two MT5 ADX variants: <https://admiralmarkets.com/education/articles/forex-indicators/how-to-use-adx-indicator-in-mt4>
- RMA definition as Wilder intended: <https://github.com/TA-Lib/ta-lib/issues/348>

### 2.3 Position — where price sits inside its own volatility envelope

**What it is.** The Bollinger idea: a middle average with a band whose width is the instrument's
own recent dispersion. Read as **position** — top, middle, bottom of the band — and as
**width** — squeeze or expansion.

**Why it earns the position slot.** Position is the one measurement that is genuinely about
*stretch* rather than *speed*, so it is not a third copy of momentum. It also carries the
squeeze, which is the best-understood thing this family measures.

**The modern parts.**

1. **Percentile position, not raw percentage.** Instead of "80 % of the way up the band", the
   reading is "where this position sits in its own recent distribution". Same information,
   comparable across symbols and eras.
2. **Width as a percentile too.** Band width compared with its own history — the 5th percentile
   is genuine compression, the 95th genuine expansion — rather than an arbitrary "narrow" or
   "wide".
3. **Volatility is a state, not a signal.** A wide band in a wild market means a different
   thing from a wide band in a quiet one, and the CONDITION column keeps that distinction
   visible rather than folding it into the vote.

Sources:
- Percentile-based band-width regimes and normalisation: <https://www.tradingview.com/script/23tnzSdb/>
- Bollinger bands as a volatility-relative measure (and why a fixed-threshold oscillator is
  not the same statement): <https://www.tradingview.com/chart/ES1!/FwfqO55g-Buy-the-Panic-What-20-Million-Bollinger-Tests-Found/>

---

## 3. The two context measures, shown as one REGIME cell

Neither votes. Both are shown because they change how a reading should be read by a human. On the
panel they sit together as one `REGIME` cell with two words — `Trending Wild`, `Random Normal`,
`Ranging Quiet` — because they are two halves of one description: what kind of series this is,
and how loud it currently is. The exact procedures are in section 9.5.

### 3.1 CONDITION — volatility against its own range

`Quiet`, `Normal`, `Wild`, from the percentile of current volatility in the instrument's own
recent history. Volatility clusters: high follows high, low follows low. This column exists so
that "the target is 575 points" is read in context, and so a wide-spread hour is visible before
it becomes a refusal.

### 3.2 MEMORY — does this market push, wander, or snap back

`Trending`, `Random`, `Reverting`, from a rolling estimate of long-range dependence — the Hurst
exponent, cross-checked by a variance ratio. Conventionally: above about 0.55 the series
persists, below about 0.45 it reverts, near 0.5 it is a random walk and neither momentum nor
mean reversion has structural support.

**Why this instead of a moving-average band.** A band tells you where price is relative to an
average. Memory tells you what kind of series you are in — which is the question a strategy
actually needs answered, and the reason it is now the standard regime core in quantitative
practice.

**The honest limits, stated up front.**

- The Hurst exponent is an **estimate**, and on short windows it is a noisy one. Two estimators
  (rescaled range and detrended fluctuation analysis) give different answers; DFA is the more
  robust, and will be the primary with rescaled range as a cross-check.
- Estimates that disagree are shown as `Unclear`, never averaged into a false confidence.
- It is a **context label, not a veto**. Whole profitable days happen at a Hurst near 0.5, and
  blocking them on a noisy estimate would be a silent strategy change.

Sources:
- Hurst as regime core, with the 0.55 / 0.45 conventions: <https://fractalcycles.com/guides/market-regime-detection>
- Peer-reviewed comparison of estimators, and regime-conditional performance: <https://apjm.apacific.org/PDFs/12-109.pdf>
- Practical three-number regime checklist (ADX + volatility percentile + Hurst): <https://fortraders.com/blog/momentum-vs-mean-reversion-strategies-for-challenges>

---

## 4. The spares — measured, and may take a slot

Neither is in the design above, and neither is ruled out. Both are conventional, both are
upgraded in the same way, and both are measured in stage 0 against the three chosen readings. If
one of them separates outcomes better than a chosen reading, it takes that slot and this file
records the swap.

| Spare | Modern form | Why it might win | Why it might not |
|---|---|---|---|
| **RSI** | Wilder's RSI whose *smoothing speed* adapts to how clean the move is (Kaufman's efficiency ratio, bounded by the classic fast/slow constants), with thresholds as percentiles of its own history | reacts faster in a clean move and stays quiet in chop — precisely the failure mode of a fixed 14 | it is a close relative of the momentum reading, so it may fail the independence check |
| **Stochastic** | same adaptive treatment, plus percentile thresholds, plus velocity of the two lines rather than only their cross | it is a position measure that includes a turn, which the envelope alone does not | same overlap risk with the position reading |

Sources:
- Adaptive RSI via efficiency ratio, with bounded smoothing and the same 30/50/70 reading:
  <https://docs.wickra.org/Indicators/Indicator-AdaptiveRsi>
- Efficiency ratio as the general adaptive mechanism (KAMA lineage):
  <https://www.luxalgo.com/library/concept/adaptive-parameterization/>
- Percentile-adaptive thresholds in practice: <https://www.tradingview.com/script/a6c7sYp1-Adaptive-RSI-BOSWaves/>

---

## 5. The reject pile, and why

| Rejected | Reason |
|---|---|
| **Nadaraya-Watson envelope / kernel smoothing** (the popular 2024–25 indicator) | in its default mode it fits each bar using bars on both sides, so the historical chart shows a curve that did not exist in real time. It repaints. A non-repainting mode exists, but a repainting *default* is exactly the trap a real-money EA must not carry: <https://www.quantum-algo.com/blog/guides/nadaraya-watson-envelope-complete-guide/>, <https://www.mql5.com/en/blogs/post/766072> |
| **KNN / "machine learning" classification indicators** | no auditable arithmetic; a closed trade could not be explained to its owner. Refused on that ground, not because it is new |
| **Ehlers cycle/bandpass filters** | already built and already measured in `Automate`: the sign was a coin flip against direction on every test, because the filter removes the slow drift a trend reading is supposed to report. Kept there only as a printed comparison. Not carried into OldMate |
| **Kalman-filter slope** | measured against the simpler alternatives in `Automate` and not reachable; nothing to gain by re-running it here |
| **Laguerre RSI, Jurik-style smoothing** | closed-form or opaque smoothing whose properties cannot be verified from the source; a reading must be reproducible by hand from exported bars |
| **Renko / Heikin-Ashi charts as a basis** | invented prices. Everything here is built from the real bars the broker delivers |
| **Volume and order-flow families** | symbol-dependent and unreliable across the brokers this EA will actually meet; not refused forever, but out of version 1 |
| **A "confidence %" from a fitted model** | already tried in `Automate`: a logistic model on nine indicators helped in one era and hurt when the eras were swapped, and was badly calibrated out of sample. The record keeps a counted scoreboard instead of a fitted percentage |

---

## 6. What must be measured before any of this ships

Stage 0 exists so that the choices above are tested rather than asserted. All results are
printed, including the ones that make this document look silly.

| # | Test | Pass condition | If it fails |
|---|---|---|---|
| 1 | **Independence** — agreement matrix between the three readings, several symbols, long history | no pair agrees more than roughly 9 times in 10 | the most redundant reading is replaced by a spare |
| 2 | **Direction** — sign at bar *t* against the next 4 / 6 / 8 bars, real and synthetic | materially better than a coin flip where structure exists, and no worse than a coin flip on pure noise | recorded in this file; the reading is demoted, not deleted |
| 3 | **Threshold calibration** — does a 5 % percentile fire about 5 % of the time? | within a stated tolerance, on every lane | the percentile window or the calculation is wrong and is fixed before stage 2 |
| 4 | **Repaint** — value stored at close versus value recomputed ten bars later | identical, bar for bar | the reading is rebuilt, not shipped |
| 5 | **Swap of eras** — any calibration fitted on one period, tested on another, both directions | the gain keeps its sign both ways | the calibration is noise and is deleted |
| 6 | **Synthetic truth** — series with known drift, known regimes, known noise | the readings behave as described in this file | the description is wrong and gets corrected here |
| 7 | **Per-reading scoreboard** — after a few hundred real calls | each reading's hit rate is visible and stable enough to mean something | the column stays in hover text only |

Automate's own experience is the warning: two rounds of confident advice about which filter was
best were both overturned by measurement, and the simplest option won. The same could happen
here — and if it does, this file records it rather than quietly moving on.

---

## 7. Canonical, adaptive, or measured — the three kinds of number

The single most important rule in this file, because it is where a "self-configuring" EA usually
turns into a curve-fitted one.

| Kind | Examples | Rule |
|---|---|---|
| **Identity** | 12 / 26 / 9 for MACD, 26 for its volatility window, 14 for directional movement, 3-bar swing confirmation | **fixed and canonical.** These lengths *are* the instrument the owner can see on their own chart. Changing them silently would make the panel describe a chart nobody can look at, and would end the comparison with Automate |
| **Unit** | the size of an ordinary bar, one tick, this hour's median spread | **always measured from this symbol.** This is the only reason one file behaves sanely on gold at 3,500 and on EUR/USD at 1.08 |
| **Threshold** | what counts as stretched, strong, quiet, or far enough apart to vote | **measured from the reading's own distribution**, as a percentile, with the sample count shown. This is what removes every tuning input |
| **Speed** | how fast a smoothing reacts | **measured from the cleanliness of the move** (efficiency ratio), inside fixed documented bounds |

Two things this rule forbids, both of which would otherwise sneak in:

- **Fitting identity lengths to history.** A 9/19/7 MACD that back-tested better last quarter is
  not a better indicator, it is an indicator fitted to last quarter. If stage 0 finds a
  non-canonical setting genuinely superior, it becomes a **documented constant with its
  measurement beside it**, not a live search.
- **Falling back to a written-down threshold** when there is not enough data to compute a
  percentile. The correct behaviour is to report `CALIBRATING` and vote neutral, which makes the
  lane unable to trade on an unmeasured reading. A fallback would hide exactly the situation the
  owner most needs to see.

---

## 8. Lane personalities — the numbers that actually change

The three lanes are the same method at three working speeds. These are the quantities that
differ, and each difference has a reason.

| Quantity | M5 — scalping | M15 — short-term | M30 — intraday | Why |
|---|---|---|---|---|
| Planning horizon | 4 bars | 6 bars | 8 bars | how far ahead the lane is allowed to claim a target |
| Structure window | 36 bars | 48 bars | 72 bars | a scalper's valid turning point is recent; an intraday one is not |
| Deadband width | tightest | middle | widest | on M5 a small move *is* the trade; on M30 it is noise to be ignored |
| Percentile lookback | shortest | middle | longest | M5 must adapt within an hour; M30 should reflect the session |
| Adaptive speed bounds | fastest pair | middle pair | slowest pair | the role of the lane, expressed inside Kaufman's classic bounds |
| Spread gate | strictest | middle | most forgiving | the spread is a large share of a scalper's target and a small share of an intraday one |
| Limit patience | 15 min | 45 min | 90 min | three lane-periods, so the clock is the lane's own unit |
| Risk per idea | 0.50 % | 0.50 % | 0.50 % | deliberately equal: the lanes differ in speed, not in how much the owner can lose |

Equal risk is a decision, not an oversight. Sizing the scalper smaller "because it trades more"
would mean the three lanes can no longer be compared on the record, which is the purpose of the
whole exercise.

---

## 9. Exact procedures

Written at formula level so that each can be checked by hand against exported bars. In the code,
each of these sits next to a comment naming the procedure and its source.

### 9.1 The measured unit

`unit = median( |close[i] − close[i−1]| )` over the calibration window, floored at one tick.

Median, not mean: a single news candle must not redefine the instrument. Every deadband is then
`unit × √horizon`, floored at one tick — the square root because a move over four bars is larger
than over one, and √n is the honest scaling for a wandering series, not noise-free travel.

### 9.2 Momentum — MACD-V

1. `EMA_fast` and `EMA_slow` over 12 and 26, **seeded by a simple average** of their first n
   values, so the first printed value is not a warm-up artefact.
2. `ATR_26` by **Wilder's smoothing**: first value is the simple average of 26 true ranges, then
   `ATR = ATR_prev + (TR − ATR_prev)/26`. True range is `max(H−L, |H−C_prev|, |L−C_prev|)` — gaps
   count.
3. `MACD-V = (EMA_fast − EMA_slow) / ATR_26 × 100`. The denominator's window matches the slow
   average, which is why the ratio is dimensionless.
4. Signal line: 9-period EMA of MACD-V, seeded the same way.
5. **Vote:** up when MACD-V is above its own neutral band and above its signal line; down
   mirrored; otherwise neutral. The neutral band is a percentile of `|MACD-V|` in its own recent
   history, not the published ±50 — the published zones are used only as a human-readable label
   and are never the trigger.
6. **Percentile:** the value's rank among its own last N closed readings, N set by the lane's
   role, with the sample count required and displayed.

### 9.3 Push — directional movement, Wilder-correct

1. `+DM = max(H − H_prev, 0)` when it exceeds `L_prev − L`, else 0; `−DM` mirrored. Inside bars
   produce zero for both, which is correct.
2. Smooth `+DM`, `−DM` and `TR` with **Wilder's 1/n smoothing**, simple-average seed.
3. `+DI = 100 × smoothed(+DM)/smoothed(TR)`, `−DI` mirrored.
4. `DX = 100 × |+DI − −DI| / (+DI + −DI)`, `ADX` = Wilder-smoothed `DX`.
5. **Vote:** up when `+DI − −DI` exceeds a deadband of `unit × √horizon` **and** `ADX` is at or
   above its own percentile threshold for this symbol; down mirrored; **neutral** when the two
   directional lines are inside the deadband, or when `ADX` is below the threshold. Abstention is
   deliberate: without it `2/3` cannot occur and the score is a two-state guess.
6. Warm-up: Wilder's smoothing converges slowly — roughly 150 bars for a 14-period ADX to match
   the converged value. That is computed and enforced; the lane says `DATA WAIT` until it is met.

### 9.4 Position — the envelope

1. Middle = 20-period simple average. Width = 2 × **population** standard deviation over the same
   20 bars (Bollinger's own convention, `n`, not `n−1`).
2. `position = (close − middle) / (2 × SD)`, which is %B expressed around the middle.
3. **Percentile-rank `position`** in its own recent history. The vote is on that rank, not on the
   raw value: "top of the top decile of this symbol's own positional readings", not "0.9".
4. `width` is likewise ranked, giving the volatility state (`Quiet` / `Normal` / `Wild`) used by
   REGIME and by CONDITION, as a 5th–95th percentile compression/expansion reading.
5. **Vote:** up when the positional rank is high and the market is not in the reverting state, low
   mirrored, otherwise neutral. The persistence condition prevents the classic error of buying a
   stretched market that is being squeezed upward in a downtrend.

### 9.5 REGIME — memory and volatility

1. **Memory.** Detrended fluctuation analysis gives the Hurst estimate on the lane's long window;
   rescaled range gives a second estimate. Agreement within tolerance → `Trending` (above the
   upper band), `Ranging` (below the lower), `Random` (between). Disagreement → `Unclear`.
   Never an average of the two.
2. **Variance ratio** on the same window: long-horizon variance over short-horizon variance.
   Above one supports persistence, below one supports reversion. It is a **check** on the memory
   word, and a contradiction between word and ratio is shown as `Unclear` rather than resolved
   silently.
3. **Volatility.** The percentile of current volatility (ATR, or the envelope half-width) in its
   own recent history: bottom of the distribution `Quiet`, middle `Normal`, top `Wild`.
4. **Neighbouring windows** may also be computed for comparison; if the label flips between
   neighbouring window lengths, the window is too short and the label reads `Unclear`. (Automate
   learned this the hard way with a 128-hour regime span that could not resolve a label.)

### 9.6 The forward numbers — counted, not predicted

All four come from **recorded outcomes on this lane**, never from a formula applied to a trend
line.

| Number | Procedure |
|---|---|
| **HOLDS** (bars remaining) | Take this lane's completed runs of the same state. Keep those that outlived the current age. The median of their residuals is the estimate; the interquartile range is shown beside it in hover. Below a minimum count of survivors, the cell shows `--` |
| **share that reach target** | Take replayed analogues of the same grade, direction and stop size. Count those that reached the measured target before an equal-sized stop within the horizon. The share and its sample count are shown; below the minimum count, the number is withheld |
| **est. bars to target** | Among the analogues that *did* reach it, the distribution of bars taken. Shown as a middle range, and only when the lane's measured travel per bar points toward the target. Otherwise `unclear` |
| **travel per bar** | Median favourable and adverse travel per bar in this state, on this lane, in units of the measured unit. Hover only |

A straight-line extrapolation of the current move is **not** used anywhere. That is the one
forecast method Automate tested and refused, and nothing here re-introduces it.

---

## 10. Sources

- Spiroglou, A. — *MACD-V: Volatility Normalised Momentum* (2022). Dow Award, NAAIM Founders
  Award. <https://www.benzinga.com/pressreleases/22/05/p27046755/>
- Kaufman, P. J. — efficiency ratio and the adaptive moving average (1995).
  <https://chartschool.stockcharts.com/table-of-contents/technical-indicators-and-overlays/technical-overlays/kaufmans-adaptive-moving-average-kama>
- Wilder, J. W. — *New Concepts in Technical Trading Systems* (1978): RSI, ATR, ADX and the
  smoothing used throughout. <https://github.com/TA-Lib/ta-lib/issues/348>
- Adaptive parameterisation as a design principle.
  <https://www.luxalgo.com/library/concept/adaptive-parameterization/>
- Percentile-based thresholds instead of fixed levels.
  <https://www.tradingview.com/script/23tnzSdb/>
- Hurst exponent as a regime core, with the standard conventions.
  <https://fractalcycles.com/guides/market-regime-detection>
- Detrended fluctuation analysis versus rescaled range (peer reviewed).
  <https://apjm.apacific.org/PDFs/12-109.pdf>
- The repainting warning, stated by the indicator family's own users.
  <https://www.quantum-algo.com/blog/guides/nadaraya-watson-envelope-complete-guide/>
