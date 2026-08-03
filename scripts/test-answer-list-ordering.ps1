$ErrorActionPreference = 'Stop'

$html = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot '..\index.html')

$checks = @(
  @{ Name = 'keeps every answer in the selected problem'; Pattern = 'orderedItems=orderAnswers\(p\.items\)' },
  @{ Name = 'does not auto-select the first situation'; Pattern = 'if\(state\.situation&&!situations\.includes\(state\.situation\)\)state\.situation=null' },
  @{ Name = 'does not auto-select the first platform'; Pattern = 'if\(state\.platform&&!platforms\.includes\(state\.platform\)\)state\.platform=null' },
  @{ Name = 'prioritizes the selected situation'; Pattern = 'situationRank' },
  @{ Name = 'prioritizes the selected platform'; Pattern = 'platformRank' },
  @{ Name = 'renders the complete answer collection'; Pattern = 'group\.items\.map\(' },
  @{ Name = 'shows the total answer count'; Pattern = 'compact-total' },
  @{ Name = 'groups answers by situation'; Pattern = 'class="answer-group' },
  @{ Name = 'uses compact answer rows'; Pattern = 'class="answer-row' },
  @{ Name = 'keeps copy actions on every row'; Pattern = 'answer-row-actions' },
  @{ Name = 'keeps optional image preview'; Pattern = 'previewImage' }
)

foreach ($check in $checks) {
  if ($html -notmatch $check.Pattern) {
    throw "FAILED: $($check.Name)"
  }
  Write-Host "PASS: $($check.Name)"
}

Write-Host 'All answer-list ordering checks passed.'
