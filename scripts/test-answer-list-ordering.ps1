$ErrorActionPreference = 'Stop'

$html = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot '..\index.html')

$checks = @(
  @{ Name = 'keeps every displayed answer in the selected problem'; Pattern = 'orderedItems\s*=\s*orderAnswers\(\s*displayItems' },
  @{ Name = 'does not auto-select the first situation'; Pattern = 'if\s*\(state\.situation\s*&&\s*!situations\.includes\(state\.situation\)\)' },
  @{ Name = 'does not auto-select the first platform'; Pattern = 'if\s*\(state\.platform\s*&&\s*!platforms\.includes\(state\.platform\)\)' },
  @{ Name = 'prioritizes the selected situation'; Pattern = 'situationRank' },
  @{ Name = 'prioritizes the selected platform'; Pattern = 'selectedPlatformRank' },
  @{ Name = 'renders the complete answer collection'; Pattern = 'group\.items\s*\.map\(' },
  @{ Name = 'shows the total answer count'; Pattern = 'compact-total' },
  @{ Name = 'groups answers by situation'; Pattern = 'class="answer-group' },
  @{ Name = 'uses compact answer rows'; Pattern = 'class="answer-row' },
  @{ Name = 'keeps copy actions on every row'; Pattern = 'answer-row-actions' },
  @{ Name = 'copies image and text from the platform button'; Pattern = 'class="answer-platform"[^>]+onclick="app\.copyBoth' },
  @{ Name = 'keeps optional image preview'; Pattern = 'previewImage' }
)

foreach ($check in $checks) {
  if ($html -notmatch $check.Pattern) {
    throw "FAILED: $($check.Name)"
  }
  Write-Host "PASS: $($check.Name)"
}

Write-Host 'All answer-list ordering checks passed.'
