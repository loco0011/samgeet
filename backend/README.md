# Samgeet backend (PHP + MySQL on Hostinger)

A tiny API that keeps a copy of each signed-in listener's **profile**: name, email, icon or emoji,
favourite languages, moods and singers, and device details only if they opted in.
Playlists, favourites, history and uploaded photos stay on the phone.

The app never talks to MySQL directly. The database password lives only in `api/config.php`
on the server, which is git-ignored.

## Set it up (about 10 minutes)

1. **Create the table.** hPanel -> Databases -> phpMyAdmin -> open your database -> **SQL** tab ->
   paste `schema.sql` -> Go.
2. **Point a subdomain at the hosting.** The main site is on Netlify (no PHP), so the API lives on
   its own subdomain, `api.sambitmaity.fun`: add an **A** record `api` -> the Hostinger server IP in
   the domain's DNS, then add the subdomain in hPanel -> Domains -> Subdomains and enable its SSL.
   Upload `api/profile.php` and `api/.htaccess` into that subdomain's folder.
3. **Add the credentials.** Create `config.php` from `api/config.sample.php` and fill in your real
   database name, user and password (the host stays `localhost`). Best: save it as
   `samgeet_config.php` **outside** `public_html`, in the site's own folder (the one that contains
   `public_html`), so it can never be served. If you can't, put `config.php` next to `profile.php`;
   `.htaccess` blocks it.
4. **Check it.** Open `https://api.sambitmaity.fun/profile.php` in a browser. Seeing
   `{"error":"post_only"}` means PHP is running and the route is right. (If a POST says
   `not_configured`, `config.php` is missing; `db` means the credentials are wrong; `server` usually
   means the tables from step 1 don't exist yet.)
5. **Build the app** and sign in with a test profile. A new row should appear in the
   `profiles` table.

The app's API address is `CloudService.baseUrl` in `lib/data/cloud_service.dart`.

## Notes
- Signing out deletes that install's row from the server.
- Only the sha256 of each install's secret is stored, so nobody can edit another profile.
- Requests are limited to 60 per IP every 10 minutes (`api_hits` table); the app retries later.
- The API only writes. It has no endpoint that returns anyone's profile.
- Change the database password if it was ever shared outside hPanel.

## Share page (`api/share.php`)
The page a friend lands on when they open a shared song or playlist link: title, artist and cover art
(or the playlist name and song count) plus a **Download Samgeet** button that points at the latest
GitHub release. Upload it next to `profile.php`; it needs no database or config.

- `https://api.sambitmaity.fun/share.php?t=song&s=Title&a=Artist&al=Album&i=<cover>`
- `https://api.sambitmaity.fun/share.php?t=playlist&n=Name&c=12#p=<playlist code>`

It hosts no music or audio. It shows only text carried in the link, escapes all of it, and embeds
cover art only from `*.saavncdn.com`. The `#p=` code never reaches the server. If you rename the
APK or move the repo, change `APK_URL` at the top of the file.

## Making links open the app (`api/.well-known/assetlinks.json`)
Upload the whole `.well-known` folder next to `share.php` so that
`https://api.sambitmaity.fun/.well-known/assetlinks.json` returns the JSON. Android reads it once at
install time to confirm Samgeet owns `api.sambitmaity.fun/share.php` links; after that, tapping such a
link opens the app directly instead of the browser. It lists the SHA-256 fingerprint of the **release**
signing key, so builds signed with another key (debug builds) won't open the links. If the file isn't
live yet, links open the web page, whose **Open in Samgeet** button still works. To re-check on a phone:
`adb shell pm get-app-links app.samgeet.music` should show `api.sambitmaity.fun: verified`.
