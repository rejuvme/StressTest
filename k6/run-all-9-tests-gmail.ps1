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
  [int]$PollIntervalSeconds = $(if ($env:EMAIL_OTP_POLL_INTERVAL_SECONDS) { [int]$env:EMAIL_OTP_POLL_INTERVAL_SECONDS } else { 5 }),

  [Parameter(Mandatory = $false)]
  [string]$SearchQuery = $(if ($env:SEARCH_QUERY) { $env:SEARCH_QUERY } else { 'sleep' }),

  [Parameter(Mandatory = $false)]
  [string]$OutputDir = (Join-Path $PSScriptRoot '..\reports'),

  [switch]$OpenReport
)

$tokenResult = & (Join-Path $PSScriptRoot 'get-tokens-gmail.ps1') -BaseUrl $BaseUrl -Email $Email -GmailAddress $GmailAddress -GmailAppPassword $GmailAppPassword -Timezone $Timezone -GmailFromFilter $GmailFromFilter -GmailSubjectFilter $GmailSubjectFilter -TimeoutSeconds $TimeoutSeconds -PollIntervalSeconds $PollIntervalSeconds

if (-not $tokenResult -or [string]::IsNullOrWhiteSpace($tokenResult.RefreshToken)) {
  throw 'Failed to bootstrap REFRESH_TOKEN from Gmail OTP flow.'
}

& (Join-Path $PSScriptRoot 'run-all-9-tests.ps1') -BaseUrl $BaseUrl -AccessToken $tokenResult.AccessToken -RefreshToken $tokenResult.RefreshToken -SearchQuery $SearchQuery -OutputDir $OutputDir -OpenReport:$OpenReport
