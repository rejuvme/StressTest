# RejuvMe k6 Pressure Testing

This folder contains the first-round executable load-testing scripts for the three highest-priority launch APIs:

1. `/api/app/init`
2. `/api/daily-boost/me`
3. `/api/search`

## Files
- `config.js` — shared configuration helpers
- `app-init.js` — pressure test for `/api/app/init`
- `daily-boost.js` — pressure test for `/api/daily-boost/me`
- `search.js` — pressure test for `/api/search`

## Prerequisites
Install k6 on the machine that will run the test.

Examples:
- Windows (winget): `winget install k6.k6`
- macOS (brew): `brew install k6`

## Required environment variables
At minimum:
- `BASE_URL` — API base URL, for example `https://api.rejuvme.health/api`
- `ACCESS_TOKEN` — bearer token for a valid test user

Optional:
- `SEARCH_QUERY` — keyword used by `search.js` (default: `breath`)
- `SEARCH_SIZE` — page size used by `search.js` (default: `20`)
- `TEST_PROFILE` — `baseline`, `load`, or `spike`

## Test profiles
The scripts support four profiles:
- `baseline`
- `load`
- `spike`

If `TEST_PROFILE` is omitted, the scripts default to `baseline`.

## Example runs
### `/api/app/init`
```powershell
$env:BASE_URL="https://api.rejuvme.health/api"
$env:ACCESS_TOKEN="<paste-valid-test-token>"
$env:TEST_PROFILE="load"
k6 run app-init.js
```

### `/api/daily-boost/me`
```powershell
$env:BASE_URL="https://api.rejuvme.health/api"
$env:ACCESS_TOKEN="<paste-valid-test-token>"
$env:TEST_PROFILE="load"
k6 run daily-boost.js
```

### `/api/search`
```powershell
$env:BASE_URL="https://api.rejuvme.health/api"
$env:ACCESS_TOKEN="<paste-valid-test-token>"
$env:TEST_PROFILE="load"
$env:SEARCH_QUERY="sleep"
k6 run search.js
```

## Notes
- Use **staging / pre-production** for the first round.
- Do not use high-volume real OTP/SMS/email flows in k6.
- Watch ECS, RDS, Redis, and ALB metrics while tests are running.

## One-click sequence runner
To run the full 9-case matrix (`baseline + load + spike` across `app/init + daily-boost + search`) and automatically generate a report:

```powershell
cd D:\RejuvMe\pressure-testing\k6
$env:BASE_URL="https://api.rejuvme.health/api"
$env:ACCESS_TOKEN="<paste-valid-test-token>"
.\run-all-9-tests.ps1
```

Optional:
```powershell
.\run-all-9-tests.ps1 -SearchQuery "sleep" -OpenReport
```

The runner writes raw summaries and logs into:
- `pressure-testing\reports\run-<timestamp>\`

And generates:
- `pressure-test-report.md`
- `pressure-test-report.html`
