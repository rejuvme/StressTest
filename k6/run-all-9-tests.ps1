param(
  [Parameter(Mandatory = $false)]
  [string]$BaseUrl = $env:BASE_URL,

  [Parameter(Mandatory = $false)]
  [string]$AccessToken = $env:ACCESS_TOKEN,

  [Parameter(Mandatory = $false)]
  [string]$RefreshToken = $env:REFRESH_TOKEN,

  [Parameter(Mandatory = $false)]
  [string]$SearchQuery = $(if ($env:SEARCH_QUERY) { $env:SEARCH_QUERY } else { 'sleep' }),

  [Parameter(Mandatory = $false)]
  [string]$OutputDir = (Join-Path $PSScriptRoot '..\reports'),

  [switch]$OpenReport
)

$ErrorActionPreference = 'Stop'

function Require-Command($Name) {
  if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
    throw "Missing required command: $Name"
  }
}

function Require-Value($Name, $Value) {
  if ([string]::IsNullOrWhiteSpace($Value)) {
    throw "Missing required value: $Name"
  }
}

function Require-OneOf($Description, [string[]]$Values) {
  foreach ($value in $Values) {
    if (-not [string]::IsNullOrWhiteSpace($value)) {
      return
    }
  }

  throw "Missing required auth input: $Description"
}

function Safe-Name([string]$s) {
  return ($s -replace '[^A-Za-z0-9._-]', '_')
}

function Normalize-BaseUrl([string]$Value) {
  return ($Value ?? '').Trim().TrimEnd('/')
}

function Get-K6MetricValue($Summary, [string]$MetricName, [string]$Key) {
  if (-not $Summary.metrics.$MetricName) { return $null }
  $metric = $Summary.metrics.$MetricName
  if (-not $metric.values) { return $null }
  return $metric.values.$Key
}

function To-Percent($value) {
  if ($null -eq $value) { return 'n/a' }
  return ('{0:N2}%' -f ($value * 100))
}

function To-Ms($value) {
  if ($null -eq $value) { return 'n/a' }
  return ('{0:N2} ms' -f [double]$value)
}

function To-Int($value) {
  if ($null -eq $value) { return 'n/a' }
  return ('{0:N0}' -f [double]$value)
}

function Invoke-RefreshTokenExchange([string]$NormalizedBaseUrl, [string]$CurrentRefreshToken) {
  Require-Value 'REFRESH_TOKEN' $CurrentRefreshToken

  $uri = "$NormalizedBaseUrl/auth/refresh"
  $payload = @{ refreshToken = $CurrentRefreshToken } | ConvertTo-Json -Compress

  try {
    $response = Invoke-RestMethod -Method Post -Uri $uri -ContentType 'application/json' -Body $payload -TimeoutSec 60
  }
  catch {
    $message = $_.Exception.Message
    if ($_.ErrorDetails.Message) {
      $message = "$message | $($_.ErrorDetails.Message)"
    }
    throw "Refresh token exchange failed at $uri. $message"
  }

  if ($null -eq $response -or $response.success -ne $true -or $null -eq $response.data) {
    throw "Refresh token exchange returned an unexpected response from $uri"
  }

  $newAccessToken = [string]$response.data.accessToken
  $newRefreshToken = [string]$response.data.refreshToken

  if ([string]::IsNullOrWhiteSpace($newAccessToken) -or [string]::IsNullOrWhiteSpace($newRefreshToken)) {
    throw 'Refresh token exchange did not return both accessToken and refreshToken'
  }

  return [pscustomobject]@{
    AccessToken = $newAccessToken
    RefreshToken = $newRefreshToken
    ExpiresIn = $response.data.expiresIn
  }
}

function Evaluate-Step($Name, $Summary, [double]$P95LimitMs) {
  $failedRate = Get-K6MetricValue $Summary 'http_req_failed' 'rate'
  $p95 = Get-K6MetricValue $Summary 'http_req_duration' 'p(95)'
  $p99 = Get-K6MetricValue $Summary 'http_req_duration' 'p(99)'
  $avg = Get-K6MetricValue $Summary 'http_req_duration' 'avg'
  $iterations = Get-K6MetricValue $Summary 'iterations' 'count'
  $checksRate = Get-K6MetricValue $Summary 'checks' 'rate'

  $passError = ($null -ne $failedRate) -and ([double]$failedRate -lt 0.01)
  $passP95 = ($null -ne $p95) -and ([double]$p95 -lt $P95LimitMs)
  $overall = $passError -and $passP95

  [pscustomobject]@{
    Name = $Name
    P95LimitMs = $P95LimitMs
    FailedRate = $failedRate
    ChecksRate = $checksRate
    P95 = $p95
    P99 = $p99
    Avg = $avg
    Iterations = $iterations
    PassErrorRate = $passError
    PassP95 = $passP95
    Passed = $overall
  }
}

function Run-K6Step(
  [string]$Name,
  [string]$ScriptFile,
  [string]$Profile,
  [double]$P95LimitMs,
  [hashtable]$ExtraEnv,
  [string]$RunDir,
  [string]$NormalizedBaseUrl,
  [string]$CurrentAccessToken
) {
  $stepDir = Join-Path $RunDir (Safe-Name $Name)
  New-Item -ItemType Directory -Force -Path $stepDir | Out-Null
  $summaryFile = Join-Path $stepDir 'summary.json'
  $stdoutFile = Join-Path $stepDir 'stdout.log'
  $stderrFile = Join-Path $stepDir 'stderr.log'

  $env:BASE_URL = $NormalizedBaseUrl
  $env:ACCESS_TOKEN = $CurrentAccessToken
  $env:TEST_PROFILE = $Profile
  foreach ($k in $ExtraEnv.Keys) {
    Set-Item -Path "Env:$k" -Value ([string]$ExtraEnv[$k])
  }

  Write-Host "==> Running $Name ($ScriptFile, profile=$Profile)"
  & k6 run --summary-export "$summaryFile" "$ScriptFile" 1> "$stdoutFile" 2> "$stderrFile"

  if ($LASTEXITCODE -ne 0) {
    throw "k6 step failed: $Name. See $stderrFile"
  }

  $summary = Get-Content $summaryFile -Raw | ConvertFrom-Json
  $result = Evaluate-Step -Name $Name -Summary $summary -P95LimitMs $P95LimitMs

  return [pscustomobject]@{
    Name = $Name
    ScriptFile = $ScriptFile
    Profile = $Profile
    StepDir = $stepDir
    SummaryFile = $summaryFile
    StdoutFile = $stdoutFile
    StderrFile = $stderrFile
    Summary = $summary
    Result = $result
  }
}

Require-Command 'k6'
Require-Value 'BASE_URL' $BaseUrl
Require-OneOf 'ACCESS_TOKEN or REFRESH_TOKEN' @($AccessToken, $RefreshToken)

$normalizedBaseUrl = Normalize-BaseUrl $BaseUrl
$currentAccessToken = $AccessToken
$currentRefreshToken = $RefreshToken
$refreshAttemptCount = 0
$refreshSuccessCount = 0
$authMode = if (-not [string]::IsNullOrWhiteSpace($currentRefreshToken)) { 'refresh-token automation' } else { 'access-token only' }

if ([string]::IsNullOrWhiteSpace($currentAccessToken) -and -not [string]::IsNullOrWhiteSpace($currentRefreshToken)) {
  Write-Host '==> Bootstrapping fresh access token from REFRESH_TOKEN'
  $refreshAttemptCount++
  $bootstrap = Invoke-RefreshTokenExchange -NormalizedBaseUrl $normalizedBaseUrl -CurrentRefreshToken $currentRefreshToken
  $currentAccessToken = $bootstrap.AccessToken
  $currentRefreshToken = $bootstrap.RefreshToken
  $refreshSuccessCount++
}

Require-Value 'ACCESS_TOKEN' $currentAccessToken

if ([string]::IsNullOrWhiteSpace($currentRefreshToken)) {
  Write-Warning 'REFRESH_TOKEN not provided. ACCESS_TOKEN-only mode may fail on longer multi-step runs if the token expires.'
}

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$runDir = Join-Path $OutputDir "run-$timestamp"
New-Item -ItemType Directory -Force -Path $runDir | Out-Null

$steps = @(
  @{ Name = 'Baseline-AppInit'; Script = (Join-Path $PSScriptRoot 'app-init.js'); Profile = 'baseline'; P95Limit = 1200; ExtraEnv = @{} },
  @{ Name = 'Baseline-DailyBoost'; Script = (Join-Path $PSScriptRoot 'daily-boost.js'); Profile = 'baseline'; P95Limit = 700; ExtraEnv = @{} },
  @{ Name = 'Baseline-Search'; Script = (Join-Path $PSScriptRoot 'search.js'); Profile = 'baseline'; P95Limit = 700; ExtraEnv = @{ SEARCH_QUERY = $SearchQuery } },
  @{ Name = 'Load-AppInit'; Script = (Join-Path $PSScriptRoot 'app-init.js'); Profile = 'load'; P95Limit = 1200; ExtraEnv = @{} },
  @{ Name = 'Load-DailyBoost'; Script = (Join-Path $PSScriptRoot 'daily-boost.js'); Profile = 'load'; P95Limit = 700; ExtraEnv = @{} },
  @{ Name = 'Load-Search'; Script = (Join-Path $PSScriptRoot 'search.js'); Profile = 'load'; P95Limit = 700; ExtraEnv = @{ SEARCH_QUERY = $SearchQuery } },
  @{ Name = 'Spike-AppInit'; Script = (Join-Path $PSScriptRoot 'app-init.js'); Profile = 'spike'; P95Limit = 1200; ExtraEnv = @{} },
  @{ Name = 'Spike-DailyBoost'; Script = (Join-Path $PSScriptRoot 'daily-boost.js'); Profile = 'spike'; P95Limit = 700; ExtraEnv = @{} },
  @{ Name = 'Spike-Search'; Script = (Join-Path $PSScriptRoot 'search.js'); Profile = 'spike'; P95Limit = 700; ExtraEnv = @{ SEARCH_QUERY = $SearchQuery } }
)

$executions = @()
foreach ($step in $steps) {
  if (-not [string]::IsNullOrWhiteSpace($currentRefreshToken)) {
    Write-Host "==> Refreshing auth before $($step.Name)"
    $refreshAttemptCount++
    $refreshResult = Invoke-RefreshTokenExchange -NormalizedBaseUrl $normalizedBaseUrl -CurrentRefreshToken $currentRefreshToken
    $currentAccessToken = $refreshResult.AccessToken
    $currentRefreshToken = $refreshResult.RefreshToken
    $refreshSuccessCount++
  }

  $executions += Run-K6Step -Name $step.Name -ScriptFile $step.Script -Profile $step.Profile -P95LimitMs $step.P95Limit -ExtraEnv $step.ExtraEnv -RunDir $runDir -NormalizedBaseUrl $normalizedBaseUrl -CurrentAccessToken $currentAccessToken
}

$results = $executions | ForEach-Object { $_.Result }
$overallPass = ($results | Where-Object { -not $_.Passed }).Count -eq 0
$reportMd = Join-Path $runDir 'pressure-test-report.md'
$reportHtml = Join-Path $runDir 'pressure-test-report.html'

$htmlResults = $results | ForEach-Object {
  [pscustomobject]@{
    Name = $_.Name
    Profile = ($executions | Where-Object Name -eq $_.Name | Select-Object -First 1 -ExpandProperty Profile)
    Avg = $_.Avg
    P95 = $_.P95
    P99 = $_.P99
    FailedRate = $_.FailedRate
    ChecksRate = $_.ChecksRate
    Iterations = $_.Iterations
    P95LimitMs = $_.P95LimitMs
    PassErrorRate = $_.PassErrorRate
    PassP95 = $_.PassP95
    Passed = $_.Passed
  }
}

$groupedResults = @{
  baseline = @($htmlResults | Where-Object { $_.Profile -eq 'baseline' })
  load     = @($htmlResults | Where-Object { $_.Profile -eq 'load' })
  spike    = @($htmlResults | Where-Object { $_.Profile -eq 'spike' })
}

$groupTitles = @{
  baseline = 'Baseline Group'
  load     = 'Load Group'
  spike    = 'Spike Group'
}

$groupNotes = @{
  baseline = 'Light concurrency reference run for all three endpoints.'
  load     = 'Normal launch-load simulation for all three endpoints.'
  spike    = 'Burst traffic simulation for all three endpoints.'
}

function New-HtmlRows($Items) {
  $rows = @()
  foreach ($r in $Items) {
    $resultText = if ($r.Passed) { 'PASS' } else { 'FAIL' }
    $resultClass = if ($r.Passed) { 'pass' } else { 'fail' }
    $rows += "<tr><td>$($r.Name)</td><td>$(To-Ms $r.Avg)</td><td>$(To-Ms $r.P95)</td><td>$(To-Ms $r.P99)</td><td>$(To-Percent $r.FailedRate)</td><td>$(To-Percent $r.ChecksRate)</td><td>$(To-Int $r.Iterations)</td><td>$(To-Ms $r.P95LimitMs)</td><td class='$resultClass'>$resultText</td></tr>"
  }
  return $rows
}

$baselineRows = New-HtmlRows $groupedResults['baseline']
$loadRows = New-HtmlRows $groupedResults['load']
$spikeRows = New-HtmlRows $groupedResults['spike']

$groupStatus = @{}
foreach ($groupKey in @('baseline', 'load', 'spike')) {
  $groupItems = $groupedResults[$groupKey]
  if ($groupItems.Count -eq 0) {
    $groupStatus[$groupKey] = $null
  } else {
    $groupStatus[$groupKey] = (($groupItems | Where-Object { -not $_.Passed }).Count -eq 0)
  }
}

$md = @()
$md += '# RejuvMe Pressure Test Report'
$md += ''
$md += "- Generated at: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$md += "- BASE_URL: `$normalizedBaseUrl`"
$md += "- SEARCH_QUERY: `$SearchQuery`"
$md += "- Auth mode: `$authMode`"
$md += "- Refresh attempts: `$(To-Int $refreshAttemptCount)`"
$md += "- Refresh successes: `$(To-Int $refreshSuccessCount)`"
$md += "- Overall result: **$(if ($overallPass) { 'PASS' } else { 'FAIL' })**"
$md += ''
$md += '## Scope'
$md += '- Baseline: `/api/app/init`, `/api/daily-boost/me`, `/api/search`'
$md += '- Load: `/api/app/init`, `/api/daily-boost/me`, `/api/search`'
$md += '- Spike: `/api/app/init`, `/api/daily-boost/me`, `/api/search`'
$md += ''

foreach ($groupKey in @('baseline', 'load', 'spike')) {
  $groupItems = $groupedResults[$groupKey]
  if ($groupItems.Count -eq 0) { continue }
  $md += "## $($groupTitles[$groupKey])"
  $md += ''
  $md += "- Group result: **$(if ($groupStatus[$groupKey]) { 'PASS' } else { 'FAIL' })**"
  $md += "- Purpose: $($groupNotes[$groupKey])"
  $md += ''
  $md += '| Step | Avg | p95 | p99 | Error Rate | Checks Pass Rate | Iterations | p95 Threshold | Result |'
  $md += '|---|---:|---:|---:|---:|---:|---:|---:|---|'
  foreach ($r in $groupItems) {
    $md += "| $($r.Name) | $(To-Ms $r.Avg) | $(To-Ms $r.P95) | $(To-Ms $r.P99) | $(To-Percent $r.FailedRate) | $(To-Percent $r.ChecksRate) | $(To-Int $r.Iterations) | $(To-Ms $r.P95LimitMs) | $(if ($r.Passed) { 'PASS' } else { 'FAIL' }) |"
  }
  $md += ''
}

$md += '## Pass Criteria'
$md += '- Error rate must be `< 1%`'
$md += '- `/api/app/init` p95 must be `< 1200 ms`'
$md += '- `/api/daily-boost/me` p95 must be `< 700 ms`'
$md += '- `/api/search` p95 must be `< 700 ms`'
$md += ''
$md += '## Detailed Results'
foreach ($groupKey in @('baseline', 'load', 'spike')) {
  $groupItems = $groupedResults[$groupKey]
  if ($groupItems.Count -eq 0) { continue }
  $md += ''
  $md += "### $($groupTitles[$groupKey])"
  foreach ($r in $groupItems) {
    $stepExec = $executions | Where-Object Name -eq $r.Name | Select-Object -First 1
    $md += ''
    $md += "#### $($r.Name)"
    $md += "- Script: `$([System.IO.Path]::GetFileName($stepExec.ScriptFile))`"
    $md += "- Profile: `$($stepExec.Profile)`"
    $md += "- Avg latency: $(To-Ms $r.Avg)"
    $md += "- p95 latency: $(To-Ms $r.P95)"
    $md += "- p99 latency: $(To-Ms $r.P99)"
    $md += "- Error rate: $(To-Percent $r.FailedRate)"
    $md += "- Checks pass rate: $(To-Percent $r.ChecksRate)"
    $md += "- Iterations: $(To-Int $r.Iterations)"
    $md += "- p95 threshold: $(To-Ms $r.P95LimitMs)"
    $md += "- Error-rate check: **$(if ($r.PassErrorRate) { 'PASS' } else { 'FAIL' })**"
    $md += "- p95 check: **$(if ($r.PassP95) { 'PASS' } else { 'FAIL' })**"
    $md += "- Overall: **$(if ($r.Passed) { 'PASS' } else { 'FAIL' })**"
    $md += "- Raw summary: `$($stepExec.SummaryFile)`"
    $md += "- Stdout log: `$($stepExec.StdoutFile)`"
    $md += "- Stderr log: `$($stepExec.StderrFile)`"
  }
}

$md -join "`r`n" | Set-Content -Path $reportMd

function Convert-MarkdownToHtml([string]$BaseUrlValue, [string]$SearchQueryValue, [bool]$OverallPassValue, $BaselineRowsValue, $LoadRowsValue, $SpikeRowsValue, [string]$AuthModeValue, [int]$RefreshAttemptsValue, [int]$RefreshSuccessesValue) {
  return @"
<!doctype html>
<html>
<head>
  <meta charset='utf-8' />
  <title>RejuvMe Pressure Test Report</title>
  <style>
    body { font-family: Arial, sans-serif; margin: 24px; color: #222; }
    h1, h2, h3, h4 { margin-top: 24px; }
    table { border-collapse: collapse; width: 100%; margin-top: 12px; margin-bottom: 24px; }
    th, td { border: 1px solid #ccc; padding: 8px; text-align: left; }
    th { background: #f4f4f4; }
    .pass { color: #0a7a2f; font-weight: bold; }
    .fail { color: #b00020; font-weight: bold; }
    code { background: #f6f8fa; padding: 2px 4px; }
  </style>
</head>
<body>
  <h1>RejuvMe Pressure Test Report</h1>
  <p><strong>Generated at:</strong> $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>
  <p><strong>BASE_URL:</strong> <code>$BaseUrlValue</code></p>
  <p><strong>SEARCH_QUERY:</strong> <code>$SearchQueryValue</code></p>
  <p><strong>Auth mode:</strong> <code>$AuthModeValue</code></p>
  <p><strong>Refresh attempts:</strong> <code>$RefreshAttemptsValue</code></p>
  <p><strong>Refresh successes:</strong> <code>$RefreshSuccessesValue</code></p>
  <p><strong>Overall result:</strong> <span class='$(if ($OverallPassValue) { 'pass' } else { 'fail' })'>$(if ($OverallPassValue) { 'PASS' } else { 'FAIL' })</span></p>

  <h2>Scope</h2>
  <ul>
    <li>Baseline: <code>/api/app/init</code>, <code>/api/daily-boost/me</code>, <code>/api/search</code></li>
    <li>Load: <code>/api/app/init</code>, <code>/api/daily-boost/me</code>, <code>/api/search</code></li>
    <li>Spike: <code>/api/app/init</code>, <code>/api/daily-boost/me</code>, <code>/api/search</code></li>
  </ul>

  <h2>Grouped Summary</h2>

  <h3>Baseline Group</h3>
  <p><strong>Group result:</strong> <span class='$(if ($groupStatus['baseline']) { 'pass' } else { 'fail' })'>$(if ($groupStatus['baseline']) { 'PASS' } else { 'FAIL' })</span></p>
  <p>Light concurrency reference run for all three endpoints.</p>
  <table>
    <thead>
      <tr>
        <th>Step</th><th>Avg</th><th>p95</th><th>p99</th><th>Error Rate</th><th>Checks Pass Rate</th><th>Iterations</th><th>p95 Threshold</th><th>Result</th>
      </tr>
    </thead>
    <tbody>
      $($BaselineRowsValue -join "`n      ")
    </tbody>
  </table>

  <h3>Load Group</h3>
  <p><strong>Group result:</strong> <span class='$(if ($groupStatus['load']) { 'pass' } else { 'fail' })'>$(if ($groupStatus['load']) { 'PASS' } else { 'FAIL' })</span></p>
  <p>Normal launch-load simulation for all three endpoints.</p>
  <table>
    <thead>
      <tr>
        <th>Step</th><th>Avg</th><th>p95</th><th>p99</th><th>Error Rate</th><th>Checks Pass Rate</th><th>Iterations</th><th>p95 Threshold</th><th>Result</th>
      </tr>
    </thead>
    <tbody>
      $($LoadRowsValue -join "`n      ")
    </tbody>
  </table>

  <h3>Spike Group</h3>
  <p><strong>Group result:</strong> <span class='$(if ($groupStatus['spike']) { 'pass' } else { 'fail' })'>$(if ($groupStatus['spike']) { 'PASS' } else { 'FAIL' })</span></p>
  <p>Burst traffic simulation for all three endpoints.</p>
  <table>
    <thead>
      <tr>
        <th>Step</th><th>Avg</th><th>p95</th><th>p99</th><th>Error Rate</th><th>Checks Pass Rate</th><th>Iterations</th><th>p95 Threshold</th><th>Result</th>
      </tr>
    </thead>
    <tbody>
      $($SpikeRowsValue -join "`n      ")
    </tbody>
  </table>
</body>
</html>
"@
}

Convert-MarkdownToHtml -BaseUrlValue $normalizedBaseUrl -SearchQueryValue $SearchQuery -OverallPassValue $overallPass -BaselineRowsValue $baselineRows -LoadRowsValue $loadRows -SpikeRowsValue $spikeRows -AuthModeValue $authMode -RefreshAttemptsValue $refreshAttemptCount -RefreshSuccessesValue $refreshSuccessCount | Set-Content -Path $reportHtml

Write-Host ''
Write-Host 'Completed full 9-case pressure test sequence.'
Write-Host "Markdown report: $reportMd"
Write-Host "HTML report: $reportHtml"
Write-Host "Auth mode: $authMode"
Write-Host "Refresh attempts: $refreshAttemptCount"
Write-Host "Refresh successes: $refreshSuccessCount"
Write-Host "Overall result: $(if ($overallPass) { 'PASS' } else { 'FAIL' })"

if ($OpenReport) {
  Start-Process $reportHtml
}


