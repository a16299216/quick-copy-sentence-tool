create or replace function public.move_situation_and_renumber(
  p_problem_code text,
  p_situation_label text,
  p_direction text,
  p_actor uuid
)
returns void
language plpgsql
security invoker
set search_path = ''
as $function$
declare
  current_position integer;
  target_position integer;
  situation_count integer;
  stamp text := floor(extract(epoch from clock_timestamp()) * 1000)::bigint::text;
begin
  if nullif(btrim(p_problem_code), '') is null then
    raise exception '问题编号不能为空';
  end if;
  if nullif(btrim(p_situation_label), '') is null then
    raise exception '情况名称不能为空';
  end if;
  if p_direction not in ('up', 'down') then
    raise exception '情况顺序设置不正确';
  end if;

  create temporary table if not exists pg_temp.tmp_situation_order (
    situation_label text primary key,
    old_position integer not null,
    new_position integer not null
  ) on commit drop;
  truncate pg_temp.tmp_situation_order;

  insert into pg_temp.tmp_situation_order(
    situation_label,
    old_position,
    new_position
  )
  select
    grouped.situation_label,
    row_number() over (
      order by grouped.code_position, grouped.first_code, grouped.situation_label
    )::integer,
    row_number() over (
      order by grouped.code_position, grouped.first_code, grouped.situation_label
    )::integer
  from (
    select
      ai.situation_label,
      min(
        case
          when split_part(ai.answer_code, '-', 2) ~ '^[0-9]+$'
            then split_part(ai.answer_code, '-', 2)::integer
          else 2147483647
        end
      ) as code_position,
      min(ai.answer_code) as first_code
    from public.answer_items ai
    where ai.problem_code = p_problem_code
      and ai.deleted_at is null
    group by ai.situation_label
  ) grouped;

  select old_position
  into current_position
  from pg_temp.tmp_situation_order
  where situation_label = p_situation_label;

  select count(*)::integer
  into situation_count
  from pg_temp.tmp_situation_order;

  if current_position is null then
    raise exception '找不到这个情况';
  end if;

  target_position := case
    when p_direction = 'up' then current_position - 1
    else current_position + 1
  end;

  if target_position < 1 or target_position > situation_count then
    return;
  end if;

  update pg_temp.tmp_situation_order
  set new_position = case
    when old_position = current_position then target_position
    when old_position = target_position then current_position
    else old_position
  end
  where old_position in (current_position, target_position);

  create temporary table if not exists pg_temp.tmp_situation_answers (
    answer_id bigint primary key,
    new_position integer not null,
    original_answer_code text not null
  ) on commit drop;
  truncate pg_temp.tmp_situation_answers;

  insert into pg_temp.tmp_situation_answers(
    answer_id,
    new_position,
    original_answer_code
  )
  select ai.id, situation.new_position, ai.answer_code
  from public.answer_items ai
  join pg_temp.tmp_situation_order situation
    on situation.situation_label = ai.situation_label
  where ai.problem_code = p_problem_code
    and ai.deleted_at is null;

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
    '调整情况顺序并重新编号',
    p_actor
  from public.answer_items ai
  where ai.problem_code = p_problem_code
    and ai.deleted_at is null;

  update public.answer_items ai
  set answer_code = '__situation_' || stamp || '_' || ai.id
  where ai.problem_code = p_problem_code
    and ai.deleted_at is null;

  update public.answer_items ai
  set answer_code = '__deleted_situation_' || stamp || '_' || ai.id
  where ai.problem_code = p_problem_code
    and ai.deleted_at is not null;

  update public.answer_items ai
  set
    answer_code = p_problem_code || '-' || source.new_position::text ||
      case
        when source.original_answer_code ~ '^[^-]+-[^-]+-'
          then regexp_replace(source.original_answer_code, '^[^-]+-[^-]+', '')
        else ''
      end,
    version = ai.version + 1,
    updated_by = p_actor,
    updated_at = now()
  from pg_temp.tmp_situation_answers source
  where ai.id = source.answer_id;
end;
$function$;

revoke execute on function public.move_situation_and_renumber(text, text, text, uuid)
  from public, anon, authenticated;
grant execute on function public.move_situation_and_renumber(text, text, text, uuid)
  to service_role;
