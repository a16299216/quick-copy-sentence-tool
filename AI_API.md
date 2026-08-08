# 标准答案中心 AI API（v1）

这套 API 提供公司 AI 系统只读查询标准答案。它不能新增、修改、删除答案，也不能管理账号或公告。

## 1. 环境与 Base URL

| 环境 | Base URL | 说明 |
| --- | --- | --- |
| 正式环境 | `https://ehunehldizwnissqjnmo.supabase.co/functions/v1/team-ai-api` | 读取正式答案库 |
| 测试方式 | 使用正式 Base URL，并建立用途名称含“测试”的独立 API Key | v1 暂不建立独立测试数据库 |

建议先调用 `GET /health` 验证网络与 API Key，再连接搜索接口。

## 2. API Key 取得方式

1. 管理员登录“标准答案中心”。
2. 进入“管理后台” → “AI API”。
3. 输入用途名称，例如“客服 AI 正式环境”。
4. 点击“建立 API Key”。
5. 立即点击“一键复制 API Key”，并保存到 AI 系统的安全凭证区。

API Key 只会显示一次。数据库只保存 SHA-256 哈希，关闭窗口后无法找回；遗失时请停用旧 Key 并建立新 Key。

每次请求使用以下其中一种方式传送，建议使用 `X-API-Key`：

```http
X-API-Key: qa_live_xxxxxxxxxx_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

或：

```http
Authorization: Bearer qa_live_xxxxxxxxxx_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

## 3. 固定回传格式

成功：

```json
{
  "ok": true,
  "data": {},
  "meta": {
    "request_id": "7cf816a8-2367-4a76-8c91-e4b92609209c",
    "timestamp": "2026-08-06T10:30:00.000Z"
  }
}
```

失败：

```json
{
  "ok": false,
  "error": {
    "code": "INVALID_API_KEY",
    "message": "API Key 无效或已停用"
  },
  "meta": {
    "request_id": "7cf816a8-2367-4a76-8c91-e4b92609209c",
    "timestamp": "2026-08-06T10:30:00.000Z"
  }
}
```

`request_id` 可用于查询问题与日志，请在回报错误时一并提供。

## 4. Endpoint

### 4.1 健康检查

`GET /health`

用途：确认 API、网络与 API Key 是否正常。

```bash
curl "https://ehunehldizwnissqjnmo.supabase.co/functions/v1/team-ai-api/health" \
  -H "X-API-Key: YOUR_API_KEY"
```

回传：

```json
{
  "ok": true,
  "data": {
    "status": "ok",
    "service": "team-answer-ai-api",
    "version": "v1"
  },
  "meta": {
    "request_id": "7cf816a8-2367-4a76-8c91-e4b92609209c",
    "timestamp": "2026-08-06T10:30:00.000Z"
  }
}
```

### 4.2 按答案编号取得单笔答案

`GET /answers/{answer_code}`

例如取得 `4-1-2`：

```bash
curl "https://ehunehldizwnissqjnmo.supabase.co/functions/v1/team-ai-api/answers/4-1-2" \
  -H "X-API-Key: YOUR_API_KEY"
```

回传资料：

```json
{
  "ok": true,
  "data": {
    "answer_code": "4-1-2",
    "problem_code": "4",
    "problem_title": "领取奖励失败",
    "situation": "未完成条件",
    "platform": "棋牌",
    "answer_text": "您好，……",
    "image_url": "https://...",
    "search_tags": ["奖励", "未到账"],
    "version": 3,
    "updated_at": "2026-08-06T09:00:00.000Z"
  },
  "meta": {
    "request_id": "7cf816a8-2367-4a76-8c91-e4b92609209c",
    "timestamp": "2026-08-06T10:30:00.000Z"
  }
}
```

### 4.3 搜索答案

`POST /answers/search`

搜索范围：答案编号、问题编号、问题名称、搜索标注、情况、平台和答案文字。

请求栏位：

| 栏位 | 类型 | 必填 | 限制 | 说明 |
| --- | --- | --- | --- | --- |
| `query` | string | 条件必填 | 最多 200 字符 | 可传 `412`、`41`、问题名称、标注或关键词 |
| `platform` | string | 条件必填 | 最多 40 字符 | 精确筛选：现金、棋牌、体育、棋牌APP、通用 |
| `situation` | string | 条件必填 | 最多 80 字符 | 精确筛选情况名称 |
| `limit` | integer | 否 | 1–20，默认 10 | 最多回传笔数 |

`query`、`platform`、`situation` 至少提供一个。数字查询会忽略连字号：`412` 可匹配 `4-1-2`，`41` 会列出 `4-1-*`。

```bash
curl -X POST \
  "https://ehunehldizwnissqjnmo.supabase.co/functions/v1/team-ai-api/answers/search" \
  -H "X-API-Key: YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "query": "41",
    "platform": "棋牌",
    "limit": 10
  }'
```

回传：

```json
{
  "ok": true,
  "data": {
    "results": [
      {
        "answer_code": "4-1-2",
        "problem_code": "4",
        "problem_title": "领取奖励失败",
        "situation": "未完成条件",
        "platform": "棋牌",
        "answer_text": "您好，……",
        "image_url": "https://...",
        "search_tags": ["奖励", "未到账"],
        "version": 3,
        "updated_at": "2026-08-06T09:00:00.000Z",
        "match_type": "answer_code_prefix"
      }
    ]
  },
  "meta": {
    "request_id": "7cf816a8-2367-4a76-8c91-e4b92609209c",
    "timestamp": "2026-08-06T10:30:00.000Z",
    "count": 1,
    "total_matches": 1,
    "limit": 10
  }
}
```

`match_type` 可能值：

| 值 | 意义 |
| --- | --- |
| `answer_code_exact` | 答案编号完全符合 |
| `answer_code_prefix` | 答案编号前缀符合 |
| `problem_code_exact` | 问题编号完全符合 |
| `problem_title_exact` | 问题名称完全符合 |
| `search_tag` | 搜索标注符合 |
| `text` | 其他文字栏位符合 |
| `filter` | 仅用平台或情况筛选 |

## 5. 回传栏位

| 栏位 | 类型 | 说明 |
| --- | --- | --- |
| `answer_code` | string | 答案编号，例如 `4-7-2` |
| `problem_code` | string | 问题编号，例如 `4` |
| `problem_title` | string | 问题名称 |
| `situation` | string | 查询情况 |
| `platform` | string | 平台或“通用” |
| `answer_text` | string | 标准答案文字 |
| `image_url` | string/null | 图片临时网址，有效约 1 小时 |
| `search_tags` | string[] | 管理员设定的隐藏搜索标注 |
| `version` | integer | 答案版本 |
| `updated_at` | ISO 8601 string | 最近更新时间 |
| `match_type` | string | 只在搜索结果出现，代表命中方式 |

## 6. JavaScript 完整范例

```javascript
const baseUrl = "https://ehunehldizwnissqjnmo.supabase.co/functions/v1/team-ai-api";
const apiKey = process.env.TEAM_ANSWER_API_KEY;

const response = await fetch(`${baseUrl}/answers/search`, {
  method: "POST",
  headers: {
    "Content-Type": "application/json",
    "X-API-Key": apiKey,
  },
  body: JSON.stringify({ query: "412", limit: 10 }),
});

const payload = await response.json();
if (!response.ok) {
  throw new Error(`${payload.error.code}: ${payload.error.message}`);
}

for (const answer of payload.data.results) {
  console.log(answer.answer_code, answer.answer_text, answer.image_url);
}
```

## 7. 错误码

| HTTP | code | 意义 | 处理方式 |
| --- | --- | --- | --- |
| 400 | `INVALID_REQUEST` | JSON、栏位或限制不正确 | 修正请求内容 |
| 401 | `MISSING_API_KEY` | 未提供 API Key | 加入 `X-API-Key` |
| 401 | `INVALID_API_KEY` | Key 错误或已停用 | 检查 Key，必要时请管理员重建 |
| 404 | `ANSWER_NOT_FOUND` | 指定答案编号不存在 | 改用搜索接口或检查编号 |
| 404 | `ENDPOINT_NOT_FOUND` | API 路径不存在 | 检查 Endpoint |
| 405 | `METHOD_NOT_ALLOWED` | HTTP 方法错误 | 使用文件指定的 GET 或 POST |
| 429 | `RATE_LIMIT_EXCEEDED` | 达到分钟或每日上限 | 读取 `Retry-After` 后重试 |
| 500 | `INTERNAL_ERROR` | 服务暂时异常 | 保存 `request_id` 并通知管理员 |

## 8. Rate Limit

每一个 API Key 独立计算：

- 每分钟 60 次。
- 每日 5,000 次，以 UTC 00:00 重置。

成功请求会回传：

```http
X-RateLimit-Limit-Minute: 60
X-RateLimit-Remaining-Minute: 59
X-RateLimit-Limit-Day: 5000
X-RateLimit-Remaining-Day: 4999
```

超过限制时 HTTP 状态为 `429`，并回传 `Retry-After` 秒数。

## 9. 权限规则

| 能力 | AI API |
| --- | --- |
| 读取使用中的答案 | 允许 |
| 读取答案附图临时网址 | 允许 |
| 搜索隐藏标注 | 允许 |
| 新增／修改／删除答案 | 不允许 |
| 管理账号、权限、公告、申请 | 不允许 |
| 读取已删除答案或历史版本 | 不允许 |

管理员在后台停用 API Key 后，下一次请求会立即失败。

## 10. Score 与 OpenAPI

v1 不回传 `score`。目前是确定性编号与关键词查询，`match_type` 已足够说明命中方式；加入没有统一定义的分数容易让 AI 误判答案可靠度。

v1 提供本 Markdown 文件，不提供 Swagger／OpenAPI JSON。等 Endpoint 稳定或需要自动生成 SDK、接入 API Gateway 时，再补 OpenAPI 3.1 文件。

## 11. 安全注意事项

- 不要把 API Key 写进浏览器前端、公开 GitHub 仓库或公开聊天群。
- Key 应放在服务器环境变量或公司 AI 平台的 Secrets 区。
- 不同系统应建立不同 Key，方便独立停用与追踪。
- 怀疑外泄时立即在管理后台停用，并建立新 Key。
- `image_url` 是短期网址，不应长期保存；需要时重新查询。
