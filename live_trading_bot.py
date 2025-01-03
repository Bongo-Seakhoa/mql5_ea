#!/usr/bin/env python3
"""
Comprehensive Trading Bot with the Full Notebook Logic + Live Trading
---------------------------------------------------------------------
1. Connect to MetaTrader5 and download H1 data.
2. Perform full feature engineering & advanced labeling (simulate_trades_with_atr).
3. Prepare data, do an 80/20 time-based split, train an XGBoost model (GridSearchCV).
4. Generate a signal for the LAST candle. If not older than 1 hour in UTC => Place trade.
5. Sleep ~10 minutes, repeat indefinitely.

Author: Bongo Seakhoa
Date: 2025-01-03
"""

import time
import warnings
warnings.filterwarnings('ignore')

# ========= 1) Imports & Initialization =========
import MetaTrader5 as mt5
import pandas as pd
import numpy as np
import ta
from datetime import datetime, timedelta
import pytz

# For concurrency in data fetching
from concurrent.futures import ThreadPoolExecutor

# For modeling
from sklearn.model_selection import TimeSeriesSplit, GridSearchCV
from sklearn.preprocessing import MinMaxScaler, StandardScaler
from sklearn.metrics import precision_score, recall_score, make_scorer, f1_score
import xgboost as xgb

# For optional visualization/backtesting
import matplotlib.pyplot as plt
import seaborn as sns

# ========== Connect to MT5 ==========
ACCOUNT_ID =
PASSWORD   =
SERVER     =

if not mt5.initialize():
    print("MetaTrader 5 initialization failed.")
    mt5.shutdown()
    quit()
else:
    print("Connected to MetaTrader 5 terminal successfully")

# Login
if mt5.login(login=ACCOUNT_ID, password=PASSWORD, server=SERVER):
    print(f"Connected to account #{ACCOUNT_ID}")
else:
    print("Failed to connect, error code:", mt5.last_error())
    mt5.shutdown()
    quit()

# ========== 2) Define Symbols & Retrieval =========
pairs       = ['EURUSD', 'GBPUSD', 'USDJPY', 'AUDUSD']
timeframe   = mt5.TIMEFRAME_H1
days_back   = 730
symbol_info_cache = {}

# -------- Spread & Contract Utils --------
def convert_spread(spread_points, currency_pair):
    """
    Convert integer spread points to decimal spread using symbol point value.
    """
    try:
        if currency_pair not in symbol_info_cache:
            symbol_info = mt5.symbol_info(currency_pair)
            if symbol_info is None or not symbol_info.visible:
                if not mt5.symbol_select(currency_pair, True):
                    print(f"Failed to select symbol {currency_pair}.")
                    return None
            symbol_info_cache[currency_pair] = symbol_info
        symbol_info = symbol_info_cache[currency_pair]
        return spread_points * symbol_info.point
    except Exception as e:
        print(f"Error converting spread for {currency_pair}: {e}")
        return None

def get_pip_value(pair):
    """
    Dynamically calculates the pip value for the given currency pair or instrument
    using MetaTrader 5's symbol information.
    """
    symbol_info = mt5.symbol_info(pair)
    if symbol_info is None:
        print(f"Symbol {pair} not found for pip value.")
        return None
    if not symbol_info.visible:
        if not mt5.symbol_select(pair, True):
            print(f"Failed to select symbol '{pair}' for pip value.")
            return None
    return symbol_info.trade_tick_value

def get_contract_size(pair):
    """
    Dynamically retrieves the contract size for the given currency pair or instrument
    using MetaTrader 5's symbol information.
    """
    symbol_info = mt5.symbol_info(pair)
    if symbol_info is None:
        print(f"Symbol {pair} not found for contract size.")
        return None
    if not symbol_info.visible:
        if not mt5.symbol_select(pair, True):
            print(f"Failed to select symbol '{pair}' for contract size.")
            return None
    return symbol_info.trade_contract_size

# -------- Data Download --------
def download_data(pair, timeframe=mt5.TIMEFRAME_H1, days_back=730*2):
    """
    Download historical data for a given currency pair, in UTC.
    """
    try:
        utc_tz    = pytz.timezone("UTC")
        date_to   = datetime.now(tz=utc_tz)
        date_from = date_to - timedelta(days=days_back)

        rates = mt5.copy_rates_range(pair, timeframe, date_from, date_to)
        if rates is None or len(rates) == 0:
            print(f"Failed to retrieve data for {pair}, error code:", mt5.last_error())
            return None

        df = pd.DataFrame(rates)
        df['time'] = pd.to_datetime(df['time'], unit='s', utc=True)
        df.set_index('time', inplace=True)
        return df
    except Exception as e:
        print(f"Error downloading data for {pair}: {e}")
        return None

# ========== 3) Feature Engineering =========
def calculate_adaptive_moving_average(df, period=10):
    multiplier = 2 / (period + 1)
    df['ama'] = df['close'].ewm(alpha=multiplier).mean()
    return df

def calculate_kalman_filter(df):
    n_iter = len(df)
    Q = 1e-5
    xhat = np.zeros(n_iter)
    P = np.zeros(n_iter)
    xhatminus = np.zeros(n_iter)
    Pminus = np.zeros(n_iter)
    K = np.zeros(n_iter)
    R = 0.1**2
    xhat[0] = df['close'][0]
    P[0] = 1.0
    for k in range(1, n_iter):
        xhatminus[k] = xhat[k - 1]
        Pminus[k] = P[k - 1] + Q
        K[k] = Pminus[k] / (Pminus[k] + R)
        xhat[k] = xhatminus[k] + K[k] * (df['close'][k] - xhatminus[k])
        P[k] = (1 - K[k]) * Pminus[k]
    df['kalman'] = xhat
    return df

def calculate_volatility_adjusted_rsi(df, period=14):
    delta = df['close'].diff()
    gain = delta.clip(lower=0)
    loss = -delta.clip(upper=0)
    avg_gain = gain.ewm(alpha=1 / period, adjust=False).mean()
    avg_loss = loss.ewm(alpha=1 / period, adjust=False).mean()
    rs = avg_gain / avg_loss
    rsi = 100 - (100 / (1 + rs))
    volatility = df['close'].rolling(window=period).std()
    df['vol_adjusted_rsi'] = rsi / volatility
    return df

def calculate_macd(df):
    df['macd'] = df['close'].ewm(span=12, adjust=False).mean() - df['close'].ewm(span=26, adjust=False).mean()
    df['macd_signal'] = df['macd'].ewm(span=9, adjust=False).mean()
    return df

def calculate_rsi(df, period=14):
    delta = df['close'].diff()
    gain = delta.clip(lower=0)
    loss = -delta.clip(upper=0)
    avg_gain = gain.rolling(window=period).mean()
    avg_loss = loss.rolling(window=period).mean()
    rs = avg_gain / avg_loss
    df['rsi'] = 100 - (100 / (1 + rs))
    return df

def calculate_adx(df, period=14):
    df['plus_dm'] = df['high'].diff()
    df['minus_dm'] = df['low'].diff().abs()
    df['plus_dm'] = np.where((df['plus_dm'] > df['minus_dm']) & (df['plus_dm'] > 0), df['plus_dm'], 0)
    df['minus_dm'] = np.where((df['minus_dm'] > df['plus_dm']) & (df['minus_dm'] > 0), df['minus_dm'], 0)
    tr = pd.concat([
        df['high'] - df['low'],
        (df['high'] - df['close'].shift()).abs(),
        (df['low'] - df['close'].shift()).abs()
    ], axis=1).max(axis=1)
    atr = tr.rolling(window=period).mean()
    df['plus_di'] = 100 * (df['plus_dm'].rolling(window=period).mean() / atr)
    df['minus_di'] = 100 * (df['minus_dm'].rolling(window=period).mean() / atr)
    df['dx'] = 100 * (np.abs(df['plus_di'] - df['minus_di']) / (df['plus_di'] + df['minus_di']))
    df['adx'] = df['dx'].rolling(window=period).mean()
    df.drop(['plus_dm', 'minus_dm', 'plus_di', 'minus_di', 'dx'], axis=1, inplace=True)
    return df

def calculate_cci(df, period=20):
    tp = (df['high'] + df['low'] + df['close']) / 3
    ma = tp.rolling(window=period).mean()
    md = tp.rolling(window=period).apply(lambda x: np.mean(np.abs(x - x.mean())))
    df['cci'] = (tp - ma) / (0.015 * md)
    return df

def calculate_stochastic_oscillator(df, k_period=14, d_period=3):
    df['lowest_low'] = df['low'].rolling(window=k_period).min()
    df['highest_high'] = df['high'].rolling(window=k_period).max()
    df['%K'] = 100 * ((df['close'] - df['lowest_low']) / (df['highest_high'] - df['lowest_low']))
    df['%D'] = df['%K'].rolling(window=d_period).mean()
    df.drop(['lowest_low', 'highest_high'], axis=1, inplace=True)
    return df

def calculate_williams_r(df, period=14):
    highest_high = df['high'].rolling(window=period).max()
    lowest_low  = df['low'].rolling(window=period).min()
    df['williams_r'] = -100 * ((highest_high - df['close']) / (highest_high - lowest_low))
    return df

def calculate_momentum(df, period=10):
    df['momentum'] = df['close'] - df['close'].shift(period)
    return df

def calculate_macd_histogram(df):
    df['macd_line'] = df['close'].ewm(span=12, adjust=False).mean() - df['close'].ewm(span=26, adjust=False).mean()
    df['macd_signal_line'] = df['macd_line'].ewm(span=9, adjust=False).mean()
    df['macd_hist'] = df['macd_line'] - df['macd_signal_line']
    df.drop(['macd_line', 'macd_signal_line'], axis=1, inplace=True)
    return df

def calculate_atr(df, period=14):
    df['high_low']  = df['high'] - df['low']
    df['high_close']= abs(df['high'] - df['close'].shift())
    df['low_close'] = abs(df['low'] - df['close'].shift())
    df['true_range']= df[['high_low','high_close','low_close']].max(axis=1)
    df['atr']       = df['true_range'].rolling(window=period).mean()
    df.drop(['high_low','high_close','low_close','true_range'], axis=1, inplace=True)
    return df

def calculate_vwap(df):
    df['vwap'] = (df['close'] * df['tick_volume']).cumsum() / df['tick_volume'].cumsum()
    return df

def calculate_price_action_features(df):
    df['open_close_distance'] = df['close'] - df['open']
    df['high_low_range']      = df['high'] - df['low']
    return df

def calculate_time_features(df):
    df['hour_of_day'] = df.index.hour
    df['day_of_week'] = df.index.dayofweek

    # Cyclical encoding
    df['hour_sin'] = np.sin(2 * np.pi * df['hour_of_day'] / 24)
    df['hour_cos'] = np.cos(2 * np.pi * df['hour_of_day'] / 24)
    df['day_sin']  = np.sin(2 * np.pi * df['day_of_week'] / 7)
    df['day_cos']  = np.cos(2 * np.pi * df['day_of_week'] / 7)

    return df.drop(['hour_of_day','day_of_week'], axis=1)

def normalize_features(df, features):
    scaler = MinMaxScaler(feature_range=(0,1))
    df[features] = scaler.fit_transform(df[features])
    return df

def calculate_support_resistance(df, days=30):
    candles_per_day = 24
    window = days * candles_per_day
    window = min(window, len(df))

    df['support'] = df['low'].rolling(window=window, min_periods=1).min()
    df['resistance'] = df['high'].rolling(window=window, min_periods=1).max()
    df['range'] = df['resistance'] - df['support']
    df['range'].replace(0, np.nan, inplace=True)
    df['position_in_range'] = (df['close'] - df['support']) / df['range']
    df['position_in_range'] = df['position_in_range'].clip(0,1)
    df.drop(['support','resistance','range'], axis=1, inplace=True)
    return df

def calculate_candlestick_patterns(df):
    # Bullish Engulfing
    df['bullish_engulfing'] = (
        (df['close'] > df['open']) &
        (df['close'].shift(1) < df['open'].shift(1)) &
        (df['close'] > df['open'].shift(1)) &
        (df['open'] < df['close'].shift(1))
    ).astype(int)

    # Bearish Engulfing
    df['bearish_engulfing'] = (
        (df['close'] < df['open']) &
        (df['close'].shift(1) > df['open'].shift(1)) &
        (df['open'] > df['close'].shift(1)) &
        (df['close'] < df['open'].shift(1))
    ).astype(int)

    # Hammer
    df['hammer'] = (
        (df['high'] - df['low'] > 3*(df['open'] - df['close'])) &
        ((df['close'] - df['low'])/(0.001 + df['high']-df['low'])>0.6) &
        ((df['open'] - df['low']) /(0.001 + df['high']-df['low'])>0.6)
    ).astype(int)

    # Shooting Star
    df['shooting_star'] = (
        (df['high'] - df['low'] > 3*(df['open'] - df['close'])) &
        ((df['high'] - df['close']) /(0.001 + df['high']-df['low'])>0.6) &
        ((df['high'] - df['open']) /(0.001 + df['high']-df['low'])>0.6)
    ).astype(int)

    # Doji
    df['doji'] = (
        abs(df['close'] - df['open']) <= (df['high'] - df['low'])*0.1
    ).astype(int)

    return df

# ========== 3B) Signal Labeling =========
def simulate_trades_with_atr(df, atr_period=14, sl_multiplier=1, tp_multiplier=2):
    """
    ATR-based label assignment:
    0 => Short 2x profit target hit first,
    1 => Both stop-losses triggered eventually,
    2 => Long 2x profit target hit first
    """
    if 'atr' not in df.columns:
        raise ValueError("ATR is required for this function. Please calculate it first.")

    labels = []
    time_to_resolution = []

    for i in range(len(df)):
        entry_price = df['close'].iloc[i]
        atr = df['atr'].iloc[i]
        spread = df['spread'].iloc[i]

        sl_long   = entry_price - (atr * sl_multiplier)
        tp_long   = entry_price + (atr * tp_multiplier) + spread
        sl_short  = entry_price + (atr * sl_multiplier)
        tp_short  = entry_price - (atr * tp_multiplier) - spread

        long_sl_hit  = False
        short_sl_hit = False
        duration     = 0

        for j in range(i+1, len(df)):
            high = df['high'].iloc[j]
            low  = df['low'].iloc[j]

            # check long TP
            if high >= tp_long:
                labels.append(2)
                duration = j - i
                break
            # check short TP
            if low <= tp_short:
                labels.append(0)
                duration = j - i
                break
            # check long SL
            if low <= sl_long and not long_sl_hit:
                long_sl_hit = True
            # check short SL
            if high >= sl_short and not short_sl_hit:
                short_sl_hit = True
            # both SL
            if long_sl_hit and short_sl_hit:
                labels.append(1)
                duration = j - i
                break

        if len(labels) <= i:
            labels.append(1)
            duration = len(df) - i

        time_to_resolution.append(duration)

    df['label']            = labels
    df['time_to_resolution']= time_to_resolution
    return df


# ========== 4) Data Preparation for Modeling =========
from sklearn.preprocessing import StandardScaler
from sklearn.feature_selection import SelectKBest, mutual_info_classif

def prepare_modeling_data(df, indicator_cols, max_lag=3, future_bars=5, atr_multiplier=2):
    """
    Prepare data for modeling, with lagged features and
    a second style of labeling:
      - label=2 if price rises >= atr_target,
      - label=0 if price falls >= atr_target,
      - label=1 otherwise
    """
    # Add lagged
    for col in indicator_cols:
        for lag in range(1, max_lag+1):
            df[f"{col}_lag{lag}"] = df[col].shift(lag)

    df['future_high'] = df['high'].rolling(window=future_bars).max().shift(-future_bars)
    df['future_low']  = df['low'].rolling(window=future_bars).min().shift(-future_bars)
    df['atr_target']  = df['atr'] * atr_multiplier

    df['label'] = 1  # default no-trade
    df.loc[(df['future_high'] - df['close'] >= df['atr_target']), 'label'] = 2
    df.loc[(df['close'] - df['future_low'] >= df['atr_target']), 'label'] = 0

    # drop rows if missing
    df.dropna(subset=indicator_cols + ['label'], inplace=True)

    # features
    feature_cols = indicator_cols + [f"{col}_lag{lag}" for col in indicator_cols for lag in range(1, max_lag+1)]
    X = df[feature_cols]
    y = df['label']

    scaler = StandardScaler()
    X_scaled = scaler.fit_transform(X)
    return X_scaled, y, feature_cols

# ========== 5) Model Training & Signal Generation =========
from sklearn.model_selection import TimeSeriesSplit, GridSearchCV
from sklearn.metrics import make_scorer, f1_score

def train_and_generate_signals(prepared_data, param_grid=None):
    """
    Train an XGBoost model for each pair with TimeSeriesSplit,
    then store signals & confidence in prepared_data.
    """
    if param_grid is None:
        param_grid = {
            'max_depth': [3, 5, 7],
            'n_estimators': [50, 100, 200],
            'learning_rate': [0.01, 0.1, 0.2],
            'subsample': [0.8, 1.0]
        }

    tscv = TimeSeriesSplit(n_splits=5)
    models = {}

    for pair, pdata in prepared_data.items():
        print(f"Training model for {pair}...")
        X, y = pdata['X'], pdata['y']

        # handle class imbalance
        class_counts = pd.Series(y).value_counts()
        scale_pos_weight = class_counts.min()/class_counts.max() if len(class_counts)>1 else 1

        xgb_model = xgb.XGBClassifier(
            objective='multi:softprob',
            eval_metric='mlogloss',
            use_label_encoder=False,
            scale_pos_weight=scale_pos_weight
        )

        grid_search = GridSearchCV(
            estimator=xgb_model,
            param_grid=param_grid,
            scoring=make_scorer(f1_score, average='macro'),
            cv=tscv,
            n_jobs=-1,
            verbose=1
        )
        grid_search.fit(X, y)

        best_model = grid_search.best_estimator_
        models[pair] = best_model

        # Generate signals
        predictions = best_model.predict(X)
        confidence  = best_model.predict_proba(X).max(axis=1)
        prepared_data[pair]['signals']   = predictions
        prepared_data[pair]['confidence']= confidence

    return models, prepared_data

def has_open_trade(symbol):
    positions = mt5.positions_get(symbol=symbol)
    return len(positions) > 0


# ========== 6) (Optional) Backtesting Utilities =========
def calculate_drawdown(equity_curve):
    peak = equity_curve[0]
    max_dd = 0
    drawdowns = []
    for val in equity_curve:
        if val>peak: peak=val
        dd = peak - val
        drawdowns.append(dd)
        if dd>max_dd: max_dd=dd
    return max_dd, drawdowns

def calculate_performance_metrics(trades, initial_balance):
    metrics = {
        'Total Trades': len(trades),
        'Winning Trades': len([t for t in trades if t['PnL']>0]),
        'Losing Trades': len([t for t in trades if t['PnL']<0]),
        'Win Rate': None,
        'Average Trade Duration': None,
        'Total PnL': None,
        'Max Drawdown': None,
        'Profit Factor': None,
        'Average PnL per Trade': None,
        'Balance': None,
    }
    if trades:
        total_pnl    = sum(t['PnL'] for t in trades)
        winning_pnl  = sum(t['PnL'] for t in trades if t['PnL']>0)
        losing_pnl   = sum(t['PnL'] for t in trades if t['PnL']<0)
        total_dur    = sum(t['Duration'] for t in trades)
        metrics.update({
            'Win Rate': metrics['Winning Trades']/metrics['Total Trades'],
            'Average Trade Duration': total_dur/metrics['Total Trades'],
            'Total PnL': total_pnl,
            'Profit Factor': abs(winning_pnl/losing_pnl) if losing_pnl!=0 else float('inf'),
            'Average PnL per Trade': total_pnl/metrics['Total Trades'],
            'Balance': initial_balance+total_pnl,
        })
    return metrics

def backtest_strategy(prepared_data, data_dict, initial_balance=1000, risk_per_trade=0.02, confidence_threshold=0.6):
    equity_curve = [initial_balance]
    all_trades = []
    detailed_metrics = {}

    for pair, pdata in prepared_data.items():
        print(f"Backtesting strategy for {pair}...")
        df = data_dict[pair].copy()
        df['signal']     = pdata['signals']
        df['confidence'] = pdata['confidence']

        balance = initial_balance
        trades  = []
        for i in range(len(df)):
            signal = df['signal'].iloc[i]
            conf   = df['confidence'].iloc[i]
            if signal==1 or conf<confidence_threshold:
                continue

            direction = 1 if signal==2 else -1
            entry_price= df['close'].iloc[i]
            atr        = df['atr'].iloc[i]
            stop_loss  = entry_price - direction*atr
            take_profit= entry_price + direction*2*atr

            trade_closed=False
            duration=0

            for j in range(i+1, len(df)):
                duration+=1
                high, low = df['high'].iloc[j], df['low'].iloc[j]
                if direction==1 and low<=stop_loss: # long SL
                    pnl = -risk_per_trade*balance
                    balance += pnl
                    trades.append({
                        'Entry Time': df.index[i],
                        'Exit Time' : df.index[j],
                        'Direction' : 'Long',
                        'Entry Price': entry_price,
                        'Exit Price' : stop_loss,
                        'PnL'       : pnl,
                        'Duration'  : duration
                    })
                    trade_closed=True
                    break
                elif direction==-1 and high>=stop_loss: # short SL
                    pnl = -risk_per_trade*balance
                    balance+=pnl
                    trades.append({
                        'Entry Time': df.index[i],
                        'Exit Time' : df.index[j],
                        'Direction' : 'Short',
                        'Entry Price': entry_price,
                        'Exit Price' : stop_loss,
                        'PnL'       : pnl,
                        'Duration'  : duration
                    })
                    trade_closed=True
                    break
                elif direction==1 and high>=take_profit: # long TP
                    pnl = risk_per_trade*balance*2
                    balance+=pnl
                    trades.append({
                        'Entry Time': df.index[i],
                        'Exit Time' : df.index[j],
                        'Direction' : 'Long',
                        'Entry Price': entry_price,
                        'Exit Price' : take_profit,
                        'PnL'       : pnl,
                        'Duration'  : duration
                    })
                    trade_closed=True
                    break
                elif direction==-1 and low<=take_profit: # short TP
                    pnl = risk_per_trade*balance*2
                    balance+=pnl
                    trades.append({
                        'Entry Time': df.index[i],
                        'Exit Time' : df.index[j],
                        'Direction' : 'Short',
                        'Entry Price': entry_price,
                        'Exit Price' : take_profit,
                        'PnL'       : pnl,
                        'Duration'  : duration
                    })
                    trade_closed=True
                    break

            if trade_closed:
                equity_curve.append(balance)

        all_trades.extend(trades)
        pair_metrics = calculate_performance_metrics(trades, initial_balance)
        max_dd, dd_arr= calculate_drawdown(equity_curve)
        pair_metrics['Max Drawdown'] = max_dd
        detailed_metrics[pair]=pair_metrics

    return equity_curve, detailed_metrics, all_trades


# ========== 7) Final Trading Loop =========
def place_trade(pair, label, confidence, df, confidence_threshold=0.6, risk_per_trade=0.01):
    """
    Place a live trade if label=0 or 2, confidence>=threshold.
    We do a naive 1*ATR SL, 2*ATR TP. 
    Adapt as needed. 
    """
    if has_open_trade(pair):
        print(f"{pair}: There's already an open position. Skipping new trade.")
        return


    if label not in [0, 2]:
        print(f"{pair}: label={label}, no trade action.")
        return

    if confidence<confidence_threshold:
        print(f"{pair}: Confidence {confidence:.2f} < {confidence_threshold}, no trade.")
        return

    # Buy or Sell
    direction_str = "BUY" if label==2 else "SELL"
    order_type    = mt5.ORDER_TYPE_BUY if label==2 else mt5.ORDER_TYPE_SELL

    last_close = df['close'].iloc[-1]
    atr        = df['atr'].iloc[-1] if 'atr' in df.columns else 0.001

    if label==2: # buy
        sl_price = last_close - atr
        tp_price = last_close + 2*atr
    else: # sell
        sl_price = last_close + atr
        tp_price = last_close - 2*atr

    # Basic lot sizing. E.g. risk = risk_per_trade * balance
    acc_info = mt5.account_info()
    if not acc_info:
        print(f"{pair}: No account info. Skip trade.")
        return
    balance = acc_info.balance
    risk_amount = balance * risk_per_trade

    # distance to SL
    distance_sl = abs(last_close - sl_price)
    sym_info    = mt5.symbol_info(pair)
    if not sym_info:
        print(f"{pair}: No symbol info found. Skip.")
        return
    tick_size   = sym_info.point
    if tick_size<=0:
        tick_size=0.00001
    pip_val     = get_pip_value(pair) or 1.0

    # naive formula
    sl_in_ticks = distance_sl / tick_size
    lot_size    = risk_amount / max(sl_in_ticks*pip_val, 1e-8)
    lot_size    = max(round(lot_size, 2), 0.01)

    digits = sym_info.digits
    sl_rounded = round(sl_price, digits)
    tp_rounded = round(tp_price, digits)
    price_rounded= round(last_close, digits)

    request = {
        "action": mt5.TRADE_ACTION_DEAL,
        "symbol": pair,
        "volume": lot_size,
        "type": order_type,
        "price": price_rounded,
        "sl": sl_rounded,
        "tp": tp_rounded,
        "deviation": 50,
        "magic": 234000,
        "comment": "Auto-Trade XGB",
        "type_time": mt5.ORDER_TIME_GTC,
        "type_filling": mt5.ORDER_FILLING_IOC,
    }
    result = mt5.order_send(request)
    if result.retcode==mt5.TRADE_RETCODE_DONE:
        print(f"{pair}: {direction_str} order placed. Label={label}, conf={confidence:.2f}, lot={lot_size}")
    else:
        print(f"{pair}: order failed. Retcode={result.retcode}, comment={result.comment}")

def time_split_80_20(X, y):
    """
    A simple time-based split: first 80% => train, last 20% => test.
    """
    n = len(X)
    split_idx = int(n*0.8)
    X_train, X_valid = X[:split_idx], X[split_idx:]
    y_train, y_valid = y[:split_idx], y[split_idx:]
    return X_train, y_train, X_valid, y_valid


def main_loop():
    """
    Infinite loop:
      1) For each symbol, download & process data fully,
      2) Check last candle staleness (<=1h),
      3) Feature engineering + labeling,
      4) prepare_modeling_data => (X,y),
      5) time-split => train an XGBoost => pick best model,
      6) Predict on the last candle => place trade,
      7) Sleep ~10 minutes => repeat
    """
    utc_now = lambda: datetime.now(tz=pytz.UTC)

    indicator_cols = [
        'rsi', 'adx', 'cci', '%K', '%D', 'williams_r', 'momentum',
        'macd', 'macd_signal', 'macd_hist', 'ama', 'kalman',
        'vol_adjusted_rsi', 'vwap', 'open_close_distance',
        'high_low_range', 'hour_sin', 'hour_cos', 'day_sin', 'day_cos',
        'position_in_range', 'bullish_engulfing', 'bearish_engulfing',
        'hammer', 'shooting_star', 'doji'
    ]

    while True:
        print("\n=============== New Cycle ===============")
        for pair in pairs:
            print(f"\n--- Processing {pair} ---")
            df_raw = download_data(pair, timeframe, days_back)
            if df_raw is None or len(df_raw)<300:
                print(f"{pair}: Not enough data.")
                continue

            # Convert spread
            df_raw['spread'] = df_raw['spread'].apply(lambda x: convert_spread(x, pair))

            # Check staleness of last bar
            last_ts = df_raw.index[-1]
            # Must be within 1 hour of current UTC
            if (utc_now()-last_ts)>timedelta(hours=1):
                print(f"{pair}: last bar older than 1hr, skip trading.")
                continue

            # ========== Apply all feature engineering from your notebook ==========
            df = df_raw.copy()
            df = calculate_adaptive_moving_average(df)
            df = calculate_kalman_filter(df)
            df = calculate_volatility_adjusted_rsi(df)
            df = calculate_macd(df)
            df = calculate_rsi(df)
            df = calculate_adx(df)
            df = calculate_cci(df)
            df = calculate_stochastic_oscillator(df)
            df = calculate_williams_r(df)
            df = calculate_momentum(df)
            df = calculate_macd_histogram(df)
            df = calculate_atr(df)
            df = calculate_vwap(df)
            df = calculate_price_action_features(df)
            df = calculate_time_features(df)
            df = calculate_support_resistance(df, days=30)
            df = calculate_candlestick_patterns(df)

            # Clip & normalize
            df['williams_r'] = df['williams_r'] * -1
            df['williams_r'] = df['williams_r'].clip(0, 100)
            df['cci']        = df['cci'].clip(-200,200)
            df['cci']        = (df['cci']+200)/400

            features_to_normalize = ['momentum','macd','macd_signal','macd_hist','ama','kalman','vol_adjusted_rsi']
            df.dropna(subset=features_to_normalize, inplace=True)
            df = normalize_features(df, features_to_normalize)

            # ========== Labeling with your advanced approach ==========

            # 1) Make sure 'atr' is in df (already from calculate_atr above).
            if 'atr' not in df.columns:
                df = calculate_atr(df, period=14)
            df = simulate_trades_with_atr(df, atr_period=14, sl_multiplier=1, tp_multiplier=2)

            # 2) Additional labeling approach for classification
            X_scaled, y, feat_cols = prepare_modeling_data(df, indicator_cols)

            if len(X_scaled)<50:
                print(f"{pair}: not enough data after prep.")
                continue

            # ========== 80/20 Time Split & Train ========== 
            X_train, y_train, X_valid, y_valid = time_split_80_20(X_scaled, y)
            if len(X_train)<20 or len(X_valid)<10:
                print(f"{pair}: Not enough train/valid data.")
                continue

            # Build a new XGBoost model
            param_grid = {
                'max_depth': [5,7,9,11],
                'n_estimators': [50,100,200],
                'learning_rate': [0.01,0.1,0.2],
                'subsample': [0.8,1.0]
            }
            xgb_model = xgb.XGBClassifier(objective='multi:softprob', eval_metric='mlogloss', use_label_encoder=False)
            # We'll do a simple TimeSeriesSplit on the training portion only
            # for hyperparameter selection:
            tscv = TimeSeriesSplit(n_splits=3)

            grid_search = GridSearchCV(
                estimator=xgb_model,
                param_grid=param_grid,
                scoring=make_scorer(f1_score, average='macro'),
                cv=tscv,
                n_jobs=-1,
                verbose=0
            )
            grid_search.fit(X_train, y_train)
            best_model = grid_search.best_estimator_
            print(f"{pair}: Best params => {grid_search.best_params_}, Score => {grid_search.best_score_:.4f}")

            # Evaluate on validation
            valid_preds = best_model.predict(X_valid)
            valid_f1    = f1_score(y_valid, valid_preds, average='macro')
            print(f"{pair}: Validation F1 => {valid_f1:.4f}")

            # ========== Predict on the LAST candle of df ========== 
            last_row = df.iloc[[-1]].copy()
            # Make sure it has the same columns as used for X
            for col in feat_cols:
                if col not in last_row.columns:
                    last_row[col]=np.nan

            if last_row[feat_cols].isnull().any(axis=None):
                print(f"{pair}: last row has NaN in features. No trade.")
                continue

            lastX = StandardScaler().fit_transform(df[feat_cols])  # careful: new scale or same scale
            # Actually, we used StandardScaler in prepare_modeling_data. But that was "fitted" to the entire df 
            # or a portion. For a quick hack, we can re-fit on full df then transform the last row. 
            # We'll do that approach here for demonstration:
            scaler = StandardScaler()
            allX   = scaler.fit_transform(df[feat_cols])
            lastX  = allX[-1:].copy()

            pred_label = best_model.predict(lastX)[0]
            pred_proba = best_model.predict_proba(lastX)
            confidence = float(pred_proba.max(axis=1)[0])

            print(f"{pair}: Last candle label={pred_label}, conf={confidence:.2f}")

            # ========== Place trade if valid ========== 
            place_trade(pair, pred_label, confidence, df, confidence_threshold=0.6, risk_per_trade=0.01)

        # Sleep ~10 minutes
        print("\nCycle done. Sleeping 10 minutes...\n")
        time.sleep(600)


if __name__=="__main__":
    try:
        main_loop()
    except KeyboardInterrupt:
        print("Bot stopped by user.")
    finally:
        mt5.shutdown()
