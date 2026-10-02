# Samgeet: project brief for Claude

Samgeet is an open-source, ad-free Android music player (Flutter) by Sambit Maity. It streams from
JioSaavn's unofficial web API, learns taste on-device, and syncs each listener's library through a
small PHP + MySQL server of its own. MIT licensed; the name and logo are not.

## Links

| What | Where |
| --- | --- |
| Source (GitHub) | https://github.com/loco0011/samgeet (default branch `main`) |
| Releases | https://github.com/loco0011/samgeet/releases (latest APK: `.../releases/latest/download/Samgeet.apk`) |
| API server | https://api.sambitmaity.fun (Hostinger, PHP + MySQL, files in `backend/api/`) |
| Short share links | `https://api.sambitmaity.fun/s/<7-char code>` |
| Author | https://www.linkedin.com/in/sambitmaity/ |
| Deeper docs | `README.md`, `HOW_IT_WORKS.md` (architecture, legal risks), `NOTICE.md` (privacy), `backend/README.md` |

## Stack and commands

- Flutter 3.44.2 (Dart ^3.12), Android is the only target that matters (min Android 7.0).
- Build: `flutter build apk --release --dart-define-from-file=secrets.json` → `build/app/outputs/flutter-apk/app-release.apk`
  (~57 MB, all ABIs). `secrets.json` (git-ignored) holds `SAMGEET_API` (the private API path) and `SAMGEET_APP_KEY`;
  without it the app can't reach its server (no sync, data, updates or messages). Never print or commit it.
- Tests (offline): `flutter test` (109 tests). Analyzer: `flutter analyze` (only `tool/` has known info lints).
- Live checks: `flutter test tool/live_api_check.dart`, `dart run tool/check_stream.dart`.
- Release signing: `android/key.properties` + keystore (git-ignored, never print or commit them).
- `cached_network_image` is pinned to 3.4.x; `android/app/src/main/res/raw/keep.xml` keeps notification icons in release builds.
- `third_party/just_audio_background` is a local, modified copy (notification buttons, stop when swiped away).

## Code map

| Area | Files |
| --- | --- |
| Music API + stream decryption | `lib/data/saavn_api.dart`, `lib/data/track.dart` |
| Library (favourites, playlists, history, settings) | `lib/data/library_store.dart` (`SharedPreferences`) |
| Signed API client | `lib/data/api_client.dart` (HMAC-signed requests, session token, clock-skew retry) |
| Accounts + sync | `lib/data/sync_service.dart` (email + password → PBKDF2 key → session; 3-way merge; rev-checked saves) |
| Listening data | `lib/data/analytics.dart` (queued events → `events.php`); hooks in player, library, downloads, share |
| Updates + admin messages | `lib/data/app_config.dart` (asks every 30 min, phone notifications), `lib/ui/widgets/fancy_dialog.dart`, `update_dialog.dart` |
| Player looks | `lib/data/player_style.dart`, `lib/ui/widgets/player_style_picker.dart`, layouts in `now_playing_screen.dart` |
| Login gates | `lib/ui/nav.dart` (`requireSignIn`, `toggleLike`, `downloadGated`, `shareTrackGated`) |
| Profile copy on server | `lib/data/cloud_service.dart` → `backend/samgeet/api/auth.php` (action `profile`) |
| Sharing, short links, deep links | `lib/data/share_service.dart`, `lib/data/deep_link.dart` → `backend/api/link.php`, `share.php` |
| In-app updates | `lib/data/update_service.dart` (admin panel release; GitHub only for builds without `secrets.json`) |
| Player, queue, smart radio, sleep timer | `lib/player/player_controller.dart` |
| Equalizer + loudness boost + saved sounds | `lib/player/audio_fx.dart` (`fx.mine`), Sound sheet in `lib/ui/widgets/player_sheets.dart` |
| Offline downloads | `lib/data/download_service.dart` (files in `no_backup/offline`, index `dl.index`, never synced), `lib/ui/widgets/download_widgets.dart` |
| Browse catalogue, new releases | `lib/data/catalog.dart` (tiles, `strictLanguage`, `moreQueries`), `lib/ui/screens/category_screen.dart`, `new_releases_screen.dart` |
| Animated launch logo | `lib/ui/widgets/launch_splash.dart` (takes over from Android's splash, same `splash_logo.png`) |
| Recommendations, mood | `lib/engine/*`, `lib/ui/mood_theme.dart` |
| Voice ("play X on Samgeet") | `android/.../MainActivity.kt` → `samgeet://play?q=` → `lib/ui/shell.dart` |
| Sign-in + popup | `lib/ui/screens/sign_in_screen.dart`, `lib/ui/widgets/sign_in_nudge.dart` |

## Server (`backend/`)

Version 2 (app 1.4.0+): `backend/samgeet/` deployed at `api.sambitmaity.fun/<private id>/samgeet/`, with `api/`
(auth, library, events, app, link: all signed, see `backend/README.md`) and `admin/` (reports, accounts, releases,
notifications, CSV export). Private id, app key and admin seed: `secrets.json` + `deploy/` (git-ignored).
The 1.3.x endpoints below stay until old phones have updated; accounts migrate on their first 1.4 sign-in.


Endpoints on `api.sambitmaity.fun`: `profile.php` (profile copy per install), `backup.php` (account
libraries: load/save with `base_rev`, 409 on conflict, `check_email`), `link.php` (make/look up short
links), `share.php` (landing page; `/s/<code>` rewrites to it via `.htaccess`). Tables in
`backend/schema.sql`: `profiles`, `backups`, `short_links`, `api_hits` (60 requests / 10 min / IP).
Credentials live only in `samgeet_config.php` on the server. Claude cannot upload to Hostinger: the
owner uploads changed files and runs SQL in phpMyAdmin; Claude then tests the live endpoints with curl.

## Releasing an update

1. Bump `version:` in `pubspec.yaml` (`x.y.z+build`) and `kVersionName` + `kBuildNumber` in `lib/app_info.dart` (the
   server offers updates by build number, so they must match).
2. `flutter build apk --release --dart-define-from-file=secrets.json`, copy to `dist/Samgeet.apk` (keep that exact name: download links use it).
3. GitHub release tagged `vX.Y.Z` from `main`, title `Samgeet X.Y.Z`, notes in the 1.3.x style (bold lead
   per bullet, an Install section, the SHA-256). Create as draft, upload the APK, then publish. The word
   `[required]` in the notes forces the update. Pre-releases and drafts are ignored by the app.
4. Add the SHA-256 to `docs/release-checksums.md` (local only, git-ignored).
Installed apps see the update popup about 4 s after opening. From 1.4.0 the app reads updates from the admin panel
(Admin → App updates): add each release there too. 1.3.x phones still read GitHub, so keep publishing there.

## Installing on a real phone

- Install ONLY a release build with `adb install -r`. Never `flutter run` a debug build over an installed
  release: on a signature mismatch Flutter uninstalls the app and wipes the user's data (this happened once).
- Never uninstall or clear app data without the owner's explicit OK.
- Device details for this machine: `CLAUDE.local.md` (not in git).

## Conventions

- Commit messages: short summary line (`v1.3.3: ...` for releases), a plain-English body.
- Work on a branch, then fast-forward `main` when the owner asks to merge or push.
- UI copy is plain and friendly; match the dark "Ember" look (`lib/ui/theme.dart`, `mood_theme.dart`).
- Keep the About screen, `NOTICE.md`, `README.md` and `HOW_IT_WORKS.md` accurate when data handling changes.

## Status (2026-09-25)

- Latest release: **1.3.3** (build 8): accounts + sync, equalizer, short share links, voice play, sign-in popup.
- 1.4.0 (branch `features/admin-analytics-1.4`): private signed API, admin panel, listening data, login required to
  like/download/share, player looks, admin-sent updates and notifications.
- Known gaps: messages arrive only while the app runs (no push service); `HOW_IT_WORKS.pdf` is older than `HOW_IT_WORKS.md`;
  equalizer ideas for later are written up (phase 1: own presets, Simple mode, A/B compare, undo).
