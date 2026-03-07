# mql5_ea

MetaTrader 5 Expert Advisors and research files for a Bollinger Band mean-reversion day-trading strategy with EMA, RSI, ATR, and broker-side risk management.

## Current Status

The recommended EA in this repository is `DayTradingEA_v2.mq5`.

Repository roles:

- `DayTradingEA_v2.mq5`: primary implementation and current recommended EA
- `TestEA.mq5`: earlier simplified implementation kept for reference
- `Black_Box.mq5`: experimental / cautionary implementation kept for comparison
- `Bot v_1_03.ipynb`: exploratory backtest notebook
- `audit.md`: verified engineering audit of the earlier codebase
- `CHANGELOG.md`: change history for the repository

`TestEA.mq5` and `Black_Box.mq5` should not be treated as the preferred production candidate while `DayTradingEA_v2.mq5` exists.

## Strategy Summary

The core strategy is a short-term mean-reversion model intended for `M5` and `M15` charts.

Entry logic in the v2 EA:

- price extends outside Bollinger Bands
- recent candles confirm short-term exhaustion
- EMA provides directional context
- RSI acts as a momentum filter
- candlestick confirmation is required
- trade is entered either immediately on valid re-entry or after a limited re-entry wait state

Risk management in the v2 EA:

- ATR-based initial stop loss
- take profit at the opposing Bollinger Band
- broker-side trailing via break-even, EMA, and Fibonacci progression
- dynamic lot sizing based on equity and stop distance
- spread filter
- trading-session filter
- daily and total drawdown circuit breakers
- magic number isolation

## Recommended File

Use `DayTradingEA_v2.mq5` if you want the cleanest current implementation.

Reasons:

- broker-synced position handling
- closed-candle signal evaluation
- explicit re-entry state machine
- spread/session/drawdown safety controls
- clearer separation between signal generation, execution, and trade management

## Important Constraints

- One chart per symbol/timeframe. The EA is not a one-chart multi-symbol engine.
- Session inputs are interpreted from broker server time.
- The notebook is research tooling, not proof of live profitability.
- No file in this repository guarantees profits, low drawdown, or stable win rate across brokers or symbols without fresh testing.

## Setup

### MetaTrader 5

1. Place `DayTradingEA_v2.mq5` in your MT5 `MQL5/Experts/` folder.
2. Open MetaEditor and compile the file.
3. Attach the EA to one chart per symbol/timeframe you want to trade.
4. Enable Algo Trading in MT5.
5. Start on a demo account before considering any live deployment.

### Notebook

`Bot v_1_03.ipynb` is available for exploratory analysis and backtesting.

Python packages typically used by the notebook:

```bash
pip install MetaTrader5 pandas_ta backtesting seaborn matplotlib plotly
```

## Key Inputs In `DayTradingEA_v2.mq5`

- `inp_risk_perc`: equity risk per trade
- `inp_max_spread`: maximum spread allowed for new entries
- `inp_session_start` / `inp_session_end`: trading session window in server time
- `inp_max_daily_dd`: daily drawdown stop level
- `inp_max_total_dd`: total drawdown stop level from peak equity
- `inp_reentry_limit`: candles allowed for delayed re-entry
- `inp_rsi_buy_max` / `inp_rsi_sell_min`: RSI filters for buys and sells

## Validation Workflow

Before live use, validate the EA in this order:

1. Compile cleanly in MetaEditor.
2. Run MT5 backtests with realistic spread assumptions.
3. Include commission and slippage in the evaluation.
4. Test on multiple symbols and market regimes.
5. Do out-of-sample and walk-forward validation.
6. Forward-test on demo for multiple weeks.

Metrics to watch:

- net expectancy after costs
- profit factor
- maximum drawdown
- trade frequency
- average winner vs average loser
- stability across symbols and date ranges

## Documentation Map

- `audit.md`: baseline audit findings and architectural concerns discovered during review
- `CHANGELOG.md`: repository-level change history
- `DayTradingEA_v2.mq5`: current primary EA source

## Development Notes

The repository still keeps older implementations because they are useful as reference material, but they should not be confused with the recommended path forward. If you extend the strategy further, use `DayTradingEA_v2.mq5` as the base and treat each new filter or optimization as a testable hypothesis rather than an assumed improvement.

## Risk Notice

Trading leveraged products is risky. This repository is software and research material, not a promise of returns or a guarantee of suitability for any account.
