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
 MT V1.00 | XAUUSDm | Metal | OPEN | Se 08:00-17:00 | 14:35:07 srv
```

| Cell | Content |
|---|---|
| `MT V1.00` | name and version |
| Symbol name | the broker's own spelling |
| Symbol type | Forex / Metal / Index / Energy / Crypto / Stock / Other |
| `OPEN` / `CLOSED` | market state |
| `Se` | the broker's own session window for today, in server time |
| `14:35:07 srv` | live server time, ticking every second |

66 characters — about 528 px at 10 pt.

The clock is the sync check: it ticks every second while the terminal is connected, and freezes
when it is not, so a stopped clock beside `OPEN` says the panel is reading stale data.

When the market is shut the state cell reads `CLOSED` and the window is still shown, so the owner
can see when it reopens:

```text
 MT V1.00 | XAUUSDm | Metal | CLOSED | Se 08:00-17:00 | 14:35:07 srv
```

When the broker publishes no session table — crypto, usually — the cell says so instead of
inventing a window:

```text
 MT V1.00 | BTCUSDm | Crypto | OPEN | Se - no table - | 14:35:07 srv
```
