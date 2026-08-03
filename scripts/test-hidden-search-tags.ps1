$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$html = Get-Content -Raw -Encoding UTF8 (Join-Path $repoRoot 'index.html')
$api = Get-Content -Raw -Encoding UTF8 (Join-Path $repoRoot 'supabase\functions\team-api\index.ts')
$migration = Get-ChildItem (Join-Path $repoRoot 'supabase\migrations\*_add_problem_search_tags.sql') -ErrorAction SilentlyContinue | Select-Object -Last 1
$migrationSql = if ($migration) { Get-Content -Raw -Encoding UTF8 $migration.FullName } else { '' }
$renderStart = $html.IndexOf('function render(){')
$renderEnd = $html.IndexOf('async function copyText', $renderStart)
$normalRender = if ($renderStart -ge 0 -and $renderEnd -gt $renderStart) { $html.Substring($renderStart, $renderEnd - $renderStart) } else { '' }
$utf8 = [Text.Encoding]::UTF8
$tagTab = $utf8.GetString([Convert]::FromBase64String('5pCc57Si5qCH5rOo'))
$tagHelp = $utf8.GetString([Convert]::FromBase64String('5qCH5rOo5Y+q55So5LqO5pCc57Si77yM5LiN5Lya5pi+56S65Zyo5L2/55So6aG16Z2i'))

$checks = [ordered]@{
  search_uses_tags = $html.Contains('p.search_tags.join(" ")')
  admin_tag_tab = $html.Contains($tagTab)
  admin_tag_help = $html.Contains($tagHelp)
  save_tag_function = $html.Contains('function saveProblemTags(')
  api_tag_normalizer = $api.Contains('function cleanSearchTags(')
  api_tag_action = $api.Contains('action === "updateProblemTags"')
  api_attaches_tags = $api.Contains('const search_tags = tagMap.get(item.problem_code)')
  migration_adds_array = $migrationSql.Contains('add column if not exists search_tags text[]')
  reorder_preserves_tags = $migrationSql.Contains('insert into problem_orders(problem_code, sort_order, search_tags)')
  tags_not_rendered_on_usage_page = -not $normalRender.Contains('search_tags')
  numeric_tags_allowed = $api.Contains('String(item ?? "")')
}

$failed = @($checks.GetEnumerator() | Where-Object { -not $_.Value } | ForEach-Object { $_.Key })
if ($failed.Count) {
  throw "Missing hidden search tag features: $($failed -join ', ')"
}

Write-Output 'PASS hidden problem search tags support words, Chinese, and numbers'
