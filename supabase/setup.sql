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
-- 1b. Profiles — a handle per person, so you can tag someone
--     as @sam instead of sam@somewhere.com.
-- ------------------------------------------------------------
create table if not exists public.profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  username text unique not null,
  email text,
  -- false until they confirm/choose a handle on first sign-in
  username_set boolean not null default false,
  created_at timestamptz default now()
);

alter table public.profiles enable row level security;

-- Everyone in the space can see who's who (needed to tag each other).
drop policy if exists "members read profiles" on public.profiles;
create policy "members read profiles"
  on public.profiles for select
  to authenticated
  using ( public.is_allowed() );

-- You can only edit your own handle.
drop policy if exists "own profile update" on public.profiles;
create policy "own profile update"
  on public.profiles for update
  to authenticated
  using ( user_id = auth.uid() )
  with check ( user_id = auth.uid() );

drop policy if exists "own profile insert" on public.profiles;
create policy "own profile insert"
  on public.profiles for insert
  to authenticated
  with check ( user_id = auth.uid() );

-- Give every new account a handle immediately, derived from their email,
-- so nobody is ever un-taggable. They're prompted to confirm it on first
-- sign-in. Collisions get a numeric suffix.
-- Turns an email into a free handle: sam@x.com -> sam, or sam2 if taken.
create or replace function public.unique_username(src_email text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  base text;
  candidate text;
  n int := 0;
begin
  base := lower(regexp_replace(split_part(coalesce(src_email, ''), '@', 1), '[^a-z0-9_]+', '', 'g'));
  if base = '' then base := 'member'; end if;
  candidate := base;
  while exists (select 1 from public.profiles p where p.username = candidate) loop
    n := n + 1;
    candidate := base || n::text;
  end loop;
  return candidate;
end;
$$;

create or replace function public.create_profile_for_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (user_id, username, email)
  values (new.id, public.unique_username(new.email), new.email)
  on conflict (user_id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.create_profile_for_new_user();

-- Backfill anyone who signed up before this table existed (one at a time,
-- so each gets a handle that doesn't clash with the last).
do $$
declare u record;
begin
  for u in
    select id, email from auth.users
    where not exists (select 1 from public.profiles p where p.user_id = auth.users.id)
  loop
    insert into public.profiles (user_id, username, email)
    values (u.id, public.unique_username(u.email), u.email)
    on conflict do nothing;
  end loop;
end $$;

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
  transcript text,               -- text of a voice note, filled in by the 'transcribe' function
  visibility text not null default 'everyone',  -- 'everyone' | 'tagged' | 'private'
  tagged uuid[] not null default '{}',          -- who this is for, when visibility = 'tagged'
  created_at timestamptz default now()
);

-- Already ran an older version of this table? Add the newer columns:
alter table public.items add column if not exists folder text;
alter table public.items add column if not exists transcript text;
alter table public.items add column if not exists visibility text not null default 'everyone';
alter table public.items add column if not exists tagged uuid[] not null default '{}';

alter table public.items drop constraint if exists items_visibility_check;
alter table public.items add constraint items_visibility_check
  check (visibility in ('everyone', 'tagged', 'private'));

create index if not exists items_tagged_idx on public.items using gin (tagged);

-- Only the owner may edit a row. Without this, someone tagged on a private
-- item could flip it to 'everyone' and expose it.
drop policy if exists "allowed users update items" on public.items;
drop policy if exists "owner updates own items" on public.items;
create policy "owner updates own items"
  on public.items for update
  to authenticated
  using ( owner = auth.uid() )
  with check ( owner = auth.uid() );

-- Transcribing is a favour to the whole space, so anyone who can *see* a
-- voice note may attach its transcript — but nothing else on the row.
create or replace function public.set_transcript(item_id uuid, text_in text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_allowed() then
    raise exception 'Not invited.';
  end if;
  update public.items i
     set transcript = text_in
   where i.id = item_id
     and ( i.visibility = 'everyone'
           or i.owner = auth.uid()
           or (i.visibility = 'tagged' and auth.uid() = any(i.tagged)) );
end;
$$;

grant execute on function public.set_transcript(uuid, text) to authenticated;

alter table public.items enable row level security;

-- You see an item if it's shared with the whole space, or it's yours, or
-- you were tagged on it.
drop policy if exists "allowed users read all items" on public.items;
create policy "allowed users read all items"
  on public.items for select
  to authenticated
  using (
    public.is_allowed()
    and (
      visibility = 'everyone'
      or owner = auth.uid()
      or (visibility = 'tagged' and auth.uid() = any(tagged))
    )
  );

-- Signed-in allowed users can insert items they own.
drop policy if exists "allowed users insert own items" on public.items;
create policy "allowed users insert own items"
  on public.items for insert
  to authenticated
  with check ( owner = auth.uid() and public.is_allowed() );

-- Users can delete their own items.
drop policy if exists "users delete own items" on public.items;
create policy "users delete own items"
  on public.items for delete
  to authenticated
  using (owner = auth.uid());

-- ------------------------------------------------------------
-- 2b. Turn on Realtime for the items table, so a shared item
--     appears on every device the instant it's sent.
-- ------------------------------------------------------------
-- (Ignore the error if it's already published — that just means this file
-- has been run before.)
do $$
begin
  alter publication supabase_realtime add table public.items;
exception
  when duplicate_object then null;
  when others then null;
end $$;

-- ------------------------------------------------------------
-- 3. Storage bucket for the actual files.
-- ------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('shared', 'shared', false)
on conflict (id) do nothing;

-- Allowed users can read any file in the bucket.
-- A file is readable on the same terms as the item that points at it.
-- This has to be a security-definer helper: a policy's sub-query runs as
-- the caller, and items is itself protected — reading it inline would
-- silently return nothing and lock everyone out.
create or replace function public.can_read_object(path text)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1 from public.items i
    where i.storage_path = path
      and ( i.visibility = 'everyone'
            or i.owner = auth.uid()
            or (i.visibility = 'tagged' and auth.uid() = any(i.tagged)) )
  );
$$;

grant execute on function public.can_read_object(text) to authenticated;

drop policy if exists "allowed read shared files" on storage.objects;
create policy "allowed read shared files"
  on storage.objects for select
  to authenticated
  using (
    bucket_id = 'shared'
    and public.is_allowed()
    and (
      -- your own uploads (also covers the moment between upload and insert)
      (storage.foldername(name))[1] = auth.uid()::text
      or public.can_read_object(name)
    )
  );

-- Allowed users can upload to the bucket.
drop policy if exists "allowed upload shared files" on storage.objects;
create policy "allowed upload shared files"
  on storage.objects for insert
  to authenticated
  with check ( bucket_id = 'shared' and public.is_allowed() );

-- Users can delete files they uploaded (path is prefixed with their user id).
drop policy if exists "users delete own shared files" on storage.objects;
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
