# Changelog

## 2026-03-07

### Added

- Added `DayTradingEA_v2.mq5` as the primary clean rewrite of the strategy.
- Added broker-synced position handling, session filtering, spread filtering, RSI gating, re-entry state management, and drawdown circuit breakers in the v2 EA.
- Added `CHANGELOG.md` for repository-level change tracking.

### Changed

- Reworked `audit.md` into a verified audit focused on confirmed defects and defensible recommendations.
- Corrected `DayTradingEA_v2.mq5` time handling to use resolved server time via `TimeToStruct(...)`.
- Hardened volume normalization in `DayTradingEA_v2.mq5` so lot sizing is aligned to broker min/max/step constraints more safely.
- Updated `Black_Box.mq5` with corrected Bollinger buffer mapping, broker-magic filtering, re-entry state handling, slippage configuration, and safer lot-size guards.
- Updated `TestEA.mq5` with closed-candle indicator reads, RSI filter usage, broker-side position modification, spread filtering, handle cleanup, and `CTrade`-based execution.

### Documentation

- Rewrote `README.md` to reflect the actual current repository structure and recommended EA.
- Documented `DayTradingEA_v2.mq5` as the preferred implementation and marked the older EAs as reference material.
- Added clearer validation guidance and risk disclaimers.
