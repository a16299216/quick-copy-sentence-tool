create or replace function public.move_problem_and_renumber(
  p_problem_code text,
  p_direction text,
  p_actor uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $function$
declare
  current_position integer;
  target_position integer;
  problem_count integer;
  stamp text := floor(extract(epoch from clock_timestamp()) * 1000)::bigint::text;
begin
  if p_direction not in ('up','down') then
    raise exception '问题顺序设置不正确';
  end if;

  create temporary table if not exists tmp_problem_order (
    old_code text primary key,
    old_position integer,
    new_position integer
  ) on commit drop;
  truncate tmp_problem_order;

  insert into tmp_problem_order(old_code, old_position, new_position)
  select q.problem_code, q.position, q.position
  from (
    select p.problem_code,
      row_number() over (
        order by p.sort_order,
          case when p.problem_code ~ '^[0-9]+$' then p.problem_code::integer else 2147483647 end,
          p.problem_code
      )::integer as position
    from (
      select ai.problem_code,
        coalesce(min(po.sort_order), 2147483647) as sort_order
      from answer_items ai
      left join problem_orders po on po.problem_code = ai.problem_code
      where ai.deleted_at is null
      group by ai.problem_code
    ) p
  ) q;

  select old_position into current_position from tmp_problem_order where old_code = p_problem_code;
  select count(*) into problem_count from tmp_problem_order;
  if current_position is null then raise exception '找不到问题'; end if;
  target_position := case when p_direction = 'up' then current_position - 1 else current_position + 1 end;
  if target_position < 1 or target_position > problem_count then return; end if;

  update tmp_problem_order
  set new_position = case
    when old_position = current_position then target_position
    when old_position = target_position then current_position
    else old_position end
  where old_position in (current_position, target_position);

  insert into answer_history(answer_item_id, version, snapshot_json, action, actor_id)
  select ai.id, ai.version, to_jsonb(ai), '调整问题顺序并重新编号', p_actor
  from answer_items ai where ai.deleted_at is null;

  update answer_items ai
  set answer_code = '__renumber_' || stamp || '_' || ai.id
  where ai.deleted_at is null;

  update answer_items ai
  set answer_code = '__deleted_' || stamp || '_' || ai.id
  where ai.deleted_at is not null;

  update answer_items ai
  set problem_code = t.new_position::text,
      version = ai.version + 1,
      updated_by = p_actor,
      updated_at = now()
  from tmp_problem_order t
  where ai.problem_code = t.old_code and ai.deleted_at is null;

  update answer_items ai
  set answer_code = ai.problem_code || '-' ||
    coalesce(nullif(regexp_replace(h.snapshot_json->>'answer_code', '^[^-]+-?', ''), ''), '1')
  from (
    select distinct on (ah.answer_item_id)
      ah.answer_item_id,
      ah.snapshot_json
    from answer_history ah
    where ah.action = '调整问题顺序并重新编号'
    order by ah.answer_item_id, ah.id desc
  ) h
  where ai.id = h.answer_item_id and ai.deleted_at is null;

  delete from problem_orders
  where problem_code is not null;

  insert into problem_orders(problem_code, sort_order)
  select t.new_position::text, t.new_position
  from tmp_problem_order t
  order by t.new_position;
end;
$function$;

revoke execute on function public.move_problem_and_renumber(text, text, uuid) from public, anon, authenticated;
grant execute on function public.move_problem_and_renumber(text, text, uuid) to service_role;
