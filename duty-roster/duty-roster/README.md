# Duty Roster

Weekly duty roster board (Supabase database + login, static page hosted on Vercel).

## Files
- `index.html`: the whole app. Put your Supabase URL and anon key near the top of the script.
- `schema.sql`: run once in the Supabase SQL Editor. Creates tables, security rules and both rosters.

## Deploy
1. Run `schema.sql` in Supabase.
2. Edit the two keys at the top of the script in `index.html`.
3. Import this repository in Vercel (Add New > Project). Leave all settings as they are. No build step.
4. Sign up in the live app with your own email first: the first account becomes the admin.
