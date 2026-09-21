# Samgeet

**An open-source, ad-free music player for Android — created by [Sambit Maity](https://www.linkedin.com/in/sambitmaity/).**

Streams up to 320 kbps, smart mood-matched autoplay, on-device taste learning, background playback with lock-screen controls.

[![Download APK](https://img.shields.io/badge/Download-Samgeet.apk-7c4dff?style=for-the-badge&logo=android&logoColor=white)](https://github.com/loco0011/samgeet/releases/latest/download/Samgeet.apk)
[![Latest release](https://img.shields.io/github/v/release/loco0011/samgeet?style=for-the-badge)](https://github.com/loco0011/samgeet/releases/latest)

Licence: MIT (see [LICENSE](LICENSE)) · © 2026 Sambit Maity

## Download and install (Android)
1. Download **[Samgeet.apk](https://github.com/loco0011/samgeet/releases/latest/download/Samgeet.apk)** (or pick a version on the [Releases page](https://github.com/loco0011/samgeet/releases)).
2. Open the file. Android will ask to allow installs from your browser or file manager — allow it once. (This is normal for any app installed outside the Play Store.)
3. Open **Samgeet** and allow notifications so the lock-screen player shows up.

Needs Android 7.0 or newer. Play Protect may warn about an unrecognised app because it is not from the Play Store; choose *Install anyway*. Each release page lists the SHA-256 of the APK so you can check the download.

## Sharing
Sharing a song or playlist sends a link to a small page on `api.sambitmaity.fun` that shows the song or playlist and a **Download Samgeet** button. Friends who already have the app just tap the link: it opens Samgeet, which plays the song or asks before adding the playlist (Android App Links, with an **Open in Samgeet** button on the page as a fallback). Playlist messages can also be pasted into **Library → Import**. The page hosts no music and no audio, only what the link itself carries plus the cover art from the catalogue's CDN. Playlist contents travel in the link's `#…` part, which browsers never send to the server. See [`backend/`](backend/README.md).

## Build from source
- Build APK: `flutter build apk --release` → `build/app/outputs/flutter-apk/app-release.apk`
- Unit tests (offline): `flutter test`
- Live server checks: `flutter test tool/live_api_check.dart`, `dart run tool/check_stream.dart`
- Release signing: put your keystore details in `android/key.properties` (git-ignored). Without it the build falls back to the debug key, which is fine for testing but not for publishing. How to back the key up, restore it and publish a release: [`docs/Samgeet-Signing-Key-Backup-Guide.pdf`](docs/Samgeet-Signing-Key-Backup-Guide.pdf).

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
"Sign in" creates a profile stored on this phone (name, required email, favourite languages/moods/singers). Optionally — off by default — it also keeps the device model and an approximate (city-level) location; the public IP will be recorded by the server once accounts exist. Guests can keep 5 songs per playlist and can't share playlists; signing in lifts both limits and seeds the recommendations. A copy of the profile is saved on the author's server (a small PHP + MySQL API, see [`backend/`](backend/README.md)) and deleted on sign-out; playlists, favourites, history and the uploaded photo stay on the phone. There is no password or restore-by-email yet.

## Logo
`assets/mark-chrome.webp` is the master (transparent background). The Android launcher, adaptive/monochrome and splash images under `android/app/src/main/res/` were generated from it.

## Credits, licence and branding
- **Author:** Sambit Maity — https://www.linkedin.com/in/sambitmaity/
- **Source code:** https://github.com/loco0011/samgeet
- **Licence:** the code is MIT licensed. Keep the copyright notice and credit the original author in any copy or fork.
- **Name and logo:** "Samgeet" and the logo belong to Sambit Maity and are *not* covered by the MIT licence. Forks must use their own name and logo.
- **Music:** the app hosts no music; songs are streamed from a third-party catalogue and belong to their rights holders. Not affiliated with that service or any label. Personal, non-commercial use only.
- **No warranty:** provided "as is". See [NOTICE.md](NOTICE.md) and the in-app About screen.
