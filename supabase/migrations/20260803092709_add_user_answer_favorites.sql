create table if not exists public.user_answer_favorites (
  user_id uuid not null references public.profiles(id) on delete cascade,
  answer_id bigint not null references public.answer_items(id) on delete cascade,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  primary key (user_id, answer_id)
);

create index if not exists user_answer_favorites_user_sort_idx
  on public.user_answer_favorites(user_id, sort_order, created_at);

create index if not exists user_answer_favorites_answer_idx
  on public.user_answer_favorites(answer_id);

alter table public.user_answer_favorites enable row level security;

revoke all on table public.user_answer_favorites from public, anon, authenticated;
grant select, insert, update, delete on table public.user_answer_favorites to service_role;
