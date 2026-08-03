$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$html = Get-Content -Raw -Encoding UTF8 (Join-Path $repoRoot 'index.html')
$api = Get-Content -Raw -Encoding UTF8 (Join-Path $repoRoot 'supabase\functions\team-api\index.ts')

$checks = [ordered]@{
  numeric_search_includes_tags = $html.Contains('const tagHit = p.search_tags.some') -and $html.Contains('if (numeric && !tagHit)')
  blank_tags_send_empty_array = $html.Contains('function parseSearchTags(value)') -and $html.Contains('search_tags: parseSearchTags(value)')
  explicit_search_count = $html.Contains('problemCountLabel') -and $html.Contains('matchedAnswerCount')
  busy_feedback_helper = $html.Contains('function beginBusy(') -and $html.Contains('busyLabel')
  favorite_rows_are_directly_draggable = $html.Contains('draggable=') -and $html.Contains('state.query.trim() ? "false" : "true"')
  favorite_has_reliable_move_controls = $html.Contains('app.moveFavorite(${a.id}, -1)') -and $html.Contains('app.moveFavorite(${a.id}, 1)')
  favorite_reorder_shared_helper = $html.Contains('async function saveFavoriteOrder(order, previous)')
  chinese_punctuation_is_protected = $api.Contains('const protectedPunctuation') -and $api.Contains('restoreProtectedPunctuation')
  draft_can_prefill_answer_manager = $html.Contains('function openDraftInAnswerManager(id)') -and $html.Contains('draft-prefill-button')
  announcement_status_filter = $html.Contains('announcementFilter: "published"') -and $html.Contains('setAnnouncementFilter')
}

$failed = @($checks.GetEnumerator() | Where-Object { -not $_.Value })
if ($failed.Count) {
  $failed | ForEach-Object { Write-Host "FAIL $($_.Key)" -ForegroundColor Red }
  exit 1
}

Write-Host 'PASS customer-service QA regression safeguards' -ForegroundColor Green
