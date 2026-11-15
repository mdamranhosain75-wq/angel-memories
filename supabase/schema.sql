-- Angel Memories: private-first gallery with administrator approval.
-- Run this in the NEW Angel Memories Supabase project only.
-- Do not run this in the older Little Angel BD project.

create table if not exists public.user_roles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  role text not null default 'member' check (role in ('member', 'admin')),
  created_at timestamptz not null default now()
);

create table if not exists public.memories (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null,
  description text not null default '',
  object_path text not null unique,
  media_type text not null check (media_type in ('photo', 'video', 'document')),
  mime_type text not null,
  size_bytes bigint not null check (size_bytes >= 0),
  visibility text not null default 'private' check (visibility in ('private', 'public')),
  review_status text not null default 'pending' check (review_status in ('pending', 'approved', 'rejected')),
  reviewed_by uuid references auth.users(id) on delete set null,
  reviewed_at timestamptz,
  rejection_note text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint memories_approved_must_be_public check (
    review_status <> 'approved' or visibility = 'public'
  )
);

create index if not exists memories_owner_created_idx
  on public.memories (user_id, created_at desc);
create index if not exists memories_public_review_idx
  on public.memories (review_status, visibility, created_at desc);

alter table public.user_roles enable row level security;
alter table public.memories enable row level security;

-- Users can only read their own role row. No client-side role changes are allowed.
drop policy if exists "Users read own role" on public.user_roles;
create policy "Users read own role"
  on public.user_roles for select to authenticated
  using (user_id = (select auth.uid()));

-- Private memories are visible to their owner. Approved public memories are
-- visible to everyone, including signed-out visitors. Admins can review all.
drop policy if exists "Read own or approved public memories" on public.memories;
create policy "Read own or approved public memories"
  on public.memories for select
  using (
    (visibility = 'public' and review_status = 'approved')
    or (
      auth.uid() is not null
      and (
        user_id = (select auth.uid())
        or exists (
          select 1 from public.user_roles r
          where r.user_id = (select auth.uid()) and r.role = 'admin'
        )
      )
    )
  );

-- New uploads always enter the review queue, even if the user requests public.
drop policy if exists "Members upload pending memories" on public.memories;
create policy "Members upload pending memories"
  on public.memories for insert to authenticated
  with check (
    user_id = (select auth.uid())
    and review_status = 'pending'
    and reviewed_by is null
    and reviewed_at is null
  );

-- Owners may edit descriptive metadata and visibility requests, but cannot
-- approve content, change ownership, or set review fields.
drop policy if exists "Owners update pending memory details" on public.memories;
create policy "Owners update pending memory details"
  on public.memories for update to authenticated
  using (user_id = (select auth.uid()) and review_status <> 'approved')
  with check (
    user_id = (select auth.uid())
    and review_status = 'pending'
    and reviewed_by is null
    and reviewed_at is null
  );

drop policy if exists "Owners or admins delete memories" on public.memories;
create policy "Owners or admins delete memories"
  on public.memories for delete to authenticated
  using (
    user_id = (select auth.uid())
    or exists (
      select 1 from public.user_roles r
      where r.user_id = (select auth.uid()) and r.role = 'admin'
    )
  );

-- Only a real admin can change review status or review metadata.
drop policy if exists "Admins review memories" on public.memories;
create policy "Admins review memories"
  on public.memories for update to authenticated
  using (
    exists (
      select 1 from public.user_roles r
      where r.user_id = (select auth.uid()) and r.role = 'admin'
    )
  )
  with check (
    exists (
      select 1 from public.user_roles r
      where r.user_id = (select auth.uid()) and r.role = 'admin'
    )
  );

-- Private bucket: even approved gallery assets are served only after Storage RLS
-- confirms that the matching memory row is approved and public.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'angel-memories',
  'angel-memories',
  false,
  52428800,
  array[
    'image/jpeg','image/png','image/webp','image/gif',
    'video/mp4','video/webm',
    'application/pdf','application/zip'
  ]
)
on conflict (id) do update
set public = false,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "Members upload into own folder" on storage.objects;
create policy "Members upload into own folder"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'angel-memories'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

drop policy if exists "Read owned or approved public assets" on storage.objects;
create policy "Read owned or approved public assets"
  on storage.objects for select
  using (
    bucket_id = 'angel-memories'
    and (
      owner_id = (select auth.uid())::text
      or exists (
        select 1 from public.memories m
        where m.object_path = name
          and m.visibility = 'public'
          and m.review_status = 'approved'
      )
      or exists (
        select 1 from public.user_roles r
        where r.user_id = (select auth.uid()) and r.role = 'admin'
      )
    )
  );

drop policy if exists "Owners delete own assets" on storage.objects;
create policy "Owners delete own assets"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'angel-memories'
    and (
      owner_id = (select auth.uid())::text
      or exists (
        select 1 from public.user_roles r
        where r.user_id = (select auth.uid()) and r.role = 'admin'
      )
    )
  );

-- IMPORTANT: after the first trusted admin signs up, run this once in SQL Editor,
-- replacing the email with the exact administrator email:
-- insert into public.user_roles (user_id, role)
-- select id, 'admin' from auth.users where email = 'YOUR_ADMIN_EMAIL'
-- on conflict (user_id) do update set role = 'admin';
