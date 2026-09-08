# DhanuFX — v2.10

Higher-timeframe areas of interest, matching lower-timeframe entries, money risk sizing, wick-based SL and reward/risk TP. This version can submit market orders when attached with trading enabled. It has been compiled but has not been attached to a live chart or run against a broker during development.

## Inputs

| Input | Default | Meaning |
|---|---|---|
| Timeframe | M90 | Higher timeframe defining the area; standard MT5 dropdown periods plus M90 |
| Lower_Timeframe | M5 | Entry timeframe; must be strictly lower than Timeframe |
| Body_to_wick_ratio | 20 | Strict maximum directional wick percentage, shared by both timeframes |
| Risk_Money | 20.0 | Estimated loss at SL in account currency; volume is calculated automatically |
| Take_Profit_RR | 2.0 | Reward divided by risk; 2.0 means 1:2 |
| Enable_Trading | true | False retains HTF visualization without sending orders |
| Magic_Number | 26090901 | Identifier on EA orders |
| Deviation_Points | 20 | Execution deviation in symbol points |

## Pattern rules — both timeframes

At a new candle, [1] is the candle that just closed and [2] is its predecessor.

- Sell: [2] bullish, [1] bearish, [1] close below [2] open, [1] high above [2] high, and lower wick / (body + lower wick) * 100 strictly below the threshold.
- Buy: [2] bearish, [1] bullish, [1] close above [2] open, [1] low below [2] low, and upper wick / (body + upper wick) * 100 strictly below the threshold.
- Body = absolute open/close difference. Equality and dojis do not qualify.

## Area and entry lifecycle

1. A confirmed HTF pattern creates a zone bounded by HTF candle[2]'s open and close.
2. The zone is active from confirmation until five HTF periods after confirmation (five calendar months for MN1). The chart's dashed projection ends at this same expiry.
3. On each new LTF candle, evaluate the two closed LTF candles with the same pattern rules. The direction must match an active HTF area.
4. At least one of those two LTF candles must overlap the area's body prices with its high/low range. This defines the retest; the confirming close may reject out of the zone. A touch many candles earlier does not qualify by itself.
5. The older LTF candle must start at/after HTF confirmation, and the newer LTF candle must start at/after the area actually became available. Patterns formed before zone creation cannot trigger retrospectively.
6. Submit a market order on the first available tick after LTF confirmation. The entry is the current market quote, not the historical LTF close.

When several areas qualify, the newest takes priority. Each area permits one accepted order; partial fills and ambiguous timeouts also consume it to avoid retrying that area. A rejected request may be attempted on a later, distinct qualifying LTF pattern. A given LTF candle is evaluated for order submission only once.

The EA does not enter while any position or pending order already exists on the same symbol, including manual/other-EA exposure. It does not modify or close those positions. Unused zones expire, and a buy zone is invalidated if Bid reaches its wick SL; a sell zone is invalidated if Ask reaches its wick SL. Existing trades keep their original SL/TP when an area expires or a new area appears.

## Money risk sizing

Risk_Money replaces Lot_Size. Default 20 means 20 units of the account currency (USD 20 on a USD account). The EA uses MT5 OrderCalcProfit at the current entry quote and normalized SL to calculate loss per lot. It rounds volume down to the broker step and caps it at the symbol maximum/directional limit. If the smallest lot exceeds the budget, it skips the entry rather than increasing risk. Calculated volume and estimated SL loss are logged. Risk covers price movement to SL; commission, swap, slippage and gaps can make actual loss exceed the input. Existing positions are not resized. Old set files should be updated to use Risk_Money.

## SL and TP

- Buy SL: the lower of HTF candle[1] low and candle[2] low, including wicks.
- Sell SL: the higher of HTF candle[1] high and candle[2] high, including wicks.
- SL is placed at that extreme, with no extra buffer, rounded outward only if required by the broker's price tick size.
- Buy TP = Ask + RR * (Ask - SL).
- Sell TP = Bid - RR * (SL - Bid).
- TP rounds outward to the broker tick size. Both protective prices are included in the initial order request.
- The EA skips an entry if the specified wick SL is on the wrong side of the market or violates minimum stop distance; it does not silently widen the stop.
- RR uses the quote immediately before submission. Slippage, spreads and trading costs can make realized reward/risk differ; TP is not recalculated after execution.

## Visualization and data

Gold boxes show the selected HTF candle[2] body; blue boxes show candle[1]. Labels identify the HTF. Dashed green/red boxes project buy/sell areas. The EA does not draw buy/sell arrows or additional LTF body boxes. MT5 may display its own executed-trade markers.

M90 uses midnight-aligned broker-server intervals: 00:00, 01:30, 03:00, etc. OHLC is aggregated from M1 data. Each of the two M90 candles must have data in all three M30 sections, avoiding narrowed partial-session candles. Isolated no-tick minutes are permitted; this is not a guarantee of complete broker history. Native periods use MT5 bars.

Both timeframe clocks operate independently of the chart timeframe. On attachment, the EA waits for new bars and does not backfill old zones. Active areas are held in memory; reinitialization clears them and the EA's old chart drawings. Open orders/positions retain broker SL/TP. Removing the EA leaves drawings for inspection; restarting clears them.

## Strategy Tester

Refresh Navigator, select DhanuFX\DhanuFX, and start a fresh visual test with M90/M5, Risk_Money=20 and RR 2.0. Use Every tick based on real ticks for the most useful execution test. Every tick or 1 minute OHLC can also exercise the logic, but modeled intrabar paths can change retests, invalidation and SL/TP results. Avoid coarse Open prices only runs for multi-timeframe execution.

Use the Journal to inspect area activation/expiry, wick SL, LTF entry direction, order return codes and fill price. No entry is expected until an HTF area forms and a later matching LTF retest occurs.

## Verification

MetaEditor compilation: 0 errors, 0 warnings. Executable: DhanuFX.ex5.

Test-TradeRules.ps1 executes shared MQL trade-decision/calculation bodies through .NET with syntax adaptations. All 42 checks passed: direction matching, retests, pre-activation rejection, expiry, consumed zones, wick-stop invalidation, bid/ask RR calculations, tick-size rounding and invalid stop/quote rejection, and money-risk volume rounding, minimum-lot rejection and maximum-volume caps. These checks do not submit orders or replace an MT5 runtime/backtest.

Run from this directory:

```powershell
& ([scriptblock]::Create((Get-Content .\Test-TradeRules.ps1 -Raw)))
```

Compile with D:\Trading\MetaEditor64.exe using F7 or `/compile:"<absolute source path>" /log`.

