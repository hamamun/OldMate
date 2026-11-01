# MT — Master Trade

A new Expert Advisor, built **phase by phase**, on the mechanism that was worth keeping from
OldMate. OldMate is not being repaired: it was built in one push, it has hidden logic problems we
have not found, and the honest move is to stop adding to it.

**OldMate is now a frozen reference, not a project.** `OldMate.mq5` and `oldmate_master.md` stay in
the repository as the record of what was measured and what went wrong. Nothing new is added to
them.

## How this project works

Each phase is a **gate**. A phase is finished when its own acceptance list is met on a real chart,
not when the code compiles. Nothing from a later phase is written early, and nothing is "declared
and left inert" — the failure mode that made OldMate untrustworthy.

Two rules inherited, because they were right:

1. **No fallback.** A number that cannot be measured is shown as `DATA WAIT`, `--` or `Unclear`.
2. **The EA may do less than this document says. It may never do something this document does not
   say.**

---

## Phase 1 — the panel: layout, background, font

**Scope: the box, the type, and the grid it sits on. Nothing inside it yet.**

The panel is first because it is the only part the owner sees every minute of every day, and
because OldMate's panel was rebuilt three times in a day for faults that were all visible in the
first screenshot: no background, overlapping lines, the word `Label` on blank rows, and no repaint
on a closed market. A layout decided once, with real numbers taken from working code, removes that
whole class of rework.

### 1.1 What SimpleEA actually uses

Read from `SimpleEA/SimpleAdvisor.mq5` (8 332 lines), the working EA this panel model comes from.
Line numbers are given so every value can be checked rather than trusted.

| What | Value in SimpleEA | Where |
|---|---|---|
| Font face | **`Consolas`** — "monospaced aligns best" | line 168 |
| Font size | **10 points**, as an input, clamped to a **minimum of 6** | lines 167, 7189 |
| Panel background | **`C'48,48,48'`** — a neutral dark grey, as an input with that default | line 169 |
| Panel border | **`clrDimGray`**, flat, 1 px | lines 7315, 7290–7292 |
| Title colour | **`clrWhite`** | line 170 |
| Title size | **font size + 1** → 11 pt at the default | line 7402 |
| Emphasised values | **font size + 1** → 11 pt (trend direction, regime word) | lines 7495 and following |
| Captions (`Trend:`, `Signal:`) | `clrGray`, font size | lines 7471–7478 |
| Secondary text | `clrSilver` | lines 7404, 7413 |
| Separator rule | 1 px `clrDimGray`, inset **4 px** each side, at `y + headerHeight − 6` | line 7316 |
| Left/right padding | **10 px** | line 7350 |
| Title baseline | `y + 7`; other header labels `y + 8` | lines 7401, 7404 |
| Row height | **font size + 11** → **21 px** at the default | line 573 |
| Header band | `HEAD_H` **34 px** + one row = 55 px total | lines 273, 5447 |
| Minimum panel width | **406 px** | line 275 |
| Column anchors | 150 / 282 / 414 px, drawn at a **font-9** design and scaled with the font | lines 282–284, 7261 |
| Character width model | `ceil(size × DPI / 72 × 0.55)` — uses the terminal's real DPI, never assumes 96 | line 7229 |
| Object flags | corner left-upper, anchor left-upper, **not selectable, hidden from the object list, drawn in front** | lines 7191–7205 |
| Direction colours | up `clrLime`, down `clrTomato`, sideways `clrSilver`, timing/countdown `clrOrange` | lines 171–173, 7410 |

Two further design rules in SimpleEA are worth more than any single value:

- **The panel is measured before it is drawn.** Width is computed from the longest line it will
  contain, then the background is drawn — so the box always hugs its content and a long line can
  never be clipped (lines 7362–7372).
- **One number sizes everything.** Every column is expressed in **em** — the pixel advance of one
  character — so raising the font widens the columns in proportion instead of crowding text into
  the next cell (lines 7233–7265). Before that change, the columns were raw pixels tuned at font
  9, and at font 10 the caption ran into its own value.

### 1.2 What MT will use

Adopted as-is from SimpleEA, because these are working, readable values, not a matter of taste:

| Element | MT value | Reason |
|---|---|---|
| Font | `Consolas` | a monospaced face is the only way a column layout stays aligned at any size |
| Font size | **10**, clamped to 6 minimum | the size the model was designed at, and the size that was readable on a real chart |
| Background | **`C'48,48,48'`** | opaque, neutral, and dark enough for white and lime text; it reads as a panel, not as part of the candles |
| Border | `clrDimGray`, flat, 1 px | defines the edge on a light or a dark chart template without shouting |
| Title | white, size 11 | one line, immediately identifiable |
| Emphasised values | size 11 | the word the owner is looking for |
| Body text | size 10 | everything else |
| Row height | font size + 11 | 21 px at the default; the number that stopped lines overlapping |
| Padding | 10 px horizontally, 7/8 px from the top | |
| Separator | 1 px, inset 4 px | divides the header from the rows without a second box |
| Minimum width | 406 px | the width at which the longest status line still fits |

Two departures, both because OldMate proved they matter:

1. **Blank rows are drawn as a single space, never an empty string.** An empty string does not
   clear a label in MT5 — the object keeps its default caption, which is how the word `Label`
   appeared on a live chart.
2. **The panel repaints on a timer, not only on a tick.** A closed market produces no ticks, and a
   panel that waits for one is invisible exactly when the owner most wants to know why nothing is
   happening.

### 1.3 The geometry, in the order it is computed

This is the whole layout model; nothing else in Phase 1 is allowed to hard-code a pixel position.

1. `em = ceil(fontSize × DPI / 72 × 0.55)` — one character's advance, from the real DPI.
2. Every column's x is `pad + designPx × em / em9`, where `designPx` comes from the font-9
   anchors (150 / 282 / 414) and `em9` is `em` at size 9. Raising the font widens the grid.
3. Width is measured **before** drawing, from the longest line the panel will contain, with
   406 px as the floor.
4. Height is `header + rows × rowHeight + margins`, all from the same `rowHeight`.
5. The background rectangle is drawn at that computed size, 1 px border.
6. Labels are placed on the grid, each with selectable off, hidden on, and the anchor that matches
   its alignment.
7. The chart is redrawn immediately after the panel changes.

### 1.4 Palette, and the rule for colour

| Meaning | Colour |
|---|---|
| Panel surface | `C'48,48,48'` |
| Border, separator | `clrDimGray` |
| Title, primary values | `clrWhite` |
| Secondary values, idle state | `clrSilver` |
| Captions, units, hints | `clrGray` |
| Up, buy, ready | `clrLime` |
| Down, sell, refusal | `clrTomato` |
| Waiting, timing, pending | `clrOrange` |

**Colour is a state, never decoration.** A word that is not carrying a state is `clrGray`. This is
the rule that keeps a panel readable when six things are true at once.

### 1.5 Phase 1 acceptance list

The phase is done when every line below is true on a live chart, checked by eye and by screenshot:

- [ ] Attached to M15: the panel appears within one second, on an opaque `C'48,48,48'` box with a
      1 px `clrDimGray` border.
- [ ] Title is 11 pt white; body text is 10 pt; no line touches the line above or below it.
- [ ] No cell shows the word `Label`, including on rows that are empty.
- [ ] A placeholder table of three rows (M5, M15, M30) is aligned in columns at 10 pt **and** at
      12 pt after changing the one font-size value — nothing crowds, nothing clips.
- [ ] The panel still appears when the market is closed and when the chart is on an unsupported
      timeframe, and it says which of the two it is.
- [ ] Resizing the chart does not move the panel or cut it off.
- [ ] Removing the EA leaves no object behind — checked by re-attaching and by the object list.
- [ ] The panel carries a build stamp, so a screenshot can be tied to a version.

Nothing else is drawn in Phase 1. No symbol name, no session, no readings, no signal, no numbers.
A layout that cannot be verified empty cannot be trusted full.

### 1.6 What Phase 1 deliberately does not include

The contents of the panel. The rows are placeholders, and the words in them are invented for
layout testing only, marked as such on the panel itself so no screenshot can later be mistaken for
a measurement.

---

## The phases after this

Named now so the shape is agreed, specified only when we reach them. Each is a separate gate.

| Phase | What it settles | Why it comes there |
|---|---|---|
| **2** | the symbol: classification, digits, tick, contract, volume rules, stops level, filling mode, account type | everything later is measured in this instrument's units |
| **3** | market state: open, closed and when, session, and what the broker actually publishes | a panel that cannot say this is untrustworthy before it says anything else |
| **4** | the readings, one at a time, each with its own measurement and its own abstention | the part that was least examined in OldMate |
| **5** | the decision rule, and this time the "one reading may decide" question is settled **with you** before it is coded | it is a risk decision, not an arithmetic one |
| **6** | the plan: entry, structural stop, measured target, and size from the terminal's own money calculation | the first phase where money is at stake |
| **7** | sending: the gate list, and a refusal that always names its reason and its numbers | |
| **8** | management: TP1, trailing, limit life, cold start | |
| **9** | the record: one file, graded in money, read back at attach | without it nothing later can be justified |
| **10** | the bounded self-tweak | last, because it depends on a record existing |
| **11** | a week on demo, then the decision about live size | |

## The core that survives from OldMate

Kept, because it was measured and it held up:

- **Percentiles instead of fixed levels.** Every threshold is where the reading sits in its own
  recent distribution, with a minimum sample count and no written-down fallback.
- **The family finding.** Conventional indicators collapse into two opinions, continuation and
  reversion, and the rule that lets market memory choose the family was the only one never below a
  coin flip across five kinds of market.
- **One continuation reading, one participation reading, one reversion reading** — not three
  copies of the same opinion, and `±3` accepted as impossible rather than faked.
- **Sizing by the terminal's own money calculation**, never hand arithmetic.
- **A record graded in money**, with a per-reading scoreboard, so the EA can be argued with.
- **The build stamp and the refusal with numbers** — how a report becomes a diagnosis.

## What is being re-examined rather than ported

Named honestly, because these are the places the hidden problems are most likely to be:

1. **How permissive the decision is.** In OldMate, a single reading could open a trade at `1/1`.
   That followed from a measurement, but the consequence was never put to you as a choice. It is
   Phase 5's first question.
2. **The size of the file.** OldMate reached 3 438 lines in one push. MT is built in gates, and a
   phase that needs more than its gate allows is a sign the phase is wrong.
3. **The record before the strategy.** OldMate kept its diary late in the build. Here the record is
   Phase 9 only because it depends on a trade existing — but its schema is decided in Phase 6, when
   the first trade is planned, not discovered afterwards.
4. **Session and market reading.** The OldMate bug was reading one of MT5's two session tables and
   calling the other one unknown. Phase 3 has to answer which table says what, before it writes a
   line.
5. **Anything measured on the tester alone.** Every number that reaches the panel must be
   reproducible by hand from exported bars, or it does not go on the panel.

---

## Source for Phase 1

`SimpleEA` — <https://github.com/hamamun/SimpleEA>, file `SimpleAdvisor.mq5`, version string
`SimpleEA2.0`. Values above are cited by line number against that file as it stands today. If it
changes, this document is the one that is wrong.
