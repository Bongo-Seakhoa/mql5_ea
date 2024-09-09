//+------------------------------------------------------------------+
//|                                                    TestEA.mq5    |
//|                                                    Bongo Seakhoa |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Bongo Seakhoa"
#property link      ""
#property version   "1.01"

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

// Indicator handles
int handle_ema20, handle_ema50, handle_rsi, handle_atr, handle_bb;
bool trade_open = false;
double entry_price = 0.0;
double stop_loss = 0.0;
double take_profit = 0.0;
int trade_direction = 0; // 1 for sell, 2 for buy
int reentry_wait_counter = 0; // Count how many candles passed for re-entry

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

   Print("EA initialized successfully");
   return INIT_SUCCEEDED;
  }
  
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   Print("EA deinitialized, reason: ", reason);
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   // Arrays to hold the indicator data
   double ema20[], ema50[], rsi[], atr[], bb_upper[], bb_middle[], bb_lower[];

   // Copy indicator values into arrays
   if (CopyBuffer(handle_ema20, 0, 0, 1, ema20) <= 0 ||
       CopyBuffer(handle_ema50, 0, 0, 1, ema50) <= 0 ||
       CopyBuffer(handle_rsi, 0, 0, 1, rsi) <= 0 ||
       CopyBuffer(handle_atr, 0, 0, 1, atr) <= 0 ||
       CopyBuffer(handle_bb, 1, 0, 1, bb_upper) <= 0 ||
       CopyBuffer(handle_bb, 2, 0, 1, bb_lower) <= 0 ||
       CopyBuffer(handle_bb, 0, 0, 1, bb_middle) <= 0)
     {
      Print("Error retrieving indicator data");
      return;
     }

   // Get the current and previous values of the indicators
   double current_ema20 = ema20[0];
   double current_ema50 = ema50[0];
   double current_rsi = rsi[0];
   double current_atr = atr[0]; // Correct usage of ATR
   double current_bb_upper = bb_upper[0];
   double current_bb_middle = bb_middle[0];
   double current_bb_lower = bb_lower[0];

   // Get the current close, high, and low prices
   double close_price = iClose(_Symbol, _Period, 1);
   double low_price = iLow(_Symbol, _Period, 1);
   double high_price = iHigh(_Symbol, _Period, 1);

   // Determine if a trade should be opened (initial signal)
   int signal = 0;
   if ((close_price < current_bb_lower || low_price < current_bb_lower) && close_price < current_ema20 && close_price < current_ema50)
     {
      signal = 2; // Buy signal
      reentry_wait_counter = 0; // Reset the re-entry wait counter
     }
   else if ((close_price > current_bb_upper || high_price > current_bb_upper) && close_price > current_ema20 && close_price > current_ema50)
     {
      signal = 1; // Sell signal
      reentry_wait_counter = 0; // Reset the re-entry wait counter
     }

   // Manage re-entry conditions
   if (signal > 0 && reentry_wait_counter < reentry_candle_limit)
     {
      reentry_wait_counter++;
      if ((signal == 2 && close_price > current_bb_lower && close_price < current_bb_middle) || (signal == 1 && close_price < current_bb_upper && close_price > current_bb_middle))
        {
         OpenTrade(signal, current_atr, current_bb_upper, current_bb_middle, current_bb_lower); // Pass current_atr
        }
     }
   else if (reentry_wait_counter >= reentry_candle_limit)
     {
      signal = 0;
      reentry_wait_counter = 0;
     }

   // Manage open trades and adjust SL based on Fibonacci levels
   if (trade_open)
     {
      AdjustStopLossAndTakeProfit(close_price, current_ema20, current_bb_upper, current_bb_lower);
     }
  }

//+------------------------------------------------------------------+
//| Execute trade                                                     |
//+------------------------------------------------------------------+
void OpenTrade(int direction, double current_atr, double current_bb_upper, double current_bb_middle, double current_bb_lower)
  {
   MqlTradeRequest request;
   MqlTradeResult result;
   ZeroMemory(request);

   if (!trade_open)
     {
      double stop_loss_distance;
      double lot_size;

      if (direction == 2) // Buy
        {
         entry_price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         stop_loss = entry_price - (current_atr * atr_multiplier);
         take_profit = current_bb_upper;
         stop_loss_distance = entry_price - stop_loss;
         trade_direction = 2;
        }
      else if (direction == 1) // Sell
        {
         entry_price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         stop_loss = entry_price + (current_atr * atr_multiplier);
         take_profit = current_bb_lower;
         stop_loss_distance = stop_loss - entry_price;
         trade_direction = 1;
        }

      // Calculate lot size based on risk percentage and stop loss distance
      lot_size = CalculateLotSize(stop_loss_distance, direction == 2);

      // Populate the trade request
      request.action = TRADE_ACTION_DEAL;
      request.symbol = _Symbol;
      request.volume = lot_size;
      request.price = entry_price;
      request.sl = stop_loss;
      request.tp = take_profit;
      request.type = (direction == 2) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      request.deviation = 3;

      // Send the trade request
      if (OrderSend(request, result))
        {
         trade_open = true;
         Print("Trade opened: ", (direction == 2 ? "Buy" : "Sell"), " at ", entry_price, " with lot size ", lot_size);
        }
     }
  }

//+------------------------------------------------------------------+
//| Adjust Stop Loss and Take Profit based on Fibonacci Levels        |
//+------------------------------------------------------------------+
void AdjustStopLossAndTakeProfit(double close_price, double ema20, double bb_upper, double bb_lower)
  {
   double fib_levels[] = {0.236, 0.382, 0.5, 0.618};

   if (trade_direction == 2) // Buy trade
     {
      if (close_price >= ema20)
        stop_loss = MathMax(stop_loss, ema20);

      for (int i = 0; i < ArraySize(fib_levels); i++)
        {
         double fib_target = ema20 + fib_levels[i] * (bb_upper - ema20);
         if (close_price >= fib_target)
            stop_loss = MathMax(stop_loss, fib_target);
        }
     }
   else if (trade_direction == 1) // Sell trade
     {
      if (close_price <= ema20)
        stop_loss = MathMin(stop_loss, ema20);

      for (int i = 0; i < ArraySize(fib_levels); i++)
        {
         double fib_target = ema20 - fib_levels[i] * (ema20 - bb_lower);
         if (close_price <= fib_target)
            stop_loss = MathMin(stop_loss, fib_target);
        }
     }

   if (close_price <= stop_loss || close_price >= take_profit)
     {
      if (PositionSelect(_Symbol))
        {
         double volume = PositionGetDouble(POSITION_VOLUME);
         double price = (trade_direction == 2) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);

         MqlTradeRequest request;
         MqlTradeResult result;
         ZeroMemory(request);

         request.action = TRADE_ACTION_DEAL;
         request.symbol = _Symbol;
         request.volume = volume;
         request.price = price;
         request.deviation = 3;
         request.type = (trade_direction == 2) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;

         if (OrderSend(request, result))
            trade_open = false;
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
