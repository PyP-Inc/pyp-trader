# PyP Trader

> Plug-and-play MT4/MT5 Expert Advisor powered by PyP AI signals.

## Setup

1. Download the EA for your platform:
   - **MT4** → `mt4/PyP_EA.mq4`
   - **MT5** → `mt5/PyP_EA.mq5`

2. Open MetaEditor (F4 in MetaTrader), open the file, hit **F7** to compile.

3. Attach the compiled EA to any chart and set:
   - `EAToken` — your token from the [PyP dashboard](https://pyp.stanlink.online)
   - `LotSize` — your preferred lot size

4. Allow WebRequests for `https://api.pyp.stanlink.online` in  
   **Tools → Options → Expert Advisors**.

That's it. PyP handles the analysis — your EA handles the trades.

## How it works

The EA polls PyP every 5 seconds for new signals on your deployment. When a BUY or SELL signal arrives, it executes a market order instantly. HOLD signals are ignored.

## Security

Your EA token is unique to your account. Never share it. You can regenerate it anytime from your dashboard.
