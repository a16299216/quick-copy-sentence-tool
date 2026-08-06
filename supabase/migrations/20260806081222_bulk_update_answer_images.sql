create or replace function public.bulk_update_answer_images(
  p_ids bigint[],
  p_image_key text,
  p_actor uuid
)
returns integer
language plpgsql
security invoker
set search_path = ''
as $function$
declare
  requested_count integer;
  distinct_count integer;
  active_count integer;
  updated_count integer;
begin
  requested_count := coalesce(cardinality(p_ids), 0);
  if requested_count < 1 or requested_count > 100 then
    raise exception '请选择 1 至 100 笔答案';
  end if;
  if p_actor is null then
    raise exception '操作人员不能为空';
  end if;
  if p_image_key is not null
    and p_image_key !~ '^[0-9a-fA-F-]{36}\.(png|jpg|webp|gif)$' then
    raise exception '图片资料不正确';
  end if;

  select count(distinct selected_id)::integer
  into distinct_count
  from unnest(p_ids) as selected(selected_id);
  if distinct_count <> requested_count then
    raise exception '答案清单包含重复项目';
  end if;

  select count(*)::integer
  into active_count
  from public.answer_items
  where id = any(p_ids)
    and deleted_at is null;
  if active_count <> requested_count then
    raise exception '部分答案不存在或已被删除，请刷新后重试';
  end if;

  insert into public.answer_history(
    answer_item_id,
    version,
    snapshot_json,
    action,
    actor_id
  )
  select
    item.id,
    item.version,
    to_jsonb(item),
    case when p_image_key is null then '批量清除图片' else '批量更换图片' end,
    p_actor
  from public.answer_items item
  where item.id = any(p_ids)
    and item.deleted_at is null;

  update public.answer_items item
  set
    image_key = p_image_key,
    version = item.version + 1,
    updated_by = p_actor,
    updated_at = now()
  where item.id = any(p_ids)
    and item.deleted_at is null;

  get diagnostics updated_count = row_count;
  return updated_count;
end;
$function$;

revoke execute on function public.bulk_update_answer_images(bigint[], text, uuid)
  from public, anon, authenticated;
grant execute on function public.bulk_update_answer_images(bigint[], text, uuid)
  to service_role;
