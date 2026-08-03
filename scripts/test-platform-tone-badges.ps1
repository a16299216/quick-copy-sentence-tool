$ErrorActionPreference = 'Stop'

$html = Get-Content -Raw -Encoding UTF8 (Join-Path $PSScriptRoot '..\index.html')

$checks = [ordered]@{
  cash_uses_forest_green = $html.Contains('[data-platform-tone="cash"]') -and $html.Contains('#0f7a4e')
  board_uses_poster_purple = $html.Contains('[data-platform-tone="board"]') -and $html.Contains('#7c3aed')
  sports_uses_poster_blue = $html.Contains('[data-platform-tone="sports"]') -and $html.Contains('#0284c7')
  app_uses_mint_green = $html.Contains('[data-platform-tone="app"]') -and $html.Contains('#0d9488')
  exact_platform_mapping = $html -match "const tones=\{[^}]+:'cash'[^}]+:'board'[^}]+:'sports'[^}]+:'app'\}"
  answer_only_scope = $html.Contains('$("answerPane").querySelectorAll(''.answer-platform'')')
  observer_reapplies_after_render = $html.Contains('const platformToneObserver=new MutationObserver(applyPlatformTones)')
}

$failed = @($checks.GetEnumerator() | Where-Object { -not $_.Value })
if ($failed.Count) {
  $failed | ForEach-Object { Write-Host "FAIL $($_.Key)" -ForegroundColor Red }
  exit 1
}

Write-Host 'PASS platform badges use poster-derived colors' -ForegroundColor Green
