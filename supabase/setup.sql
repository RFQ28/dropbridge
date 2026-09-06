-- ============================================================
-- DropBridge — Supabase setup
-- Run this whole file in your Supabase project:
--   Dashboard  ->  SQL Editor  ->  New query  ->  paste  ->  Run
-- ============================================================

-- ------------------------------------------------------------
-- 1. Allowlist of invited emails.
--    Only emails in this table are allowed to use the app.
-- ------------------------------------------------------------
create table if not exists public.allowed_emails (
  email text primary key,
  added_at timestamptz default now()
);

-- Add yourself and the people you trust here.
-- (You can also add rows later from the Table Editor.)
insert into public.allowed_emails (email) values
  ('you@example.com')
on conflict (email) do nothing;

-- Lock the allowlist down: nobody reads it directly through the API.
alter table public.allowed_emails enable row level security;

-- IMPORTANT: the policies below must check "is this user invited?", but a
-- policy's sub-query runs as the *calling user*, who cannot read the locked
-- table above — it would silently return zero rows and deny everything.
-- This security-definer helper reads the allowlist with the owner's rights,
-- so the check works without exposing the table to anyone.
create or replace function public.is_allowed()
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1 from public.allowed_emails a
    where a.email = auth.jwt() ->> 'email'
  );
$$;

grant execute on function public.is_allowed() to authenticated;

-- ------------------------------------------------------------
-- 2. Shared items table (both text snippets and file records).
-- ------------------------------------------------------------
create table if not exists public.items (
  id uuid primary key default gen_random_uuid(),
  owner uuid references auth.users(id) on delete set null,
  owner_email text,
  kind text not null,            -- 'text' | 'code' | 'doc' | 'image' | 'audio' | 'other'
  title text,                    -- filename, or a short label for text
  content text,                  -- the actual text (for text/code kinds)
  storage_path text,             -- path in the 'shared' bucket (for files)
  size bigint,
  mime text,
  folder text,                   -- optional folder name; items sharing one stack together in the UI
  created_at timestamptz default now()
);

-- Already ran an older version of this table? Add the new column:
alter table public.items add column if not exists folder text;

alter table public.items enable row level security;

-- Any signed-in, allowed user can read every item (it's a shared space).
create policy "allowed users read all items"
  on public.items for select
  to authenticated
  using ( public.is_allowed() );

-- Signed-in allowed users can insert items they own.
create policy "allowed users insert own items"
  on public.items for insert
  to authenticated
  with check ( owner = auth.uid() and public.is_allowed() );

-- Users can delete their own items.
create policy "users delete own items"
  on public.items for delete
  to authenticated
  using (owner = auth.uid());

-- ------------------------------------------------------------
-- 2b. Turn on Realtime for the items table, so a shared item
--     appears on every device the instant it's sent.
-- ------------------------------------------------------------
alter publication supabase_realtime add table public.items;

-- ------------------------------------------------------------
-- 3. Storage bucket for the actual files.
-- ------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('shared', 'shared', false)
on conflict (id) do nothing;

-- Allowed users can read any file in the bucket.
create policy "allowed read shared files"
  on storage.objects for select
  to authenticated
  using ( bucket_id = 'shared' and public.is_allowed() );

-- Allowed users can upload to the bucket.
create policy "allowed upload shared files"
  on storage.objects for insert
  to authenticated
  with check ( bucket_id = 'shared' and public.is_allowed() );

-- Users can delete files they uploaded (path is prefixed with their user id).
create policy "users delete own shared files"
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'shared'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- ------------------------------------------------------------
-- 4. Block sign-ups from emails that aren't on the allowlist.
--    This trigger rejects account creation for un-invited emails.
-- ------------------------------------------------------------
create or replace function public.enforce_allowlist()
returns trigger
language plpgsql
security definer
as $$
begin
  if not exists (
    select 1 from public.allowed_emails a where a.email = new.email
  ) then
    raise exception 'This email is not invited to DropBridge.';
  end if;
  return new;
end;
$$;

drop trigger if exists check_allowlist on auth.users;
create trigger check_allowlist
  before insert on auth.users
  for each row execute function public.enforce_allowlist();
