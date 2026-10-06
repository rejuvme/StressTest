# RejuvMe Pressure Testing Guide

_Last updated: October 6, 2026_

## Purpose

This guide explains the first pressure-testing round for RejuvMe before launch.

Target context:
- first-wave audience may include up to **5,000 potential users**
- first pressure-testing round focuses on the three highest-priority APIs:
  1. `/api/app/init`
  2. `/api/daily-boost/me`
  3. `/api/search`
- current execution model is a **9-case matrix**:
  - `baseline` × 3 endpoints
  - `load` × 3 endpoints
  - `spike` × 3 endpoints

---

## What pressure testing means

Pressure testing simulates many users hitting the backend at the same time and checks:
- response speed
- error rate
- ECS saturation
- RDS saturation
- cache behavior under load

This is different from functional QA.

- Functional QA asks: does the feature work?
- Pressure testing asks: does the system still work well under concurrency?

---

## Why RejuvMe should do this

RejuvMe depends on:
- authenticated API traffic
- ECS application servers
- RDS reads under personalization
- cache behavior on hot endpoints

The main launch risk is not only incorrect logic, but also:
- slow `/api/app/init`
- rising latency under concurrent app opens
- DB connection pressure
- cache misses causing DB fallback bursts
- timeouts or 5xx during spikes

---

## What 5,000 potential users means

5,000 potential users does **not** mean 5,000 concurrent users.

For the first round, use these planning assumptions:
- light peak: **50 concurrent users**
- normal peak: **100 concurrent users**
- safer target: **200 concurrent users**

The first-round objective is to confirm that the core APIs remain healthy at:
- **100 concurrent users** under load
- **200 concurrent users** under spike conditions

---

## APIs in scope

## `/api/app/init`
Why it matters:
- closest backend proxy to “user opens the app”
- likely the heaviest launch-critical endpoint

## `/api/daily-boost/me`
Why it matters:
- core personalized user feature
- likely to exercise plan/day aggregation logic

## `/api/search`
Why it matters:
- common user action
- high-frequency candidate during active browsing sessions

---

## Test types in scope

## Baseline
Purpose:
- establish low-load reference performance

Typical shape:
- 5 → 10 → 20 users
- short staged run

## Load
Purpose:
- simulate realistic launch traffic

Typical shape:
- 20 → 50 → 100 → 150 users
- longer staged run

## Spike
Purpose:
- simulate a sudden burst

Typical shape:
- start low
- jump quickly to 100 or 200 users
- hold briefly
- drop back down

---

## Current 9-case matrix

| Group | Endpoint |
|---|---|
| Baseline | `/api/app/init` |
| Baseline | `/api/daily-boost/me` |
| Baseline | `/api/search` |
| Load | `/api/app/init` |
| Load | `/api/daily-boost/me` |
| Load | `/api/search` |
| Spike | `/api/app/init` |
| Spike | `/api/daily-boost/me` |
| Spike | `/api/search` |

---

## Key metrics to watch

## API metrics
- p50
- p95
- p99
- error rate
- request count / iterations

## ECS metrics
- CPU
- memory
- task health / restarts

## RDS metrics
- CPU
- connections
- read / write latency
- top SQL / slow queries

## Cache metrics
- hit rate
- memory
- evictions

---

## Pass criteria

Minimum first-round pass criteria:
- `/api/app/init` p95 `< 1200 ms`
- `/api/daily-boost/me` p95 `< 700 ms`
- `/api/search` p95 `< 700 ms`
- error rate `< 1%`
- ECS remains healthy
- RDS connections remain below risky levels

Strong result:
- `/api/app/init` p95 `< 1000 ms`
- `/api/daily-boost/me` p95 `< 500–700 ms`
- `/api/search` p95 `< 500 ms`
- near-zero 5xx

---

## Failure signals

Treat the tested load level as unsafe if you see:
- repeated 5xx spikes
- request timeouts
- ECS CPU or memory pinned near limit
- task restarts
- RDS connections approaching exhaustion
- obvious slow-query spikes
- large p95 jumps during concurrency ramps

---

## Environment guidance

Recommended:
- use **staging** or **pre-production** first
- keep ECS / RDS / cache settings as close to production as practical
- avoid high-volume real SMS / email / payment side effects

---

## Next artifact

The executable implementation for this guide lives in:
- `pressure-testing/k6/config.js`
- `pressure-testing/k6/app-init.js`
- `pressure-testing/k6/daily-boost.js`
- `pressure-testing/k6/search.js`
- `pressure-testing/k6/run-all-9-tests.ps1`
