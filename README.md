# <img src="./docs/assets/pyp-logo.png" alt="PyP" width="180" />

# PyP Trader

Official MT4/MT5 Expert Advisors for the PyP trading platform.

This repository gives you two ways to run PyP live:

- the easy path: download the latest prebuilt EA release and a `.set` preset from your PyP dashboard
- the advanced path: open the source in MetaEditor and compile it yourself

## What PyP Trader does

PyP Trader connects your MetaTrader terminal to PyP live signals.

The EA:

- polls PyP for new signals on your configured deployment
- receives the exact pair, confidence, and execution payload for that deployment
- opens trades when a new `BUY` or `SELL` signal arrives
- ignores stale signals after restart
- can filter to the chart symbol
- uses your deployment-specific runtime settings from PyP

## Recommended Setup

This is the flow non-technical users should use.

### 1. Get the EA from the latest GitHub release

Download the latest prebuilt files here:

- [Latest Release](https://github.com/PyP-Inc/pyp-trader/releases/latest)

From the release, use:

- `PyP_EA.ex4` for MT4
- `PyP_EA.ex5` for MT5

### 2. Configure the strategy in the PyP dashboard

In PyP:

1. subscribe to the strategy or open your live deployment
2. configure your execution settings
3. connect an MT4 or MT5 integration
4. open the subscription/deployment setup page
5. download the generated `.set` preset for MT4 or MT5

Download your `.set` preset from your PyP subscription area here:

- [https://pyp.stanlink.online/subscriptions/strategies](https://pyp.stanlink.online/subscriptions/strategies)

The preset includes the values the EA actually needs, including:

- your EA token
- deployment ID
- API URL
- default lot size input
- chart-symbol filtering

### 3. Install the EA in MetaTrader

1. copy `PyP_EA.ex4` or `PyP_EA.ex5` into your terminal's `Experts` folder
2. restart MetaTrader
3. attach the EA to the chart you want to trade
4. load the `.set` file you downloaded from PyP
5. enable Algo Trading / AutoTrading

### 4. Allow the PyP API URL

In MetaTrader:

- `Tools -> Options -> Expert Advisors`

Add this URL to allowed WebRequests:

- `https://api.pyp.stanlink.online`

## Dashboard Preset Flow

The `.set` file is the preferred setup method.

Why:

- no need to manually copy long tokens
- no need to guess the deployment ID
- fewer setup mistakes
- matches the exact subscription or deployment the user configured in PyP

For marketplace subscriptions, the preset is generated from the saved subscription runtime settings.

For owned deployments, the same principle applies: the EA should be tied to the exact deployment the user wants to run.

## Manual Setup

If you do not use the `.set` file, the main EA inputs are:

- `EAToken`
- `DeploymentId`
- `ApiUrl`
- `LotSize`
- `MagicNumber`
- `Slippage`
- `EnableTrading`
- `TradeOnlyChartSymbol`

Typical values:

- `ApiUrl = https://api.pyp.stanlink.online`
- `TradeOnlyChartSymbol = true`

## Build From Source

This is the advanced path for technical users.

### MT4

1. open `mt4/PyP_EA.mq4` in MetaEditor
2. press `F7` to compile
3. the output will be `PyP_EA.ex4`

### MT5

1. open `mt5/PyP_EA.mq5` in MetaEditor
2. press `F7` to compile
3. the output will be `PyP_EA.ex5`

## Repository Layout

- [`mt4/PyP_EA.mq4`](./mt4/PyP_EA.mq4)
- [`mt5/PyP_EA.mq5`](./mt5/PyP_EA.mq5)
- [`docs/assets/pyp-logo.png`](./docs/assets/pyp-logo.png)

## Release Process

This repository publishes release artifacts through GitHub Actions when a tag is pushed:

- `.github/workflows/release.yml`

The release should attach:

- `PyP_EA.ex4`
- `PyP_EA.ex5`

Users who do not want to compile should use the latest release page instead of the source files.

## Security

Your EA token is sensitive.

Do not share:

- EA tokens
- `.set` files that contain active tokens
- screenshots showing the full token

If needed, revoke and regenerate the token from your PyP dashboard.

## Troubleshooting

### `API returned HTTP 404`

Usually means:

- wrong deployment ID
- token does not have access to that deployment

### `retcode=10030`

Usually means:

- the broker rejected the requested filling mode

Use the latest EA build, which selects a broker-supported filling mode automatically.

### Transport codes like `1001`, `1003`, `1009`

These are terminal-side transport/request issues, not normal PyP app HTTP statuses.

Use the latest EA build and verify:

- `ApiUrl`
- allowed WebRequest URL
- stable network access from the terminal

## Platform

PyP dashboard:

- [https://pyp.stanlink.online](https://pyp.stanlink.online)

Latest releases:

- [https://github.com/PyP-Inc/pyp-trader/releases/latest](https://github.com/PyP-Inc/pyp-trader/releases/latest)
