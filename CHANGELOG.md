# Changelog

## 0.2.1 — 3 October 2026

- Show Codex banked-reset arrivals as ticket markers in the 14-day usage history, with dates on hover.
- Reconcile duplicate live and historical observations of the same weekly reset, including already saved history.
- Center dotted reset markers between bars and align dates in hover cards.
- Keep the last known allowance visible after a failed refresh, with a stale-data indicator.
- Improve Prompting loading states and animate switching between Usage and Prompting, respecting Reduce Motion.
- Restore the olive palette while preserving scalar settings and backing up previous colors.

Bank arrivals use provider-reported grant IDs and dates. They do not indicate that a reset was used. Missing provider history remains unavailable.
