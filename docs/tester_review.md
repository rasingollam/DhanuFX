# DhanuFX tester review — 9 September 2026

## Filter experiment results (EA v2.30, four separate backtests)

Running source: `C:\Users\User\AppData\Roaming\MetaQuotes\Tester\12FE2A177E39CFD95D50E79D01391499\Agent-127.0.0.1-3000\logs\20260909.log` (runs at lines 4184, 18427, 32387, 46370). All four runs: XAUUSD, M90 areas, M5 entries, wick threshold 20%, fixed USD 100 risk, RR 2, USD 10,000 deposit, 2014-01-14 to 2026-09-08. Only the named filter is on per run; default 0 means off. Reproduce with `python docs/analyze_tester_logs.py` (set `DHANU_TESTER_LOG` to the Agent-3000 path).

| Config | Trades | Wins | Win % | Gross rec. | Final balance | Net | PF (gross rec.) | DD est. | Loss streak | Filtered-out |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| Baseline (no filter) | 244 | 86 | 35.25% | +$1,257.7 | $10,442.90 | +$442.90 | 1.081 | $1,487 | 10 | — |
| `Min_HTF_Source_Body_Percent=20` | 210 | 76 | 36.19% | +$1,783.2 | $10,989.90 | +$989.90 | 1.137 | $1,087 | 8 | 55 |
| `Max_Entry_Distance_R=0.25` | 212 | 77 | 36.32% | +$1,704.1 | $10,908.77 | +$908.77 | 1.128 | $1,387 | 10 | 41 |
| `Min_Zone_Age_Minutes=90` | 175 | 65 | 37.14% | +$1,796.8 | $11,257.75 | +$1,257.75 | 1.166 | $896 | 7 | 118 |

Each filter removes a trade subset that was demonstrably weak in the baseline, then frees the symbol for different later entries, so reruns do not equal simple subsets. Reconstructed gross assumes 100 oz/lot and excludes costs; per-trade net after costs is baseline +$1.82, body +$4.71, distance +$4.29, age +$7.19. Costs are roughly $-3 to $-4 per trade, so relative comparisons are valid; absolute figures need the deal report.

## Within-baseline association (the edge the filters exploit)

From the baseline run: trades enter below the cutoff are a minority that destroys the majority of profit.

| Group in baseline | Trades | Win % | Gross rec. P/L |
|---|---:|---:|---:|
| HTF body >= 20% | 210 | 36.19% | +$1,783 |
| HTF body < 20% | 34 | 29.41% | -$525 |
| Chase <= 0.25R | 206 | 36.41% | +$1,702 |
| Chase > 0.25R | 38 | 28.95% | -$444 |
| Zone age > 90m | 140 | 38.57% | +$2,005 |
| Zone age <= 90m | 104 | 30.77% | -$747 |

The zone-age group is the largest weak slice (42.6% of trades) but "young-zone entries are bad" is the least intuitive claim and the most exposed to regime drift.

## Stability across time (chronological split of each run)

| Config | First half win % | Second half win % | Last 3y win % | Trades |
|---|---:|---:|---:|---:|
| Baseline | 34.43% | 36.07% | 41.0% | 244 |
| Body >= 20% | 37.14% | 35.24% | 38.0% | 210 |
| Entry distance <= 0.25R | 34.91% | 37.74% | 42.7% | 212 |
| Zone age >= 90m | 33.33% | 40.91% | 44.4% | 175 |

The source-body and entry-distance filters hold up in both halves. The zone-age filter is the single biggest net gain but its strength is concentrated in the second half and last three years; its first half is *weaker* than the baseline first half (33.3% vs 34.4%). Treat the age edge as recent-regime-dependent until forward data confirms it.

## Combination results (batch 2, same window/risk as batch 1)

Running source: Agent-3000 log, runs at lines 60090, 73620, 87147, 100534. Only the listed filters are active; defaults are off.

| Config | Trades | Win % | Gross rec. | Final balance | Net | PF (gross rec.) | DD est. | Loss streak | Filtered-out |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| A: body 20 + age 90 | 154 | 38.96% | +$2,510.3 | $11,989.69 | +$1,989.69 | 1.274 | $796 | 7 | 151 |
| B: dist 0.25 + age 90 | 153 | 38.56% | +$2,173.0 | $11,642.38 | +$1,642.38 | 1.233 | $704 | 6 | 143 |
| C: all 20 / 0.25 / 90 | 137 | 40.15% | +$2,683.8 | $12,171.62 | +$2,171.62 | 1.335 | $804 | 5 | 171 |
| D: body 20 + dist 0.25 | 188 | 37.23% | +$2,127.1 | $11,353.26 | +$1,353.26 | 1.185 | $1,294 | 9 | 83 |

Chronological (first half / second half / last 3y win %):
- A: 37.7 / 40.3 / 42.9 (n 154)
- B: 36.8 / 40.3 / 45.5 (n 153)
- C: 39.7 / 40.6 / 44.9 (n 137)
- D: 37.2 / 37.2 / 40.6 (n 188)

Every combination beats every single filter from batch 1. Config C (all three) is best on net (+$2,171.62), PF (1.335) and loss streak (5), and its half-split (39.7/40.6) is the most balanced of all runs to date. Notably, the age filter's lone first-half weakness (33.3% alone) disappears in every pairing, and is best in C. Config D shows the age filter is the main driver of the recent-period gains; but D still retains the long 9-streak and higher drawdown. Config C cuts the baseline from 244 to 137 trades, so the per-year samples are small (n 9–21); robustness must come from forward data, not more slicing.

## Verdict

1. Keep `Min_HTF_Source_Body_Percent=20`. Cheap (removes 14% of trades), stable across halves, best balance of consistency vs gain.
2. Keep `Max_Entry_Distance_R=0.25` as anti-chase discipline. Stable, but it neither shortens the loss streak nor lowers drawdown much.
3. Keep `Min_Zone_Age_Minutes=90` as the primary profit driver, but only after (a) it survives the combination runs and (b) forward validation. Its first-half weakness is a real red flag.
4. Do not tune thresholds further on this sample. Every threshold now was chosen from this same inspected history, so all gains here are somewhat in-sample. The next improvement claim must come from data the thresholds did not see.

## Prior context (kept for continuity)

Earlier RR sweep on the same baseline entries (Agent-3001 runs): RR 0.5 won 66% and lost -$522.95; RR 1 won 51.63% for +$257.93; RR 2 won 35.25% for +$442.90; RR 3 won 29.17% for +$2,868.64 (longest streak 15). High win rate alone selects a losing config; RR 3 is not automatically best on drawdown. The 2026-only RR 2 window had 18 trades at 55.56% — small and unrepresentative. Fifteen market-closed rejects per run are an execution-scheduling issue, not the source of losses. Gross closed-balance drawdown estimates above are diagnostics, not the tester's equity drawdown.

## Next step

Lock the selected entry rules to `Min_HTF_Source_Body_Percent=20`, `Max_Entry_Distance_R=0.25`, `Min_Zone_Age_Minutes=90` (config C, now the v2.3x input default) and sweep the take-profit ratio on the same window/risk: RR 1 and RR 3 (RR 2 is already measured at +$2,171.62). Expect RR 3 to raise net and stretch loss streaks, RR 1 to raise win rate at lower net.

Then test stop-loss placement (v2.32, `Stop_Mode`): HTF wick vs HTF body vs LTF swing with `Stop_Swing_Count` 1/3/5, only on the RR winner, keeping the config-C filters fixed. Because risk is a fixed dollar amount, the SL method changes trade size, win rate and the entry mix rather than the per-winner payout; judge it on net, drawdown, streak and half-split stability, not on "tighter = better". The LTF-swing mode needs a native lower timeframe (M90 falls back to wick and logs it).

After the RR and SL passes, freeze the full parameter set and validate on genuinely unseen data (live/forward window after 2026-09-08, or at minimum a 2021+ holdout reported separately with all thresholds fixed) before claiming improvement. Parameters have now been selected repeatedly from the same 2014–2026 sample, so the batch-2 numbers include in-sample selection bias; the forward pass is what decides whether the config ships. In parallel, implement deal-level profit logging (realized profit, commission, swap per ticket) so the analysis no longer depends on the 100 oz/lot gross reconstruction.