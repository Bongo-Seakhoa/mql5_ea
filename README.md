### mql5_ea: **Forex Trading Automation EA & Backtest**

---

### Repository Overview
This repository contains multiple components designed for automating and backtesting Forex trading strategies. It features Expert Advisors (EAs) for MetaTrader 5 (MT5) and a Jupyter notebook for backtesting. The repository encourages community contributions but also provides a word of caution regarding overdevelopment with a sample EA that went beyond practical optimization.

---

### Files Included:
1. **TestEA.mq5**: A well-balanced Expert Advisor (EA) that trades based on technical indicators and offers flexible risk management.
2. **Bot_v_1_03.ipynb**: A Jupyter notebook that performs backtesting and analysis of the EA strategy, allowing users to evaluate its effectiveness on historical data.
3. **Black_Box.mq5**: A cautionary example of an EA that was over-developed, demonstrating the dangers of excessive optimization and complex logic. It highlights potential pitfalls that developers should avoid when creating trading algorithms.

---

### Key Features
- **TestEA.mq5**:
  - **Technical Indicators**: Utilizes Bollinger Bands, Exponential Moving Averages (EMA), Relative Strength Index (RSI), and Average True Range (ATR) to generate trade signals.
  - **Risk Management**: Implements adjustable stop-loss and take-profit levels based on volatility and Fibonacci levels for maximizing profit while minimizing risk.
  - **Dynamic Lot Size**: The EA calculates the appropriate lot size based on account equity and stop-loss distance, ensuring proper risk management on every trade.
  - **Re-entry Logic**: Trades are only executed after price re-enters a favorable range within the Bollinger Bands, helping to avoid premature entries.

- **Bot_v_1_03.ipynb**:
  - **Backtesting**: Connects to MT5 to pull historical data and applies the same strategy as `TestEA.mq5`, allowing for in-depth performance evaluation before live trading.
  - **Signal Generation**: Performs technical analysis using Bollinger Bands, EMA, RSI, and ATR, generating buy/sell signals that can be visually inspected.
  - **Performance Metrics**: Displays trade statistics including win rate, total trades, and total profit/loss.
  - **Visualizations**: Creates plots to visualize trading signals, equity curves, and technical indicators, helping traders understand how the strategy performs over time.

- **Black_Box.mq5** (Cautionary Example):
  - **Over-Development Pitfalls**: Demonstrates how excessive complexity and frequent retry mechanisms can reduce trading efficiency and lead to poor execution.
  - **Advanced Signal Detection**: Includes complex candlestick pattern detection (e.g., hammer, engulfing, and morning star patterns), re-entry logic, and risk management that sometimes lead to decision delays.
  - **Warning**: While comprehensive in features, this EA is an example of how trading logic can become inefficient and counterproductive when overly optimized. This script should serve as a learning tool to avoid adding unnecessary complexity.

---

### Getting Started

#### 1. **MetaTrader 5 Expert Advisor Setup**:
   - Download either `TestEA.mq5` or `Black_Box.mq5`.
   - Place the files into your `MQL5/Experts/` directory in MetaTrader 5.
   - Open the MetaEditor, compile the EA, and attach it to a trading chart within MT5.

#### 2. **Backtesting Setup in Jupyter Notebook**:
   - Download `Bot_v_1_03.ipynb`.
   - Install the necessary Python libraries by running the following commands:
     ```bash
     pip install MetaTrader5 pandas_ta backtesting seaborn matplotlib plotly
     ```
   - Open the notebook and configure your MT5 login credentials. Run the cells to start backtesting the strategy using historical data.

---

### Technical Indicators Used:
- **Bollinger Bands**: Identifies price volatility and generates signals based on price re-entry into the bands.
- **Exponential Moving Averages (EMA)**: Helps identify market trends and determines entry/exit points.
- **Relative Strength Index (RSI)**: Measures momentum and indicates overbought/oversold conditions.
- **Average True Range (ATR)**: Used for calculating volatility and determining stop-loss levels.

---

### How It Works
#### **TestEA.mq5**:
- **Signal Generation**: Generates buy or sell signals based on the interaction between price and technical indicators like Bollinger Bands and EMA.
- **Re-entry Logic**: The EA ensures that trades are only taken when the price re-enters a favorable range within the Bollinger Bands.
- **Dynamic Stop-Loss & Take-Profit**: The EA adjusts stop-loss and take-profit levels dynamically based on the Fibonacci retracement levels between the EMA and Bollinger Bands.

#### **Black_Box.mq5** (Cautionary Example):
- **Complex Signal Logic**: This EA goes beyond standard signal detection and includes candlestick pattern recognition. It highlights how over-complication can lead to inefficiencies.
- **Error Handling & Retry Logic**: The EA aggressively retries failed trades, which can sometimes cause excessive drawdown or missed opportunities.

---

### Cautionary Note: **Over-Development Pitfalls**
The `Black_Box.mq5` file serves as an educational tool to demonstrate the risks of over-developing an EA. While it includes advanced features such as candlestick pattern detection, intricate re-entry logic, and aggressive risk management, the complexity may hinder performance. Developers should aim for simplicity and focus on core trading logic to maintain efficiency and reduce unnecessary trade execution errors.

---

### Example Usage
- **Live Trading**: Use `TestEA.mq5` for live or demo accounts to automate trades based on tested signals.
- **Backtesting**: Before going live, run backtests in `Bot_v_1_03.ipynb` to evaluate strategy performance on historical data.
- **Education**: Learn from the overdevelopment in `Black_Box.mq5` by analyzing how complexity can impact trading outcomes and understanding how to avoid these issues in your own development.

---

### Prerequisites
- **MetaTrader 5**: Download and install for live/demonstration trading.
- **Python 3.7+**: Required to run the backtesting notebook.
- **Required Python Libraries**:
  ```bash
  pip install MetaTrader5 pandas_ta backtesting seaborn matplotlib plotly
  ```

---

### What was the goal when I started ?

Expert Advisor (EA) will implement a day trading strategy on the MetaTrader 5 (MT5) platform, focusing on Forex pairs and commodities (gold, silver, oil). The strategy is based on Bollinger Bands, EMA, candlestick pattern confirmations, and dynamic risk management. The EA is designed to operate on 5-minute (5M) and 15-minute (15M) timeframes and aims to achieve a minimum annual profit of 60%.

#### **Core Functionality**

1. **Trading Conditions and Strategy**

   - **Market Instruments**: Forex pairs and commodities (gold, silver, oil).
   - **Timeframes**: 5M and 15M.

   ##### **Entry Conditions**

   **Buy Signal**:
   1. **Bollinger Band Condition**:
      - The previous candle ([i-1]) must have:
        - Closed below the lower Bollinger Band (BB Lower), or
        - The lowest price (low) of the candle must have been below the BB Lower.
   2. **EMA Condition**:
      - The closing prices of the two candles before the previous one ([i-3] and [i-2]) must have been below the 20-period EMA.
   3. **Price Trend Condition**:
      - The closing prices over the last three candles ([i-3], [i-2], and [i-1]) must show a decreasing trend:
        - Close of [i-3] > Close of [i-2] > Close of [i-1].
   4. **Candlestick Pattern Confirmation**:
      - The confirmation candle ([i]) must form one of the following patterns: Pin Bar, Hammer, Hanging Man, Morning Star, Evening Star, or an Engulfing candle.
      - If the confirmation candle forms any of these patterns but does not close inside the Bollinger Band middle and lower band range, the EA will wait. If the next candle ([i+1]) or the candle after that ([i+2]) closes inside the Bollinger Band range, a trade must immediately be executed at the current price.
      - **OR**: If the confirmation candle ([i]) forms an Engulfing candle and closes inside the Bollinger Band middle and lower band range, the EA must immediately execute a trade at the current price.
   5. **Re-entry Condition** (Final Validation):
      - The EA must wait for the price to re-enter the Bollinger Band range before executing a trade. If the price does not re-enter within the next two candles, the EA should not enter the trade and should look for a new opportunity.

   **Sell Signal**:
   1. **Bollinger Band Condition**:
      - The previous candle ([i-1]) must have:
        - Closed above the upper Bollinger Band (BB Upper), or
        - The highest price (high) of the candle must have been above the BB Upper.
   2. **EMA Condition**:
      - The closing prices of the two candles before the previous one ([i-3] and [i-2]) must have been above the 20-period EMA.
   3. **Price Trend Condition**:
      - The closing prices over the last three candles ([i-3], [i-2], and [i-1]) must show an increasing trend:
        - Close of [i-3] < Close of [i-2] < Close of [i-1].
   4. **Candlestick Pattern Confirmation**:
      - The confirmation candle ([i]) must form one of the following patterns: Pin Bar, Hammer, Hanging Man, Morning Star, Evening Star, or an Engulfing candle.
      - If the confirmation candle forms any of these patterns but does not close inside the Bollinger Band middle and upper band range, the EA will wait. If the next candle ([i+1]) or the candle after that ([i+2]) closes inside the Bollinger Band range, a trade must immediately be executed at the current price.
      - **OR**: If the confirmation candle ([i]) forms an Engulfing candle and closes inside the Bollinger Band middle and upper band range, the EA must immediately execute a trade at the current price.
   5. **Re-entry Condition** (Final Validation):
      - The EA must wait for the price to re-enter the Bollinger Band range before executing a trade. If the price does not re-enter within the next two candles, the EA should not enter the trade and should look for a new opportunity.

2. **Risk Management**

   - **Dynamic Lot Sizing**:
     - The lot size will be calculated dynamically using the following formula:
       
python
       #------ Lot sizing considering risk --------------------------
       pip_value = (1e-4 / self.data.Close[-1]) * 1e5
       size = int(self.risk_perc * self.equity / (slatr * pip_value))

     - **Risk Per Trade**: Maximum of 5% of account equity.
     - **Minimum Lot Size**: 0.01 lots.

   - **Dynamic Stop Loss (SL)**:
     - Set at the current price ± 2 * ATR value.

   - **Take Profit (TP)**:
     - Initially set at the opposing upper/lower Bollinger Band level.
     - The EA should manage the trade internally by adjusting the trailing stop based on Fibonacci retracement levels (23.6%, 38.2%, 50%, 61.8%) as the price moves favourably.
     - The TP should be updated to the latest value of the opposing Bollinger Band if it is more profitable than the previous level.

3. **Price Monitoring**

   - The EA should closely monitor live price action, including both bid and ask prices, which are essential for accurate trade execution and management.
   - The EA must track these prices to determine the best entry and exit points and to ensure the internal risk management strategy is effectively implemented.
   - **Price Action Monitoring**:
     - The EA should focus on closed candles and continuously monitor live prices to make real-time adjustments to trades (the Notebook focusses on Closed candles only).

#### **Technical Requirements**

- **Platform**: MetaTrader 5 (MT5)
- **Language**: MQL5
- **Deliverables**:
  - Full source code (.mq5)
  - User guide and documentation explaining setup, parameters, and strategy logic.

#### **Additional Notes**

- The EA must be designed to handle multiple currency pairs and commodities (gold, silver, oil) simultaneously.
- The internal logic should be modular, allowing for easy updates or adjustments to the strategy.

---

### Contributing
Contributions are welcome. Feel free to submit issues, offer suggestions, or contribute to the codebase. When making changes, remember to keep the trading logic simple and efficient. Avoid adding unnecessary complexity that can degrade performance or introduce bugs.

---

### Sources and credit 

Lot sizing considering risk  - https://www.youtube.com/@CodeTradingCafe (No affiliation but the videos helped in creating the code)
MQL EA coding                - https://www.youtube.com/c/Ren%C3%A9Balke (No affiliation but the videos helped in creating the code)

