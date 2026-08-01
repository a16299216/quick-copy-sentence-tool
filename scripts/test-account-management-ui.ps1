$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$html = Get-Content -Raw -Encoding UTF8 (Join-Path $repoRoot 'index.html')
$api = Get-Content -Raw -Encoding UTF8 (Join-Path $repoRoot 'supabase\functions\team-api\index.ts')
$utf8 = [Text.Encoding]::UTF8
$randomLabel = $utf8.GetString([Convert]::FromBase64String('6ZqP5py655Sf5oiQ'))
$deleteLabel = $utf8.GetString([Convert]::FromBase64String('5Yig6Zmk6LSm5Y+3'))
$resetCopyLabel = $utf8.GetString([Convert]::FromBase64String('55Sf5oiQ5paw5a+G56CB5bm25aSN5Yi2'))

$checks = [ordered]@{
  random_generator = $html.Contains('function randomAccount()')
  credential_generator = $html.Contains('function generatePassword()')
  credential_copy = $html.Contains('function copyCredentials(')
  reset_and_copy = $html.Contains('function resetAndCopy(')
  delete_user_ui = $html.Contains('function deleteUser(')
  random_label = $html.Contains($randomLabel)
  delete_label = $html.Contains($deleteLabel)
  reset_copy_label = $html.Contains($resetCopyLabel)
  api_delete_action = $api.Contains('action === "deleteUser"')
  api_deleted_filter = $api.Contains('.is("deleted_at", null)')
  api_self_delete_guard = $api.Contains('id === profile.id')
  api_last_admin_guard = $api.Contains('last active admin')
  no_local_password_storage = -not ($html -match 'localStorage[^\r\n;]*password')
}

$failed = @($checks.GetEnumerator() | Where-Object { -not $_.Value } | ForEach-Object { $_.Key })
if ($failed.Count) {
  throw "Missing account management features: $($failed -join ', ')"
}

Write-Output 'PASS secure account generation, copy, and deletion controls are present'
