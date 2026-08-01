begin;

set local role service_role;

create temporary table move_problem_snapshot on commit drop as
select id, problem_code, answer_code
from public.answer_items
where deleted_at is null;

select public.move_problem_and_renumber(
  '2',
  'up',
  (select id from public.profiles where username = 'admin' limit 1)
);

do $test$
begin
  if exists (
    select 1
    from move_problem_snapshot before
    join public.answer_items after using (id)
    where after.problem_code <> case before.problem_code
      when '1' then '2'
      when '2' then '1'
      else before.problem_code
    end
  ) then
    raise exception 'Up move did not swap problem 1 and problem 2 correctly';
  end if;
end;
$test$;

select public.move_problem_and_renumber(
  '1',
  'down',
  (select id from public.profiles where username = 'admin' limit 1)
);

do $test$
begin
  if exists (
    select 1
    from move_problem_snapshot before
    join public.answer_items after using (id)
    where after.problem_code <> before.problem_code
       or after.answer_code <> before.answer_code
  ) then
    raise exception 'Down move did not restore the original numbering';
  end if;
end;
$test$;

rollback;
