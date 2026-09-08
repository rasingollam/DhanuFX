# DhanuFX tester review — 9 September 2026

## Evidence and scope

Read the local Agent-127.0.0.1-3001 log `20260909.log`, last modified 03:16:15, plus the older Agent-3000 log. The primary analysis covers nine Agent-3001 runs. No EA source or executable was changed and no new backtests were launched.

Primary source: `C:\Users\User\AppData\Roaming\MetaQuotes\Tester\12FE2A177E39CFD95D50E79D01391499\Agent-127.0.0.1-3001\logs\20260909.log`.

The latest run starts at source line 87223. Requested dates: 2014-01-14 through 2026-09-08; actual matched trades start in May 2017. The log contains many incomplete M90/history messages. Therefore this is not evidence of continuous tradable M1 coverage throughout the requested period. Inputs: XAUUSD, M90 areas, M5 entries, wick threshold 20%, fixed USD 100, RR 2, USD 10,000 initial deposit.

All 244 successful entries were matched to SL/TP outcomes. Another 15 attempts were rejected with market-closed return codes; they are not losing trades. Entry and exit timestamps, source line numbers, prices and area features are in `tester_analysis.json`. Reproduce using `python docs/analyze_tester_logs.py`.

## Actual run comparison

| Fixed USD 100 run | Completed trades | Wins | Win rate | Final balance | Net change | Longest loss streak |
|---|---:|---:|---:|---:|---:|---:|
| RR 0.5 | 246 | 163 | 66.26% | $9,477.05 | -$522.95 | 6 |
| RR 1 | 246 | 127 | 51.63% | $10,257.93 | +$257.93 | 6 |
| RR 2 | 244 | 86 | 35.25% | $10,442.90 | +$442.90 | 10 |
| RR 3 | 240 | 70 | 29.17% | $12,868.64 | +$2,868.64 | 15 |

These are actual separate logged runs, not hypothetical TP conversions. Trade counts vary because holding time changes which later entries are blocked. Maximizing win rate alone would select the losing RR 0.5 run. RR 3 performed best by final balance here, but produced longer loss streaks; it is not automatically the best drawdown choice.

The 2026-only RR 2 run had 18 trades and 55.56% wins, ending at $11,177.66. That small recent sample is substantially stronger than the long run and should not be extrapolated.

The percentage run used 5% equity and finished at $8,233.19. It started with about $500 risk, versus $100 in fixed mode. This is not an equal-risk comparison and does not establish that percentage sizing inherently worsens entry quality. Keeping fixed money is reasonable for a controlled baseline; compare 1% equity if evaluating sizing methods fairly.

## Filter candidates supported by logged associations

These are retrospective groups from the latest RR 2 run, not results from filtered backtests. Removing a trade can free the symbol for a different later trade, so subset statistics do not predict a rerun exactly.

| Feature | Weaker group | Comparison group | Candidate to test independently |
|---|---|---|---|
| HTF candle[2] body / full high-low range | Below 20%: 9/32 wins, 28.12% | At least 20%: 77/212, 36.32% | `Min_HTF_Source_Body_Percent=20` |
| Entry distance outside zone / initial entry-to-SL distance | Above 0.25R: 13/46 wins, 28.26% | At most 0.25R: 73/198, 36.87% | `Max_Entry_Distance_R=0.25` |
| Zone age at entry | At most 90 minutes: 32/104 wins, 30.77% | Over 90 minutes: 54/140, 38.57% | Optional minimum age; compare off versus one HTF period |

Entry-distance definition: zero inside the zone, otherwise distance to the nearest body boundary divided by entry-to-SL distance. This is a proposed anti-chasing filter; use the current executable quote in the EA, not a future price.

Prioritize the source-body and entry-distance filters because they directly describe setup quality. The age result is less intuitive and needs independent validation. Do not combine all three immediately or optimize many thresholds on the same sample.

The HTF wick groups were almost identical: below 10% produced 47/134 wins (35.07%); 10–20% produced 39/110 (35.45%). There is no useful evidence here for tightening this threshold alone. This comparison does not test a changed LTF wick threshold.

Buy versus sell was 36.51% versus 33.90%; the difference is too weak to justify disabling sells. Hourly buckets have only 5–19 trades per hour across the run, making cherry-picked session exclusions fragile.

## Execution and measurement improvements

1. Record entry spread, spread/SL distance, actual deal profit, commission, swap, maximum favorable/adverse excursion, source body fraction, zone age and entry distance. The existing log cannot validate breakeven, trailing-stop or news filters because it lacks the necessary intratrade paths and news labels.
2. Check broker trading sessions before submission. Fifteen rejected market-closed attempts are an execution-quality issue, not a source of the 158 actual losses.
3. Investigate history completeness before claiming a full 2014–2026 result. Keep the M90 component guard; do not remove it simply to increase sample size.
4. Retain fixed risk while testing entries. Reducing risk can reduce money drawdown, but it does not make a losing setup more likely to win.

Reconstructed gross closed-trade P/L at actual logged exit prices is approximately +$1,257.72, assuming 100 oz per lot as implied by logged risk. Actual final-balance gain is +$442.90; $814.82 remains unreconciled in this reconstruction. Fees, swap or other accounting details require the tester deal report. Consequently, gross closed-balance drawdown of about $1,487.07 is only a diagnostic estimate; it is not the tester's equity drawdown or net profit factor. Do not use it as an exact risk report.

## Proposed next experiment

Keep M90/M5, fixed $100 and RR 2 as baseline. Run: baseline; source-body filter only; entry-distance filter only; age filter only. Compare net expectancy, net profit factor, equity drawdown, loss streak, trade count and win rate across chronological subperiods. Only combine candidates that hold up independently. Then compare RR 1, 2 and 3 with the selected entry rules.

Use a small, predeclared parameter set and forward testing. The full existing history has now been inspected, so it is exploratory evidence, not a pristine holdout. Validate on genuinely unseen subsequent data before claiming improvement. MetaTrader documents forward testing specifically to reduce parameter fitting: https://www.metatrader5.com/en/terminal/help/algotrading/strategy_optimization
