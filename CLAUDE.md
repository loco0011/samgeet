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
- Build: `flutter build apk --release` → `build/app/outputs/flutter-apk/app-release.apk` (~57 MB, all ABIs).
- Tests (offline): `flutter test` (85 tests). Analyzer: `flutter analyze` (only `tool/` has known info lints).
- Live checks: `flutter test tool/live_api_check.dart`, `dart run tool/check_stream.dart`.
- Release signing: `android/key.properties` + keystore (git-ignored, never print or commit them).
- `cached_network_image` is pinned to 3.4.x; `android/app/src/main/res/raw/keep.xml` keeps notification icons in release builds.
- `third_party/just_audio_background` is a local, modified copy (notification buttons, stop when swiped away).

## Code map

| Area | Files |
| --- | --- |
| Music API + stream decryption | `lib/data/saavn_api.dart`, `lib/data/track.dart` |
| Library (favourites, playlists, history, settings) | `lib/data/library_store.dart` (`SharedPreferences`) |
| Accounts + sync | `lib/data/sync_service.dart` (email + password → PBKDF2 key; 3-way merge; rev-checked saves) |
| Profile copy on server | `lib/data/cloud_service.dart` → `backend/api/profile.php` |
| Sharing, short links, deep links | `lib/data/share_service.dart`, `lib/data/deep_link.dart` → `backend/api/link.php`, `share.php` |
| In-app updates | `lib/data/update_service.dart`, `lib/ui/widgets/update_dialog.dart` (reads GitHub latest release) |
| Player, queue, smart radio, sleep timer | `lib/player/player_controller.dart` |
| Equalizer + loudness boost | `lib/player/audio_fx.dart`, Sound sheet in `lib/ui/widgets/player_sheets.dart` |
| Recommendations, mood | `lib/engine/*`, `lib/ui/mood_theme.dart` |
| Voice ("play X on Samgeet") | `android/.../MainActivity.kt` → `samgeet://play?q=` → `lib/ui/shell.dart` |
| Sign-in + popup | `lib/ui/screens/sign_in_screen.dart`, `lib/ui/widgets/sign_in_nudge.dart` |

## Server (`backend/`)

Endpoints on `api.sambitmaity.fun`: `profile.php` (profile copy per install), `backup.php` (account
libraries: load/save with `base_rev`, 409 on conflict, `check_email`), `link.php` (make/look up short
links), `share.php` (landing page; `/s/<code>` rewrites to it via `.htaccess`). Tables in
`backend/schema.sql`: `profiles`, `backups`, `short_links`, `api_hits` (60 requests / 10 min / IP).
Credentials live only in `samgeet_config.php` on the server. Claude cannot upload to Hostinger: the
owner uploads changed files and runs SQL in phpMyAdmin; Claude then tests the live endpoints with curl.

## Releasing an update

1. Bump `version:` in `pubspec.yaml` (`x.y.z+build`) and `kVersionName` in `lib/app_info.dart`.
2. `flutter build apk --release`, copy to `dist/Samgeet.apk` (keep that exact name: download links use it).
3. GitHub release tagged `vX.Y.Z` from `main`, title `Samgeet X.Y.Z`, notes in the 1.3.x style (bold lead
   per bullet, an Install section, the SHA-256). Create as draft, upload the APK, then publish. The word
   `[required]` in the notes forces the update. Pre-releases and drafts are ignored by the app.
4. Add the SHA-256 to `docs/release-checksums.md` (local only, git-ignored).
Installed apps see the update popup about 4 s after opening.

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
- Known gaps: no in-app "delete my account data"; `HOW_IT_WORKS.pdf` is older than `HOW_IT_WORKS.md`;
  equalizer ideas for later are written up (phase 1: own presets, Simple mode, A/B compare, undo).
