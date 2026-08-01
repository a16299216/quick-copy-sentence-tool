$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$html = Get-Content -Raw -Encoding UTF8 (Join-Path $repoRoot 'index.html')
$api = Get-Content -Raw -Encoding UTF8 (Join-Path $repoRoot 'supabase\functions\team-api\index.ts')
$utf8 = [Text.Encoding]::UTF8
$modifyLabel = $utf8.GetString([Convert]::FromBase64String('5o+Q5Ye65L+u5pS5'))
$submitLabel = $utf8.GetString([Convert]::FromBase64String('5o+Q5Lqk5a6h5qC4'))
$successMessage = $utf8.GetString([Convert]::FromBase64String('55Sz6K+35bey5o+Q5Lqk77yM562J5b6F566h55CG5ZGY5a6h5qC4'))

$checks = [ordered]@{
  editor_create_button = $html.Contains('id="editorCreateButton"')
  editor_drafts_button = $html.Contains('id="myDraftsButton"')
  editor_modify_action = $html.Contains($modifyLabel)
  editor_submit_label = $html.Contains($submitLabel)
  editor_success_message = $html.Contains($successMessage)
  editor_role_visibility = $html.Contains('state.data.user.role==="editor"')
  editor_drafts_payload = $api.Contains('my_drafts')
}

$failed = @($checks.GetEnumerator() | Where-Object { -not $_.Value } | ForEach-Object { $_.Key })
if ($failed.Count) {
  throw "Missing editor draft UI: $($failed -join ', ')"
}

Write-Output 'PASS editor draft controls and payload are present'
