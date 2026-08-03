$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$html = Get-Content -Raw -Encoding UTF8 (Join-Path $repoRoot 'index.html')
$api = Get-Content -Raw -Encoding UTF8 (Join-Path $repoRoot 'supabase\functions\team-api\index.ts')
$migration = Get-ChildItem (Join-Path $repoRoot 'supabase\migrations\*_add_announcements_and_request_workflow.sql') | Select-Object -Last 1
$sql = Get-Content -Raw -Encoding UTF8 $migration.FullName
$cleanupMigration = Get-ChildItem (Join-Path $repoRoot 'supabase\migrations\*_normalize_and_repair_answer_text.sql') | Select-Object -Last 1
$cleanupSql = Get-Content -Raw -Encoding UTF8 $cleanupMigration.FullName
$cleanupReportExists = Test-Path (Join-Path $repoRoot 'ANSWER_TEXT_CLEANUP.md')

$checks = [ordered]@{
  compact_numeric_search = $html.Contains('codeCompact.startsWith(compact)')
  numeric_search_excludes_answer_text = $html.Contains('numeric =') -and $html.Contains('if (numeric)')
  exact_answer_priority = $html.Contains('exactAnswerId') -and $html.Contains('exactRank')
  exact_answer_group_first = $html.Contains('const exactSituation = c.exactAnswerId')
  search_result_count = $html.Contains('matchedAnswerCount')
  search_clear_action = $html.Contains('function clearSearch()')
  duplicate_rich_copy_removed = -not $html.Contains('>图文</button>')
  platform_copy_fallback = $html.Contains('if (!a.image_url) return copyText(id)')
  favorite_opens_first = $html.Contains('const first = favoriteItems(false)[0]')
  announcement_button = $html.Contains('id="announcementsButton"')
  announcement_drawer = $html.Contains('function renderAnnouncementDrawer()')
  announcement_image_preview = $html.Contains('function previewAnnouncementImage(id)')
  announcement_admin = $html.Contains('state.adminTab === "announcements"') -and $html.Contains('all_announcements')
  draft_three_types = ($html -match "startRequest\('supplement'\)") -and ($html -match "startRequest\('new_problem'\)")
  draft_edit_cancel = $html.Contains('function editDraft(id)') -and $html.Contains('function cancelDraft(id)')
  draft_two_states = $html.Contains('"unprocessed"') -and $html.Contains('"processed"')
  manual_processing_only = $html.Contains('action: "markDraftProcessed"') -and -not $html.Contains('action: "approveDraft"')
  simplified_normalization = $api.Contains('opencc-js@1.4.1') -and $api.Contains('.normalize("NFKC")')
  announcement_api = $api.Contains('action === "saveAnnouncement"') -and $api.Contains('action === "markAnnouncementRead"')
  request_api = $api.Contains('action === "saveDraft"') -and $api.Contains('action === "cancelDraft"') -and $api.Contains('action === "markDraftProcessed"')
  announcement_tables_rls = $sql.Contains('alter table public.announcements enable row level security') -and $sql.Contains('alter table public.announcement_reads enable row level security')
  browser_table_access_revoked = $sql.Contains('revoke all on table public.announcements from public, anon, authenticated')
  cleanup_has_history_backup = $cleanupSql.Contains('insert into public.answer_history(answer_item_id')
  cleanup_report_exists = $cleanupReportExists
}

$failed = @($checks.GetEnumerator() | Where-Object { -not $_.Value } | ForEach-Object { $_.Key })
if ($failed.Count) {
  throw "Missing usability upgrade features: $($failed -join ', ')"
}

Write-Output 'PASS search, applications, announcements, copy, favorites, and normalization upgrades are present'
