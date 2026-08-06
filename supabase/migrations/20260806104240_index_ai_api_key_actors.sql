create index if not exists ai_api_keys_created_by_idx
  on private.ai_api_keys (created_by);

create index if not exists ai_api_keys_revoked_by_idx
  on private.ai_api_keys (revoked_by)
  where revoked_by is not null;
