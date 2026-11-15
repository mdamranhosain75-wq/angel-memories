# Angel Memories — Every Memory, One Home

Angel Memories is a private memory gallery: members can share photos, videos and documents; each member can see only their own private gallery; each account has its own permanent Supabase Auth user ID. Only an administrator can delete memories or stored files.

## Current repository build

- Royal blue and gold responsive private-gallery interface.
- Home, Private Gallery, Photos, Videos, Documents and Admin sections.
- Google OAuth client flow is wired but requires a separate Supabase project and Google provider configuration.
- Upload client supports images, videos, PDF, ZIP and common office documents.
- Private Storage bucket with signed URLs for authorized viewing.
- Database schema includes user profiles, unique Auth IDs, member/admin roles, private-only access and admin-only deletion RLS.
- Admin member directory and delete controls are wired in the client.

## Cloud project status

A separate Supabase project named `angel-memories` has been created. The private-gallery schema, RLS policies, private Storage bucket, and browser-safe project URL/publishable key are configured. The older `little-angel` project is separate and unchanged.

Remaining launch steps:

1. Configure Google OAuth credentials in Supabase Authentication (requires the owner's Google OAuth client ID and secret).
2. The owner must sign in once with the intended administrator Google account; then promote that exact account using the trusted one-time SQL statement at the bottom of `supabase/schema.sql`.
3. Deploy this repository to Vercel and add the deployed domain to Supabase Auth redirect allow list and Google OAuth authorized origins.

Never put a service-role or secret key in browser files. The public publishable key is intended for browser use and access is restricted by database RLS.

## Security model

- Every new Auth user receives a member role and a profile row.
- Every memory is private and readable only by its owner and admins.
- Members may upload and update their own private memory metadata.
- Only users with the database-backed admin role may delete memory rows or Storage objects.
- Admin authorization is checked in database RLS, not trusted from browser state.
- Storage bucket remains private and assets are delivered using short-lived signed URLs.

## Deploy

Import this repository into Vercel. It is a static site with no build command; output directory is `.`.
