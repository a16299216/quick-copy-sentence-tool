$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$html = Get-Content -Raw -Encoding UTF8 (Join-Path $repoRoot 'index.html')
$api = Get-Content -Raw -Encoding UTF8 (Join-Path $repoRoot 'supabase\functions\team-api\index.ts')
$migration = Get-ChildItem (Join-Path $repoRoot 'supabase\migrations\*_add_user_answer_favorites.sql') | Select-Object -Last 1
$sql = Get-Content -Raw -Encoding UTF8 $migration.FullName

$checks = [ordered]@{
  personal_table = $sql.Contains('create table if not exists public.user_answer_favorites')
  composite_owner_key = $sql.Contains('primary key (user_id, answer_id)')
  rls_enabled = $sql.Contains('alter table public.user_answer_favorites enable row level security')
  browser_roles_revoked = $sql.Contains('revoke all on table public.user_answer_favorites from public, anon, authenticated')
  api_scopes_by_profile = $api.Contains('.eq("user_id", profile.id)')
  api_returns_favorites = $api.Contains('favorites: (favorites || []).filter')
  toggle_action_before_admin_gate = $api.IndexOf('action === "toggleFavorite"') -gt 0 -and $api.IndexOf('action === "toggleFavorite"') -lt $api.IndexOf('requireRole(profile, ["admin"]);')
  left_search_tabs = $html.Contains('id="problemsTab"') -and $html.Contains('id="favoritesTab"')
  answer_add_button = $html.Contains('onclick="app.toggleFavorite(${a.id})"')
  favorites_inside_search_pane = $html.Contains("state.listMode==='favorites'") -and $html.Contains('class="favorite-row')
  no_top_button_or_popup = -not $html.Contains('id="favoritesButton"') -and -not $html.Contains('function favoritesModal(')
  direct_navigation = $html.Contains('state.problem=a.problem_code') -and $html.Contains('state.situation=a.situation_label') -and $html.Contains('state.platform=a.platform||null')
}

$failed = @($checks.GetEnumerator() | Where-Object { -not $_.Value })
if ($failed.Count) {
  $failed | ForEach-Object { Write-Host "FAIL $($_.Key)" -ForegroundColor Red }
  exit 1
}
Write-Host 'PASS personal favorite answers support add, remove, and direct navigation' -ForegroundColor Green
