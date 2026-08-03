$ErrorActionPreference = 'Stop'

$html = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot '..\index.html')

$checks = @(
  @{ Name = 'stores the active admin category'; Pattern = 'adminProblem:"all"' },
  @{ Name = 'filters answers by problem code'; Pattern = 'function adminAnswerItems\(\)' },
  @{ Name = 'renders the category navigation row'; Pattern = 'class="answer-category-bar"' },
  @{ Name = 'marks the active category'; Pattern = 'state\.adminProblem===p\.code' },
  @{ Name = 'renders only visible answers'; Pattern = 'visibleItems\.map\(' },
  @{ Name = 'checks selection against visible answers'; Pattern = 'visibleItems\.every\(' },
  @{ Name = 'exposes category switching'; Pattern = 'adminProblem:setAdminProblem' },
  @{ Name = 'limits select-all to the active category'; Pattern = 'for\(const item of adminAnswerItems\(\)\)' }
)

foreach ($check in $checks) {
  if ($html -notmatch $check.Pattern) {
    throw "FAILED: $($check.Name)"
  }
  Write-Host "PASS: $($check.Name)"
}

Write-Host 'All answer category management checks passed.'
