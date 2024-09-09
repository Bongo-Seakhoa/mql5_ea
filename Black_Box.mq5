//+------------------------------------------------------------------+
//|                                           DayTradingStrategy.mq5 |
//|                                                    Bongo Seakhoa |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Bongo Seakhoa"
#property link      ""
#property version   "5.02"

#include <Trade\Trade.mqh>

#define ERR_INVALID_STOPS 130
#define ERR_TRADE_VOLUME_INVALID 131
#define ERR_NOT_ENOUGH_MONEY 134
#define ERR_TRADE_CONTEXT_BUSY 146


// Declare a global trade object
CTrade trade;

// Define input parameters
input double risk_perc = 0.05;    // Risk percentage per trade
input int atr_period = 14;        // ATR period for Stop Loss calculation
input double min_lot_size = 0.01; // Minimum lot size
input int bb_period = 20;         // Bollinger Bands period
input double bb_deviation = 2.0;  // Bollinger Bands deviation
input int ema_period = 20;        // EMA period
int last_trade_candle = -3; // Initialize to a value that ensures the first trade can occur

// Indicator handles
int handle_bb;
int handle_ema;
int handle_atr;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   // Bollinger Bands initialization
   handle_bb = iBands(_Symbol, _Period, bb_period, 0, bb_deviation, PRICE_CLOSE);

   // EMA initialization
   handle_ema = iMA(_Symbol, _Period, ema_period, 0, MODE_EMA, PRICE_CLOSE);

   // ATR initialization
   handle_atr = iATR(_Symbol, _Period, atr_period);

   if(handle_bb == INVALID_HANDLE || handle_ema == INVALID_HANDLE || handle_atr == INVALID_HANDLE)
     {
      Print("Error initializing indicators!");
      return INIT_FAILED;
     }

   Print("EA initialized successfully");
   return INIT_SUCCEEDED;
  }
  
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   // Release the indicator handles
   if(handle_bb != INVALID_HANDLE)
     {
      IndicatorRelease(handle_bb);
      handle_bb = INVALID_HANDLE;
     }
   
   if(handle_ema != INVALID_HANDLE)
     {
      IndicatorRelease(handle_ema);
      handle_ema = INVALID_HANDLE;
     }
   
   if(handle_atr != INVALID_HANDLE)
     {
      IndicatorRelease(handle_atr);
      handle_atr = INVALID_HANDLE;
     }
   
   Print("EA deinitialized, reason: ", reason);
  }
  
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    // Arrays to hold the indicator data
    double bb_upper[], bb_middle[], bb_lower[], ema_value[];

    // Copy indicator values into arrays
    if(CopyBuffer(handle_bb, 0, 0, 3, bb_upper) <= 0 ||
       CopyBuffer(handle_bb, 1, 0, 3, bb_middle) <= 0 ||
       CopyBuffer(handle_bb, 2, 0, 3, bb_lower) <= 0 ||
       CopyBuffer(handle_ema, 0, 0, 3, ema_value) <= 0)
    {
        Print("Error retrieving indicator data");
        return;
    }

    // Get the current and previous values of the indicators
    double current_bb_upper = bb_upper[1]; // Now using [i-1] values
    double current_bb_middle = bb_middle[1];
    double current_bb_lower = bb_lower[1];
    double current_ema_value = ema_value[1];

    // Get the current candle index
    int current_candle = iBars(_Symbol, _Period) - 1;

    // Check if there's an open position on the current symbol
    bool has_open_trade = PositionSelect(_Symbol);

    // Display comments on the chart
    string comment_text = StringFormat("Upper BB: %.5f\nMiddle BB: %.5f\nLower BB: %.5f\nEMA: %.5f\nHas Open Trade: %s\nLast Trade Candle: %d",
                                        current_bb_upper, current_bb_middle, current_bb_lower, current_ema_value,
                                        has_open_trade ? "Yes" : "No", last_trade_candle);
    Comment(comment_text);

    // If there's no open trade, check for new entry opportunities based on the latest candles
    if(!has_open_trade && (current_candle - last_trade_candle) > 2)
    {
        // --- Buy Signal Conditions ---
        double close_i4 = iClose(_Symbol, _Period, 4); // Close of candle [i-4]
        double close_i3 = iClose(_Symbol, _Period, 3); // Close of candle [i-3]
        double close_i2 = iClose(_Symbol, _Period, 2); // Close of candle [i-2]
        double low_i2 = iLow(_Symbol, _Period, 2);     // Low of candle [i-2]

        // Condition 1: Bollinger Band Condition (Buy)
        bool bb_condition_buy = close_i2 < current_bb_lower || low_i2 < current_bb_lower;

        // Condition 2: EMA Condition (Buy)
        bool ema_condition_buy = close_i4 < current_ema_value && close_i3 < current_ema_value;

        // Condition 3: Price Trend Condition (Buy)
        bool trend_condition_buy = (close_i4 > close_i3) && (close_i3 > close_i2);

        // Condition 4: Candlestick Pattern Confirmation (Buy)
        bool pattern_condition_buy = CheckForBullishPattern(_Symbol, _Period); // Now runs on [i-1]

        // If all buy conditions are met, check for re-entry condition and execute trade
        if(bb_condition_buy && ema_condition_buy && trend_condition_buy && pattern_condition_buy)
        {
            if(close_i2 > current_bb_lower && close_i2 < current_bb_middle)
            {
                OpenTrade(true, current_bb_upper, current_bb_middle, current_bb_lower);
                last_trade_candle = current_candle; // Update last trade candle index
            }
            else
            {
                // Wait for up to two more candles to close inside the Bollinger Band range
                WaitForReEntry(true, current_bb_upper, current_bb_middle, current_bb_lower);
            }
        }

        // --- Sell Signal Conditions ---
        double high_i2 = iHigh(_Symbol, _Period, 2);  // High of candle [i-2]

        // Condition 1: Bollinger Band Condition (Sell)
        bool bb_condition_sell = close_i2 > current_bb_upper || high_i2 > current_bb_upper;

        // Condition 2: EMA Condition (Sell)
        bool ema_condition_sell = close_i4 > current_ema_value && close_i3 > current_ema_value;

        // Condition 3: Price Trend Condition (Sell)
        bool trend_condition_sell = (close_i4 < close_i3) && (close_i3 < close_i2);

        // Condition 4: Candlestick Pattern Confirmation (Sell)
        bool pattern_condition_sell = CheckForBearishPattern(_Symbol, _Period); // Now runs on [i-1]

        // If all sell conditions are met, check for re-entry condition and execute trade
        if(bb_condition_sell && ema_condition_sell && trend_condition_sell && pattern_condition_sell)
        {
            if(close_i2 < current_bb_upper && close_i2 > current_bb_middle)
            {
                OpenTrade(false, current_bb_upper, current_bb_middle, current_bb_lower);
                last_trade_candle = current_candle; // Update last trade candle index
            }
            else
            {
                // Wait for up to two more candles to close inside the Bollinger Band range
                WaitForReEntry(false, current_bb_upper, current_bb_middle, current_bb_lower);
            }
        }
    }
    else if (has_open_trade)
    {
        // Manage risk only at the close of a candle
        static int last_checked_candle = -1;
        if (current_candle != last_checked_candle) // Check if the current candle is a new candle
        {
            last_checked_candle = current_candle;

            // Manage risk for the open trade
            double entry_price = PositionGetDouble(POSITION_PRICE_OPEN);
            bool is_buy = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
            ManageRisk(is_buy, entry_price, current_bb_upper, current_bb_middle, current_bb_lower);
        }
    }
}

//+------------------------------------------------------------------+
//| Function to check for bullish candlestick patterns               |
//+------------------------------------------------------------------+
bool CheckForBullishPattern(string symbol, ENUM_TIMEFRAMES timeframe)
  {
   double open_i1 = iOpen(symbol, timeframe, 1);  // Open of the previous candle [i-1]
   double close_i1 = iClose(symbol, timeframe, 1);// Close of the previous candle [i-1]
   double high_i1 = iHigh(symbol, timeframe, 1);  // High of the previous candle [i-1]
   double low_i1 = iLow(symbol, timeframe, 1);    // Low of the previous candle [i-1]

   double open_prev = iOpen(symbol, timeframe, 2);   // Open of the candle before the previous one [i-2]
   double close_prev = iClose(symbol, timeframe, 2); // Close of the candle before the previous one [i-2]
   double high_prev = iHigh(symbol, timeframe, 2);   // High of the candle before the previous one [i-2]
   double low_prev = iLow(symbol, timeframe, 2);     // Low of the candle before the previous one [i-2]

   // Detect Hammer/Pin Bar pattern
   double body_size = MathAbs(close_i1 - open_i1);
   double upper_wick = high_i1 - MathMax(close_i1, open_i1);
   double lower_wick = MathMin(close_i1, open_i1) - low_i1;
   bool is_hammer = (lower_wick > 2 * body_size) && (upper_wick < 0.5 * body_size);

   // Detect Bullish Engulfing pattern
   bool is_engulfing = (close_i1 >= open_i1) && (close_i1 >= close_prev) && (open_i1 <= open_prev);

   // Morning Star detection (simplified version)
   bool is_morning_star = (close_prev <= open_prev) &&    // Previous candle is bearish
                          (body_size < (high_i1 - low_i1) * 0.3) &&  // Small body in the middle (doji/spinning top)
                          (close_i1 > (open_prev + close_prev) / 2); // Previous candle closes above midpoint of [i-2]

   // Return true if any pattern is detected
   return is_hammer || is_engulfing || is_morning_star;
  }

//+------------------------------------------------------------------+
//| Function to check for bearish candlestick patterns               |
//+------------------------------------------------------------------+
bool CheckForBearishPattern(string symbol, ENUM_TIMEFRAMES timeframe)
  {
   double open_i1 = iOpen(symbol, timeframe, 1);  // Open of the previous candle [i-1]
   double close_i1 = iClose(symbol, timeframe, 1);// Close of the previous candle [i-1]
   double high_i1 = iHigh(symbol, timeframe, 1);  // High of the previous candle [i-1]
   double low_i1 = iLow(symbol, timeframe, 1);    // Low of the previous candle [i-1]

   double open_prev = iOpen(symbol, timeframe, 2);   // Open of the candle before the previous one [i-2]
   double close_prev = iClose(symbol, timeframe, 2); // Close of the candle before the previous one [i-2]
   double high_prev = iHigh(symbol, timeframe, 2);   // High of the candle before the previous one [i-2]
   double low_prev = iLow(symbol, timeframe, 2);     // Low of the candle before the previous one [i-2]

   // Detect Hanging Man/Pin Bar pattern
   double body_size = MathAbs(close_i1 - open_i1);
   double upper_wick = high_i1 - MathMax(close_i1, open_i1);
   double lower_wick = MathMin(close_i1, open_i1) - low_i1;
   bool is_hanging_man = (upper_wick > 2 * body_size) && (lower_wick < 0.5 * body_size);

   // Detect Bearish Engulfing pattern
   bool is_engulfing = (close_i1 <= open_i1) && (close_i1 <= close_prev) && (open_i1 >= open_prev);

   // Evening Star detection (simplified version)
   bool is_evening_star = (close_prev >= open_prev) &&    // Previous candle is bullish
                          (body_size < (high_i1 - low_i1) * 0.3) &&  // Small body in the middle (doji/spinning top)
                          (close_i1 < (open_prev + close_prev) / 2); // Previous candle closes below midpoint of [i-2]

   // Return true if any pattern is detected
   return is_hanging_man || is_engulfing || is_evening_star;
  }

//+------------------------------------------------------------------+
//| Function to wait for re-entry into Bollinger Band range           |
//+------------------------------------------------------------------+
void WaitForReEntry(bool is_buy, double current_bb_upper, double current_bb_middle, double current_bb_lower)
{
   for(int i = 1; i <= 2; i++)
   {
      double close_next = iClose(_Symbol, _Period, i);
      
      if(is_buy)
      {
         if(close_next > current_bb_lower && close_next < current_bb_middle)
         {
            OpenTrade(true, current_bb_upper, current_bb_middle, current_bb_lower);
            return; // Exit loop after trade execution
         }
      }
      else
      {
         if(close_next < current_bb_upper && close_next > current_bb_middle)
         {
            OpenTrade(false, current_bb_upper, current_bb_middle, current_bb_lower);
            return; // Exit loop after trade execution
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Function to calculate lot size based on risk management          |
//+------------------------------------------------------------------+
double CalculateLotSize(double stop_loss_distance, bool is_buy)
{
    // Get the current price depending on the trade direction
    double price = is_buy ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);

    // Calculate the pip value per lot for the symbol
    double pip_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE) / SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);

    // Calculate the lot size based on risk percentage and stop loss distance
    double lot_size = (risk_perc / 100.0) * AccountInfoDouble(ACCOUNT_EQUITY) / (stop_loss_distance * pip_value);

    // Ensure that lot size is within the valid range for the symbol
    lot_size = MathMax(lot_size, min_lot_size);

    // Adjust the lot size according to the broker's volume step
    double volume_step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    lot_size = MathFloor(lot_size / volume_step) * volume_step;

    // Normalize to the broker's allowed precision
    lot_size = NormalizeDouble(lot_size, (int)MathLog10(1.0 / volume_step));

    return lot_size;
}

//+------------------------------------------------------------------+
//| Main function to open a trade                                    |
//+------------------------------------------------------------------+
void OpenTrade(bool is_buy, double current_bb_upper, double current_bb_middle, double current_bb_lower)
{
    double price = is_buy ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);

    // Set stop loss and take profit based on your specified logic
    double stop_loss = is_buy 
                       ? price - (current_bb_middle - current_bb_lower)   // SL = Entry Price - (Middle BB - Lower BB)
                       : price + (current_bb_upper - current_bb_middle) ; // SL = Entry Price + (Upper BB - Middle BB)

    double take_profit = is_buy ? current_bb_upper : current_bb_lower;

    // Ensure absolute values for stop loss and take profit
    stop_loss = MathAbs(stop_loss);
    take_profit = MathAbs(take_profit);

    // Ensure precision is maintained for SL and TP
    stop_loss = NormalizeDouble(stop_loss, _Digits);
    take_profit = NormalizeDouble(take_profit, _Digits);

    // Retrieve the minimum stop level required by the broker
    double min_stop_level = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;

    // Ensure stop loss and take profit levels are valid
    if (is_buy)
    {
        if ((price - stop_loss) < min_stop_level) stop_loss = price - min_stop_level;
        if ((take_profit - price) < min_stop_level) take_profit = price + min_stop_level;
    }
    else
    {
        if ((stop_loss - price) < min_stop_level) stop_loss = price + min_stop_level;
        if ((price - take_profit) < min_stop_level) take_profit = price - min_stop_level;
    }

    // Calculate lot size based on stop loss distance and account equity
    double stop_loss_distance = MathAbs(price - stop_loss);
    double lot_size = CalculateLotSize(stop_loss_distance, is_buy);

    int max_retries = 3;
    int retry_count = 0;
    bool result = false;

    while(retry_count < max_retries)
    {
        if(is_buy)
            result = trade.Buy(lot_size, _Symbol, price, stop_loss, take_profit, "Buy Order");
        else
            result = trade.Sell(lot_size, _Symbol, price, stop_loss, take_profit, "Sell Order");

        if(result)
        {
            Print("Trade successfully opened on attempt ", retry_count + 1);
            break;
        }
        else
        {
            int error_code = GetLastError();
            Print("Failed to open trade on attempt ", retry_count + 1, ": ", error_code);

            if(error_code == ERR_INVALID_STOPS)
            {
                Print("Retrying due to Invalid Stops...");

                // Increment stop loss and take profit by a small amount
                double adjustment = min_stop_level * 1.5; // Example adjustment factor

                if(is_buy)
                {
                    stop_loss -= adjustment;
                    take_profit += adjustment;
                }
                else
                {
                    stop_loss += adjustment;
                    take_profit -= adjustment;
                }

                stop_loss = NormalizeDouble(stop_loss, _Digits);
                take_profit = NormalizeDouble(take_profit, _Digits);

                retry_count++;
            }
            else if(error_code == ERR_TRADE_VOLUME_INVALID || error_code == ERR_NOT_ENOUGH_MONEY)
            {
                lot_size = lot_size / 2; // Reduce the lot size by half

                if(lot_size >= min_lot_size)
                {
                    Print("Reducing lot size to ", lot_size, " and retrying");
                    retry_count++;
                }
                else
                {
                    Print("Lot size is too small to retry the trade");
                    break; // Stop retrying if the lot size is too small
                }
            }
            else
            {
                // If the error is not recoverable, break out of the loop
                break;
            }
        }
    }

    if(!result)
    {
        // If all retries fail, log and alert
        Print("Failed to open trade after ", max_retries, " attempts");
        Alert("Critical: Failed to open trade after multiple retries!");
        SendNotification("EA failed to open trade after multiple retries on " + _Symbol);
    }
}


//+------------------------------------------------------------------+
//| Function to manage risk based on Fibonacci levels and close prices|
//+------------------------------------------------------------------+
void ManageRisk(bool is_buy, double entry_price, double current_bb_upper, double current_bb_middle, double current_bb_lower)
{
    double close_price = iClose(_Symbol, _Period, 1); // Use close price of the previous candle [i-1]

    // Calculate the Fibonacci levels based on the current Bollinger Bands
    double fib_236 = is_buy ? current_bb_lower + 0.236 * (current_bb_upper - current_bb_lower) : current_bb_upper - 0.236 * (current_bb_upper - current_bb_lower);
    double fib_382 = is_buy ? current_bb_lower + 0.382 * (current_bb_upper - current_bb_lower) : current_bb_upper - 0.382 * (current_bb_upper - current_bb_lower);
    double fib_500 = is_buy ? current_bb_lower + 0.500 * (current_bb_upper - current_bb_lower) : current_bb_upper - 0.500 * (current_bb_upper - current_bb_lower);
    double fib_618 = is_buy ? current_bb_lower + 0.618 * (current_bb_upper - current_bb_lower) : current_bb_upper - 0.618 * (current_bb_upper - current_bb_lower);

    // Retrieve the current position details
    double current_tp = PositionGetDouble(POSITION_TP);
    double current_sl = PositionGetDouble(POSITION_SL);
    ulong ticket = PositionGetTicket(0);

    // Adjust the trailing stop dynamically based on close price
    double new_sl = current_sl;
    double new_tp = current_tp;
    bool sl_needs_adjustment = false;

    if (is_buy)
    {
        if (close_price > fib_618 && fib_500 > new_sl)
        {
            new_sl = fib_500;
            sl_needs_adjustment = true;
        }
        else if (close_price > fib_500 && fib_382 > new_sl)
        {
            new_sl = fib_382;
            sl_needs_adjustment = true;
        }
        else if (close_price > fib_382 && fib_236 > new_sl)
        {
            new_sl = fib_236;
            sl_needs_adjustment = true;
        }

        if (current_bb_upper > current_tp)
        {
            new_tp = current_bb_upper;
        }
    }
    else
    {
        if (close_price < fib_618 && fib_500 < new_sl)
        {
            new_sl = fib_500;
            sl_needs_adjustment = true;
        }
        else if (close_price < fib_500 && fib_382 < new_sl)
        {
            new_sl = fib_382;
            sl_needs_adjustment = true;
        }
        else if (close_price < fib_382 && fib_236 < new_sl)
        {
            new_sl = fib_236;
            sl_needs_adjustment = true;
        }

        if (current_bb_lower < current_tp)
        {
            new_tp = current_bb_lower;
        }
    }

    // Normalize and modify the SL and TP only if needed
    if (sl_needs_adjustment)
    {
        new_sl = NormalizeDouble(new_sl, _Digits);
        new_tp = NormalizeDouble(new_tp, _Digits);

        if (trade.PositionModify(ticket, new_sl, new_tp))
        {
            Print("SL/TP adjusted. New SL: ", new_sl, ", New TP: ", new_tp);
        }
        else
        {
            int error_code = GetLastError();
            Print("Error modifying SL/TP. Error code: ", error_code);
        }
    }
}

//+------------------------------------------------------------------+