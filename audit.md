# Verified EA Audit - `Black_Box.mq5`, `TestEA.mq5`, `Bot v_1_03.ipynb`

## Scope

This audit was reworked to distinguish:

- Verified code defects that change live trading behavior
- Documentation mismatches
- Strategy ideas that still need backtesting

This is a static source audit. The EAs were not compiled or forward-tested in MT5 in this environment, so no claim here should be read as a profit guarantee. "Best possible" for a trading system is not something that can be promised from code inspection alone; the practical goal is to remove correctness bugs first, then optimize with controlled backtests and forward tests.

---

## Executive Summary

The current repository does not contain a live-ready EA.

- `Black_Box.mq5` has a critical Bollinger Bands buffer-mapping error that corrupts its core signal and risk logic.
- `TestEA.mq5` is structurally simpler, but it is unsafe for live trading because it tracks trade state locally instead of from the broker and never sends trailing-stop updates back to the broker.
- The notebook backtest output is not strong enough to justify deployment. It reports `3198` trades, `0.5980992236832418` total raw profit, and `61.91%` win rate, which is effectively flat before commission and slippage.
- The previous version of `audit.md` caught several real issues, but it missed the most serious defect in `Black_Box.mq5` and made performance projections that are not defensible without fresh testing.

### Bottom line

Do not merge the two existing EAs into one by using `Black_Box.mq5` as the base. If you want the best engineering path, start from `TestEA.mq5` as the simpler reference or do a clean rewrite from the strategy spec, then add features only after the core execution model is correct.

---

## Verified Critical Defects

### 1. `Black_Box.mq5` maps Bollinger buffers incorrectly

**File**: `Black_Box.mq5:95-97`

`iBands()` in MQL5 exposes:

- buffer `0` = middle/base
- buffer `1` = upper
- buffer `2` = lower

But `Black_Box.mq5` loads:

- buffer `0` into `bb_upper`
- buffer `1` into `bb_middle`
- buffer `2` into `bb_lower`

This means the EA is treating the middle band as the upper band throughout signal generation, SL/TP placement, re-entry logic, and trailing logic.

**Impact**:

- buy/sell trigger logic is distorted
- take-profit targets are wrong
- stop-loss distances are wrong
- Fibonacci trail levels are built from invalid band levels

This is the single most important defect in the repository and was missed by the previous audit.

### 2. `Black_Box.mq5` does not actually "wait" for future re-entry candles

**File**: `Black_Box.mq5:273-292`

`WaitForReEntry()` loops over `iClose(_Symbol, _Period, i)` for `i = 1..2`, which reads already-closed historical candles in the same `OnTick()` pass. It does not persist pending signal state and it does not wait across future candles.

**Impact**:

- re-entry behavior does not match the stated strategy
- the EA can only re-check old candles, not future ones
- live behavior diverges from intended design

### 3. `TestEA.mq5` uses local trade state instead of broker state

**File**: `TestEA.mq5:29`, `TestEA.mq5:130`, `TestEA.mq5:145`, `TestEA.mq5:183`, `TestEA.mq5:240`

`trade_open`, `entry_price`, `stop_loss`, `take_profit`, and `trade_direction` are maintained locally. If MT5 restarts, the EA is removed/reloaded, or the broker closes the position by server-side SL/TP, those variables are no longer reliable.

**Impact**:

- the EA can stop trading even though no position exists
- the EA can manage the wrong state after restart
- local SL/TP and direction can diverge from the broker's actual position

The broker must be the source of truth.

### 4. `TestEA.mq5` trailing-stop logic never modifies the live position on the broker

**File**: `TestEA.mq5:192-240`

`AdjustStopLossAndTakeProfit()` updates the local `stop_loss` variable, but it never calls `PositionModify()` or an equivalent broker-side modification request. The only broker interaction in that function is a manual close when the local logic believes SL or TP has been reached.

**Impact**:

- the broker keeps the original SL/TP, not the trailed values
- the EA is effectively paper-trailing locally
- restart or latency breaks risk management behavior

### 5. `TestEA.mq5` duplicates broker SL/TP handling with manual close logic

**File**: `TestEA.mq5:168-178`, `TestEA.mq5:221-239`

The trade is opened with broker-side `sl` and `tp`, but the EA also manually checks `close_price <= stop_loss` or `close_price >= take_profit` and sends another market order to close the position.

**Impact**:

- race conditions with broker-side execution
- duplicate close attempts
- mismatch between candle-close logic and actual tick-level fills

### 6. `TestEA.mq5` mixes current-bar indicators with closed-bar price logic

**File**: `TestEA.mq5:75-81`, `TestEA.mq5:97-99`

Indicators are copied from shift `0` (current forming bar), while price conditions use `iClose/iLow/iHigh(..., 1)` from the last closed candle.

**Impact**:

- signals repaint during the open candle
- conditions are internally inconsistent
- backtest/live comparability degrades

This is a real issue, but it belongs to `TestEA.mq5`, not the Bollinger buffer order itself. The previous audit attributed the buffer problem to the wrong file.

### 7. `Black_Box.mq5` can modify the wrong position ticket

**File**: `Black_Box.mq5:114`, `Black_Box.mq5:459`, `Black_Box.mq5:519`

The EA checks `PositionSelect(_Symbol)` but later gets the ticket with `PositionGetTicket(0)`, which fetches the position at index `0`, not necessarily the selected symbol position.

**Impact**:

- wrong position may be modified if more than one position exists
- behavior becomes unsafe in multi-symbol or mixed manual/EA trading

### 8. Both EAs have unsafe lot-sizing guards

**Files**:

- `Black_Box.mq5:301-319`
- `TestEA.mq5:248-271`

Both lot-size functions:

- divide by `SYMBOL_TRADE_TICK_SIZE` without guarding against zero
- divide by `stop_loss_distance` without guarding against zero
- enforce only minimum volume, not broker maximum volume

**Impact**:

- invalid lot sizes
- order rejection
- NaN/infinite calculation risk

### 9. `Black_Box.mq5` risk configuration is inconsistent with the stated design

**File**: `Black_Box.mq5:22`, `Black_Box.mq5:310`

`risk_perc` is set to `0.05`, then divided by `100.0` in position sizing. That means effective risk is `0.05%`, not `5%`.

**Impact**:

- the EA is not operating at the documented risk level
- performance comparisons between `Black_Box.mq5`, `TestEA.mq5`, and the notebook are not apples-to-apples

This should be treated as a configuration/logic mismatch, not as a minor note.

---

## High-Priority Structural Issues

### 10. `TestEA.mq5` does not release indicator handles

**File**: `TestEA.mq5:61-64`

`OnDeinit()` logs only a message and does not call `IndicatorRelease()` for any handle.

### 11. Neither EA isolates its own trades with a magic number

**Files**:

- `Black_Box.mq5`
- `TestEA.mq5`

Both EAs rely on symbol-level position checks. That is not safe if another EA or manual trade is active on the same symbol.

### 12. `Black_Box.mq5` hides bad price calculations with `MathAbs()`

**File**: `Black_Box.mq5:340-341`

Applying `MathAbs()` to price levels is not a valid fix. If SL/TP math produces an invalid sign, the EA should fail safely and log the reason.

### 13. `TestEA.mq5` initializes RSI but does not use it

**File**: `TestEA.mq5:44`, `TestEA.mq5:77`, and signal logic at `TestEA.mq5:102-127`

This is not just dead code. It is also a documentation mismatch because the README describes RSI as part of the decision process.

### 14. Neither EA has minimum execution-quality filters

Missing controls include:

- maximum spread filter
- trading-session filter
- daily loss / max drawdown circuit breaker
- freeze-level checks

These are not optional polish items for live deployment; they are baseline execution safeguards.

---

## Notebook Findings

### 15. The notebook result does not show a deployable edge

**File**: `Bot v_1_03.ipynb`

Verified outputs in the notebook:

- `Total Trades: 3198`
- `Total Profit: 0.5980992236832418`
- `Win Rate: 61.91%`

That profit figure is effectively flat before commission and real slippage. A strategy with near-zero raw edge is not ready for live use even if the win rate looks acceptable.

### 16. The notebook includes spread, but not full trading costs

**File**: `Bot v_1_03.ipynb:764-768`

The backtest adjusts entry price by spread, but there is no visible commission model and no realistic execution/slippage model.

### 17. The notebook re-entry state does not track signal direction

**File**: `Bot v_1_03.ipynb:656-689`

`re_entry_wait` is a single boolean. Once enabled, the next re-entry condition can fire either buy or sell. Direction is not explicitly preserved in state.

---

## What The Previous Audit Got Wrong

### 1. It missed the most serious defect

The previous audit did not identify the Bollinger buffer-mapping bug in `Black_Box.mq5`, even though that bug invalidates the strategy's core calculations.

### 2. It put the Bollinger indexing concern on the wrong file

`TestEA.mq5` uses the correct `iBands()` buffer indices. Its actual issue is using shift `0` for indicators while using closed-bar price data for signals.

### 3. It recommended using `Black_Box.mq5` as the base for a new EA

That recommendation is not supported by the code. `Black_Box.mq5` is more complex, more fragile, and already described in the README as a cautionary example.

### 4. It made unsupported performance projections

Claims such as "win rate should improve to 65-70%" or "profit factor should improve to 1.3-1.5" are not audit findings. They are hypotheses and require fresh backtests, out-of-sample validation, and forward testing.

### 5. It mixed verified defects with speculative enhancements

Items like RSI thresholds, ATR filters, higher-timeframe filters, and session filters may be good experiments, but they are not the same class of issue as broken execution logic or wrong indicator mapping.

---

## Recommended Build Direction

### Use one clean EA, not a merge of both current files

Recommended order of preference:

1. Clean rewrite from the documented strategy rules
2. If a rewrite is not desired, refactor `TestEA.mq5` as the simpler baseline
3. Do not use `Black_Box.mq5` as the architecture base

### Mandatory engineering fixes before any optimization

1. Correct the Bollinger buffer mapping in `Black_Box.mq5` or retire that file from production consideration.
2. Replace local trade-state tracking with broker-derived state.
3. Use closed-bar-only signal evaluation with an explicit new-candle gate.
4. Implement real broker-side position modification for trailing and break-even logic.
5. Add magic number filtering.
6. Add lot-size guards for zero distance, zero tick size, min/max volume, and volume step.
7. Add spread and session safety filters.
8. Add drawdown circuit breakers.

Only after those steps are complete should strategy optimization begin.

---

## Strategy Experiments Worth Testing After Core Fixes

These are hypotheses, not guaranteed improvements:

- explicit RSI confirmation, if you want the code to match the README
- ATR or Bollinger bandwidth regime filter to avoid dead/chaotic markets
- higher-timeframe trend filter
- break-even logic after reaching a defined reward multiple
- partial scaling out instead of single full exits
- Friday risk reduction / no-new-trades window

Each experiment should be tested one at a time against a locked baseline.

---

## Validation Standard For "Best Possible"

If the goal is to build the strongest version of this EA, optimize for measured robustness, not for an attractive single backtest.

Minimum validation standard:

1. Cost-adjusted expectancy must be clearly positive after spread, commission, and slippage assumptions.
2. Profit factor, drawdown, and trade frequency must remain acceptable across multiple symbols and market regimes.
3. Results must survive out-of-sample testing and walk-forward testing.
4. Demo forward testing should run for at least several weeks before any live deployment.
5. Any optimization parameter chosen from backtests should be revalidated on data not used for tuning.

---

## Final Recommendation

The right next step is not to add more features to the current code immediately. The right next step is to build a correct execution core first.

At present:

- `Black_Box.mq5` is not trustworthy because its Bollinger inputs are miswired.
- `TestEA.mq5` is not trustworthy because its trade management is local instead of broker-synced.
- The notebook result does not show enough raw edge to justify live deployment.

If you want the best realistic path forward, rebuild the EA around a clean, broker-synced, closed-bar execution model and treat every strategy enhancement as an experiment that must earn its place through testing.
