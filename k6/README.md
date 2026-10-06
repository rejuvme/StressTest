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
- `get-tokens-gmail.ps1` — sends email OTP, polls Gmail, and bootstraps `ACCESS_TOKEN` + `REFRESH_TOKEN`
- `run-all-9-tests.ps1` — runs the 9-case matrix with refresh-token rotation before each case
- `run-all-9-tests-gmail.ps1` — one-click fully automated Gmail bootstrap + 9-case run

## Prerequisites
Install k6 on the machine that will run the test.

Examples:
- Windows (winget): `winget install k6.k6`
- macOS (brew): `brew install k6`

For Gmail automation, prepare a dedicated Gmail inbox and a Gmail App Password.

## Required environment variables
At minimum for single-script runs:
- `BASE_URL` — API base URL, for example `https://api.rejuvme.health/api`
- `ACCESS_TOKEN` — bearer token for a valid test user

Recommended for unattended full-sequence runs:
- `REFRESH_TOKEN` — rotating refresh token for the same valid test user; `run-all-9-tests.ps1` refreshes auth before each case so the 9-step run can finish without manual re-login

Required for Gmail OTP automation:
- `GMAIL_ADDRESS` — Gmail inbox used to receive OTP emails
- `GMAIL_APP_PASSWORD` — 16-character Gmail App Password for IMAP access
- `TEST_EMAIL` — email address used to log into RejuvMe; usually the same as `GMAIL_ADDRESS`

Optional:
- `GMAIL_FROM_FILTER` — sender filter to narrow the OTP email search
- `GMAIL_SUBJECT_FILTER` — subject filter; default: `RejuvMe`
- `EMAIL_OTP_TIMEOUT_SECONDS` — default: `180`
- `EMAIL_OTP_POLL_INTERVAL_SECONDS` — default: `5`
- `SEARCH_QUERY` — keyword used by `search.js` (default: `breath`)
- `SEARCH_SIZE` — page size used by `search.js` (default: `20`)
- `TEST_PROFILE` — `baseline`, `load`, or `spike`
- `X_TIMEZONE` — default: `America/Chicago`

## Test profiles
The scripts support three profiles:
- `baseline`
- `load`
- `spike`

If `TEST_PROFILE` is omitted, the scripts default to `baseline`.

## Example runs
### Single endpoint
```powershell
$env:BASE_URL="https://api.rejuvme.health/api"
$env:ACCESS_TOKEN="<paste-valid-test-token>"
$env:TEST_PROFILE="load"
k6 run app-init.js
```

### Full 9-case run with an existing refresh token
```powershell
cd D:\RejuvMe\pressure-testing\k6
$env:BASE_URL="https://api.rejuvme.health/api"
$env:REFRESH_TOKEN="<paste-valid-test-refresh-token>"
.\run-all-9-tests.ps1
```

### Gmail bootstrap only
```powershell
cd D:\RejuvMe\pressure-testing\k6
$env:BASE_URL="https://api.rejuvme.health/api"
$env:GMAIL_ADDRESS="your-test-inbox@gmail.com"
$env:GMAIL_APP_PASSWORD="your16charapppassword"
$env:TEST_EMAIL="your-test-inbox@gmail.com"
.\get-tokens-gmail.ps1 -Email $env:TEST_EMAIL
```

### Fully automated: Gmail bootstrap + 9-case run
```powershell
cd D:\RejuvMe\pressure-testing\k6
$env:BASE_URL="https://api.rejuvme.health/api"
$env:GMAIL_ADDRESS="your-test-inbox@gmail.com"
$env:GMAIL_APP_PASSWORD="your16charapppassword"
$env:TEST_EMAIL="your-test-inbox@gmail.com"
.\run-all-9-tests-gmail.ps1 -Email $env:TEST_EMAIL -SearchQuery "sleep" -OpenReport
```

## Gmail setup
1. Use a dedicated Gmail inbox for testing.
2. Turn on Google 2-Step Verification for that Gmail account.
3. Create a Gmail App Password for `Mail`.
4. Put that 16-character value into `GMAIL_APP_PASSWORD`.
5. Keep `TEST_EMAIL` mapped to the RejuvMe test account that should receive the OTP.

## Notes
- Use **staging / pre-production** for the first round.
- Do not use high-volume real OTP/SMS/email flows in k6.
- Watch ECS, RDS, Redis, and ALB metrics while tests are running.
- Gmail automation is best with a mailbox dedicated to load testing.
- After a full run, the refresh token rotates; for a fresh unattended run, bootstrap again via Gmail.

## Output
The runner writes raw summaries and logs into:
- `pressure-testing\reports\run-<timestamp>\`

And generates:
- `pressure-test-report.md`
- `pressure-test-report.html`
