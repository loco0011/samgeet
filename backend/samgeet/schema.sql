-- Samgeet server, version 2: accounts, devices, sessions, listening data, releases and notifications.
-- Run once in phpMyAdmin (open the database -> SQL tab -> paste -> Go). Safe to run again.
-- The old tables (profiles, backups, short_links, api_hits) stay: accounts move over from `backups` the
-- first time each listener signs in with the new app, and short links keep working.
--
-- How the tables relate:
--   users 1-n devices (last account on that phone), sessions, user_tastes, events
--   users 1-1 libraries (the synced library)
--   devices 1-n sessions, events, notification_receipts
--   tracks n-n artists (track_artists); tracks 1-n events
--   admins 1-n releases, notifications; notifications 1-n notification_receipts

SET NAMES utf8mb4;

CREATE TABLE IF NOT EXISTS users (
  id            INT UNSIGNED NOT NULL AUTO_INCREMENT,
  email         VARCHAR(190) NOT NULL,
  email_hash    CHAR(64)     NOT NULL,            -- sha256('samgeet-email:' + email), as the app computes it
  key_hash      CHAR(64)     NOT NULL,            -- sha256('samgeet-backup:' + account key); the key is derived on the phone
  name          VARCHAR(80)  NOT NULL DEFAULT '',
  avatar        VARCHAR(40)  NOT NULL DEFAULT '',
  player_style  VARCHAR(20)  NOT NULL DEFAULT 'disc',
  status        ENUM('active','blocked') NOT NULL DEFAULT 'active',
  created_at    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  last_seen_at  DATETIME     NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_users_email_hash (email_hash),
  UNIQUE KEY uq_users_key_hash (key_hash),
  KEY idx_users_last_seen (last_seen_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Favourite languages, moods and singers picked at sign-in, one row each (easy to count and group).
CREATE TABLE IF NOT EXISTS user_tastes (
  user_id  INT UNSIGNED NOT NULL,
  kind     ENUM('language','mood','artist') NOT NULL,
  value    VARCHAR(80)  NOT NULL,
  PRIMARY KEY (user_id, kind, value),
  KEY idx_tastes_kind_value (kind, value),
  CONSTRAINT fk_tastes_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- One row per install. The app makes a random 64-hex secret on first run; only its hash is stored.
CREATE TABLE IF NOT EXISTS devices (
  id           INT UNSIGNED NOT NULL AUTO_INCREMENT,
  install_hash CHAR(64)     NOT NULL,
  user_id      INT UNSIGNED NULL,                 -- the account last signed in on it
  brand        VARCHAR(40)  NOT NULL DEFAULT '',
  model        VARCHAR(80)  NOT NULL DEFAULT '',
  os_version   VARCHAR(20)  NOT NULL DEFAULT '',
  sdk          SMALLINT UNSIGNED NULL,
  app_version  VARCHAR(20)  NOT NULL DEFAULT '',
  app_build    INT UNSIGNED NULL,
  locale       VARCHAR(20)  NOT NULL DEFAULT '',
  timezone     VARCHAR(40)  NOT NULL DEFAULT '',
  last_ip      VARCHAR(45)  NULL,
  first_seen_at DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  last_seen_at  DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_devices_install (install_hash),
  KEY idx_devices_user (user_id),
  KEY idx_devices_last_seen (last_seen_at),
  KEY idx_devices_version (app_build),
  CONSTRAINT fk_devices_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Sign-in sessions: the app sends "Authorization: Bearer <token>"; only the token's hash is stored.
CREATE TABLE IF NOT EXISTS sessions (
  id           INT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id      INT UNSIGNED NOT NULL,
  device_id    INT UNSIGNED NOT NULL,
  token_hash   CHAR(64)     NOT NULL,
  created_at   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  last_used_at DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  expires_at   DATETIME     NOT NULL,
  revoked_at   DATETIME     NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_sessions_token (token_hash),
  KEY idx_sessions_user (user_id),
  KEY idx_sessions_device (device_id),
  CONSTRAINT fk_sessions_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE,
  CONSTRAINT fk_sessions_device FOREIGN KEY (device_id) REFERENCES devices (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- The synced library (playlists, favourites, history, settings): gzip'd JSON, opaque to the server.
CREATE TABLE IF NOT EXISTS libraries (
  user_id    INT UNSIGNED NOT NULL,
  data       MEDIUMTEXT   NOT NULL,
  rev        INT UNSIGNED NOT NULL DEFAULT 1,     -- a save must name the rev it built on (409 otherwise)
  updated_at DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (user_id),
  CONSTRAINT fk_libraries_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=ascii;

-- Songs and singers seen in listening data (details as the catalogue gave them), for reports.
CREATE TABLE IF NOT EXISTS tracks (
  id           VARCHAR(64)  NOT NULL,             -- the catalogue's song id
  title        VARCHAR(200) NOT NULL DEFAULT '',
  album        VARCHAR(200) NOT NULL DEFAULT '',
  album_id     VARCHAR(64)  NOT NULL DEFAULT '',
  language     VARCHAR(30)  NOT NULL DEFAULT '',
  year         SMALLINT UNSIGNED NULL,
  duration_sec SMALLINT UNSIGNED NULL,
  image        VARCHAR(400) NOT NULL DEFAULT '',
  first_seen_at DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_tracks_language (language),
  KEY idx_tracks_album (album_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS artists (
  id    VARCHAR(64)  NOT NULL,                    -- the catalogue's artist id, or 'name:<name>' when it has none
  name  VARCHAR(160) NOT NULL,
  PRIMARY KEY (id),
  KEY idx_artists_name (name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS track_artists (
  track_id  VARCHAR(64) NOT NULL,
  artist_id VARCHAR(64) NOT NULL,
  position  TINYINT UNSIGNED NOT NULL DEFAULT 0,  -- 0 = the main singer
  PRIMARY KEY (track_id, artist_id),
  KEY idx_track_artists_artist (artist_id),
  CONSTRAINT fk_ta_track FOREIGN KEY (track_id) REFERENCES tracks (id) ON DELETE CASCADE,
  CONSTRAINT fk_ta_artist FOREIGN KEY (artist_id) REFERENCES artists (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Everything the app reports: plays, skips, likes, downloads, shares, searches, opens...
-- See backend/README.md for the list of types and what `value` and `meta` hold for each.
CREATE TABLE IF NOT EXISTS events (
  id         BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  device_id  INT UNSIGNED NOT NULL,
  user_id    INT UNSIGNED NULL,                   -- null for guests
  type       VARCHAR(24)  NOT NULL,
  track_id   VARCHAR(64)  NULL,
  ms         INT UNSIGNED NULL,                   -- time listened (play_end), or other durations
  value      VARCHAR(255) NULL,                   -- e.g. the search text, the reason a song ended, a setting
  meta       TEXT         NULL,                   -- small JSON with anything else
  client_at  DATETIME     NOT NULL,               -- when it happened on the phone (UTC)
  created_at DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_events_type_time (type, client_at),
  KEY idx_events_user_time (user_id, client_at),
  KEY idx_events_device_time (device_id, client_at),
  KEY idx_events_track_type (track_id, type),
  CONSTRAINT fk_events_device FOREIGN KEY (device_id) REFERENCES devices (id) ON DELETE CASCADE,
  CONSTRAINT fk_events_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE,
  CONSTRAINT fk_events_track FOREIGN KEY (track_id) REFERENCES tracks (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- People who can open the admin panel. Passwords are stored as bcrypt hashes only.
CREATE TABLE IF NOT EXISTS admins (
  id            INT UNSIGNED NOT NULL AUTO_INCREMENT,
  email         VARCHAR(190) NOT NULL,
  password_hash VARCHAR(255) NOT NULL,
  created_at    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  last_login_at DATETIME     NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_admins_email (email)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Admin sign-in attempts, for locking out password guessing (old rows are purged).
CREATE TABLE IF NOT EXISTS admin_logins (
  id         INT UNSIGNED NOT NULL AUTO_INCREMENT,
  ip_hash    CHAR(64)     NOT NULL,
  email      VARCHAR(190) NOT NULL,
  success    TINYINT(1)   NOT NULL,
  created_at DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_admin_logins_ip (ip_hash, created_at),
  KEY idx_admin_logins_email (email, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- App versions published from the admin panel. The app offers the newest published one.
CREATE TABLE IF NOT EXISTS releases (
  id           INT UNSIGNED NOT NULL AUTO_INCREMENT,
  version_name VARCHAR(20)  NOT NULL,             -- "1.4.0"
  build        INT UNSIGNED NOT NULL,             -- pubspec build number; newer = bigger
  notes        TEXT         NOT NULL,
  apk_url      VARCHAR(400) NOT NULL,
  sha256       CHAR(64)     NOT NULL DEFAULT '',
  size_bytes   BIGINT UNSIGNED NULL,
  required     TINYINT(1)   NOT NULL DEFAULT 0,   -- no "Later" button
  published    TINYINT(1)   NOT NULL DEFAULT 0,
  created_by   INT UNSIGNED NULL,
  created_at   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  published_at DATETIME     NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_releases_build (build),
  KEY idx_releases_published (published, build),
  CONSTRAINT fk_releases_admin FOREIGN KEY (created_by) REFERENCES admins (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Messages sent from the admin panel: a popup inside the app, a phone notification, or both.
CREATE TABLE IF NOT EXISTS notifications (
  id           INT UNSIGNED NOT NULL AUTO_INCREMENT,
  title        VARCHAR(120) NOT NULL,
  body         TEXT         NOT NULL,
  image_url    VARCHAR(400) NOT NULL DEFAULT '',
  style        ENUM('info','celebrate','warning') NOT NULL DEFAULT 'info',
  action       ENUM('none','url','update','search') NOT NULL DEFAULT 'none',
  action_value VARCHAR(400) NOT NULL DEFAULT '',  -- the link, or the search text
  action_label VARCHAR(40)  NOT NULL DEFAULT '',
  show_as      ENUM('popup','system','both') NOT NULL DEFAULT 'both',
  audience     ENUM('all','signed_in','guests','below_build') NOT NULL DEFAULT 'all',
  audience_build INT UNSIGNED NULL,               -- for below_build: only apps older than this build
  starts_at    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  ends_at      DATETIME     NULL,
  active       TINYINT(1)   NOT NULL DEFAULT 1,
  created_by   INT UNSIGNED NULL,
  created_at   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_notifications_live (active, starts_at),
  CONSTRAINT fk_notifications_admin FOREIGN KEY (created_by) REFERENCES admins (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Which phone got which message, and whether it was opened or dismissed.
CREATE TABLE IF NOT EXISTS notification_receipts (
  notification_id INT UNSIGNED NOT NULL,
  device_id       INT UNSIGNED NOT NULL,
  delivered_at    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  opened_at       DATETIME     NULL,
  dismissed_at    DATETIME     NULL,
  PRIMARY KEY (notification_id, device_id),
  KEY idx_receipts_device (device_id),
  CONSTRAINT fk_receipts_notification FOREIGN KEY (notification_id) REFERENCES notifications (id) ON DELETE CASCADE,
  CONSTRAINT fk_receipts_device FOREIGN KEY (device_id) REFERENCES devices (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Per-caller request counter for rate limiting (rows are purged automatically).
-- Created by the first version too; the new API counts per phone as well as per IP.
CREATE TABLE IF NOT EXISTS api_hits (
  ip_hash CHAR(64)     NOT NULL,                  -- sha256 of the caller (IP or phone), never the IP itself
  bucket  INT UNSIGNED NOT NULL,                  -- unix time / 600 (a 10-minute window)
  hits    SMALLINT UNSIGNED NOT NULL DEFAULT 0,
  PRIMARY KEY (ip_hash, bucket)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Short share links (from schema v1, used by /s/<code>). Who shared what is in `events` (share_song,
-- share_playlist, with the code in `value`).
CREATE TABLE IF NOT EXISTS short_links (
  code         CHAR(7)   NOT NULL,
  payload_hash CHAR(64)  NOT NULL,
  payload      TEXT      NOT NULL,
  created_at   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (code),
  UNIQUE KEY uq_payload (payload_hash)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
