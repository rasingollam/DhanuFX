# DhanuFX entry visualization — v1.42

This EA implements the entry conditions in `idea.md`, draws both candle bodies and projected signal zones, and logs the evidence. It does not place orders.

## Inputs

- **Signal timeframe** (`Timeframe`): one dropdown containing all standard MT5 periods plus **M90 (90 minutes)**. Default M90. The chart timeframe does not control the selected signal timeframe.
- **Maximum directional wick percentage** (`Body_to_wick_ratio`): default 20. This means `wick / (body + wick) * 100 < 20`, with strict comparisons.

Old `.set` files with `Custom_Timeframe_Minutes` must be updated: select the intended timeframe in the new dropdown.

## Entry rules

At the start of a new signal candle, candle[1] is the signal candle that just closed and candle[2] is the candle before it.

| Requirement | Sell | Buy |
|---|---|---|
| Candle[2] | Bullish | Bearish |
| Candle[1] | Bearish | Bullish |
| Candle[1] close | Below candle[2] open | Above candle[2] open |
| Sweep | High above candle[2] high | Low below candle[2] low |
| Directional wick | Close minus low | High minus close |
| Wick fraction | Below threshold | Below threshold |

Body is the absolute difference between open and close. Dojis and equal-price boundaries fail. The conditions are unchanged from `idea.md`; the surrounding aggregation and drawing behavior has been revised.

## Drawings

- **Signal body [1]:** a blue unfilled box around the selected timeframe's candle[1], bounded by its exact open/close prices and its own interval start/end. It is labeled with the timeframe and [1], and appears alongside the gold candle[2] body when a signal is confirmed.

- **Source body:** a bright gold unfilled box covering only selected-timeframe candle[2], from its opening time to its interval end, bounded by its exact open and close. A gold label identifies the timeframe and `[2]`.
- **Projection:** an unfilled dashed green (buy) or red (sell) box starts at the source body end and extends the same prices into the future. It leaves underlying candles visible. A thin source body stays at its true prices; it is never enlarged to look stronger.
- **Right edge:** five signal periods after confirmation. For M90, that is 450 minutes after confirmation. Monthly signals use five calendar months. Other projections are elapsed time and do not predict future market closures.
- Tooltips give the signal timeframe, source candle times, body prices, close price and confirmation time. The Journal also records both candles' full OHLC and directional wick percentage.

Example: for M90, candle[2] starts at 00:00, candle[1] at 01:30 and confirmation is at 03:00. The gold source body spans 00:00 to 01:30, the dashed projection runs from 01:30 to 10:30. These objects first appear at/after 03:00.

## M90 data and lifecycle

M90 is built from chronological M1 history in broker-server time. Boundaries are 00:00, 01:30, 03:00, etc. OHLC uses the first available open, highest high, lowest low and last available close inside each interval. Minutes with no ticks need not have an M1 bar. Both M90 candles must contain data in all three M30 sections. If a complete section is absent (for example around a session break), the pair is rejected instead of drawing a reduced M90 body. This is a component-coverage check, not a guarantee of complete tick history. Empty intervals are never invented. History synchronization and earlier coverage are checked before evaluation; synchronized history can still contain broker data gaps that the EA cannot distinguish from no-tick minutes.

Only the two immediately preceding clock intervals are evaluated for M90. Across a completely empty interval, that pair will not signal. Standard timeframes use MT5's own two previous bars.

The EA waits for the next interval after attachment and does not backfill historical signals. Unavailable history is retried once per minute. A delayed tick/history load can delay evaluation. When initialized again, it clears its own symbol's drawings on this chart across all previous signal timeframes so stale zones cannot be confused with the new settings. Objects remain after stopping for inspection.

The displayed chart candles remain their native timeframe. M90 body outlines on an M5 chart show the selected M90 candles, not M5 signals. A chart legend explicitly shows the selected signal timeframe. Use the tooltip to identify its source.

## Strategy Tester

1. Refresh Navigator and select **DhanuFX\DhanuFX**.
2. Select **M90 (90 minutes)** in the EA's signal timeframe dropdown.
3. Enable visualization. M5 or M15 is useful for inspecting custom boundaries.
4. Use **Every tick based on real ticks**, **Every tick**, or **1 minute OHLC**. Coarse **Open prices only** can miss M90 boundaries.
5. Inspect both candle bodies, projected zone, tooltip and Journal OHLC together. No trades or profit statistics are expected.

## Verification

MetaEditor compilation: **0 errors, 0 warnings**. Output: `DhanuFX.ex5`.

The shared MQL headers were executed through a .NET harness with syntax adaptations: **32 signal cases, 16 aggregation cases and 7 M90 component/session coverage cases and 4 drawing-coordinate cases passed (including 2 end-to-end aggregation/signal cases)**. Cases include buy/sell symmetry, equality thresholds, dojis, midnight boundaries, sparse minutes, duplicate rejection, forming-bar exclusion and exact drawing coordinates, plus thin-body and closing-time regressions at M30 and M90. This is not an MT5 runtime or visual-rendering test; those remain to be performed in Strategy Tester.

Run from this directory:

```powershell
& ([scriptblock]::Create((Get-Content .\Test-EntrySignal.ps1 -Raw)))
```

Compile with `D:\Trading\MetaEditor64.exe`, opening `DhanuFX.mq5` and pressing F7, or with `/compile:"<absolute source path>" /log`. Compiler results are in `DhanuFX.log`.




