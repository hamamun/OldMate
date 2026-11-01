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

Open:

```text
 MT V1.00 | XAUUSDm | Metal | OPEN | 2026.11.01 11:57:34
```

**Note — when closed, the last cell shows the next opening time instead of the running clock:**

```text
 MT V1.00 | XAUUSDm | Metal | close | Open at 2026.11.01 11:57:34
```

| Cell | Content |
|---|---|
| `MT V1.00` | name and version |
| Symbol name | the broker's own spelling |
| Symbol type | Forex / Metal / Index / Energy / Crypto / Stock / Other |
| `OPEN` / `close` | market state |
| last cell | while open: server date and time, ticking every second. While closed: `Open at` and the next opening time, from the broker's session table |

56 characters open, 65 closed — **about 448 and 520 px** at 10 pt.

The box is sized to the **widest** of the two states, so it never resizes when the market shuts.
The date and time are fixed width, so nothing shifts as the seconds change.

If the broker publishes no table there is no opening time to count to, and the cell says so
rather than inventing one:

```text
 MT V1.00 | BTCUSDm | Crypto | close | Open at --
```
