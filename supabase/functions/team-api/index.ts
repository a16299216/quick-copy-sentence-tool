import { createClient } from "npm:@supabase/supabase-js@2";
import OpenCC from "npm:opencc-js@1.4.1";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};

const url = Deno.env.get("SUPABASE_URL")!;
const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const service = createClient(url, serviceKey, {
  auth: { persistSession: false },
});

type Profile = {
  id: string;
  username: string;
  display_name: string;
  role: "admin" | "editor" | "viewer";
  status: "active" | "disabled";
  session_epoch: number;
  deleted_at: string | null;
};
type Answer = {
  id?: number | null;
  answer_code?: string;
  problem_code?: string;
  problem_title?: string;
  situation_label?: string;
  platform?: string | null;
  answer_text?: string;
  image_key?: string | null;
  sort_order?: number;
  version?: number;
};
type DraftRequest = Answer & {
  draft_id?: number | null;
  request_type?: "edit" | "supplement" | "new_problem";
  request_reason?: string;
  member_question?: string;
};

const toSimplified = OpenCC.Converter({ from: "t", to: "cn" });

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "content-type": "application/json; charset=utf-8" },
  });
}

function cleanText(value: unknown) {
  return String(value ?? "").trim();
}
function normalizeChineseText(value: unknown) {
  return toSimplified(cleanText(value).normalize("NFKC"));
}
function norm(value: unknown) {
  return cleanText(value).toLocaleLowerCase("zh-CN");
}
function cleanSearchTags(value: unknown) {
  const raw = Array.isArray(value)
    ? value
    : String(value ?? "").split(/[,，、;；\n]+/);
  const tags: string[] = [];
  const seen = new Set<string>();
  for (const item of raw) {
    const tag = normalizeChineseText(item);
    if (!tag) continue;
    if (tag.length > 40) throw new Error("每个搜索标注最多 40 个字符");
    const key = tag.toLocaleLowerCase("zh-CN");
    if (!seen.has(key)) {
      seen.add(key);
      tags.push(tag);
    }
  }
  if (tags.length > 20) throw new Error("每个问题最多设置 20 个搜索标注");
  return tags;
}
function emailForUsername(username: string) {
  return `${username.toLowerCase()}@team-answer.local`;
}
function codePart(code: string, index: number) {
  const value = Number(code.split("-")[index]);
  return Number.isInteger(value) && value > 0 ? value : 0;
}

async function currentProfile(req: Request) {
  const token = req.headers.get("authorization")?.replace(/^Bearer\s+/i, "");
  if (!token) throw new Error("UNAUTHORIZED");
  const { data: authData, error: authError } =
    await service.auth.getUser(token);
  if (authError || !authData.user) throw new Error("UNAUTHORIZED");
  const { data: profile, error } = await service
    .from("profiles")
    .select("*")
    .eq("id", authData.user.id)
    .single();
  if (error || !profile || profile.status !== "active" || profile.deleted_at)
    throw new Error("UNAUTHORIZED");
  return profile as Profile;
}

function requireRole(profile: Profile, roles: Profile["role"][]) {
  if (!roles.includes(profile.role)) throw new Error("FORBIDDEN");
}

async function audit(
  profile: Profile,
  action: string,
  entityType: string,
  entityId: string | number,
  before: unknown,
  after: unknown,
) {
  await service.from("audit_logs").insert({
    actor_id: profile.id,
    actor_name: profile.display_name,
    action,
    entity_type: entityType,
    entity_id: String(entityId),
    before_json: before,
    after_json: after,
  });
}

function automaticNumbering(items: Answer[], draft: Answer) {
  const existingProblem = items.find(
    (item) => norm(item.problem_title) === norm(draft.problem_title),
  );
  const largestProblem = items.reduce(
    (max, item) => Math.max(max, Number(item.problem_code) || 0),
    0,
  );
  const problemCode =
    existingProblem?.problem_code || String(largestProblem + 1);
  const problemItems = items.filter(
    (item) => item.problem_code === problemCode,
  );
  const existingSituation = problemItems.find(
    (item) => norm(item.situation_label) === norm(draft.situation_label),
  );
  const situationNumber = existingSituation
    ? codePart(existingSituation.answer_code || "", 1) || 1
    : Math.max(
        0,
        ...problemItems.map((item) => codePart(item.answer_code || "", 1)),
      ) + 1;
  const situationItems = problemItems.filter(
    (item) => norm(item.situation_label) === norm(draft.situation_label),
  );
  const platform = cleanText(draft.platform) || null;
  const duplicate = situationItems.find(
    (item) => norm(item.platform) === norm(platform),
  );
  if (duplicate)
    throw new Error("这个问题、情况和平台已经有答案，请直接修改原答案");
  if (!platform)
    return {
      problem_code: problemCode,
      answer_code: `${problemCode}-${situationNumber}`,
    };
  const platformNumber =
    Math.max(
      0,
      ...situationItems.map((item) => codePart(item.answer_code || "", 2)),
    ) + 1;
  return {
    problem_code: problemCode,
    answer_code: `${problemCode}-${situationNumber}-${platformNumber}`,
  };
}

function cleanAnswer(input: Answer) {
  const answer = {
    id: input.id ? Number(input.id) : null,
    answer_code: cleanText(input.answer_code),
    problem_code: cleanText(input.problem_code),
    problem_title: normalizeChineseText(input.problem_title),
    situation_label: normalizeChineseText(input.situation_label),
    platform: normalizeChineseText(input.platform) || null,
    answer_text: normalizeChineseText(input.answer_text),
    image_key: cleanText(input.image_key) || null,
    sort_order: Number(input.sort_order) || 0,
  };
  if (!answer.problem_title || !answer.situation_label || !answer.answer_text)
    throw new Error("请完整填写问题名称、情况和标准答案");
  return answer;
}

function cleanDraftRequest(input: DraftRequest) {
  const requestType =
    cleanText(input.request_type) || (input.id ? "edit" : "supplement");
  if (!["edit", "supplement", "new_problem"].includes(requestType))
    throw new Error("申请类型不正确");
  const draft = {
    draft_id: input.draft_id ? Number(input.draft_id) : null,
    id: input.id ? Number(input.id) : null,
    answer_code: cleanText(input.answer_code),
    problem_code: cleanText(input.problem_code),
    problem_title: normalizeChineseText(input.problem_title),
    situation_label: normalizeChineseText(input.situation_label),
    platform: normalizeChineseText(input.platform) || null,
    answer_text: normalizeChineseText(input.answer_text),
    image_key: cleanText(input.image_key) || null,
    sort_order: Number(input.sort_order) || 0,
    request_type: requestType as DraftRequest["request_type"],
    request_reason: normalizeChineseText(input.request_reason),
    member_question: normalizeChineseText(input.member_question),
  };
  if (requestType === "edit") {
    if (
      !draft.id ||
      !draft.problem_title ||
      !draft.situation_label ||
      !draft.answer_text
    )
      throw new Error("请完整填写修改内容");
    if (!draft.request_reason) throw new Error("请选择修改原因");
  } else if (
    !draft.problem_title ||
    !draft.situation_label ||
    !draft.member_question
  ) {
    throw new Error("请完整填写问题名称、情况和会员实际询问内容");
  }
  return draft;
}

async function savePublished(
  raw: Answer,
  profile: Profile,
  action = "发布答案",
) {
  const answer = cleanAnswer(raw);
  const { data: all } = await service
    .from("answer_items")
    .select("*")
    .is("deleted_at", null);
  const before = answer.id
    ? (all || []).find((item) => item.id === answer.id)
    : null;
  const classificationChanged =
    before &&
    (norm(before.problem_title) !== norm(answer.problem_title) ||
      norm(before.situation_label) !== norm(answer.situation_label) ||
      norm(before.platform) !== norm(answer.platform));
  if (!before || classificationChanged) {
    const numbered = automaticNumbering(
      (all || []).filter((item) => item.id !== answer.id),
      answer,
    );
    answer.problem_code = numbered.problem_code;
    answer.answer_code = numbered.answer_code;
  }
  if (!answer.problem_code || !answer.answer_code)
    throw new Error("无法产生答案编号");
  if (before) {
    await service.from("answer_history").insert({
      answer_item_id: before.id,
      version: before.version,
      snapshot_json: before,
      action,
      actor_id: profile.id,
    });
    const { data, error } = await service
      .from("answer_items")
      .update({
        ...answer,
        version: Number(before.version) + 1,
        updated_by: profile.id,
        updated_at: new Date().toISOString(),
        deleted_at: null,
      })
      .eq("id", answer.id)
      .select()
      .single();
    if (error) throw error;
    await audit(profile, action, "answer", answer.id!, before, data);
    return data;
  }
  const { id: _generatedId, ...insertableAnswer } = answer;
  const { data, error } = await service
    .from("answer_items")
    .insert({
      ...insertableAnswer,
      created_by: profile.id,
      updated_by: profile.id,
    })
    .select()
    .single();
  if (error) throw new Error(error.message);
  const { data: orders } = await service
    .from("problem_orders")
    .select("sort_order")
    .order("sort_order", { ascending: false })
    .limit(1);
  await service.from("problem_orders").upsert(
    {
      problem_code: answer.problem_code,
      sort_order: (orders?.[0]?.sort_order || 0) + 1,
    },
    { onConflict: "problem_code", ignoreDuplicates: true },
  );
  await audit(profile, action, "answer", data.id, null, data);
  return data;
}

async function getData(profile: Profile) {
  const [
    { data: items },
    { data: orders },
    { data: favorites },
    { data: announcements },
    { data: announcementReads },
  ] = await Promise.all([
    service.from("answer_items").select("*").is("deleted_at", null),
    service.from("problem_orders").select("*").order("sort_order"),
    service
      .from("user_answer_favorites")
      .select("answer_id, sort_order")
      .eq("user_id", profile.id)
      .order("sort_order"),
    service
      .from("announcements")
      .select("*")
      .eq("status", "published")
      .order("is_pinned", { ascending: false })
      .order("created_at", { ascending: false }),
    service
      .from("announcement_reads")
      .select("announcement_id")
      .eq("user_id", profile.id),
  ]);
  const orderMap = new Map(
    (orders || []).map((entry) => [entry.problem_code, entry.sort_order]),
  );
  const tagMap = new Map(
    (orders || []).map((entry) => [
      entry.problem_code,
      entry.search_tags || [],
    ]),
  );
  const sorted = (items || []).sort(
    (a, b) =>
      (orderMap.get(a.problem_code) ?? 999999) -
        (orderMap.get(b.problem_code) ?? 999999) ||
      a.answer_code.localeCompare(b.answer_code, "zh-CN", { numeric: true }),
  );
  const withImages = await Promise.all(
    sorted.map(async (item) => {
      const search_tags = tagMap.get(item.problem_code) || [];
      if (!item.image_key) return { ...item, image_url: null, search_tags };
      const { data } = await service.storage
        .from("answer-images")
        .createSignedUrl(item.image_key, 3600);
      return { ...item, image_url: data?.signedUrl || null, search_tags };
    }),
  );
  const activeIds = new Set(withImages.map((item) => item.id));
  const announcementsWithImages = await Promise.all(
    (announcements || []).map(async (item) => {
      if (!item.image_key) return { ...item, image_url: null };
      const { data } = await service.storage
        .from("answer-images")
        .createSignedUrl(item.image_key, 3600);
      return { ...item, image_url: data?.signedUrl || null };
    }),
  );
  const readAnnouncementIds = new Set(
    (announcementReads || []).map((entry) => Number(entry.announcement_id)),
  );
  const payload: Record<string, unknown> = {
    user: profile,
    items: withImages,
    favorites: (favorites || []).filter((entry) =>
      activeIds.has(entry.answer_id),
    ),
    announcements: announcementsWithImages,
    unread_announcement_ids: announcementsWithImages
      .filter((item) => !readAnnouncementIds.has(Number(item.id)))
      .map((item) => Number(item.id)),
  };
  if (profile.role === "admin") {
    const [
      { data: users },
      { data: drafts },
      { data: allAnnouncements },
      { data: deleted },
      { data: history },
      { data: logs },
    ] = await Promise.all([
      service
        .from("profiles")
        .select("*")
        .is("deleted_at", null)
        .order("created_at"),
      service
        .from("answer_drafts")
        .select("*")
        .order("created_at", { ascending: false })
        .limit(200),
      service
        .from("announcements")
        .select("*")
        .order("created_at", { ascending: false })
        .limit(200),
      service
        .from("answer_items")
        .select("*")
        .not("deleted_at", "is", null)
        .order("deleted_at", { ascending: false }),
      service
        .from("answer_history")
        .select("*")
        .order("created_at", { ascending: false })
        .limit(100),
      service
        .from("audit_logs")
        .select("*")
        .order("created_at", { ascending: false })
        .limit(150),
    ]);
    Object.assign(payload, {
      users,
      drafts,
      all_announcements: allAnnouncements,
      deleted_items: deleted,
      history,
      audit: logs,
    });
  } else if (profile.role === "editor") {
    const { data: myDrafts } = await service
      .from("answer_drafts")
      .select("*")
      .eq("created_by", profile.id)
      .order("created_at", { ascending: false })
      .limit(50);
    Object.assign(payload, { my_drafts: myDrafts || [] });
  }
  return payload;
}

async function bulkUpdate(
  ids: number[],
  changes: Record<string, unknown>,
  profile: Profile,
) {
  const { data: all, error } = await service
    .from("answer_items")
    .select("*")
    .is("deleted_at", null);
  if (error) throw error;
  const selectedSet = new Set(ids.map(Number));
  const selected = (all || []).filter((item) => selectedSet.has(item.id));
  if (!selected.length || selected.length !== selectedSet.size)
    throw new Error("请选择要整理的答案");
  const problemTitle = cleanText(changes.problem_title) || null;
  const situationLabel = cleanText(changes.situation_label) || null;
  const platformSpecified =
    changes.clear_platform === true || cleanText(changes.platform) !== "";
  const platform =
    changes.clear_platform === true
      ? null
      : cleanText(changes.platform) || null;
  if (!problemTitle && !situationLabel && !platformSpecified)
    throw new Error("请至少填写一个要修改的项目");
  const simulated = (all || []).filter((item) => !selectedSet.has(item.id));
  const planned: Answer[] = [];
  for (const item of selected) {
    const draft = {
      ...item,
      problem_title: problemTitle || item.problem_title,
      situation_label: situationLabel || item.situation_label,
      platform: platformSpecified ? platform : item.platform,
    };
    const numbered = automaticNumbering([...simulated, ...planned], draft);
    planned.push({ ...draft, ...numbered });
  }
  const stamp = Date.now();
  for (const item of selected) {
    await service.from("answer_history").insert({
      answer_item_id: item.id,
      version: item.version,
      snapshot_json: item,
      action: "批量整理",
      actor_id: profile.id,
    });
    await service
      .from("answer_items")
      .update({ answer_code: `__bulk_${stamp}_${item.id}` })
      .eq("id", item.id);
  }
  for (const item of planned) {
    const { error: updateError } = await service
      .from("answer_items")
      .update({
        answer_code: item.answer_code,
        problem_code: item.problem_code,
        problem_title: item.problem_title,
        situation_label: item.situation_label,
        platform: item.platform,
        version: Number(item.version) + 1,
        updated_by: profile.id,
        updated_at: new Date().toISOString(),
      })
      .eq("id", item.id);
    if (updateError) throw updateError;
  }
  await audit(
    profile,
    "批量整理",
    "answer_batch",
    ids.join(","),
    selected,
    planned,
  );
}

async function handleJson(
  req: Request,
  profile: Profile,
  body: Record<string, unknown>,
) {
  const action = cleanText(body.action);
  if (action === "getData") return json(await getData(profile));
  if (action === "saveAnswer") {
    requireRole(profile, ["admin", "editor"]);
    if (profile.role === "admin")
      return json({
        ok: true,
        item: await savePublished(body.answer as Answer, profile),
      });
  }
  if (action === "saveAnswer" || action === "saveDraft") {
    requireRole(profile, ["editor"]);
    const draft = cleanDraftRequest(
      (body.answer || body.draft) as DraftRequest,
    );
    const { data: original } = draft.id
      ? await service
          .from("answer_items")
          .select("*")
          .eq("id", draft.id)
          .is("deleted_at", null)
          .single()
      : { data: null };
    if (draft.request_type === "edit" && !original)
      throw new Error("找不到要修改的答案");
    if (draft.request_type === "edit" && original) {
      const beforeComparable = JSON.stringify({
        problem_title: normalizeChineseText(original.problem_title),
        situation_label: normalizeChineseText(original.situation_label),
        platform: normalizeChineseText(original.platform) || null,
        answer_text: normalizeChineseText(original.answer_text),
        image_key: cleanText(original.image_key) || null,
      });
      const afterComparable = JSON.stringify({
        problem_title: draft.problem_title,
        situation_label: draft.situation_label,
        platform: draft.platform,
        answer_text: draft.answer_text,
        image_key: draft.image_key,
      });
      if (beforeComparable === afterComparable)
        throw new Error("内容没有变动，请修改后再提交");
    }
    const proposedJson = { ...draft };
    delete proposedJson.draft_id;
    const record = {
      answer_item_id: draft.id,
      proposed_json: proposedJson,
      original_json: original,
      request_type: draft.request_type,
      request_reason: draft.request_reason || null,
      created_by: profile.id,
      updated_at: new Date().toISOString(),
    };
    if (draft.draft_id) {
      const { data: existing } = await service
        .from("answer_drafts")
        .select("*")
        .eq("id", draft.draft_id)
        .eq("created_by", profile.id)
        .eq("status", "unprocessed")
        .single();
      if (!existing) throw new Error("这笔申请已处理，无法修改");
      const { error } = await service
        .from("answer_drafts")
        .update(record)
        .eq("id", draft.draft_id)
        .eq("created_by", profile.id)
        .eq("status", "unprocessed");
      if (error) throw error;
      await audit(
        profile,
        "修改申请",
        "draft",
        draft.draft_id,
        existing,
        record,
      );
      return json({ ok: true, mode: "draft", id: draft.draft_id });
    }
    const { data: saved, error } = await service
      .from("answer_drafts")
      .insert(record)
      .select("id")
      .single();
    if (error) throw error;
    await audit(profile, "提出申请", "draft", saved.id, null, record);
    return json({ ok: true, mode: "draft", id: saved.id });
  }
  if (action === "cancelDraft") {
    requireRole(profile, ["editor"]);
    const id = Number(body.id);
    const { data: existing } = await service
      .from("answer_drafts")
      .select("*")
      .eq("id", id)
      .eq("created_by", profile.id)
      .eq("status", "unprocessed")
      .single();
    if (!existing) throw new Error("这笔申请已处理，无法取消");
    const { error } = await service
      .from("answer_drafts")
      .delete()
      .eq("id", id)
      .eq("created_by", profile.id)
      .eq("status", "unprocessed");
    if (error) throw error;
    await audit(profile, "取消申请", "draft", id, existing, null);
    return json({ ok: true });
  }
  if (action === "markAnnouncementRead") {
    const id = Number(body.id);
    const { data: announcement } = await service
      .from("announcements")
      .select("id")
      .eq("id", id)
      .eq("status", "published")
      .single();
    if (!announcement) throw new Error("找不到公告");
    const { error } = await service.from("announcement_reads").upsert({
      announcement_id: id,
      user_id: profile.id,
      read_at: new Date().toISOString(),
    });
    if (error) throw error;
    return json({ ok: true });
  }
  if (action === "toggleFavorite") {
    const answerId = Number(body.answer_id);
    if (!Number.isInteger(answerId) || answerId <= 0)
      throw new Error("答案资料不正确");
    const { data: answer } = await service
      .from("answer_items")
      .select("id")
      .eq("id", answerId)
      .is("deleted_at", null)
      .maybeSingle();
    if (!answer) throw new Error("找不到答案");
    const { data: existing } = await service
      .from("user_answer_favorites")
      .select("answer_id")
      .eq("user_id", profile.id)
      .eq("answer_id", answerId)
      .maybeSingle();
    if (existing) {
      const { error } = await service
        .from("user_answer_favorites")
        .delete()
        .eq("user_id", profile.id)
        .eq("answer_id", answerId);
      if (error) throw error;
      return json({ ok: true, favorite: false, answer_id: answerId });
    }
    const { data: last } = await service
      .from("user_answer_favorites")
      .select("sort_order")
      .eq("user_id", profile.id)
      .order("sort_order", { ascending: false })
      .limit(1);
    const { error } = await service.from("user_answer_favorites").insert({
      user_id: profile.id,
      answer_id: answerId,
      sort_order: (last?.[0]?.sort_order || 0) + 1,
    });
    if (error) throw error;
    return json({ ok: true, favorite: true, answer_id: answerId });
  }
  if (action === "reorderFavorites") {
    const rawIds = Array.isArray(body.answer_ids) ? body.answer_ids : [];
    const answerIds = rawIds.map(Number);
    const requestedIds = new Set(answerIds);
    if (
      answerIds.length > 100 ||
      requestedIds.size !== answerIds.length ||
      answerIds.some((id) => !Number.isInteger(id) || id <= 0)
    ) {
      throw new Error("常用排序资料不正确");
    }
    const { data: existing, error: existingError } = await service
      .from("user_answer_favorites")
      .select("answer_id")
      .eq("user_id", profile.id);
    if (existingError) throw existingError;
    const existingIds = (existing || []).map((entry) =>
      Number(entry.answer_id),
    );
    if (
      existingIds.length !== answerIds.length ||
      existingIds.some((id) => !requestedIds.has(id))
    ) {
      throw new Error("常用列表已更新，请刷新后再排序");
    }
    for (let index = 0; index < answerIds.length; index += 1) {
      const { error } = await service
        .from("user_answer_favorites")
        .update({ sort_order: index + 1 })
        .eq("user_id", profile.id)
        .eq("answer_id", answerIds[index]);
      if (error) throw error;
    }
    return json({ ok: true, answer_ids: answerIds });
  }
  requireRole(profile, ["admin"]);
  if (action === "saveAnnouncement") {
    const id = body.id ? Number(body.id) : null;
    const title = normalizeChineseText(body.title);
    const announcementBody = normalizeChineseText(body.body);
    const imageKey = cleanText(body.image_key) || null;
    const isPinned = body.is_pinned === true;
    if (!title || !announcementBody) throw new Error("请填写公告标题与内容");
    if (title.length > 120) throw new Error("公告标题最多 120 个字符");
    const now = new Date().toISOString();
    if (id) {
      const { data: before } = await service
        .from("announcements")
        .select("*")
        .eq("id", id)
        .single();
      if (!before) throw new Error("找不到公告");
      const { data, error } = await service
        .from("announcements")
        .update({
          title,
          body: announcementBody,
          image_key: imageKey,
          is_pinned: isPinned,
          status: "published",
          archived_at: null,
          updated_at: now,
        })
        .eq("id", id)
        .select()
        .single();
      if (error) throw error;
      await service
        .from("announcement_reads")
        .delete()
        .eq("announcement_id", id);
      await audit(profile, "修改公告", "announcement", id, before, data);
      return json({ ok: true, item: data });
    }
    const { data, error } = await service
      .from("announcements")
      .insert({
        title,
        body: announcementBody,
        image_key: imageKey,
        is_pinned: isPinned,
        created_by: profile.id,
      })
      .select()
      .single();
    if (error) throw error;
    await audit(profile, "发布公告", "announcement", data.id, null, data);
    return json({ ok: true, item: data });
  }
  if (action === "archiveAnnouncement") {
    const id = Number(body.id);
    const { data: before } = await service
      .from("announcements")
      .select("*")
      .eq("id", id)
      .single();
    if (!before) throw new Error("找不到公告");
    const { data, error } = await service
      .from("announcements")
      .update({
        status: "archived",
        archived_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      })
      .eq("id", id)
      .select()
      .single();
    if (error) throw error;
    await audit(profile, "下架公告", "announcement", id, before, data);
    return json({ ok: true });
  }
  if (action === "markDraftProcessed") {
    const id = Number(body.id);
    const note = normalizeChineseText(body.review_note);
    const { data: before } = await service
      .from("answer_drafts")
      .select("*")
      .eq("id", id)
      .eq("status", "unprocessed")
      .single();
    if (!before) throw new Error("找不到未处理申请");
    const processed = {
      status: "processed",
      review_note: note || null,
      reviewed_by: profile.id,
      reviewed_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
    };
    const { error } = await service
      .from("answer_drafts")
      .update(processed)
      .eq("id", id)
      .eq("status", "unprocessed");
    if (error) throw error;
    await audit(profile, "标记申请已处理", "draft", id, before, {
      ...before,
      ...processed,
    });
    return json({ ok: true });
  }
  if (action === "updateProblemTags") {
    const problemCode = cleanText(body.problem_code);
    const searchTags = cleanSearchTags(body.search_tags);
    const { data: existingAnswer } = await service
      .from("answer_items")
      .select("id")
      .eq("problem_code", problemCode)
      .is("deleted_at", null)
      .limit(1)
      .maybeSingle();
    if (!existingAnswer) throw new Error("找不到问题");
    const { data: before } = await service
      .from("problem_orders")
      .select("*")
      .eq("problem_code", problemCode)
      .maybeSingle();
    let saved;
    if (before) {
      const { data, error } = await service
        .from("problem_orders")
        .update({
          search_tags: searchTags,
          updated_at: new Date().toISOString(),
        })
        .eq("problem_code", problemCode)
        .select()
        .single();
      if (error) throw error;
      saved = data;
    } else {
      const { data: last } = await service
        .from("problem_orders")
        .select("sort_order")
        .order("sort_order", { ascending: false })
        .limit(1);
      const { data, error } = await service
        .from("problem_orders")
        .insert({
          problem_code: problemCode,
          sort_order: (last?.[0]?.sort_order || 0) + 1,
          search_tags: searchTags,
        })
        .select()
        .single();
      if (error) throw error;
      saved = data;
    }
    await audit(
      profile,
      "更新搜索标注",
      "problem",
      problemCode,
      before?.search_tags || [],
      searchTags,
    );
    return json({
      ok: true,
      problem_code: problemCode,
      search_tags: saved.search_tags || [],
    });
  }
  if (action === "bulkUpdateAnswers") {
    await bulkUpdate(
      ((body.ids as unknown[]) || []).map(Number),
      (body.changes || {}) as Record<string, unknown>,
      profile,
    );
    return json({ ok: true });
  }
  if (action === "moveProblem") {
    const { error } = await service.rpc("move_problem_and_renumber", {
      p_problem_code: cleanText(body.problem_code),
      p_direction: cleanText(body.direction),
      p_actor: profile.id,
    });
    if (error) throw error;
    await audit(
      profile,
      "调整问题顺序并重新编号",
      "problem",
      cleanText(body.problem_code),
      { direction: body.direction },
      { moved: true },
    );
    return json({ ok: true });
  }
  if (action === "deleteAnswer") {
    const id = Number(body.id);
    const { data: before } = await service
      .from("answer_items")
      .select("*")
      .eq("id", id)
      .single();
    const { error } = await service
      .from("answer_items")
      .update({ deleted_at: new Date().toISOString(), updated_by: profile.id })
      .eq("id", id);
    if (error) throw error;
    await audit(profile, "删除答案", "answer", id, before, null);
    return json({ ok: true });
  }
  if (action === "restoreAnswer") {
    const id = Number(body.id);
    const { data: item } = await service
      .from("answer_items")
      .select("*")
      .eq("id", id)
      .single();
    if (!item) throw new Error("找不到答案");
    const { data: active } = await service
      .from("answer_items")
      .select("*")
      .is("deleted_at", null);
    const numbered = automaticNumbering(active || [], item);
    const { error } = await service
      .from("answer_items")
      .update({ ...numbered, deleted_at: null, updated_by: profile.id })
      .eq("id", id);
    if (error) throw error;
    await audit(profile, "恢复答案", "answer", id, item, {
      ...item,
      ...numbered,
      deleted_at: null,
    });
    return json({ ok: true });
  }
  if (action === "createUser") {
    const username = cleanText(body.username);
    const password = String(body.password || "");
    const displayName = cleanText(body.display_name);
    const role = cleanText(body.role);
    if (
      !/^[a-zA-Z0-9._-]{3,32}$/.test(username) ||
      password.length < 8 ||
      !displayName ||
      !["admin", "editor", "viewer"].includes(role)
    )
      throw new Error("账号资料不正确");
    const { data, error } = await service.auth.admin.createUser({
      email: emailForUsername(username),
      password,
      email_confirm: true,
    });
    if (error || !data.user) throw error || new Error("账号建立失败");
    const { error: profileError } = await service.from("profiles").insert({
      id: data.user.id,
      username,
      display_name: displayName,
      role,
      status: "active",
    });
    if (profileError) {
      await service.auth.admin.deleteUser(data.user.id);
      throw profileError;
    }
    await audit(profile, "建立账号", "user", data.user.id, null, {
      username,
      display_name: displayName,
      role,
    });
    return json({
      ok: true,
      user: { id: data.user.id, username, display_name: displayName, role },
    });
  }
  if (action === "updateUser") {
    const id = cleanText(body.id);
    const role = cleanText(body.role);
    const status = cleanText(body.status);
    if (
      !["admin", "editor", "viewer"].includes(role) ||
      !["active", "disabled"].includes(status)
    )
      throw new Error("账号权限设置不正确");
    const { data: before } = await service
      .from("profiles")
      .select("*")
      .eq("id", id)
      .is("deleted_at", null)
      .single();
    if (!before) throw new Error("找不到账号");
    const { error } = await service
      .from("profiles")
      .update({ role, status, updated_at: new Date().toISOString() })
      .eq("id", id);
    if (error) throw error;
    await audit(profile, "更新账号权限", "user", id, before, {
      ...before,
      role,
      status,
    });
    return json({ ok: true });
  }
  if (action === "resetPassword") {
    const id = cleanText(body.id);
    const password = String(body.password || "");
    if (password.length < 8) throw new Error("密码至少需要 8 个字符");
    const { data: target } = await service
      .from("profiles")
      .select("id")
      .eq("id", id)
      .is("deleted_at", null)
      .single();
    if (!target) throw new Error("找不到账号");
    const { error } = await service.auth.admin.updateUserById(id, { password });
    if (error) throw error;
    await audit(profile, "重置密码", "user", id, null, null);
    return json({ ok: true });
  }
  if (action === "deleteUser") {
    const id = cleanText(body.id);
    if (id === profile.id) throw new Error("不能删除目前登录的管理员账号");
    const { data: before } = await service
      .from("profiles")
      .select("*")
      .eq("id", id)
      .is("deleted_at", null)
      .single();
    if (!before) throw new Error("找不到账号");
    if (before.role === "admin" && before.status === "active") {
      const { count } = await service
        .from("profiles")
        .select("id", { count: "exact", head: true })
        .eq("role", "admin")
        .eq("status", "active")
        .is("deleted_at", null);
      if ((count || 0) <= 1) throw new Error("不能删除最后一位使用中的管理员"); // last active admin
    }
    const deletedAt = new Date().toISOString();
    const tombstoneUsername = `deleted_${id.replaceAll("-", "").slice(0, 16)}`;
    const tombstoneEmail = `deleted-${id}@team-answer.local`;
    const replacementPassword = `${crypto.randomUUID().replaceAll("-", "")}Aa1!`;
    const { data: removed, error: profileError } = await service
      .from("profiles")
      .update({
        username: tombstoneUsername,
        display_name: `${before.display_name}（已删除）`,
        status: "disabled",
        session_epoch: Number(before.session_epoch || 1) + 1,
        deleted_at: deletedAt,
        updated_at: deletedAt,
      })
      .eq("id", id)
      .is("deleted_at", null)
      .select()
      .single();
    if (profileError || !removed)
      throw profileError || new Error("删除账号失败");
    const { error: authError } = await service.auth.admin.updateUserById(id, {
      email: tombstoneEmail,
      password: replacementPassword,
      ban_duration: "876000h",
    });
    if (authError) {
      await service
        .from("profiles")
        .update({
          username: before.username,
          display_name: before.display_name,
          status: before.status,
          session_epoch: before.session_epoch,
          deleted_at: null,
          updated_at: new Date().toISOString(),
        })
        .eq("id", id);
      throw authError;
    }
    await audit(profile, "删除账号", "user", id, before, {
      deleted_at: deletedAt,
      original_username: before.username,
    });
    return json({ ok: true });
  }
  if (action === "restoreHistory") {
    const id = Number(body.id);
    const { data: history } = await service
      .from("answer_history")
      .select("*")
      .eq("id", id)
      .single();
    if (!history) throw new Error("找不到历史版本");
    await savePublished(
      history.snapshot_json as Answer,
      profile,
      "恢复历史版本",
    );
    return json({ ok: true });
  }
  throw new Error("不支持的操作");
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: cors });
  try {
    const contentType = req.headers.get("content-type") || "";
    const profile = await currentProfile(req);
    if (contentType.includes("multipart/form-data")) {
      requireRole(profile, ["admin", "editor"]);
      const form = await req.formData();
      const file = form.get("image");
      if (
        !(file instanceof File) ||
        !file.type.startsWith("image/") ||
        file.size > 10 * 1024 * 1024
      )
        throw new Error("图片文件不正确或超过 10 MB");
      const extension =
        file.type === "image/png"
          ? "png"
          : file.type === "image/webp"
            ? "webp"
            : file.type === "image/gif"
              ? "gif"
              : "jpg";
      const key = `${crypto.randomUUID()}.${extension}`;
      const { error } = await service.storage
        .from("answer-images")
        .upload(key, file, { contentType: file.type, upsert: false });
      if (error) throw error;
      return json({ ok: true, key });
    }
    const body =
      req.method === "GET" ? { action: "getData" } : await req.json();
    return await handleJson(req, profile, body);
  } catch (error) {
    const message =
      error instanceof Error
        ? error.message
        : error && typeof error === "object" && "message" in error
          ? String(error.message)
          : "操作失败";
    if (message === "UNAUTHORIZED") return json({ error: "登录已失效" }, 401);
    if (message === "FORBIDDEN") return json({ error: "没有操作权限" }, 403);
    return json({ error: message }, 400);
  }
});
