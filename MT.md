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
 MT V1.00  |  XAUUSDm  |  Metal  |  Open  |  Se: London
```

| Cell | Content |
|---|---|
| `MT Vxx` | name and version |
| Symbol name | the broker's own spelling |
| Symbol type | Forex / Metal / Index / Energy / Crypto / Stock / Other |
| Open / close | market state |
| `Se:` | the session |
