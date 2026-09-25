# Samgeet

**An open-source, ad-free music player for Android — created by [Sambit Maity](https://www.linkedin.com/in/sambitmaity/).**

Streams up to 320 kbps, smart mood-matched autoplay, on-device taste learning, an equalizer, background playback with lock-screen controls, and a library that syncs across your phones.

[![Download APK](https://img.shields.io/badge/Download-Samgeet.apk-7c4dff?style=for-the-badge&logo=android&logoColor=white)](https://github.com/loco0011/samgeet/releases/latest/download/Samgeet.apk)
[![Latest release](https://img.shields.io/github/v/release/loco0011/samgeet?style=for-the-badge)](https://github.com/loco0011/samgeet/releases/latest)

Licence: MIT (see [LICENSE](LICENSE)) · © 2026 Sambit Maity

## Download and install (Android)
1. Download **[Samgeet.apk](https://github.com/loco0011/samgeet/releases/latest/download/Samgeet.apk)** (or pick a version on the [Releases page](https://github.com/loco0011/samgeet/releases)).
2. Open the file. Android will ask to allow installs from your browser or file manager — allow it once. (This is normal for any app installed outside the Play Store.)
3. Open **Samgeet** and allow notifications so the lock-screen player shows up.

Needs Android 7.0 or newer. Play Protect may warn about an unrecognised app because it is not from the Play Store; choose *Install anyway*. Each release page lists the SHA-256 of the APK so you can check the download.

## Sharing
Sharing a song or playlist sends a short link like `https://api.sambitmaity.fun/s/k7qm2xa` to a small page that shows the song or playlist (with its cover) and a **Download Samgeet** button. Friends who already have the app just tap the link: it opens Samgeet, which plays the song or asks before adding the playlist (Android App Links, with an **Open in Samgeet** button on the page as a fallback). Shared messages can also be pasted into **Library → Import**. The server stores only what the link stands for (the song's details, or a playlist's name and song ids); when the phone is offline the app falls back to a long link that carries everything itself. The page hosts no music and no audio. See [`backend/`](backend/README.md).

## Voice
"Play *song* on Samgeet" works from Bixby and Google Assistant: Samgeet registers as a music app, and the spoken query plays the best match. "Play music on Samgeet" resumes the queue.

## Equalizer
The player's **Sound** button opens an equalizer (a curve you drag, presets such as Bass boost, Vocal and Late night, and a loudness boost). It uses Android's built-in `Equalizer` and `LoudnessEnhancer` effects, so it works on Android only. Settings are saved and sync with your account.

## Build from source
- Build APK: `flutter build apk --release` → `build/app/outputs/flutter-apk/app-release.apk`
- Unit tests (offline): `flutter test`
- Live server checks: `flutter test tool/live_api_check.dart`, `dart run tool/check_stream.dart`
- Release signing: put your keystore details in `android/key.properties` (git-ignored). Without it the build falls back to the debug key, which is fine for testing but not for publishing. How to back the key up, restore it and publish a release: [`docs/Samgeet-Signing-Key-Backup-Guide.pdf`](docs/Samgeet-Signing-Key-Backup-Guide.pdf).

## Layout
- `lib/data` — API client, models, library store (favourites/playlists/history), account sync, share links, catalog of categories
- `lib/engine` — `taste_profile.dart` (learns from likes/skips/completions), `recommender.dart` (pure ranking), `recommendation_service.dart` (candidate gathering)
- `lib/player` — queue, autoplay refills, sleep timer, error recovery, equalizer
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

## Accounts and sync
Signing in takes an email and a password. If that account exists, its library comes back to the phone (playlists, liked songs, history, followed artists, recent searches, taste, settings, equalizer and profile); if not, a new account starts from what's on the phone. A wrong password for a known email is refused rather than creating a second, empty account. After that, every phone signed in to the account stays in sync: changes are merged (deletions included) when the app opens, comes back to the front, or a few seconds after you change something. See `lib/data/sync_service.dart`.

The password never leaves the phone: PBKDF2 (150,000 rounds, salted with the email) turns it into the account key, and the server (a small PHP + MySQL API, see [`backend/`](backend/README.md)) stores only a hash of it, so a forgotten password can't be reset. The library is stored compressed, not encrypted. Profile photos stay on the phone. Signing out only stops syncing on that phone; the account keeps its library. There is no in-app way yet to delete an account's library from the server.

The profile also holds a name and favourite languages/moods/singers, which seed the recommendations. Optionally (off by default) it keeps the device model and an approximate, city-level location. Guests can keep 5 songs per playlist and can't share playlists; signing in lifts both limits.

## Logo
`assets/mark-chrome.webp` is the master (transparent background). The Android launcher, adaptive/monochrome and splash images under `android/app/src/main/res/` were generated from it.

## Credits, licence and branding
- **Author:** Sambit Maity — https://www.linkedin.com/in/sambitmaity/
- **Source code:** https://github.com/loco0011/samgeet
- **Licence:** the code is MIT licensed. Keep the copyright notice and credit the original author in any copy or fork.
- **Name and logo:** "Samgeet" and the logo belong to Sambit Maity and are *not* covered by the MIT licence. Forks must use their own name and logo.
- **Music:** the app hosts no music; songs are streamed from a third-party catalogue and belong to their rights holders. Not affiliated with that service or any label. Personal, non-commercial use only.
- **No warranty:** provided "as is". See [NOTICE.md](NOTICE.md) and the in-app About screen.
