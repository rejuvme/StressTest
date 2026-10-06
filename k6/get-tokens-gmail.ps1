param(
  [Parameter(Mandatory = $false)]
  [string]$BaseUrl = $env:BASE_URL,

  [Parameter(Mandatory = $true)]
  [string]$Email,

  [Parameter(Mandatory = $false)]
  [string]$GmailAddress = $(if ($env:GMAIL_ADDRESS) { $env:GMAIL_ADDRESS } else { $Email }),

  [Parameter(Mandatory = $false)]
  [string]$GmailAppPassword = $env:GMAIL_APP_PASSWORD,

  [Parameter(Mandatory = $false)]
  [string]$Timezone = $(if ($env:X_TIMEZONE) { $env:X_TIMEZONE } else { 'America/Chicago' }),

  [Parameter(Mandatory = $false)]
  [string]$GmailFromFilter = $(if ($env:GMAIL_FROM_FILTER) { $env:GMAIL_FROM_FILTER } else { '' }),

  [Parameter(Mandatory = $false)]
  [string]$GmailSubjectFilter = $(if ($env:GMAIL_SUBJECT_FILTER) { $env:GMAIL_SUBJECT_FILTER } else { 'RejuvMe' }),

  [Parameter(Mandatory = $false)]
  [int]$TimeoutSeconds = $(if ($env:EMAIL_OTP_TIMEOUT_SECONDS) { [int]$env:EMAIL_OTP_TIMEOUT_SECONDS } else { 180 }),

  [Parameter(Mandatory = $false)]
  [int]$PollIntervalSeconds = $(if ($env:EMAIL_OTP_POLL_INTERVAL_SECONDS) { [int]$env:EMAIL_OTP_POLL_INTERVAL_SECONDS } else { 5 })
)

$ErrorActionPreference = 'Stop'

function Require-Value($Name, $Value) {
  if ([string]::IsNullOrWhiteSpace($Value)) {
    throw "Missing required value: $Name"
  }
}

function Normalize-BaseUrl([string]$Value) {
  return ($Value ?? '').Trim().TrimEnd('/')
}

function Get-PythonCommand() {
  $preferred = 'C:\Users\h254164\.conda\envs\general_310\python.exe'
  if (Test-Path $preferred) {
    return $preferred
  }

  $fallback = Get-Command python -ErrorAction SilentlyContinue
  if ($fallback) {
    return $fallback.Source
  }

  throw 'Python not found. Install Python or update the script to point to a valid interpreter.'
}

Require-Value 'BASE_URL' $BaseUrl
Require-Value 'Email' $Email
Require-Value 'GmailAddress' $GmailAddress
Require-Value 'GmailAppPassword' $GmailAppPassword

$normalizedBaseUrl = Normalize-BaseUrl $BaseUrl
$python = Get-PythonCommand
$helper = Join-Path $PSScriptRoot 'gmail_otp_fetch.py'
$issuedAfterEpoch = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()

Write-Host "==> Sending OTP email to $Email"
$sendResponse = Invoke-RestMethod -Method Post -Uri "$normalizedBaseUrl/auth/email/send-code" -ContentType 'application/json' -Body (@{ email = $Email } | ConvertTo-Json -Compress) -TimeoutSec 60
if ($null -eq $sendResponse -or $sendResponse.success -ne $true) {
  throw 'Email send-code did not return success=true'
}

Write-Host '==> Polling Gmail for the newest OTP email'
$raw = & $python $helper --gmail-user $GmailAddress --gmail-app-password $GmailAppPassword --to-filter $Email --from-filter $GmailFromFilter --subject-filter $GmailSubjectFilter --timeout-seconds $TimeoutSeconds --poll-interval-seconds $PollIntervalSeconds --issued-after-epoch $issuedAfterEpoch
if ($LASTEXITCODE -ne 0) {
  throw "Gmail OTP fetch failed: $raw"
}

$emailResult = $raw | ConvertFrom-Json
if (-not $emailResult.ok) {
  throw "Gmail OTP fetch failed: $($emailResult.error)"
}

$code = [string]$emailResult.code
Require-Value 'OTP code' $code

Write-Host "==> Verifying OTP code $code"
$verifyHeaders = @{ 'x-timezone' = $Timezone }
$verifyResponse = Invoke-RestMethod -Method Post -Uri "$normalizedBaseUrl/auth/email/verify-code" -Headers $verifyHeaders -ContentType 'application/json' -Body (@{ email = $Email; code = $code } | ConvertTo-Json -Compress) -TimeoutSec 60
if ($null -eq $verifyResponse -or $verifyResponse.success -ne $true -or $null -eq $verifyResponse.data) {
  throw 'Email verify-code did not return token data'
}

$env:ACCESS_TOKEN = [string]$verifyResponse.data.accessToken
$env:REFRESH_TOKEN = [string]$verifyResponse.data.refreshToken
$env:X_TIMEZONE = $Timezone

$result = [pscustomobject]@{
  Email = $Email
  Code = $code
  EmailSubject = [string]$emailResult.subject
  EmailFrom = [string]$emailResult.from
  EmailDate = [string]$emailResult.date
  AccessToken = $env:ACCESS_TOKEN
  RefreshToken = $env:REFRESH_TOKEN
  ExpiresIn = $verifyResponse.data.expiresIn
  Timezone = $Timezone
}

Write-Host '==> Token bootstrap completed'
Write-Host 'ACCESS_TOKEN and REFRESH_TOKEN have been exported into the current PowerShell session.'
$result
