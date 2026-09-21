# Samgeet backend (PHP + MySQL on Hostinger)

A tiny API that keeps a copy of each signed-in listener's **profile**: name, email, icon or emoji,
favourite languages, moods and singers, and device details only if they opted in.
Playlists, favourites, history and uploaded photos stay on the phone.

The app never talks to MySQL directly. The database password lives only in `api/config.php`
on the server, which is git-ignored.

## Set it up (about 10 minutes)

1. **Create the table.** hPanel -> Databases -> phpMyAdmin -> open your database -> **SQL** tab ->
   paste `schema.sql` -> Go.
2. **Upload the API.** hPanel -> Files -> File Manager -> `public_html`. Create the folders
   `samgeet/api`, then upload `api/profile.php` and `api/.htaccess` into it.
3. **Add the credentials.** Create `config.php` from `api/config.sample.php` and fill in your real
   database name, user and password (the host stays `localhost`). Best: save it as
   `samgeet_config.php` **outside** `public_html`, in the site's own folder (the one that contains
   `public_html`), so it can never be served. If you can't, put `config.php` next to `profile.php`;
   `.htaccess` blocks it.
4. **Check it.** Open `https://sambitmaity.fun/samgeet/api/profile.php` in a browser. Seeing
   `{"error":"post_only"}` means PHP is running and the route is right.
5. **Build the app** and sign in with a test profile. A new row should appear in the
   `profiles` table.

The app's API address is `CloudService.baseUrl` in `lib/data/cloud_service.dart`.

## Notes
- Signing out deletes that install's row from the server.
- Only the sha256 of each install's secret is stored, so nobody can edit another profile.
- Requests are limited to 60 per IP every 10 minutes (`api_hits` table); the app retries later.
- The API only writes. It has no endpoint that returns anyone's profile.
- Change the database password if it was ever shared outside hPanel.
