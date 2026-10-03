# Samgeet backend (PHP + MySQL on Hostinger)

A tiny API that keeps a copy of each signed-in listener's **profile** (name, email, icon or emoji,
favourite languages, moods and singers, and device details only if they opted in) and a **synced copy** of
their library (playlists, favourites, history, settings), so signing in with the same email and password on
any phone, or after a reinstall, brings it all back. Uploaded photos stay on the phone.

The app never talks to MySQL directly. The database password lives only in `api/config.php`
on the server, which is git-ignored.

## Set it up (about 10 minutes)

1. **Create the table.** hPanel -> Databases -> phpMyAdmin -> open your database -> **SQL** tab ->
   paste `schema.sql` -> Go.
2. **Point a subdomain at the hosting.** The main site is on Netlify (no PHP), so the API lives on
   its own subdomain, `api.sambitmaity.fun`: add an **A** record `api` -> the Hostinger server IP in
   the domain's DNS, then add the subdomain in hPanel -> Domains -> Subdomains and enable its SSL.
   Upload `api/profile.php`, `api/backup.php`, `api/link.php`, `api/share.php` and `api/.htaccess` into that
   subdomain's folder.
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
- `profile.php` only writes. It has no endpoint that returns anyone's profile.
- `backup.php` holds each account's library. The account key is derived on the phone from the email and
  password (PBKDF2, 150,000 rounds, salted with the email); the password never leaves the phone and the
  server stores only a hash of the key, so a forgotten password can't be reset. Libraries are gzip'd JSON of
  the app's saved settings, stored as-is. Every save names the `rev` it built on, so two phones syncing at
  once merge instead of overwriting each other. `email_hash` lets sign-in say "wrong password for this
  email" instead of quietly creating a second account (it does reveal whether an email has an account).
  Signing out only stops syncing on that phone; the account stays.
- Change the database password if it was ever shared outside hPanel.

## Share page (`api/share.php`)
The page a friend lands on when they open a shared song or playlist link: title, artist and cover art
(or the playlist name and song count) plus a **Download Samgeet** button that points at the latest
GitHub release. Upload it next to `profile.php`.

- `https://api.sambitmaity.fun/s/k7qm2xa`: a **short link** (what the app shares). `.htaccess` rewrites
  it to `share.php?c=k7qm2xa`, which reads the details from the `short_links` table.
- `https://api.sambitmaity.fun/share.php?t=song&s=Title&a=Artist&al=Album&i=<cover>` and
  `...share.php?t=playlist&n=Name&c=12#p=<playlist code>`: the long links, used when the phone is
  offline (and by older app versions). The `#p=` code never reaches the server.

`api/link.php` makes and looks up short links: `POST` a song (`id`, title, artist, album, cover) or a
playlist (name + song ids) and get a 7-character code back; `GET link.php?c=<code>` returns it. The same
song or playlist always gets the same code. Only what the long link used to carry is stored.

It hosts no music or audio. It escapes everything it shows and embeds cover art only from
`*.saavncdn.com`. If you rename the APK or move the repo, change `APK_URL` at the top of the file.

## Making links open the app (`api/.well-known/assetlinks.json`)
Upload the whole `.well-known` folder next to `share.php` so that
`https://api.sambitmaity.fun/.well-known/assetlinks.json` returns the JSON. Android reads it once at
install time to confirm Samgeet owns `api.sambitmaity.fun/share.php` links; after that, tapping such a
link opens the app directly instead of the browser. It lists the SHA-256 fingerprint of the **release**
signing key, so builds signed with another key (debug builds) won't open the links. If the file isn't
live yet, links open the web page, whose **Open in Samgeet** button still works. To re-check on a phone:
`adb shell pm get-app-links app.samgeet.music` should show `api.sambitmaity.fun: verified`.

## Version 2: private API, admin panel, listening data (`samgeet/`, app 1.4.0+)
App 1.4.0 and newer talk to `samgeet/`, uploaded under a private folder on the API subdomain:
`https://api.sambitmaity.fun/<private id>/samgeet/`. The private id, the app signing key and the
admin seed live only in the git-ignored `deploy/` folder and `secrets.json` (never in git).

```
samgeet/
  .htaccess          blocks config.php, lib/, schema.sql; no listings; noindex
  config.php         'app_key' => 64 hex (same as SAMGEET_APP_KEY in secrets.json); the DB login comes
                     from samgeet_config.php or the first API's config.php (found in the folders above)
  lib/bootstrap.php  config, DB, rate limits, request signature + session checks
  api/auth.php       check_email, login, register, profile, logout, delete_account
  api/library.php    synced library: load / save with base_rev (409 on conflict)
  api/events.php     listening data in batches (up to 200 events)
  api/app.php        config at app start: newest published update + messages; receipts
  api/link.php       short share links (signed in only)
  admin/index.php    the admin panel; admin/.user.ini lets it take ~60 MB APK uploads
  files/             APKs uploaded from the admin panel (only .apk is served)
  schema.sql         tables (run once in phpMyAdmin; safe to run again)
```

**Who can call it.** Every app request is signed: `X-Samgeet-Device` (the install's random id),
`X-Samgeet-Time` and `X-Samgeet-Sign` = HMAC-SHA256(app_key, endpoint, time, device, sha256(body)).
Anything unsigned, signed for another endpoint, or more than 5 minutes old gets a bare 404
(`no_route`). Signed-in calls also send `X-Samgeet-Session`, a random token from `login`/`register`
(stored hashed, tied to that phone, renewed on use, expires after 120 idle days). The library,
profile and deletion are always chosen by the session's account, never by an id in the request.
Limits: 400 requests per IP and 150 per phone every 10 minutes, 20 sign-in tries per phone. The key
ships inside the APK, so treat it as a speed bump: the sessions and limits are the real protection.

**Accounts from 1.3.x** move over by themselves: the first `login` with an account key that only
exists in the old `backups` table copies it (and the profile name) into `users` + `libraries`.
Leave the old `profile.php`, `backup.php` and `link.php` in place until every phone has updated
(the GitHub release for 1.4.0 is marked `[required]`), then delete `profile.php` and `backup.php`.
`share.php`, `/s/<code>` and `GET link.php?c=` stay public: friends open shared links in a browser.

**Tables** (`schema.sql`): `users` 1-n `devices`, `sessions`, `user_tastes`, `events`; `users` 1-1
`libraries`; `tracks` n-n `artists` via `track_artists`; `events` reference `devices`, `users` and
`tracks`; `admins` 1-n `releases`, `notifications`; `notifications` 1-n `notification_receipts`
(per phone: delivered, opened, dismissed). Deleting a user removes its sessions, library, tastes
and events. All times are stored in UTC; the admin panel shows IST.

**Event types**: `app_open`, `app_close`, `play_start` (value: where it was started), `play_end`
(ms listened; value `complete` / `skip` / `stop`; meta `frac`), `like`, `unlike`, `download`,
`download_remove`, `share_song` / `share_playlist` (value: short code), `search` (value: the text),
`playlist_create`, `playlist_add`, `queue_add`, `radio_start`, `sleep_timer`, `player_style`,
`sign_in`, `sign_up`, `sign_out`, `device_info` (opt-in city), `notification_open` /
`notification_dismiss`, `update_open` / `update_later`.

**Admin panel** (`.../samgeet/admin/`): sign in with an `admins` row (bcrypt). Five wrong
passwords in 15 minutes lock that address out; sessions end after 2 hours idle or 12 hours. A sidebar
(a slide-in menu on phones) with:
- *Overview*: period switch (today, 7, 30, 90 days, all time) with the change against the period before;
  listeners, plays, hours, new accounts; online now, active today/week/month; daily chart; signed in vs
  guests; top songs, singers, most active listeners, top cities, app versions, listening habits.
- *Listening*: plays by hour and weekday, languages, where plays start, searches, likes, downloads,
  player looks, tastes picked at sign-up, phone models and Android versions.
- *Places*: cities and countries from `device_info` (only listeners who shared device details), each
  city with its listeners and what they play; a rough country for every phone from its language setting.
- *Listeners*: filter (active today, this week, away 30+ days, blocked), search, sort; each listener's
  page has their picture (emoji or initials; photos never leave the phone), place, phones, 30-day
  listening, time of day, top songs and singers, searches, likes, tastes, messages and an activity
  timeline, plus sign out everywhere, block and delete.
- *Messages*: tabs for all, from the web panel, from the app, and update reminders; "New message" and
  "Update reminder" (only apps older than the newest version, text filled in from its release notes).
  Each message can go out again to everyone, only phones that never got it, only phones that didn't
  open it, or (update reminders) only phones still on an old version; the original then stops.
- *App updates*: phones on each version, share on the latest, publish/unpublish, "Publish a version"
  (upload an APK or paste a link, fill in from GitHub, required or not).
- *Export*: events as CSV.

The pages are in `lib/admin_views.php`, the layout in `lib/admin_ui.php`; every number comes from
`lib/reports.php` and sending from `lib/messages.php`, which the app's admin tools (`api/admin.php`)
use too, so both show the same thing.

### Admin panel 2 (October 2026)
1. phpMyAdmin → SQL: run `migrations/2026-10-03-messages.sql` (adds `source`, `follow_up`,
   `follow_of` to `notifications`). Until then everything works except splitting messages by where they
   were sent from and re-sending to only part of an audience.
2. Upload `admin/index.php`, `api/admin.php`, `api/app.php` and the new `lib/reports.php`,
   `lib/messages.php`, `lib/admin_ui.php`, `lib/admin_views.php`.

### Deploying version 2
1. phpMyAdmin → SQL: run `deploy/1-schema.sql`, then `deploy/2-admin.sql` (the admin login).
2. Upload the folder `deploy/upload/<private id>/` into the API subdomain's web folder (the one
   with `share.php`), so `https://api.sambitmaity.fun/<private id>/samgeet/admin/` opens the panel.
3. Check: `.../samgeet/api/app.php` answers `{"error":"no_route"}` (404) in a browser,
   `.../samgeet/config.php` and `.../samgeet/lib/bootstrap.php` are refused (403), and the admin
   panel signs in.
4. Build the app with `--dart-define-from-file=secrets.json`, publish it on GitHub (marked
   `[required]` so 1.3.x phones update), then add it under Admin → App updates for 1.4.0+ phones.
