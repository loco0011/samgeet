# Samgeet — How it works, where the music comes from, drawbacks and legality

> Written from a read of the source code (v1.1.0+3). This is a technical and practical
> assessment, **not legal advice**. If you plan to publish or distribute the app, talk to a
> lawyer who knows copyright law in your country.

---

## 1. What the app is

Samgeet is a Flutter music player (Android is the main target; iOS, web, Windows, macOS and
Linux folders exist). It has no backend of its own, no music files and no user accounts. All
it does is:

1. Talk to a third-party music service's web API from the phone.
2. Play the audio streams it gets back.
3. Save your favourites, playlists, history and taste profile on the phone.

| Layer | Where | Job |
|---|---|---|
| API client | `lib/data/saavn_api.dart` | Search, home shelves, albums, artists, lyrics, radio |
| Models | `lib/data/track.dart` | `Track` model and the stream-URL decryption |
| Player | `lib/player/player_controller.dart` | Queue, `just_audio` playback, background audio, sleep timer, auto-refill |
| Recommendations | `lib/engine/*` | Mood inference, taste profile, ranking |
| Local storage | `lib/data/library_store.dart` | `SharedPreferences` (favourites, playlists, history, profile) |
| UI | `lib/ui/*` | Screens and widgets |

---

## 2. Where the music comes from

**The audio is not yours and not hosted by the app.** It is streamed from **JioSaavn**, a
commercial Indian streaming service, through its **unofficial, undocumented web API**.

Evidence in the code:

- `saavn_api.dart` sets `_host = 'www.jiosaavn.com'` and calls `https://www.jiosaavn.com/api.php`.
- The calls (`search.getResults`, `song.getDetails`, `webapi.getLaunchData`,
  `webradio.createEntityStation`, `lyrics.getLyrics`, …) use the parameters
  `ctx=web6dot0` and `api_version=4`. These are the internal calls JioSaavn's own website uses.
  There is no public, licensed developer API involved.
- The class is called `SaavnApi`, and `tool/check_stream.dart` hits `jiosaavn.com` directly.

### Step by step: from tap to sound

```
 You search / open a shelf
        │
        ▼
 SaavnApi._get()  ──►  GET https://www.jiosaavn.com/api.php?__call=...&ctx=web6dot0
        │              (sends a fake "Pixel 7 / Chrome" User-Agent)
        ▼
 JSON with songs. Each song has `encrypted_media_url`  (base64, DES-encrypted)
        │
        ▼
 Track.streamUrl() → decryptMediaUrl()
        │   DES / ECB / PKCS5 with a hard-coded key ("38346591")
        ▼
 A plain https URL ending in  _96.mp4 / _160.mp4 / _320.mp4
        │   (quality suffix is rewritten to match your Settings choice)
        ▼
 just_audio plays that URL (AudioSource.uri) with just_audio_background
        │   → notification, lock-screen controls, background playback
        ▼
 Sound
```

Key points:

1. **Search and browsing.** Plain HTTPS `GET` requests to JioSaavn, JSON back. Responses are
   cached in memory for 5 minutes to 6 hours depending on the call, so navigation feels fast.
2. **The stream link is protected on purpose.** JioSaavn does not hand out a direct MP3 URL. It
   returns an *encrypted* one. The app decrypts it with a DES key that is hard-coded in
   `track.dart`. That key is not the app's own secret. It was worked out from JioSaavn's client
   and is shared by many open-source "Saavn downloader" projects.
3. **Quality.** The URL's `_96` / `_160` / `_320` suffix is swapped to match the Settings
   choice (Data saver / Balanced / High quality). 320 kbps is only used if the song's
   `320kbps` flag is true.
4. **Playback.** `just_audio` streams the URL. Nothing is downloaded or saved to disk. The
   track is buffered as you play it, and only the song's metadata and encrypted link are stored
   locally.
5. **Lyrics.** Fetched from JioSaavn's `lyrics.getLyrics` and shown in the player.
6. **"Smart radio" / autoplay.** When the queue runs low, `RecommendationService` asks
   JioSaavn's radio endpoint for similar songs and also runs extra searches (same artist, your
   favourite artists, the category you started from). `Recommender` then ranks those candidates
   on-device using your taste profile and the inferred mood. There is no ML on the audio and no
   server of your own. The mood is guessed from title, album and era keywords (see
   `lib/engine/mood.dart`).
7. **Your data.** Profile, favourites, playlists, history and taste weights are saved as JSON in
   `SharedPreferences` on the device. The app has no backend and does not upload them. (Note
   that JioSaavn still sees every request you make: your IP, the songs you search and play,
   and the spoofed User-Agent.)
8. **"Sign in".** It is only a local profile with a name and preferences. There is no password
   and no cloud sync. It is not a real account.

---

## 3. Drawbacks and risks

### Reliability (the most likely thing to hurt you)

- **It can stop working at any time.** It depends on an undocumented API. If JioSaavn changes
  an endpoint, rotates the DES key, adds tokens or signatures, or blocks the app, everything
  breaks and there is nothing you can do on your side except push an update.
- **Ready-made kill switch for the other side.** The app pretends to be Chrome on a Pixel 7. That
  is easy to detect and rate-limit or block, especially if many people use the app from the
  same IPs.
- **Old links.** Tracks are stored with their encrypted URL. If JioSaavn expires or moves files,
  saved favourites and playlists stop playing. The app does have a "fetch details again" path
  in `_makePlayable`, but only for tracks with no URL.
- **Catalogue gaps.** Some songs are removed or region-locked. Availability and quality can
  change without notice (the app's own NOTICE says so).
- **Recommendations are approximate.** Mood is a keyword guess, not audio analysis. Expect the
  occasional mismatched song.

### Technical / product limitations

- **No offline mode.** Nothing is cached to disk, so there is no download-and-listen. This is
  also partly why it is a bit safer legally than a downloader (see below).
- **No real accounts or sync.** Changing phone means losing your library. Guests are limited to
  5 songs per playlist by design.
- **Security of the design.** The hard-coded DES key is not a secret. DES-ECB is weak
  encryption and was never meant to protect anything from you, only to stop casual scraping.
- **Privacy is only partial.** Data stays on the device, but JioSaavn receives your requests
  (IP address, search terms, play activity).
- **Dependency pin.** `cached_network_image` is pinned to 3.4.1 because 4.x doesn't compile
  with the current Flutter version. Future upgrades will need attention.
- **Platform support is uneven.** The README verifies Android behaviour (background audio,
  notifications). Other platform folders exist but are not tested.
- **Store distribution.** An app built on an unofficial scraping API and decrypted streams will
  almost certainly be rejected or removed from Google Play and the Apple App Store, so
  distribution is realistically by sideloaded APK (`dist/Samgeet.apk`).

---

## 4. Is it legal?

Short version: **the source code is legal to write and share; the way the app gets and plays
the music is very likely not authorised, and distributing it publicly is the riskiest part.**
The details depend on your country. India is used below because the catalogue is Indian and
the author appears to be there. Similar ideas apply in most places.

### 4.1 What the code itself is

- The Flutter code, UI and recommender are original work under the **MIT licence** (`LICENSE`).
  Publishing source code is not illegal in itself. The MIT licence covers the code only.
- The **name and logo** are explicitly excluded from MIT and reserved (`NOTICE.md`).

### 4.2 The music

- The songs belong to artists, labels, composers and publishers. Samgeet has no licence from
  any of them. The `NOTICE.md` disclaimer ("does not host or own any music") is honest, but
  **saying you don't host the music does not make streaming it licensed.** A disclaimer is not
  a licence.
- JioSaavn has licences to stream this catalogue **inside its own apps and website, under its
  own Terms of Use.** Those licences do not pass on to a third-party app.

### 4.3 The specific issues

| Issue | Why it matters |
|---|---|
| **Using an unofficial API** | JioSaavn's terms almost certainly forbid unauthorised access, scraping, reverse engineering and building third-party clients. Breaking a site's terms is a contract / terms-of-use problem, and in some countries can also fall under computer-misuse laws. I have not read JioSaavn's current terms. Check them. |
| **Ad-free streaming** | The app's headline feature is "ad-free". Removing or bypassing the ad and subscription model that pays for the licences is the sort of thing that gets a service to send a takedown or cease-and-desist. |
| **Decrypting the stream URL** | Decrypting a protected link with a key extracted from someone else's client can be treated as **circumventing a technical protection measure**. That is specifically restricted in many places, e.g. DMCA §1201 in the US and Section 65A of the Copyright Act, 1957 in India. It is a separate potential violation from copyright infringement itself. Whether a weak DES scheme counts as an "effective" measure is arguable, but you would be arguing it in court. |
| **Spoofed User-Agent** | The app claims to be a Chrome browser on a Pixel 7. That is a deliberate disguise and does not help if the service ever claims unauthorised access. |
| **Possibly getting around paywalls** | If some qualities (for example 320 kbps) are meant for paying subscribers, serving them to anyone who asks bypasses that. I have not confirmed how JioSaavn gates 320 kbps. Test it before making claims either way. |
| **Lyrics** | Lyrics are separately copyrighted (by writers and publishers). Showing them without a licence is its own exposure. |
| **Artwork and metadata** | Album art is loaded from JioSaavn's CDN and is also copyrighted. The app hotlinks it. |
| **Public distribution (APK in `dist/`, GitHub, WhatsApp, etc.)** | This is the big step up in risk. Personal use is one thing. Handing an app whose purpose is free, ad-free access to a licensed catalogue to other people can be treated as **facilitating or inducing infringement**, and it is exactly what rights holders and platforms act against. Under the Indian Copyright Act (Sections 51, 63) and similar laws elsewhere, commercial or large-scale infringement can bring criminal penalties, not only civil claims. |

### 4.4 Common defences, and why they are weaker than they sound

- **"It only streams, it doesn't download or store."** This helps less than people think.
  Streaming still involves communicating and reproducing the work, and doesn't fix the terms
  of use or the circumvention problem.
- **"I don't host any files."** True and useful, and it lowers the risk compared with a site
  that hosts the music, but it does not create a licence.
- **"It's open source and non-commercial."** Non-commercial helps a bit with damages and
  enforcement priority. It is not a legal defence to infringement or to breaking terms.
- **"The disclaimer says users are responsible."** That may shift some blame, but courts and
  rights holders don't accept a disclaimer as a substitute for permission, especially when the
  app's design *is* the thing that makes access possible.

### 4.5 Realistic risk picture

| Scenario | Rough risk |
|---|---|
| Using it privately, on your own phone, for yourself | Low practical risk of anyone acting against you. Still not authorised. |
| Keeping the source on GitHub with a clear disclaimer | Low to moderate. The realistic outcome is a DMCA takedown or repo removal notice, or an account warning. |
| Sharing the APK with friends | Moderate. |
| Publicly distributing the APK or promoting the app as a free, ad-free alternative | **High.** Cease-and-desist, takedown, and possibly legal action. |
| Putting it on Google Play or the App Store | Will be rejected or removed. |
| Charging money, adding your own ads or donations tied to it | **Highest.** Commercial use removes most of the sympathy and raises exposure. |

---

## 5. How to make it legitimate

If you want to keep the app and ship it safely, these are the real options:

1. **Use a properly licensed source.** Swap the data layer for something that is meant to be
   built on, e.g.
   - **Jamendo**, **Free Music Archive** and **Internet Archive**: Creative Commons /
     public-domain music with public APIs.
   - **Audius** (decentralised, has a public API).
   - **Official SDKs** such as the Spotify or Apple Music SDKs. They require the user to have
     an account and normally do not allow ad-free or free playback, but they are allowed.
   - **A licensed deal or partnership** with JioSaavn (or another service) that grants
     official API access.
2. **Make it a player for the user's own files.** Local library and user-provided sources are
   the cleanest legal model. Your UI, mood theme and recommender would work on that too.
3. **If you keep JioSaavn:** keep it private and clearly labelled as an unofficial
   proof-of-concept, do not distribute the APK, do not use the JioSaavn name or branding, and
   be ready to remove it if asked. Do not remove or hide the attribution or the disclaimers you
   already have.
4. **Whatever you choose:** don't monetise it, keep the `NOTICE.md` wording accurate, and
   consider changing the ad-free / free-320kbps marketing lines in the README, since they
   describe the exact thing rights holders care about.

---

## 6. Summary

| Question | Answer |
|---|---|
| Where does the music come from? | JioSaavn's servers, through its unofficial web API. Nothing is hosted by the app. |
| How does it play? | Fetch metadata → get an encrypted stream URL → decrypt it on-device with a hard-coded DES key → stream it with `just_audio`. |
| Where is my data? | On your phone only (`SharedPreferences`). JioSaavn still sees your requests. |
| Biggest technical drawback? | Depends on an undocumented API that can change or block you at any time. |
| Is the code legal? | Yes. It is MIT-licensed original work. |
| Is the streaming legal? | Very likely **not authorised** (terms of use, licensing, possible circumvention of protection, ad-free access). |
| Safest use? | Private and personal, or swap in a licensed or open-licence music source before sharing it. |
