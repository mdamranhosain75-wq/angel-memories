# Angel Memories — Every Memory, One Home

Angel Memories is a community memory gallery: members can share photos, videos and documents; everyone can browse public memories; each account has its own permanent Supabase Auth user ID. Only an administrator can delete memories or stored files.

## Current repository build

- Royal blue and gold responsive community interface.
- Home, Public Gallery, My Memories, Photos, Videos, Documents, Members and Admin sections.
- Google OAuth client flow is wired but requires a separate Supabase project and Google provider configuration.
- Upload client supports images, videos, PDF, ZIP and common office documents.
- Private Storage bucket with signed URLs for authorized viewing.
- Database schema includes user profiles, unique Auth IDs, member/admin roles, public/private visibility and admin-only deletion RLS.
- Admin member directory and delete controls are wired in the client.

## Important: not live yet

This repository does not contain production credentials. The frontend will show that cloud setup is pending until the NEW Angel Memories Supabase project is created and configured. Do not paste a service-role key into the browser.

The existing Supabase project named `little-angel` belongs to the older Little Angel BD site and must not be reused for Angel Memories.

## Backend setup

1. Create a separate Supabase project named `angel-memories` in the organization selected by the owner.
2. Run `supabase/schema.sql` in that new project's SQL Editor.
3. In Supabase Authentication, enable Google provider and configure its OAuth client and redirect URLs.
4. Promote the trusted administrator account using the commented one-time SQL at the bottom of `supabase/schema.sql`.
5. Copy the new project's Project URL and publishable key into `supabase-config.js`. Never use a service-role or secret key in the browser.
6. Deploy this repository to Vercel and add the deployed domain to Supabase Auth redirect allow list and Google OAuth authorized origins.

## Security model

- Every new Auth user receives a member role and a profile row.
- Public memories are readable by everyone; private memories are readable by their owner and admins.
- Members may upload and update their own memory metadata.
- Only users with the database-backed admin role may delete memory rows or Storage objects.
- Admin authorization is checked in database RLS, not trusted from browser state.
- Storage bucket remains private and assets are delivered using short-lived signed URLs.

## Deploy

Import this repository into Vercel. It is a static site with no build command; output directory is `.`.
