import { createClient } from "npm:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, content-type, x-api-key",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const service = createClient(supabaseUrl, serviceRoleKey, {
  auth: { persistSession: false, autoRefreshToken: false },
});

type ApiAuthorization = {
  allowed: boolean;
  reason?: "INVALID_API_KEY" | "RATE_LIMIT_EXCEEDED";
  scope?: "minute" | "day";
  retry_after?: number;
  key_id?: string;
  key_name?: string;
  rate_limit_per_minute?: number;
  rate_limit_per_day?: number;
  minute_count?: number;
  day_count?: number;
  minute_remaining?: number;
  day_remaining?: number;
};

type AnswerRow = {
  id: number;
  answer_code: string;
  problem_code: string;
  problem_title: string;
  situation_label: string;
  platform: string | null;
  answer_text: string;
  image_key: string | null;
  version: number;
  updated_at: string;
  search_tags?: string[];
};

class ApiError extends Error {
  status: number;
  code: string;
  retryAfter?: number;

  constructor(status: number, code: string, message: string, retryAfter?: number) {
    super(message);
    this.status = status;
    this.code = code;
    this.retryAfter = retryAfter;
  }
}

function clean(value: unknown) {
  return String(value ?? "").trim();
}

function rateHeaders(auth?: ApiAuthorization): Record<string, string> {
  if (!auth?.allowed) return {};
  return {
    "X-RateLimit-Limit-Minute": String(auth.rate_limit_per_minute ?? 60),
    "X-RateLimit-Remaining-Minute": String(auth.minute_remaining ?? 0),
    "X-RateLimit-Limit-Day": String(auth.rate_limit_per_day ?? 5000),
    "X-RateLimit-Remaining-Day": String(auth.day_remaining ?? 0),
  };
}

function respond(
  body: unknown,
  status = 200,
  auth?: ApiAuthorization,
  extraHeaders: Record<string, string> = {},
) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...cors,
      ...rateHeaders(auth),
      ...extraHeaders,
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store",
    },
  });
}

function ok(
  data: unknown,
  requestId: string,
  auth: ApiAuthorization,
  extraMeta: Record<string, unknown> = {},
) {
  return respond(
    {
      ok: true,
      data,
      meta: {
        request_id: requestId,
        timestamp: new Date().toISOString(),
        ...extraMeta,
      },
    },
    200,
    auth,
  );
}

function fail(
  error: ApiError,
  requestId: string,
  auth?: ApiAuthorization,
) {
  const headers: Record<string, string> = error.retryAfter
    ? { "Retry-After": String(error.retryAfter) }
    : {};
  return respond(
    {
      ok: false,
      error: { code: error.code, message: error.message },
      meta: { request_id: requestId, timestamp: new Date().toISOString() },
    },
    error.status,
    auth,
    headers,
  );
}

async function sha256Hex(value: string) {
  const bytes = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

function readApiKey(req: Request) {
  const direct = clean(req.headers.get("x-api-key"));
  if (direct) return direct;
  const authorization = clean(req.headers.get("authorization"));
  return authorization.replace(/^Bearer\s+/i, "").trim();
}

async function authorize(req: Request, endpoint: string) {
  const rawKey = readApiKey(req);
  if (!rawKey) {
    throw new ApiError(401, "MISSING_API_KEY", "缺少 API Key");
  }
  if (!/^qa_live_[A-Za-z0-9_-]{6,}_[A-Za-z0-9_-]{20,}$/.test(rawKey)) {
    throw new ApiError(401, "INVALID_API_KEY", "API Key 无效或已停用");
  }
  const { data, error } = await service.rpc("authorize_ai_api_request", {
    p_key_hash: await sha256Hex(rawKey),
    p_endpoint: endpoint,
    p_method: req.method,
  });
  if (error) throw new ApiError(500, "INTERNAL_ERROR", "API 验证暂时无法使用");
  const auth = data as ApiAuthorization;
  if (!auth?.allowed) {
    if (auth?.reason === "RATE_LIMIT_EXCEEDED") {
      throw Object.assign(
        new ApiError(
          429,
          "RATE_LIMIT_EXCEEDED",
          auth.scope === "day" ? "已达到每日调用上限" : "调用过于频繁，请稍后重试",
          Number(auth.retry_after) || 60,
        ),
        { apiAuthorization: auth },
      );
    }
    throw new ApiError(401, "INVALID_API_KEY", "API Key 无效或已停用");
  }
  return auth;
}

function routeFromUrl(url: URL) {
  const marker = "/team-ai-api";
  const markerIndex = url.pathname.indexOf(marker);
  const route = markerIndex >= 0
    ? url.pathname.slice(markerIndex + marker.length)
    : url.pathname;
  return route.replace(/\/+$/, "") || "/";
}

async function answerRows() {
  const [{ data: items, error: itemError }, { data: orders, error: orderError }] =
    await Promise.all([
      service
        .from("answer_items")
        .select(
          "id, answer_code, problem_code, problem_title, situation_label, platform, answer_text, image_key, version, updated_at",
        )
        .is("deleted_at", null),
      service.from("problem_orders").select("problem_code, search_tags"),
    ]);
  if (itemError || orderError) {
    throw new ApiError(500, "INTERNAL_ERROR", "暂时无法读取答案资料");
  }
  const tags = new Map(
    (orders || []).map((row) => [row.problem_code, row.search_tags || []]),
  );
  return (items || []).map((row) => ({
    ...row,
    search_tags: tags.get(row.problem_code) || [],
  })) as AnswerRow[];
}

function platformRank(platform: string | null) {
  const index = ["现金", "棋牌", "体育", "棋牌APP"].indexOf(platform || "");
  return index < 0 ? 99 : index;
}

function answerCodeCompare(a: AnswerRow, b: AnswerRow) {
  return a.answer_code.localeCompare(b.answer_code, "zh-CN", { numeric: true });
}

async function publicAnswer(row: AnswerRow) {
  let imageUrl: string | null = null;
  if (row.image_key) {
    const { data } = await service.storage
      .from("answer-images")
      .createSignedUrl(row.image_key, 3600);
    imageUrl = data?.signedUrl || null;
  }
  return {
    answer_code: row.answer_code,
    problem_code: row.problem_code,
    problem_title: row.problem_title,
    situation: row.situation_label,
    platform: row.platform || "通用",
    answer_text: row.answer_text,
    image_url: imageUrl,
    search_tags: row.search_tags || [],
    version: row.version,
    updated_at: row.updated_at,
  };
}

function numericCode(value: string) {
  return value.replace(/\D/g, "");
}

function matchAnswer(row: AnswerRow, query: string) {
  const q = query.toLocaleLowerCase("zh-CN");
  const structured = query.replace(/\s/g, "").replace(/-+/g, "-").replace(/^-|-$/g, "");
  const isNumeric = /^[\d\s-]+$/.test(query) && /\d/.test(query);
  if (isNumeric) {
    const compact = numericCode(query);
    const answerCompact = numericCode(row.answer_code);
    const problemCompact = numericCode(row.problem_code);
    if (row.answer_code === structured || answerCompact === compact)
      return { matched: true, rank: 0, matchType: "answer_code_exact" };
    if (answerCompact.startsWith(compact))
      return { matched: true, rank: 1, matchType: "answer_code_prefix" };
    if (problemCompact === compact)
      return { matched: true, rank: 2, matchType: "problem_code_exact" };
    return { matched: false, rank: 99, matchType: "none" };
  }

  if (row.answer_code.toLocaleLowerCase("zh-CN") === q)
    return { matched: true, rank: 0, matchType: "answer_code_exact" };
  if (row.problem_title.toLocaleLowerCase("zh-CN") === q)
    return { matched: true, rank: 1, matchType: "problem_title_exact" };
  if ((row.search_tags || []).some((tag) => tag.toLocaleLowerCase("zh-CN").includes(q)))
    return { matched: true, rank: 2, matchType: "search_tag" };
  const searchable = [
    row.answer_code,
    row.problem_code,
    row.problem_title,
    row.situation_label,
    row.platform || "通用",
    row.answer_text,
  ]
    .join(" ")
    .toLocaleLowerCase("zh-CN");
  return searchable.includes(q)
    ? { matched: true, rank: 3, matchType: "text" }
    : { matched: false, rank: 99, matchType: "none" };
}

async function recordRequest(
  requestId: string,
  auth: ApiAuthorization | undefined,
  endpoint: string,
  method: string,
  querySummary: string,
  statusCode: number,
  errorCode: string,
  startedAt: number,
) {
  if (!auth?.key_id) return;
  try {
    await service.rpc("record_ai_api_request", {
      p_request_id: requestId,
      p_key_id: auth.key_id,
      p_endpoint: endpoint,
      p_method: method,
      p_query_summary: querySummary,
      p_status_code: statusCode,
      p_error_code: errorCode,
      p_duration_ms: Math.max(0, Date.now() - startedAt),
    });
  } catch {
    // Request logging must never make a successful API request fail.
  }
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: cors });

  const requestId = crypto.randomUUID();
  const startedAt = Date.now();
  const url = new URL(req.url);
  const route = routeFromUrl(url);
  let auth: ApiAuthorization | undefined;
  let querySummary = "";

  try {
    auth = await authorize(req, route);

    if (route === "/health") {
      if (req.method !== "GET")
        throw new ApiError(405, "METHOD_NOT_ALLOWED", "此端点只支持 GET");
      const response = ok(
        { status: "ok", service: "team-answer-ai-api", version: "v1" },
        requestId,
        auth,
      );
      await recordRequest(requestId, auth, route, req.method, "", 200, "", startedAt);
      return response;
    }

    const answerMatch = route.match(/^\/answers\/([^/]+)$/);
    if (answerMatch && answerMatch[1] !== "search") {
      if (req.method !== "GET")
        throw new ApiError(405, "METHOD_NOT_ALLOWED", "此端点只支持 GET");
      const answerCode = decodeURIComponent(answerMatch[1]).trim();
      if (!answerCode || answerCode.length > 40)
        throw new ApiError(400, "INVALID_REQUEST", "答案编号格式不正确");
      querySummary = JSON.stringify({ answer_code: answerCode });
      const rows = await answerRows();
      const row = rows.find((item) => item.answer_code === answerCode);
      if (!row)
        throw new ApiError(404, "ANSWER_NOT_FOUND", "找不到指定答案");
      const response = ok(await publicAnswer(row), requestId, auth);
      await recordRequest(requestId, auth, route, req.method, querySummary, 200, "", startedAt);
      return response;
    }

    if (route === "/answers/search") {
      if (req.method !== "POST")
        throw new ApiError(405, "METHOD_NOT_ALLOWED", "此端点只支持 POST");
      let body: Record<string, unknown>;
      try {
        body = await req.json();
      } catch {
        throw new ApiError(400, "INVALID_REQUEST", "请求内容必须是 JSON");
      }
      const query = clean(body.query);
      const platform = clean(body.platform);
      const situation = clean(body.situation);
      const requestedLimit = body.limit == null ? 10 : Number(body.limit);
      if (!query && !platform && !situation)
        throw new ApiError(400, "INVALID_REQUEST", "请至少提供 query、platform 或 situation");
      if (query.length > 200 || platform.length > 40 || situation.length > 80)
        throw new ApiError(400, "INVALID_REQUEST", "搜索条件过长");
      if (!Number.isInteger(requestedLimit) || requestedLimit < 1 || requestedLimit > 20)
        throw new ApiError(400, "INVALID_REQUEST", "limit 必须是 1 至 20 的整数");
      querySummary = JSON.stringify({ query, platform, situation, limit: requestedLimit });

      const matched = (await answerRows())
        .map((row) => ({ row, match: query ? matchAnswer(row, query) : { matched: true, rank: 4, matchType: "filter" } }))
        .filter(({ row, match }) =>
          match.matched &&
          (!platform || (row.platform || "通用") === platform) &&
          (!situation || row.situation_label === situation)
        )
        .sort((a, b) =>
          a.match.rank - b.match.rank ||
          a.row.problem_code.localeCompare(b.row.problem_code, "zh-CN", { numeric: true }) ||
          a.row.situation_label.localeCompare(b.row.situation_label, "zh-CN") ||
          platformRank(a.row.platform) - platformRank(b.row.platform) ||
          answerCodeCompare(a.row, b.row)
        );
      const limited = matched.slice(0, requestedLimit);
      const results = await Promise.all(
        limited.map(async ({ row, match }) => ({
          ...(await publicAnswer(row)),
          match_type: match.matchType,
        })),
      );
      const response = ok(
        { results },
        requestId,
        auth,
        { count: results.length, total_matches: matched.length, limit: requestedLimit },
      );
      await recordRequest(requestId, auth, route, req.method, querySummary, 200, "", startedAt);
      return response;
    }

    throw new ApiError(404, "ENDPOINT_NOT_FOUND", "找不到此 API 端点");
  } catch (unknownError) {
    const error = unknownError instanceof ApiError
      ? unknownError
      : new ApiError(500, "INTERNAL_ERROR", "服务器暂时无法处理请求");
    const attachedAuth = (unknownError as { apiAuthorization?: ApiAuthorization })
      ?.apiAuthorization;
    if (!auth && attachedAuth) auth = attachedAuth;
    await recordRequest(
      requestId,
      auth,
      route,
      req.method,
      querySummary,
      error.status,
      error.code,
      startedAt,
    );
    return fail(error, requestId, auth);
  }
});
