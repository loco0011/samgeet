# Third-party code kept in this repository

## just_audio_background (0.0.1-beta.17)
Copied from https://pub.dev/packages/just_audio_background (MIT License, © Ryan Heise and
contributors; see `just_audio_background/LICENSE`). Samgeet's changes, all in
`just_audio_background/lib/just_audio_background.dart` and marked `Samgeet:`:

- The notification / lock-screen controls are Previous, Play/Pause and Next. The package
  always showed Stop and hid Previous on the first song of the queue.
- Previous restarts the song unless it has only just begun (like the in-app button).
- Swiping the app away from recent apps stops playback (`onTaskRemoved`).

When updating the package, re-apply these changes to the new version.
