//+------------------------------------------------------------------+
//|                                            DayTradingEA_v2.mq5   |
//|                                                    Bongo Seakhoa |
//|          Clean rewrite from strategy spec - broker-synced core   |
//+------------------------------------------------------------------+
#property copyright "Bongo Seakhoa"
#property link      ""
#property version   "2.00"
#property strict

#include <Trade\Trade.mqh>

//+------------------------------------------------------------------+
//| Input parameters                                                  |
//+------------------------------------------------------------------+

// Strategy parameters
input int    inp_bb_period       = 20;          // Bollinger Bands period
input double inp_bb_deviation    = 2.0;         // Bollinger Bands deviation
input int    inp_ema_period      = 20;          // EMA period
input int    inp_rsi_period      = 14;          // RSI period
input int    inp_atr_period      = 14;          // ATR period
input double inp_atr_multiplier  = 2.0;         // ATR multiplier for SL

// Risk management
input double inp_risk_perc       = 2.0;         // Risk % per trade (of equity)
input double inp_min_lot_size    = 0.01;        // Minimum lot size
input double inp_max_daily_dd    = 3.0;         // Max daily drawdown % before stop
input double inp_max_total_dd    = 10.0;        // Max total drawdown % from peak

// Execution filters
input int    inp_magic_number    = 202603;      // Magic number
input int    inp_max_spread      = 30;          // Max spread in points
input int    inp_slippage        = 10;          // Max slippage in points
input int    inp_reentry_limit   = 2;           // Max candles to wait for re-entry

// Session filter (server time hours, 0-23)
input int    inp_session_start   = 7;           // Trading session start hour (server time)
input int    inp_session_end     = 20;          // Trading session end hour (server time)
input bool   inp_friday_cutoff   = true;        // Close early on Friday (20:00)

// RSI thresholds
input double inp_rsi_buy_max     = 40.0;        // RSI must be below this for buy
input double inp_rsi_sell_min    = 60.0;        // RSI must be above this for sell

//+------------------------------------------------------------------+
//| Global objects                                                    |
//+------------------------------------------------------------------+
CTrade trade;

// Indicator handles
int h_bb, h_ema, h_rsi, h_atr;

// Re-entry state machine
bool   g_pending_reentry       = false;
bool   g_pending_is_buy        = false;
int    g_pending_candles_left  = 0;
double g_pending_bb_upper      = 0;
double g_pending_bb_middle     = 0;
double g_pending_bb_lower      = 0;

// Drawdown tracking
double g_daily_start_equity    = 0;
double g_peak_equity           = 0;
bool   g_daily_dd_breached     = false;
bool   g_total_dd_breached     = false;
int    g_last_dd_check_day     = -1;

//+------------------------------------------------------------------+
//| Initialization                                                    |
//+------------------------------------------------------------------+
int OnInit()
{
    h_bb  = iBands(_Symbol, _Period, inp_bb_period, 0, inp_bb_deviation, PRICE_CLOSE);
    h_ema = iMA(_Symbol, _Period, inp_ema_period, 0, MODE_EMA, PRICE_CLOSE);
    h_rsi = iRSI(_Symbol, _Period, inp_rsi_period, PRICE_CLOSE);
    h_atr = iATR(_Symbol, _Period, inp_atr_period);

    if(h_bb == INVALID_HANDLE || h_ema == INVALID_HANDLE ||
       h_rsi == INVALID_HANDLE || h_atr == INVALID_HANDLE)
    {
        Print("Error: Failed to create indicator handles");
        return INIT_FAILED;
    }

    trade.SetExpertMagicNumber(inp_magic_number);
    trade.SetDeviationInPoints(inp_slippage);

    g_daily_start_equity = AccountInfoDouble(ACCOUNT_EQUITY);
    g_peak_equity        = AccountInfoDouble(ACCOUNT_EQUITY);

    Print("DayTradingEA v2.00 initialized on ", _Symbol, " ", EnumToString(_Period));
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Deinitialization                                                   |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    if(h_bb  != INVALID_HANDLE) IndicatorRelease(h_bb);
    if(h_ema != INVALID_HANDLE) IndicatorRelease(h_ema);
    if(h_rsi != INVALID_HANDLE) IndicatorRelease(h_rsi);
    if(h_atr != INVALID_HANDLE) IndicatorRelease(h_atr);
    Print("DayTradingEA v2.00 deinitialized, reason: ", reason);
}

//+------------------------------------------------------------------+
//| New candle detection                                               |
//+------------------------------------------------------------------+
bool IsNewCandle()
{
    static int s_last_bars = 0;
    int bars = iBars(_Symbol, _Period);
    if(bars != s_last_bars)
    {
        s_last_bars = bars;
        return true;
    }
    return false;
}

//+------------------------------------------------------------------+
//| Find our position by magic number                                  |
//+------------------------------------------------------------------+
bool SelectOwnPosition()
{
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket > 0 &&
           PositionGetString(POSITION_SYMBOL) == _Symbol &&
           PositionGetInteger(POSITION_MAGIC) == inp_magic_number)
        {
            return true;
        }
    }
    return false;
}

//+------------------------------------------------------------------+
//| Read server time into MqlDateTime                                 |
//+------------------------------------------------------------------+
bool GetServerDateTime(MqlDateTime &dt)
{
    datetime server_time = TimeTradeServer();
    if(server_time <= 0)
        server_time = TimeCurrent();

    if(server_time <= 0 || !TimeToStruct(server_time, dt))
    {
        Print("Error: failed to resolve server time");
        return false;
    }

    return true;
}

//+------------------------------------------------------------------+
//| Session filter                                                     |
//+------------------------------------------------------------------+
bool IsWithinTradingHours()
{
    MqlDateTime dt;
    if(!GetServerDateTime(dt))
        return false;

    if(inp_friday_cutoff && dt.day_of_week == 5 && dt.hour >= 20)
        return false;

    if(dt.day_of_week == 0 || dt.day_of_week == 6)
        return false;

    if(inp_session_start <= inp_session_end)
        return (dt.hour >= inp_session_start && dt.hour < inp_session_end);
    else
        return (dt.hour >= inp_session_start || dt.hour < inp_session_end);
}

//+------------------------------------------------------------------+
//| Spread filter                                                      |
//+------------------------------------------------------------------+
bool IsSpreadAcceptable()
{
    int spread = (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
    if(spread > inp_max_spread)
    {
        Print("Spread too wide: ", spread, " > ", inp_max_spread);
        return false;
    }
    return true;
}

//+------------------------------------------------------------------+
//| Drawdown circuit breaker                                           |
//+------------------------------------------------------------------+
bool CheckDrawdownLimits()
{
    double equity = AccountInfoDouble(ACCOUNT_EQUITY);

    // Reset daily tracking on new day
    MqlDateTime dt;
    if(!GetServerDateTime(dt))
        return false;
    if(dt.day != g_last_dd_check_day)
    {
        g_last_dd_check_day  = dt.day;
        g_daily_start_equity = equity;
        g_daily_dd_breached  = false;
    }

    // Update peak equity
    if(equity > g_peak_equity)
        g_peak_equity = equity;

    // Daily drawdown check
    if(g_daily_start_equity > 0)
    {
        double daily_dd = (g_daily_start_equity - equity) / g_daily_start_equity * 100.0;
        if(daily_dd >= inp_max_daily_dd)
        {
            if(!g_daily_dd_breached)
                Print("Daily drawdown limit reached: ", DoubleToString(daily_dd, 2), "%");
            g_daily_dd_breached = true;
            return false;
        }
    }

    // Total drawdown check
    if(g_peak_equity > 0)
    {
        double total_dd = (g_peak_equity - equity) / g_peak_equity * 100.0;
        if(total_dd >= inp_max_total_dd)
        {
            if(!g_total_dd_breached)
                Print("Total drawdown limit reached: ", DoubleToString(total_dd, 2), "%");
            g_total_dd_breached = true;
            return false;
        }
    }

    g_total_dd_breached = false;
    return true;
}

//+------------------------------------------------------------------+
//| Resolve the supported lot precision from the broker step          |
//+------------------------------------------------------------------+
int VolumeDigits(double step)
{
    int digits = 0;
    double scaled = step;

    while(digits < 8 && MathAbs(scaled - MathRound(scaled)) > 1e-8)
    {
        scaled *= 10.0;
        digits++;
    }

    return digits;
}

//+------------------------------------------------------------------+
//| Clamp and align volume to broker limits                           |
//+------------------------------------------------------------------+
double NormalizeVolume(double lots)
{
    double vol_min  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double vol_max  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    double vol_step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    double effective_min = MathMax(inp_min_lot_size, vol_min);

    if(effective_min > vol_max)
    {
        Print("Error: effective minimum volume exceeds broker maximum");
        return 0.0;
    }

    if(vol_step <= 0)
        return MathMin(MathMax(lots, effective_min), vol_max);

    double stepped_min = MathCeil(effective_min / vol_step) * vol_step;
    if(stepped_min > vol_max)
    {
        Print("Error: stepped minimum volume exceeds broker maximum");
        return 0.0;
    }

    lots = MathMin(lots, vol_max);
    lots = MathMax(lots, stepped_min);
    lots = MathFloor((lots + 1e-12) / vol_step) * vol_step;

    if(lots < stepped_min)
        lots = stepped_min;

    lots = MathMin(lots, vol_max);
    return NormalizeDouble(lots, VolumeDigits(vol_step));
}

//+------------------------------------------------------------------+
//| Read indicator values from last closed candle                      |
//+------------------------------------------------------------------+
bool ReadIndicators(double &bb_upper, double &bb_middle, double &bb_lower,
                    double &ema_val, double &rsi_val, double &atr_val)
{
    double buf_mid[1], buf_up[1], buf_lo[1], buf_ema[1], buf_rsi[1], buf_atr[1];

    if(CopyBuffer(h_bb,  0, 1, 1, buf_mid) <= 0 ||
       CopyBuffer(h_bb,  1, 1, 1, buf_up)  <= 0 ||
       CopyBuffer(h_bb,  2, 1, 1, buf_lo)  <= 0 ||
       CopyBuffer(h_ema, 0, 1, 1, buf_ema) <= 0 ||
       CopyBuffer(h_rsi, 0, 1, 1, buf_rsi) <= 0 ||
       CopyBuffer(h_atr, 0, 1, 1, buf_atr) <= 0)
    {
        Print("Error reading indicator buffers");
        return false;
    }

    bb_middle = buf_mid[0];
    bb_upper  = buf_up[0];
    bb_lower  = buf_lo[0];
    ema_val   = buf_ema[0];
    rsi_val   = buf_rsi[0];
    atr_val   = buf_atr[0];
    return true;
}

//+------------------------------------------------------------------+
//| Calculate lot size with full validation                            |
//+------------------------------------------------------------------+
double CalculateLotSize(double sl_distance)
{
    if(sl_distance <= 0)
    {
        Print("Warning: SL distance <= 0, using minimum lot");
        return NormalizeVolume(inp_min_lot_size);
    }

    double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    if(tick_size <= 0)
    {
        Print("Warning: tick_size <= 0, using minimum lot");
        return NormalizeVolume(inp_min_lot_size);
    }

    double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double pip_value  = tick_value / tick_size;
    if(pip_value <= 0)
    {
        Print("Warning: pip_value <= 0, using minimum lot");
        return NormalizeVolume(inp_min_lot_size);
    }

    double equity   = AccountInfoDouble(ACCOUNT_EQUITY);
    double risk_amt = (inp_risk_perc / 100.0) * equity;
    double lots     = risk_amt / (sl_distance * pip_value);
    return NormalizeVolume(lots);
}

//+------------------------------------------------------------------+
//| Check bullish candlestick pattern on [i-1]                         |
//+------------------------------------------------------------------+
bool IsBullishPattern()
{
    double o1 = iOpen(_Symbol, _Period, 1);
    double c1 = iClose(_Symbol, _Period, 1);
    double h1 = iHigh(_Symbol, _Period, 1);
    double l1 = iLow(_Symbol, _Period, 1);

    double o2 = iOpen(_Symbol, _Period, 2);
    double c2 = iClose(_Symbol, _Period, 2);

    double body  = MathAbs(c1 - o1);
    double range = h1 - l1;
    if(range <= 0) return false;

    double upper_wick = h1 - MathMax(c1, o1);
    double lower_wick = MathMin(c1, o1) - l1;

    // Hammer: long lower wick, small upper wick, meaningful body
    bool hammer = (lower_wick > 2.0 * body) &&
                  (upper_wick < 0.5 * body) &&
                  (body > range * 0.1);

    // Bullish engulfing: prev candle bearish, current candle bullish and engulfs
    bool engulfing = (c2 < o2) &&
                     (c1 > o1) &&
                     (c1 > o2) &&
                     (o1 < c2);

    return hammer || engulfing;
}

//+------------------------------------------------------------------+
//| Check bearish candlestick pattern on [i-1]                         |
//+------------------------------------------------------------------+
bool IsBearishPattern()
{
    double o1 = iOpen(_Symbol, _Period, 1);
    double c1 = iClose(_Symbol, _Period, 1);
    double h1 = iHigh(_Symbol, _Period, 1);
    double l1 = iLow(_Symbol, _Period, 1);

    double o2 = iOpen(_Symbol, _Period, 2);
    double c2 = iClose(_Symbol, _Period, 2);

    double body  = MathAbs(c1 - o1);
    double range = h1 - l1;
    if(range <= 0) return false;

    double upper_wick = h1 - MathMax(c1, o1);
    double lower_wick = MathMin(c1, o1) - l1;

    // Shooting star / hanging man: long upper wick, small lower wick, meaningful body
    bool shooting_star = (upper_wick > 2.0 * body) &&
                         (lower_wick < 0.5 * body) &&
                         (body > range * 0.1);

    // Bearish engulfing: prev candle bullish, current candle bearish and engulfs
    bool engulfing = (c2 > o2) &&
                     (c1 < o1) &&
                     (o1 > c2) &&
                     (c1 < o2);

    return shooting_star || engulfing;
}

//+------------------------------------------------------------------+
//| Generate signal: 0=none, 1=sell, 2=buy                             |
//+------------------------------------------------------------------+
int GenerateSignal(double bb_upper, double bb_middle, double bb_lower,
                   double ema_val, double rsi_val)
{
    double c2 = iClose(_Symbol, _Period, 2);
    double c3 = iClose(_Symbol, _Period, 3);
    double c4 = iClose(_Symbol, _Period, 4);
    double l2 = iLow(_Symbol, _Period, 2);
    double h2 = iHigh(_Symbol, _Period, 2);

    // --- Buy conditions ---
    bool bb_buy    = (c2 < bb_lower || l2 < bb_lower);
    bool ema_buy   = (c4 < ema_val && c3 < ema_val);
    bool trend_buy = (c4 > c3 && c3 > c2);
    bool rsi_buy   = (rsi_val < inp_rsi_buy_max);
    bool pat_buy   = IsBullishPattern();

    if(bb_buy && ema_buy && trend_buy && rsi_buy && pat_buy)
        return 2;

    // --- Sell conditions ---
    bool bb_sell    = (c2 > bb_upper || h2 > bb_upper);
    bool ema_sell   = (c4 > ema_val && c3 > ema_val);
    bool trend_sell = (c4 < c3 && c3 < c2);
    bool rsi_sell   = (rsi_val > inp_rsi_sell_min);
    bool pat_sell   = IsBearishPattern();

    if(bb_sell && ema_sell && trend_sell && rsi_sell && pat_sell)
        return 1;

    return 0;
}

//+------------------------------------------------------------------+
//| Execute a trade                                                    |
//+------------------------------------------------------------------+
bool ExecuteTrade(bool is_buy, double bb_upper, double bb_middle, double bb_lower,
                  double atr_val)
{
    if(SelectOwnPosition())
        return false;

    if(!IsSpreadAcceptable())
        return false;

    double price = is_buy ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                          : SymbolInfoDouble(_Symbol, SYMBOL_BID);

    // SL: ATR-based
    double sl = is_buy ? price - (atr_val * inp_atr_multiplier)
                       : price + (atr_val * inp_atr_multiplier);

    // TP: opposite Bollinger Band
    double tp = is_buy ? bb_upper : bb_lower;

    // Validate
    if(sl <= 0 || tp <= 0)
    {
        Print("Error: invalid SL(", sl, ") or TP(", tp, "), trade aborted");
        return false;
    }

    // Enforce minimum stop distance
    double min_stop = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
    double freeze   = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL) * _Point;
    double min_dist = MathMax(min_stop, freeze);

    if(is_buy)
    {
        if((price - sl) < min_dist)  sl = price - min_dist;
        if((tp - price) < min_dist)  tp = price + min_dist;
    }
    else
    {
        if((sl - price) < min_dist)  sl = price + min_dist;
        if((price - tp) < min_dist)  tp = price - min_dist;
    }

    sl = NormalizeDouble(sl, _Digits);
    tp = NormalizeDouble(tp, _Digits);

    double sl_dist = MathAbs(price - sl);
    double lots    = CalculateLotSize(sl_dist);
    if(lots <= 0)
    {
        Print("Trade aborted: calculated volume is invalid");
        return false;
    }

    bool ok;
    if(is_buy)
        ok = trade.Buy(lots, _Symbol, price, sl, tp, "v2 Buy");
    else
        ok = trade.Sell(lots, _Symbol, price, sl, tp, "v2 Sell");

    if(ok)
        Print(is_buy ? "BUY" : "SELL", " opened: price=", price,
              " SL=", sl, " TP=", tp, " lots=", lots);
    else
        Print("Trade failed: error ", GetLastError());

    return ok;
}

//+------------------------------------------------------------------+
//| Manage open position: Fibonacci trail + dynamic TP                 |
//+------------------------------------------------------------------+
void ManagePosition(double bb_upper, double bb_middle, double bb_lower, double ema_val)
{
    if(!SelectOwnPosition())
        return;

    double current_sl   = PositionGetDouble(POSITION_SL);
    double current_tp   = PositionGetDouble(POSITION_TP);
    double entry_price  = PositionGetDouble(POSITION_PRICE_OPEN);
    long   pos_type     = PositionGetInteger(POSITION_TYPE);
    ulong  ticket       = (ulong)PositionGetInteger(POSITION_TICKET);

    double close_prev = iClose(_Symbol, _Period, 1);

    double new_sl = current_sl;
    double new_tp = current_tp;
    bool   modified = false;

    double fib_levels[] = {0.236, 0.382, 0.5, 0.618};

    if(pos_type == POSITION_TYPE_BUY)
    {
        // Break-even: once price reaches 1:1 R:R, move SL to entry
        double sl_dist = entry_price - current_sl;
        if(sl_dist > 0 && close_prev >= entry_price + sl_dist)
        {
            double be_sl = entry_price + 2 * _Point;
            if(be_sl > new_sl)
            {
                new_sl   = be_sl;
                modified = true;
            }
        }

        // EMA trail
        if(close_prev >= ema_val && ema_val > new_sl)
        {
            new_sl   = ema_val;
            modified = true;
        }

        // Fibonacci trail using EMA to BB upper range
        for(int i = 0; i < ArraySize(fib_levels); i++)
        {
            double fib_target = ema_val + fib_levels[i] * (bb_upper - ema_val);
            if(close_prev >= fib_target && fib_target > new_sl)
            {
                new_sl   = fib_target;
                modified = true;
            }
        }

        // Expand TP if BB upper moved higher
        if(bb_upper > current_tp)
        {
            new_tp   = bb_upper;
            modified = true;
        }
    }
    else if(pos_type == POSITION_TYPE_SELL)
    {
        // Break-even
        double sl_dist = current_sl - entry_price;
        if(sl_dist > 0 && close_prev <= entry_price - sl_dist)
        {
            double be_sl = entry_price - 2 * _Point;
            if(be_sl < new_sl)
            {
                new_sl   = be_sl;
                modified = true;
            }
        }

        // EMA trail
        if(close_prev <= ema_val && ema_val < new_sl)
        {
            new_sl   = ema_val;
            modified = true;
        }

        // Fibonacci trail using EMA to BB lower range
        for(int i = 0; i < ArraySize(fib_levels); i++)
        {
            double fib_target = ema_val - fib_levels[i] * (ema_val - bb_lower);
            if(close_prev <= fib_target && fib_target < new_sl)
            {
                new_sl   = fib_target;
                modified = true;
            }
        }

        // Expand TP if BB lower moved lower
        if(bb_lower < current_tp)
        {
            new_tp   = bb_lower;
            modified = true;
        }
    }

    if(modified)
    {
        new_sl = NormalizeDouble(new_sl, _Digits);
        new_tp = NormalizeDouble(new_tp, _Digits);

        if(!trade.PositionModify(ticket, new_sl, new_tp))
            Print("Failed to modify position: error ", GetLastError());
        else
            Print("Position modified: SL=", new_sl, " TP=", new_tp);
    }
}

//+------------------------------------------------------------------+
//| Main tick handler                                                  |
//+------------------------------------------------------------------+
void OnTick()
{
    if(!IsNewCandle())
        return;

    // Read indicators
    double bb_upper, bb_middle, bb_lower, ema_val, rsi_val, atr_val;
    if(!ReadIndicators(bb_upper, bb_middle, bb_lower, ema_val, rsi_val, atr_val))
        return;

    bool has_position = SelectOwnPosition();

    // Chart display
    Comment(StringFormat(
        "DayTradingEA v2.00\n"
        "BB: %.5f / %.5f / %.5f\n"
        "EMA: %.5f | RSI: %.1f | ATR: %.5f\n"
        "Position: %s | Pending: %s\n"
        "Daily DD Breached: %s | Total DD Breached: %s",
        bb_upper, bb_middle, bb_lower,
        ema_val, rsi_val, atr_val,
        has_position ? "Yes" : "No",
        g_pending_reentry ? "Yes" : "No",
        g_daily_dd_breached ? "Yes" : "No",
        g_total_dd_breached ? "Yes" : "No"));

    // Manage existing position
    if(has_position)
    {
        ManagePosition(bb_upper, bb_middle, bb_lower, ema_val);
        return;
    }

    // Check drawdown limits before considering new entries
    if(!CheckDrawdownLimits())
        return;

    // Check session filter
    if(!IsWithinTradingHours())
        return;

    // Handle pending re-entry
    if(g_pending_reentry)
    {
        g_pending_candles_left--;
        double c1 = iClose(_Symbol, _Period, 1);

        bool reentry_ok = false;
        if(g_pending_is_buy)
            reentry_ok = (c1 > g_pending_bb_lower && c1 < g_pending_bb_middle);
        else
            reentry_ok = (c1 < g_pending_bb_upper && c1 > g_pending_bb_middle);

        if(reentry_ok)
        {
            ExecuteTrade(g_pending_is_buy, bb_upper, bb_middle, bb_lower, atr_val);
            g_pending_reentry = false;
        }
        else if(g_pending_candles_left <= 0)
        {
            Print("Re-entry expired");
            g_pending_reentry = false;
        }
        return;
    }

    // Generate new signal
    int signal = GenerateSignal(bb_upper, bb_middle, bb_lower, ema_val, rsi_val);
    if(signal == 0)
        return;

    bool is_buy = (signal == 2);
    double c2 = iClose(_Symbol, _Period, 2);

    // Check if price already re-entered BB range (immediate entry)
    bool immediate = false;
    if(is_buy)
        immediate = (c2 > bb_lower && c2 < bb_middle);
    else
        immediate = (c2 < bb_upper && c2 > bb_middle);

    if(immediate)
    {
        ExecuteTrade(is_buy, bb_upper, bb_middle, bb_lower, atr_val);
    }
    else
    {
        // Set pending re-entry state
        g_pending_reentry      = true;
        g_pending_is_buy       = is_buy;
        g_pending_candles_left = inp_reentry_limit;
        g_pending_bb_upper     = bb_upper;
        g_pending_bb_middle    = bb_middle;
        g_pending_bb_lower     = bb_lower;
        Print("Pending re-entry: ", is_buy ? "BUY" : "SELL",
              ", waiting up to ", inp_reentry_limit, " candles");
    }
}
//+------------------------------------------------------------------+
