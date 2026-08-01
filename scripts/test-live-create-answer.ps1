param(
  [string]$Password = $env:TEAM_ANSWER_TEST_PASSWORD
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($Password)) {
  throw 'Set TEAM_ANSWER_TEST_PASSWORD before running this live integration test.'
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$html = Get-Content -Raw -Encoding UTF8 (Join-Path $repoRoot 'index.html')
$urlMatch = [regex]::Match($html, 'const SB_URL="([^"]+)"')
$keyMatch = [regex]::Match($html, 'const SB_KEY="([^"]+)"')
if (-not $urlMatch.Success -or -not $keyMatch.Success) {
  throw 'Unable to find the Supabase URL or publishable key in index.html.'
}

$supabaseUrl = $urlMatch.Groups[1].Value
$publishableKey = $keyMatch.Groups[1].Value
$commonHeaders = @{ apikey = $publishableKey }
$loginBody = @{
  email = 'admin@team-answer.local'
  password = $Password
} | ConvertTo-Json

$login = Invoke-RestMethod -Method Post `
  -Uri "$supabaseUrl/auth/v1/token?grant_type=password" `
  -Headers $commonHeaders `
  -ContentType 'application/json' `
  -Body $loginBody

$apiHeaders = @{
  apikey = $publishableKey
  Authorization = "Bearer $($login.access_token)"
}
$stamp = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
$title = "Codex-live-regression-$stamp"
$saveBody = @{
  action = 'saveAnswer'
  answer = @{
    id = $null
    answer_code = ''
    problem_code = ''
    problem_title = $title
    situation_label = 'create-answer-test'
    platform = $null
    answer_text = 'Temporary answer created by the live regression test.'
    image_key = $null
    sort_order = 0
  }
} | ConvertTo-Json -Depth 5

$saved = Invoke-RestMethod -Method Post `
  -Uri "$supabaseUrl/functions/v1/team-api" `
  -Headers $apiHeaders `
  -ContentType 'application/json' `
  -Body $saveBody

if (-not $saved.item.id) {
  throw 'The API returned success without a created answer id.'
}

$deleteBody = @{ action = 'deleteAnswer'; id = $saved.item.id } | ConvertTo-Json
Invoke-RestMethod -Method Post `
  -Uri "$supabaseUrl/functions/v1/team-api" `
  -Headers $apiHeaders `
  -ContentType 'application/json' `
  -Body $deleteBody | Out-Null

Write-Output "PASS created_and_soft_deleted id=$($saved.item.id) code=$($saved.item.answer_code)"
