# DhanuFX tester review — 9 September 2026

## Filter experiment results (EA v2.30, four separate backtests)

Running source: `C:\Users\User\AppData\Roaming\MetaQuotes\Tester\12FE2A177E39CFD95D50E79D01391499\Agent-127.0.0.1-3000\logs\20260909.log` (runs at lines 4184, 18427, 32387, 46370). All four runs: XAUUSD, M90 areas, M5 entries, wick threshold 20%, fixed USD 100 risk, RR 2, USD 10,000 deposit, 2014-01-14 to 2026-09-08. Only the named filter is on per run; default 0 means off. Reproduce with `python scripts/analyze_tester_logs.py` (set `DHANU_TESTER_LOG` to the Agent-3000 path).

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

## RR and SL results (batch 3, config-C filters fixed, v2.32)

Running source: Agent-3000 log, runs at lines 114324 (RR2 control), 128605/129480 (RR3 wick), 142847 (body), 156058/169106/182126 (LTF swing 1/3/5).

RR effect on config C with the structure stop:

| Config | Trades | Win % | Net | PF* | DD est. | Loss streak | Half split (1st/2nd) | Last 3y |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| RR 2, wick | 137 | 40.15% | +$2,171.62 | 1.335 | $804 | 5 | 39.7 / 40.6 | 44.9% (49) |
| RR 3, wick | 135 | 31.85% | +$2,945.42 | 1.395 | $1,192 | 11 | 34.3 / 29.4 | 33.3% (48) |

SL placement at RR 3 (same filters, same window):

| Stop mode | Trades | Win % | Net | PF* | DD est. | Loss streak |
|---|---:|---:|---:|---:|---:|---:|
| HTF wick | 135 | 31.85% | +$2,945.42 | 1.395 | $1,192 | 11 |
| HTF body | 50 | 24.00% | +$689.13 | 0.928 | $1,619 | 11 |
| LTF swing 1 | 96 | 26.04% | -$579.79 | 0.943 | $2,409 | 12 |
| LTF swing 3 | 93 | 29.03% | +$555.16 | 1.094 | $1,521 | 11 |
| LTF swing 5 | 97 | 26.80% | -$293.47 | 0.998 | $2,286 | 13 |

The SL hypothesis is answered empirically: every alternative to the structural HTF wick stop cuts win rate, collapses profit factor to roughly 1 and roughly doubles drawdown. Tightening the stop doubles position size for the same $100 risk but gives the noise more chances to stop the trade first; the edge only materializes when the stop sits beyond the HTF wick noise. Keep `Stop_Mode=SL_HTF_WICK` (default). The LTF-swing idea should not ship.

RR: RR 3 maximizes net (+$2,945 vs +$2,172) but at 1.5x drawdown and double the loss streak, and its second-half/last-3y win rates (29.4%/33.3%) are weaker than RR 2's remarkably balanced split (40.6%/44.9%). The recent regime favors the tighter RR 2 profile; the full-history optimum is RR 3. This is a risk-tolerance choice, to be settled by forward data rather than by a single number on inspected history.

## Next step

Freeze the entry rules (config C) and the stop (`SL_HTF_WICK`, both already the v2.32 defaults). Decide RR after forward validation rather than on this inspected window: the honest gate is genuinely unseen data after 2026-09-08 (or if a proxy is needed, a fixed later subperiod reported separately with all thresholds frozen). Precommit expectations before measuring: config C + RR 2 should reproduce something close to ~40% win rate and +$18/trade after costs; RR 3 ~32% win rate and roughly +$22/trade with roughly double the drawdown and occasional 11+ streaks. Do not retune on the forward result; measure it. In parallel, implement deal-level profit logging (realized profit, commission, swap per ticket) so the analysis no longer depends on the 100 oz/lot gross reconstruction.

One correctness note fixed during batch 3: the 2017-verified M90 history starts are identical across runs and both RR 2 control runs reproduce exactly (+$2,171.62), so the batches are directly comparable.