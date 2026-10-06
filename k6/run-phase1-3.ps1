param(
  [string]$BaseUrl = $env:BASE_URL,
  [string]$AccessToken = $env:ACCESS_TOKEN,
  [string]$SearchQuery = $(if ($env:SEARCH_QUERY) { $env:SEARCH_QUERY } else { 'sleep' }),
  [string]$OutputDir = (Join-Path $PSScriptRoot '..\reports'),
  [switch]$OpenReport
)

& (Join-Path $PSScriptRoot 'run-all-9-tests.ps1') -BaseUrl $BaseUrl -AccessToken $AccessToken -SearchQuery $SearchQuery -OutputDir $OutputDir -OpenReport:$OpenReport
