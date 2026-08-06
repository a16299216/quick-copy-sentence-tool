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
  fixed_platform_order = $html.Contains('const PLATFORM_ORDER = [') -and $html.Contains('function platformSortRank(platform)')
  answer_rows_use_platform_order = $html.Contains('platformSortRank(a.platform) - platformSortRank(b.platform)')
  platform_chips_use_same_order = $html.Contains('.sort((a, b) => platformSortRank(a) - platformSortRank(b))')
  situation_order_has_admin_control = $html.Contains('function situationOrderModal()') -and $html.Contains('situation-order-button')
  situation_order_calls_api = $html.Contains('action: "moveSituation"') -and $html.Contains('async function moveSituation(')
  situation_order_is_atomic = $api.Contains('service.rpc("move_situation_and_renumber"') -and $api.Contains('if (action === "moveSituation")')
  situation_order_renumbers_codes = $api.Contains('p_situation_label: situationLabel') -and $api.Contains('p_direction: direction')
  bulk_image_has_admin_control = $html.Contains('function bulkImageModal()') -and $html.Contains('app.bulkImageModal()')
  bulk_image_uploads_once = $html.Contains('async function saveBulkImage(') -and $html.Contains('action: "bulkUpdateAnswerImages"')
  bulk_image_keeps_original_file = $html.Contains('function chooseBulkImage(file)') -and $html.Contains('state.image = file;') -and $html.Contains('onchange="app.chooseBulkImage(this.files[0])"')
  bulk_image_uses_atomic_rpc = $api.Contains('if (action === "bulkUpdateAnswerImages")') -and $api.Contains('"bulk_update_answer_images"')
  bulk_image_validates_storage_key = $api.Contains('const answerImageKeyPattern') -and $api.Contains('.list("", { search: imageKey')
}

$failed = @($checks.GetEnumerator() | Where-Object { -not $_.Value })
if ($failed.Count) {
  $failed | ForEach-Object { Write-Host "FAIL $($_.Key)" -ForegroundColor Red }
  exit 1
}

Write-Host 'PASS customer-service QA regression safeguards' -ForegroundColor Green
