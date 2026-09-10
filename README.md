# Luminar-2 — v3.00

Higher-timeframe signal candle drawing with area selection and a configurable directional wick threshold. Visualization only: this version never submits orders.

## Inputs

| Input | Default | Meaning |
|---|---|---|
| SIGNAL_TIMEFRAME | M90 | Higher timeframe for the signal and area of interest; standard MT5 dropdown periods plus M90 |
| Body_to_wick_ratio | 20 | Strict maximum directional wick percentage, in %; 0..100 |

## Pattern rules

At a new candle, [1] is the candle that just closed, [2] its predecessor, [3] the candle before that. Two break variants are detected; the confirming candle is always [1]:

- One-candle break (`anchor [2]`): the anchor is candle[2] and candle[1] breaks it in one candle.
- Two-candle break (`anchor [3]`): the anchor is candle[3] and candles[2]+[1] break it together; [1] completes the break and either [2] or [1] takes out the anchor's extreme.

Sell:
- Anchor bullish; [1] bearish; [1] close below anchor open; the window extreme (for [2]: [1] high, taken out by [1]; for [3]: max([2] high, [1] high)) above anchor high; [1] lower wick / (body + lower wick) * 100 strictly below the threshold; anchor lower wick / (body + lower wick) * 100 also strictly below the threshold.

Buy (mirror): anchor bearish; [1] bullish; [1] close above anchor open; window extreme below anchor low; [1] upper wick and anchor upper wick each under the threshold.

- Body = absolute open/close difference. Equality and dojis do not qualify.

## Visualization

Gold boxes show the selected HTF anchor body ([2] or [3], depending on the variant), blue boxes show the break candle[1], and dashed green/red boxes project the buy/sell area of interest. Labels identify the HTF and the anchor index. On each new signal the EA draws the two candle bodies and projects the zone; stale drawings from earlier timeframes/versions are removed on init.

## Area selection

1. A confirmed HTF pattern creates a zone bounded by the anchor's open and close.
2. The zone is active from confirmation until five HTF periods after confirmation (five calendar months for MN1). The chart's dashed projection ends at this same expiry.
3. When several areas qualify, the newest takes priority (kept in memory, ordered oldest-first; stale ones are pruned).
4. A buy zone is invalidated if Bid reaches its HTF wick SL; a sell zone is invalidated if Ask reaches its HTF wick SL. Invalidated and expired zones are pruned and no longer drawn.

## Signal timeframe notes

M90 uses midnight-aligned broker-server intervals: 00:00, 01:30, 03:00, etc. OHLC is aggregated from M1 data. Each of the two M90 candles must have data in all three M30 sections, avoiding narrowed partial-session candles. Isolated no-tick minutes are permitted; this is not a guarantee of complete broker history. Native periods use MT5 bars.

The EA clock operates independently of the chart timeframe. On attachment, the EA waits for new bars and does not backfill old zones. Removing the EA leaves drawings for inspection; restarting clears them.

## Strategy Tester

Refresh Navigator, select Luminar-2, and start a fresh visual test on any period; the EA reads its own `SIGNAL_TIMEFRAME`. Use Every tick based on real ticks for the most useful test. Use the Journal to inspect signal evidence and area activation/invalidation. No entries or orders are sent in any mode.

## Project layout

- `Luminar-2.mq5` — the EA; includes only from `core\`.
- `core/` — shared MQL5 helper/libraries: `EntrySignal.mqh`, `SyntheticCandle.mqh`, `SignalGeometry.mqh`, `TradeRules.mqh`.
- `scripts/` — developer tooling: `Test-TradeRules.ps1` (CLR unit harness) and `analyze_tester_logs.py` (writes evidence to `docs\tester_analysis.json`).
- `docs/` — backtest evidence (`tester_analysis.json`, `tester_review.md`) and design notes (`idea.md`).

Backtest history from the trading versions (v2.x) lives in `docs/tester_review.md`: entry filters and stop-loss placement were empirically validated at `Body_to_wick_ratio` 20 with a wick-based stop; the trading layer was then removed at the user's request in v3.00.

## Verification

MetaEditor compilation: 0 errors, 0 warnings. Executable: Luminar-2.ex5.

Test-TradeRules.ps1 executes the shared MQL decision/calculation bodies through .NET with syntax adaptations. These checks do not submit orders or replace an MT5 runtime/backtest.

Run from this directory:

```powershell
& ([scriptblock]::Create((Get-Content .\scripts\Test-TradeRules.ps1 -Raw)))
```

Compile with D:\Trading\MetaEditor64.exe using F7 or `/compile:"<absolute source path>" /log`.