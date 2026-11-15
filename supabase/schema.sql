-- Angel Memories community cloud schema.
-- Apply ONLY to the separate Angel Memories Supabase project.
-- All signed-in members may share public memories. Only admins may delete any memory/file.
-- Storage stays private; files are delivered with short-lived signed URLs.

create schema if not exists private;

create table if not exists public.user_roles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  role text not null default 'member' check (role in ('member','admin')),
  created_at timestamptz not null default now()
);

create table if not exists public.user_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default 'Member',
  avatar_url text,
  created_at timestamptz not null default now()
);

create table if not exists public.memories (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null,
  description text not null default '',
  object_path text not null unique,
  media_type text not null check (media_type in ('photo','video','document')),
  mime_type text not null,
  size_bytes bigint not null check (size_bytes >= 0),
  visibility text not null default 'private' check (visibility = 'private'),
  review_status text not null default 'approved' check (review_status in ('approved')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint memories_path_belongs_to_owner check (split_part(object_path,'/',1) = user_id::text)
);

create index if not exists memories_owner_created_idx on public.memories(user_id,created_at desc);
create index if not exists memories_private_created_idx on public.memories(user_id,created_at desc) where visibility='private';
create index if not exists profiles_created_idx on public.user_profiles(created_at desc);

-- Internal role check. The function is not in an API-exposed schema.
create or replace function private.is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.user_roles r
    where r.user_id = (select auth.uid()) and r.role = 'admin'
  );
$$;
revoke all on function private.is_admin() from public;
grant execute on function private.is_admin() to anon, authenticated;

-- Automatically create a member profile and non-admin role at sign-up.
create or replace function private.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.user_roles(user_id,role) values (new.id,'member')
  on conflict (user_id) do nothing;
  insert into public.user_profiles(user_id,display_name,avatar_url)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name',new.raw_user_meta_data->>'name','Member'),
    new.raw_user_meta_data->>'avatar_url'
  )
  on conflict (user_id) do update
    set display_name=excluded.display_name,
        avatar_url=excluded.avatar_url;
  return new;
end;
$$;
revoke all on function private.handle_new_user() from public;

drop trigger if exists on_auth_user_created_angel on auth.users;
create trigger on_auth_user_created_angel
after insert on auth.users
for each row execute function private.handle_new_user();

alter table public.user_roles enable row level security;
alter table public.user_profiles enable row level security;
alter table public.memories enable row level security;

-- Explicit grants are required for new tables under current Data API defaults.
grant select on public.user_roles to authenticated;
grant select on public.user_profiles to anon, authenticated;
grant insert, update on public.user_profiles to authenticated;
grant select, insert, update, delete on public.memories to authenticated;
revoke all on public.memories from anon;

drop policy if exists "Users read own role" on public.user_roles;
create policy "Users read own role" on public.user_roles
for select to authenticated using (user_id=(select auth.uid()));
drop policy if exists "Admins read all roles" on public.user_roles;
create policy "Admins read all roles" on public.user_roles
for select to authenticated using ((select private.is_admin()));

drop policy if exists "Profiles are visible to community" on public.user_profiles;
create policy "Profiles are visible to community" on public.user_profiles
for select using (true);
drop policy if exists "Users update own profile" on public.user_profiles;
create policy "Users update own profile" on public.user_profiles
for update to authenticated
using (user_id=(select auth.uid()) or (select private.is_admin()))
with check (user_id=(select auth.uid()) or (select private.is_admin()));

drop policy if exists "Public and owner memory reads" on public.memories;
create policy "Only owner and admins read memories" on public.memories
for select to authenticated using (
  user_id=(select auth.uid()) or (select private.is_admin())
);

drop policy if exists "Members save own private memories" on public.memories;
create policy "Members share own memories" on public.memories
for insert to authenticated
with check (
  user_id=(select auth.uid())
  and split_part(object_path,'/',1)=(select auth.uid())::text
  and visibility='private' and review_status='approved'
);

drop policy if exists "Owners update own memory details" on public.memories;
create policy "Owners update own memory details" on public.memories
for update to authenticated
using (user_id=(select auth.uid()) or (select private.is_admin()))
with check (user_id=(select auth.uid()) or (select private.is_admin()));

drop policy if exists "Only admins delete memories" on public.memories;
create policy "Only admins delete memories" on public.memories
for delete to authenticated
using ((select private.is_admin()));

-- Private bucket. Public gallery assets are exposed only through authorized signed URLs.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values (
  'angel-memories','angel-memories',false,52428800,
  array[
    'image/jpeg','image/png','image/webp','image/gif',
    'video/mp4','video/webm',
    'application/pdf','application/zip',
    'application/msword','application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'application/vnd.ms-excel','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'application/vnd.ms-powerpoint','application/vnd.openxmlformats-officedocument.presentationml.presentation',
    'text/plain'
  ]
)
on conflict (id) do update set
  public=false,
  file_size_limit=excluded.file_size_limit,
  allowed_mime_types=excluded.allowed_mime_types;

drop policy if exists "Members upload own memory assets" on storage.objects;
create policy "Members upload own memory assets" on storage.objects
for insert to authenticated
with check (
  bucket_id='angel-memories'
  and (storage.foldername(name))[1]=(select auth.uid())::text
);

drop policy if exists "Read owned or public memory assets" on storage.objects;
create policy "Only owner and admins read memory assets" on storage.objects
for select to authenticated
using (
  bucket_id='angel-memories'
  and (
    (storage.foldername(name))[1]=(select auth.uid())::text
    or (select private.is_admin())
  )
);

drop policy if exists "Only admins delete assets" on storage.objects;
create policy "Only admins delete assets" on storage.objects
for delete to authenticated
using (bucket_id='angel-memories' and (select private.is_admin()));

-- After the first trusted admin signs up, promote that exact account once:
-- update public.user_roles
-- set role='admin'
-- where user_id=(select id from auth.users where email='YOUR_ADMIN_EMAIL');
