//+------------------------------------------------------------------+
//|                                                    TestEA.mq5    |
//|                                                    Bongo Seakhoa |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Bongo Seakhoa"
#property link      ""
#property version   "1.02"

#include <Trade\Trade.mqh>

// Declare a global trade object
CTrade trade;

// Define input parameters
input double atr_multiplier = 2.0;          // ATR multiplier for stop loss calculation
input int    ema20_period   = 20;           // EMA 20 period
input int    ema50_period   = 50;           // EMA 50 period
input int    rsi_period     = 14;           // RSI period
input int    atr_period     = 14;           // ATR period
input int    bband_period   = 20;           // Bollinger Bands period
input double bband_std_dev  = 2.0;          // Bollinger Bands deviation
input int    reentry_candle_limit = 2;      // Re-entry limit for candles
input double risk_perc      = 5.0;          // Risk percentage per trade
input double min_lot_size   = 0.01;         // Minimum lot size
input int    magic_number   = 202603;       // Magic number for this EA
input int    max_spread_points = 30;        // Maximum allowed spread in points

// Indicator handles
int handle_ema20, handle_ema50, handle_rsi, handle_atr, handle_bb;

// Re-entry counter (not position state -- kept as signal logic state)
int reentry_wait_counter = 0;

//+------------------------------------------------------------------+
//| New candle detection                                              |
//+------------------------------------------------------------------+
bool IsNewCandle()
  {
   static int last_bars = 0;
   int current_bars = iBars(_Symbol, _Period);
   if(current_bars != last_bars)
     {
      last_bars = current_bars;
      return true;
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   // Initialize indicators
   handle_ema20 = iMA(_Symbol, _Period, ema20_period, 0, MODE_EMA, PRICE_CLOSE);
   handle_ema50 = iMA(_Symbol, _Period, ema50_period, 0, MODE_EMA, PRICE_CLOSE);
   handle_rsi = iRSI(_Symbol, _Period, rsi_period, PRICE_CLOSE);
   handle_atr = iATR(_Symbol, _Period, atr_period);
   handle_bb = iBands(_Symbol, _Period, bband_period, 0, bband_std_dev, PRICE_CLOSE);

   if (handle_ema20 == INVALID_HANDLE || handle_ema50 == INVALID_HANDLE || handle_rsi == INVALID_HANDLE || handle_atr == INVALID_HANDLE || handle_bb == INVALID_HANDLE)
     {
      Print("Error initializing indicators!");
      return INIT_FAILED;
     }

   // Configure the trade object
   trade.SetExpertMagicNumber(magic_number);
   trade.SetDeviationInPoints(10);

   Print("EA initialized successfully");
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   IndicatorRelease(handle_ema20);
   IndicatorRelease(handle_ema50);
   IndicatorRelease(handle_rsi);
   IndicatorRelease(handle_atr);
   IndicatorRelease(handle_bb);
   Print("EA deinitialized, reason: ", reason);
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   // Only process on new candle formation
   if(!IsNewCandle())
      return;

   // Arrays to hold the indicator data
   double ema20[], ema50[], rsi[], atr[], bb_upper[], bb_middle[], bb_lower[];

   // Copy indicator values from shift 1 (last closed candle)
   if (CopyBuffer(handle_ema20, 0, 1, 1, ema20) <= 0 ||
       CopyBuffer(handle_ema50, 0, 1, 1, ema50) <= 0 ||
       CopyBuffer(handle_rsi, 0, 1, 1, rsi) <= 0 ||
       CopyBuffer(handle_atr, 0, 1, 1, atr) <= 0 ||
       CopyBuffer(handle_bb, 1, 1, 1, bb_upper) <= 0 ||
       CopyBuffer(handle_bb, 2, 1, 1, bb_lower) <= 0 ||
       CopyBuffer(handle_bb, 0, 1, 1, bb_middle) <= 0)
     {
      Print("Error retrieving indicator data");
      return;
     }

   // Get the current and previous values of the indicators
   double current_ema20 = ema20[0];
   double current_ema50 = ema50[0];
   double current_rsi = rsi[0];
   double current_atr = atr[0];
   double current_bb_upper = bb_upper[0];
   double current_bb_middle = bb_middle[0];
   double current_bb_lower = bb_lower[0];

   // Get the last closed candle prices
   double close_price = iClose(_Symbol, _Period, 1);
   double low_price = iLow(_Symbol, _Period, 1);
   double high_price = iHigh(_Symbol, _Period, 1);

   // Check if we have an open position from the broker
   bool has_position = PositionSelect(_Symbol);

   // Determine if a trade should be opened (initial signal)
   int signal = 0;
   if ((close_price < current_bb_lower || low_price < current_bb_lower) && close_price < current_ema20 && close_price < current_ema50)
     {
      if (current_rsi < 40) // RSI filter: require RSI < 40 for buy
        {
         signal = 2; // Buy signal
         reentry_wait_counter = 0;
        }
     }
   else if ((close_price > current_bb_upper || high_price > current_bb_upper) && close_price > current_ema20 && close_price > current_ema50)
     {
      if (current_rsi > 60) // RSI filter: require RSI > 60 for sell
        {
         signal = 1; // Sell signal
         reentry_wait_counter = 0;
        }
     }

   // Manage re-entry conditions (only open if no position exists)
   if (!has_position && signal > 0 && reentry_wait_counter < reentry_candle_limit)
     {
      reentry_wait_counter++;
      if ((signal == 2 && close_price > current_bb_lower && close_price < current_bb_middle) || (signal == 1 && close_price < current_bb_upper && close_price > current_bb_middle))
        {
         OpenTrade(signal, current_atr, current_bb_upper, current_bb_middle, current_bb_lower);
        }
     }
   else if (reentry_wait_counter >= reentry_candle_limit)
     {
      signal = 0;
      reentry_wait_counter = 0;
     }

   // Manage open trades and adjust SL based on Fibonacci levels
   if (has_position)
     {
      AdjustStopLossAndTakeProfit(close_price, current_ema20, current_bb_upper, current_bb_lower);
     }
  }

//+------------------------------------------------------------------+
//| Execute trade using CTrade                                        |
//+------------------------------------------------------------------+
void OpenTrade(int direction, double current_atr, double current_bb_upper, double current_bb_middle, double current_bb_lower)
  {
   // Check if position already exists
   if (PositionSelect(_Symbol))
      return;

   // Spread filter
   int current_spread = (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if (current_spread > max_spread_points)
     {
      Print("Spread too high (", current_spread, " > ", max_spread_points, "), skipping entry.");
      return;
     }

   double sl, tp, stop_loss_distance;

   if (direction == 2) // Buy
     {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      sl = ask - (current_atr * atr_multiplier);
      tp = current_bb_upper;
      stop_loss_distance = ask - sl;

      double lot_size = CalculateLotSize(stop_loss_distance, true);

      if (trade.Buy(lot_size, _Symbol, ask, sl, tp, "TestEA Buy"))
         Print("Buy trade opened at ", ask, " SL=", sl, " TP=", tp, " lots=", lot_size);
      else
         Print("Buy trade failed, error: ", GetLastError());
     }
   else if (direction == 1) // Sell
     {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      sl = bid + (current_atr * atr_multiplier);
      tp = current_bb_lower;
      stop_loss_distance = sl - bid;

      double lot_size = CalculateLotSize(stop_loss_distance, false);

      if (trade.Sell(lot_size, _Symbol, bid, sl, tp, "TestEA Sell"))
         Print("Sell trade opened at ", bid, " SL=", sl, " TP=", tp, " lots=", lot_size);
      else
         Print("Sell trade failed, error: ", GetLastError());
     }
  }

//+------------------------------------------------------------------+
//| Adjust Stop Loss and Take Profit based on Fibonacci Levels        |
//+------------------------------------------------------------------+
void AdjustStopLossAndTakeProfit(double close_price, double ema20, double bb_upper, double bb_lower)
  {
   if (!PositionSelect(_Symbol))
      return;

   // Read current position state from broker
   double current_sl = PositionGetDouble(POSITION_SL);
   double current_tp = PositionGetDouble(POSITION_TP);
   long pos_type = PositionGetInteger(POSITION_TYPE);
   ulong ticket = PositionGetInteger(POSITION_TICKET);

   double new_sl = current_sl;
   double fib_levels[] = {0.236, 0.382, 0.5, 0.618};

   if (pos_type == POSITION_TYPE_BUY)
     {
      if (close_price >= ema20)
         new_sl = MathMax(new_sl, ema20);

      for (int i = 0; i < ArraySize(fib_levels); i++)
        {
         double fib_target = ema20 + fib_levels[i] * (bb_upper - ema20);
         if (close_price >= fib_target)
            new_sl = MathMax(new_sl, fib_target);
        }
     }
   else if (pos_type == POSITION_TYPE_SELL)
     {
      if (close_price <= ema20)
         new_sl = MathMin(new_sl, ema20);

      for (int i = 0; i < ArraySize(fib_levels); i++)
        {
         double fib_target = ema20 - fib_levels[i] * (ema20 - bb_lower);
         if (close_price <= fib_target)
            new_sl = MathMin(new_sl, fib_target);
        }
     }

   // Only modify if SL actually changed
   if (MathAbs(new_sl - current_sl) > _Point)
     {
      if (!trade.PositionModify(ticket, new_sl, current_tp))
         Print("Failed to modify position, error: ", GetLastError());
      else
         Print("Position modified: new SL=", new_sl, " TP=", current_tp);
     }
  }

//+------------------------------------------------------------------+
//| Function to calculate lot size based on risk management          |
//+------------------------------------------------------------------+
double CalculateLotSize(double stop_loss_distance, bool is_buy)
{
    // Guard against division by zero
    if (stop_loss_distance <= 0)
      {
       Print("Warning: stop_loss_distance <= 0, using min lot size");
       return min_lot_size;
      }

    double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    if (tick_size == 0)
      {
       Print("Warning: tick_size == 0, using min lot size");
       return min_lot_size;
      }

    // Calculate the pip value per lot for the symbol
    double pip_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE) / tick_size;

    // Guard against pip_value being zero
    if (pip_value == 0)
      {
       Print("Warning: pip_value == 0, using min lot size");
       return min_lot_size;
      }

    // Calculate the lot size based on risk percentage and stop loss distance
    double lot_size = (risk_perc / 100.0) * AccountInfoDouble(ACCOUNT_EQUITY) / (stop_loss_distance * pip_value);

    // Clamp to broker min and max
    double volume_min = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double volume_max = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    lot_size = MathMax(lot_size, MathMax(min_lot_size, volume_min));
    lot_size = MathMin(lot_size, volume_max);

    // Adjust the lot size according to the broker's volume step
    double volume_step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    if (volume_step > 0)
      {
       lot_size = MathFloor(lot_size / volume_step) * volume_step;
       // Normalize to the broker's allowed precision
       lot_size = NormalizeDouble(lot_size, (int)MathLog10(1.0 / volume_step));
      }

    return lot_size;
}
//+------------------------------------------------------------------+
