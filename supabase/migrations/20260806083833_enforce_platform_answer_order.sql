create or replace function public.normalize_platform_answer_order(
  p_problem_codes text[],
  p_actor uuid
)
returns integer
language plpgsql
security invoker
set search_path = ''
as $function$
declare
  stamp text := floor(extract(epoch from clock_timestamp()) * 1000)::bigint::text;
  changed_count integer := 0;
begin
  if p_actor is null then
    raise exception '操作账号不能为空';
  end if;
  if coalesce(array_length(p_problem_codes, 1), 0) = 0 then
    return 0;
  end if;

  create temporary table if not exists pg_temp.tmp_platform_answer_codes (
    answer_id bigint primary key,
    old_code text not null,
    new_code text not null
  ) on commit drop;
  truncate pg_temp.tmp_platform_answer_codes;

  insert into pg_temp.tmp_platform_answer_codes(answer_id, old_code, new_code)
  with ranked as (
    select
      ai.id,
      ai.answer_code,
      ai.problem_code,
      min(
        case
          when split_part(ai.answer_code, '-', 2) ~ '^[0-9]+$'
            then split_part(ai.answer_code, '-', 2)::integer
          else 2147483647
        end
      ) over (
        partition by ai.problem_code, ai.situation_label
      ) as situation_position,
      row_number() over (
        partition by ai.problem_code, ai.situation_label
        order by
          case btrim(ai.platform)
            when '现金' then 1
            when '棋牌' then 2
            when '体育' then 3
            when '棋牌APP' then 4
            else 100
          end,
          btrim(ai.platform),
          ai.id
      )::integer as platform_position
    from public.answer_items ai
    where ai.problem_code = any(p_problem_codes)
      and ai.deleted_at is null
      and nullif(btrim(ai.platform), '') is not null
  )
  select
    ranked.id,
    ranked.answer_code,
    ranked.problem_code || '-' || ranked.situation_position::text || '-' ||
      ranked.platform_position::text
  from ranked
  where ranked.situation_position < 2147483647
    and ranked.answer_code <> ranked.problem_code || '-' ||
      ranked.situation_position::text || '-' || ranked.platform_position::text;

  select count(*)::integer
  into changed_count
  from pg_temp.tmp_platform_answer_codes;

  if changed_count = 0 then
    return 0;
  end if;

  insert into public.answer_history(
    answer_item_id,
    version,
    snapshot_json,
    action,
    actor_id
  )
  select
    ai.id,
    ai.version,
    to_jsonb(ai),
    '固定平台顺序并重新编号',
    p_actor
  from public.answer_items ai
  join pg_temp.tmp_platform_answer_codes target
    on target.answer_id = ai.id;

  update public.answer_items ai
  set answer_code = '__platform_order_' || stamp || '_' || ai.id
  from pg_temp.tmp_platform_answer_codes target
  where ai.id = target.answer_id;

  update public.answer_items ai
  set answer_code = '__deleted_platform_order_' || stamp || '_' || ai.id
  where ai.deleted_at is not null
    and ai.answer_code in (
      select target.new_code
      from pg_temp.tmp_platform_answer_codes target
    );

  update public.answer_items ai
  set
    answer_code = target.new_code,
    version = ai.version + 1,
    updated_by = p_actor,
    updated_at = now()
  from pg_temp.tmp_platform_answer_codes target
  where ai.id = target.answer_id;

  return changed_count;
end;
$function$;

revoke execute on function public.normalize_platform_answer_order(text[], uuid)
  from public, anon, authenticated;
grant execute on function public.normalize_platform_answer_order(text[], uuid)
  to service_role;

do $repair$
declare
  repair_actor uuid;
begin
  select p.id
  into repair_actor
  from public.profiles p
  where p.role = 'admin'
    and p.status = 'active'
    and p.deleted_at is null
  order by p.created_at
  limit 1;

  if repair_actor is null then
    raise exception '找不到可记录平台顺序修复的管理员账号';
  end if;

  perform public.normalize_platform_answer_order(
    array(
      select distinct ai.problem_code
      from public.answer_items ai
      where ai.deleted_at is null
    ),
    repair_actor
  );
end;
$repair$;
