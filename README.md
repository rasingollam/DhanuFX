# DhanuFX — v2.32

Higher-timeframe areas of interest, matching lower-timeframe entries, money risk sizing, wick-based SL, reward/risk TP and optional entry filters. This version can submit market orders when attached with trading enabled. It has been compiled but has not been attached to a live chart or run against a broker during development.

## Inputs

| Input | Default | Meaning |
|---|---|---|
| Timeframe | M90 | Higher timeframe defining the area; standard MT5 dropdown periods plus M90 |
| Lower_Timeframe | M5 | Entry timeframe; must be strictly lower than Timeframe |
| Body_to_wick_ratio | 20 | Strict maximum directional wick percentage, shared by both timeframes |
| Risk_Type | Fixed money | Choose fixed money or percentage of current account equity |
| Risk_Money | 100.0 | Fixed-mode budget in account currency; preserves the current source default |
| Risk_Percent | 1.0 | Percentage-mode budget: current equity * percent / 100 |
| Take_Profit_RR | 2.0 | Reward divided by risk; 2.0 means 1:2 |
| Min_HTF_Source_Body_Percent | 20.0 | Skip entries when the area's HTF source (candle[2]) body is below this % of its full high-low range. 0 = off. Verdict from filter experiment (config C) |
| Max_Entry_Distance_R | 0.25 | Skip entries whose current quote chases more than this many R beyond the zone body (0 = inside zone). 0 = off. Verdict from filter experiment (config C) |
| Min_Zone_Age_Minutes | 90 | Skip entries into areas younger than this. 0 = off. Verdict from filter experiment (config C) |
| Stop_Mode | HTF wick | SL placement: HTF wick extreme (default), HTF zone body edge, or extreme of the last N closed LTF candles |
| Stop_Swing_Count | 3 | LTF swing mode only: take the low/high over the last N closed LTF candles behind the entry (1..10) |
| Enable_Trading | true | False retains HTF visualization without sending orders |
| Magic_Number | 26090901 | Identifier on EA orders |
| Deviation_Points | 20 | Execution deviation in symbol points |

Each filter is applied independently and only at the LTF qualifying entry, measured with the current executable quote. A filtered-out entry does not consume its area, so a later qualifying LTF pattern can still fill it.

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

Risk_Type selects the budget calculation. Fixed money uses Risk_Money (current default 100 in account currency). Percentage mode uses Risk_Percent (default 1%) of current account equity, including floating P/L. The equity budget is recalculated once immediately before each candidate entry; 1% of 2,000 is 20. Only the selected mode input is validated/used. Nonpositive equity skips percentage-mode entries. The EA uses MT5 OrderCalcProfit at the current entry quote and normalized SL to calculate loss per lot. It rounds volume down to the broker step and caps it at the symbol maximum/directional limit. If the smallest lot exceeds the budget, it skips the entry rather than increasing risk. Calculated volume and estimated SL loss are logged. Risk covers price movement to SL; commission, swap, slippage and gaps can make actual loss exceed the input. Existing positions are not resized. Old set files should be updated to use Risk_Money.

## SL and TP

The protective stop level comes from `Stop_Mode` (default `SL_HTF_WICK`, unchanged behavior):

- SL_HTF_WICK — Buy SL: the lower of HTF candle[1] low and candle[2] low, including wicks; Sell SL: the higher of the two highs. This is also the structural level used to invalidate an unentered area.
- SL_HTF_BODY — Buy SL at the zone body bottom, Sell SL at the zone body top. Tighter than the wick extreme; ties the stop to the mapped body. The entry is skipped if this level is on the wrong side of the market or inside the broker minimum stop distance.
- SL_LTF_SWING — Buy SL at the lowest low, Sell SL at the highest high, over the last `Stop_Swing_Count` closed LTF candles ending at the entry pattern. The tightest mode; sizes the trade from the recent LTF swing instead of the whole HTF candle. Requires a native (non-synthetic M90) lower timeframe; otherwise that entry falls back to the HTF wick stop and logs it.
- For every mode: SL is rounded outward only if required by the broker tick size, area invalidation before entry still uses the HTF wick extreme, and an entry is skipped (never silently widened) if the selected stop fails CalculateTradePrices.
- Buy TP = Ask + RR * (Ask - SL). Sell TP = Bid - RR * (SL - Bid).
- TP rounds outward to the broker tick size. Both protective prices are included in the initial order request.
- RR uses the quote immediately before submission. Slippage, spreads and trading costs can make realized reward/risk differ; TP is not recalculated after execution.

## Visualization and data

Gold boxes show the selected HTF candle[2] body; blue boxes show candle[1]. Labels identify the HTF. Dashed green/red boxes project buy/sell areas. The EA does not draw buy/sell arrows or additional LTF body boxes. MT5 may display its own executed-trade markers.

M90 uses midnight-aligned broker-server intervals: 00:00, 01:30, 03:00, etc. OHLC is aggregated from M1 data. Each of the two M90 candles must have data in all three M30 sections, avoiding narrowed partial-session candles. Isolated no-tick minutes are permitted; this is not a guarantee of complete broker history. Native periods use MT5 bars.

Both timeframe clocks operate independently of the chart timeframe. On attachment, the EA waits for new bars and does not backfill old zones. Active areas are held in memory; reinitialization clears them and the EA's old chart drawings. Open orders/positions retain broker SL/TP. Removing the EA leaves drawings for inspection; restarting clears them.

## Strategy Tester

Refresh Navigator, select DhanuFX\DhanuFX, and start a fresh visual test with M90/M5, Risk_Money=20 (fixed baseline uses 100 for the filter experiment) and RR 2.0. Use Every tick based on real ticks for the most useful execution test. Every tick or 1 minute OHLC can also exercise the logic, but modeled intrabar paths can change retests, invalidation and SL/TP results. Avoid coarse Open prices only runs for multi-timeframe execution.

Use the Journal to inspect area activation/expiry, wick SL, LTF entry direction, entry-filter skips, order return codes and fill price. No entry is expected until an HTF area forms and a later matching LTF retest occurs.

### Filter experiment results (docs/tester_review.md)

Single filters tested independently on M90/M5, fixed USD 100, RR 2, 2014-2026: source body 20 -> +$990, entry distance 0.25R -> +$909, zone age 90 -> +$1,258, versus baseline +$443 (final balances, after costs). Combinations: all three filters (20 / 0.25 / 90, config C) = +$2,171.62 at RR 2, PF 1.335, worst streak 5, best-balanced half split (39.7%/40.6%). RR 3 on the same config = +$2,945.42 (PF 1.395) with ~1.5x drawdown and double the streak. SL placement matrix (v2.32) at RR 3: HTF wick +$2,945 decisively beats HTF body +$689 and every LTF-swing setting (from +$555 to -$580) - keep `Stop_Mode=SL_HTF_WICK` (default). Config C + wick is now the input default. Reprocess the Agent-3000 log with `docs/analyze_tester_logs.py` (`DHANU_TESTER_LOG` override) to reproduce.

Remaining scheduled work: forward validation on genuinely unseen data (post 2026-09-08) as the gate before claiming the config ships, with thresholds frozen; RR 2 vs RR 3 decided by that forward result. In parallel: deal-level profit logging.

## Verification

MetaEditor compilation: 0 errors, 0 warnings. Executable: DhanuFX.ex5.

Test-TradeRules.ps1 executes shared MQL trade-decision/calculation bodies through .NET with syntax adaptations. All 64 checks passed: direction matching, retests, pre-activation rejection, expiry, consumed zones, wick-stop invalidation, bid/ask RR calculations, tick-size rounding, invalid stop/quote rejection, money-risk volume rounding, minimum-lot rejection and maximum-volume caps, percentage budgets and equity changes, source-body percent, entry chase in R, and combined source/entry-distance/age filter decisions. These checks do not submit orders or replace an MT5 runtime/backtest.

Run from this directory:

```powershell
& ([scriptblock]::Create((Get-Content .\Test-TradeRules.ps1 -Raw)))
```

Compile with D:\Trading\MetaEditor64.exe using F7 or `/compile:"<absolute source path>" /log`.


