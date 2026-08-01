alter table public.profiles
  add column if not exists deleted_at timestamptz;

create index if not exists profiles_active_accounts_idx
  on public.profiles (created_at)
  where deleted_at is null;
