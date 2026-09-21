# Samgeet

**An open-source, ad-free music player — created by [Sambit Maity](https://www.linkedin.com/in/sambitmaity/).**

Licence: MIT (see [LICENSE](LICENSE)) · © 2026 Sambit Maity

Ad-free music player. Streams up to 320 kbps, smart mood-matched autoplay, on-device taste learning.

- Build APK: `flutter build apk --release` → `build/app/outputs/flutter-apk/app-release.apk`
- Unit tests (offline): `flutter test`
- Live server checks: `flutter test tool/live_api_check.dart`, `dart run tool/check_stream.dart`

## Layout
- `lib/data` — API client, models, library store (favourites/playlists/history), catalog of categories
- `lib/engine` — `taste_profile.dart` (learns from likes/skips/completions), `recommender.dart` (pure ranking), `recommendation_service.dart` (candidate gathering)
- `lib/player` — queue, autoplay refills, sleep timer, error recovery
- `lib/ui` — screens and widgets

## Gotchas
- `cached_network_image` is pinned to 3.4.x: 4.x pulls `material_ui`/`cupertino_ui`, which don't compile on Flutter 3.44.2.
- `android/app/src/main/res/raw/keep.xml` stops the release resource shrinker deleting the notification icons the audio plugin loads by name. Removing it silently breaks lock-screen controls in release builds only.

## Responsive layout
`lib/ui/responsive.dart` holds the breakpoints. Below 720 dp wide the app uses a bottom bar; at or above it (tablets, landscape phones) it switches to a side rail and centres content (max 1200 dp). The player goes two-pane in landscape. Verified on: 360×640 phone, 412×915 phone, 800×1280 tablet (portrait), 1280×800 tablet (landscape), phone landscape.

## Background playback (verified on an emulator)
Keeps playing with the app backgrounded, screen off, and after being swiped from recents. Lock-screen/notification next, previous, pause and play work, and smart radio keeps refilling the queue while backgrounded. `MainActivity.kt` asks for the Android 13+ notification permission on first launch; without it the media notification stays hidden.

## Look & feel
A dark "aurora" design: animated backdrop that follows the album, frosted-glass surfaces, 3-across poster cards, a floating dock, and a circular player whose ring you drag to seek. One gradient (deep cyan → violet → magenta) is used app-wide.

## Mood theme
The app recolours itself to the song's mood (Romantic, Melancholy, Party, Chill, Devotional, Nostalgic, Focus). The mood is *inferred* from title/album keywords, the category you started from and the era — there is no audio analysis. See `lib/engine/mood.dart`.

## Profile and limits
"Sign in" creates a profile stored on this phone (name, required email, favourite languages/moods/singers). Optionally — off by default — it also keeps the device model and an approximate (city-level) location; the public IP will be recorded by the server once accounts exist. Guests can keep 5 songs per playlist and can't share playlists; signing in lifts both limits and seeds the recommendations. There is no password or cloud sync yet; accounts (email one-time-code sign-in and restoring data by email) are planned on Supabase.

## Logo
`assets/mark-chrome.webp` is the master (transparent background). The Android launcher, adaptive/monochrome and splash images under `android/app/src/main/res/` were generated from it.

## Credits, licence and branding
- **Author:** Sambit Maity — https://www.linkedin.com/in/sambitmaity/
- **Source code:** https://github.com/loco0011/samgeet
- **Licence:** the code is MIT licensed. Keep the copyright notice and credit the original author in any copy or fork.
- **Name and logo:** "Samgeet" and the logo belong to Sambit Maity and are *not* covered by the MIT licence. Forks must use their own name and logo.
- **Music:** the app hosts no music; songs are streamed from a third-party catalogue and belong to their rights holders. Not affiliated with that service or any label. Personal, non-commercial use only.
- **No warranty:** provided "as is". See [NOTICE.md](NOTICE.md) and the in-app About screen.
