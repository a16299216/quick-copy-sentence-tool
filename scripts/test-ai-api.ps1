param(
  [string]$BaseUrl = "https://ehunehldizwnissqjnmo.supabase.co/functions/v1/team-ai-api",
  [string]$ApiKey = ""
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$apiSourcePath = Join-Path $repoRoot "supabase\functions\team-ai-api\index.ts"
$teamApiPath = Join-Path $repoRoot "supabase\functions\team-api\index.ts"
$migrationPath = Get-ChildItem (Join-Path $repoRoot "supabase\migrations\*_ai_api_access.sql") | Select-Object -Last 1
$docsPath = Join-Path $repoRoot "AI_API.md"
$indexPath = Join-Path $repoRoot "index.html"

foreach ($path in @($apiSourcePath, $teamApiPath, $migrationPath.FullName, $docsPath, $indexPath)) {
  if (-not (Test-Path -LiteralPath $path)) { throw "Missing required file: $path" }
}

$apiSource = Get-Content -Raw -Encoding UTF8 $apiSourcePath
$teamApiSource = Get-Content -Raw -Encoding UTF8 $teamApiPath
$migration = Get-Content -Raw -Encoding UTF8 $migrationPath.FullName
$docs = Get-Content -Raw -Encoding UTF8 $docsPath
$index = Get-Content -Raw -Encoding UTF8 $indexPath

$requiredApiTokens = @(
  '"/health"',
  '"/answers/search"',
  'authorize_ai_api_request',
  'RATE_LIMIT_EXCEEDED',
  'ANSWER_NOT_FOUND',
  'X-RateLimit-Remaining-Minute'
)
foreach ($token in $requiredApiTokens) {
  if (-not $apiSource.Contains($token)) { throw "API source is missing: $token" }
}

$requiredMigrationTokens = @(
  'private.ai_api_keys',
  'enable row level security',
  'revoke all on private.ai_api_keys from public, anon, authenticated',
  'grant execute on function public.authorize_ai_api_request',
  'rate_limit_per_minute integer not null default 60',
  'rate_limit_per_day integer not null default 5000'
)
foreach ($token in $requiredMigrationTokens) {
  if (-not $migration.Contains($token)) { throw "Migration is missing: $token" }
}

if ($index.Contains('SUPABASE_SERVICE_ROLE_KEY')) {
  throw "Public index.html must never contain the Supabase service-role key"
}
foreach ($token in @('AI API', 'createAiApiKey', 'copyCurrentAiApiKey', 'revokeAiApiKey')) {
  if (-not $index.Contains($token)) { throw "Admin UI is missing: $token" }
}
foreach ($token in @('Base URL', '/answers/search', 'MISSING_API_KEY', 'Rate Limit', 'OpenAPI')) {
  if (-not $docs.Contains($token)) { throw "API documentation is missing: $token" }
}
foreach ($token in @('createAiApiKey', 'revokeAiApiKey', 'sha256Hex')) {
  if (-not $teamApiSource.Contains($token)) { throw "team-api is missing: $token" }
}

Write-Host "Static AI API checks passed."

if ([string]::IsNullOrWhiteSpace($ApiKey)) {
  Write-Host "Live checks skipped because -ApiKey was not provided."
  exit 0
}

$headers = @{ "X-API-Key" = $ApiKey }
$health = Invoke-RestMethod -Method Get -Uri "$BaseUrl/health" -Headers $headers
if (-not $health.ok -or $health.data.status -ne "ok") { throw "Health check failed" }

$searchBody = @{ query = "41"; limit = 5 } | ConvertTo-Json
$search = Invoke-RestMethod -Method Post -Uri "$BaseUrl/answers/search" -Headers $headers -ContentType "application/json" -Body $searchBody
if (-not $search.ok -or $search.data.results.Count -lt 1) { throw "Search check failed" }
if ($null -ne $search.data.results[0].score) { throw "v1 must not return score" }

$answerCode = $search.data.results[0].answer_code
$answer = Invoke-RestMethod -Method Get -Uri "$BaseUrl/answers/$answerCode" -Headers $headers
if (-not $answer.ok -or $answer.data.answer_code -ne $answerCode) { throw "Exact answer check failed" }

Write-Host "Live AI API checks passed."
