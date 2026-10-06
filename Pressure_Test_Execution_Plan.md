# RejuvMe Pressure Test Execution Plan

_Last updated: October 6, 2026_

## Objective

Execute the first launch-readiness pressure test round for RejuvMe using the same scope as the current `k6` runner.

Execution target:
- **9 total cases**
- **3 groups**: `baseline`, `load`, `spike`
- **3 endpoints** in every group:
  - `/api/app/init`
  - `/api/daily-boost/me`
  - `/api/search`

---

## Environment

Use **staging** or **pre-production**.

Before running:
- backend must be deployed and reachable
- valid test access token must be available
- test data must exist for app init, daily boost, and search
- CloudWatch / ECS / RDS dashboards should be open

Avoid:
- production for the first round
- high-volume real OTP/SMS/email/provider traffic

---

## Metrics to capture

For every case, capture:
- avg latency
- p95 latency
- p99 latency
- error rate
- checks pass rate
- iterations / request volume

At the infrastructure level, watch:
- ECS CPU
- ECS memory
- ECS task health / restarts
- RDS CPU
- RDS connections
- RDS top SQL / slow queries
- cache health if available

---

## Success criteria

A case passes if:
- error rate `< 1%`
- `/api/app/init` p95 `< 1200 ms`
- `/api/daily-boost/me` p95 `< 700 ms`
- `/api/search` p95 `< 700 ms`

A run is considered healthy overall if:
- most or all cases pass
- ECS stays healthy
- RDS does not approach exhaustion
- no major timeout or 5xx burst appears

---

## Stop conditions

Stop early if:
- repeated 5xx spikes appear
- timeouts surge
- ECS tasks restart or go unhealthy
- RDS connections approach limit
- the shared environment becomes unstable

---

## 9-case execution matrix

## Baseline group
1. `Baseline-AppInit`
2. `Baseline-DailyBoost`
3. `Baseline-Search`

## Load group
4. `Load-AppInit`
5. `Load-DailyBoost`
6. `Load-Search`

## Spike group
7. `Spike-AppInit`
8. `Spike-DailyBoost`
9. `Spike-Search`

---

## Intended concurrency profile

## Baseline
- light staged run
- intended as low-load reference

## Load
- normal launch-load simulation
- intended to validate 100-user behavior and moderate headroom

## Spike
- burst simulation
- intended to validate sudden jumps toward 100–200 users

The exact staged values are defined in:
- `pressure-testing/k6/config.js`

---

## Recommended execution order

Run in this order:
1. Baseline-AppInit
2. Baseline-DailyBoost
3. Baseline-Search
4. Load-AppInit
5. Load-DailyBoost
6. Load-Search
7. Spike-AppInit
8. Spike-DailyBoost
9. Spike-Search
10. Review results and AWS metrics

---

## Per-endpoint notes

## `/api/app/init`
Watch most closely:
- p95 / p99
- ECS CPU
- RDS connections
- top SQL

## `/api/daily-boost/me`
Watch most closely:
- p95
- DB query behavior
- cache effectiveness

## `/api/search`
Watch most closely:
- p95
- repeated query behavior
- result-path stability under load

Recommended search coverage:
- one common keyword
- one niche keyword
- one no-result keyword

---

## Output artifacts

The current runner writes output into:
- `pressure-testing/reports/run-<timestamp>/`

Generated artifacts include:
- `pressure-test-report.md`
- `pressure-test-report.html`
- per-case `summary.json`
- per-case stdout/stderr logs

---

## Current runner

The current executable runner is:
- `pressure-testing/k6/run-all-9-tests.ps1`

That script is the source of truth for the actual automated execution order and report structure.
