# MT — Master Trade

Phase 1, appearance. Taken from `SimpleEA/SimpleAdvisor.mq5` (<https://github.com/hamamun/SimpleEA>).

| Setting | Value | Source |
|---|---|---|
| Font | **Consolas** | line 168 |
| Font size | **10** | line 167 |
| Background colour | **`C'48,48,48'`** | line 169 |

The title is drawn one point larger — **11** — in `clrWhite` (line 170).

MT uses the same three.

## Phase 1 — header, row 1

Left to right:

```text
 MT V1.00 | XAUUSDm | Metal | OPEN | 2026.11.01 11:57:34
```

| Cell | Content |
|---|---|
| `MT V1.00` | name and version |
| Symbol name | the broker's own spelling |
| Symbol type | Forex / Metal / Index / Energy / Crypto / Stock / Other |
| `OPEN` / `CLOSED` | market state |
| `2026.11.01 11:57:34` | server time and date, in the terminal's own format, ticking every second |

56 characters — about 448 px at 10 pt. The date and time are fixed width, so the cell never
shifts as the seconds change.

The clock is the sync check: it ticks every second while the terminal is connected, and freezes
when it is not, so a stopped clock beside `OPEN` says the panel is reading stale data.

```text
 MT V1.00 | XAUUSDm | Metal | CLOSED | 2026.11.01 11:57:34
 MT V1.00 | BTCUSDm | Crypto | OPEN | 2026.11.01 11:57:34
```
