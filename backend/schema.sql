-- Samgeet profile table. Run once in phpMyAdmin (Databases -> phpMyAdmin -> your database -> SQL).
CREATE TABLE IF NOT EXISTS profiles (
  id                INT UNSIGNED NOT NULL AUTO_INCREMENT,
  token_hash        CHAR(64)     NOT NULL,            -- sha256 of the per-install secret; the secret itself is never stored
  name              VARCHAR(80)  NOT NULL,
  email             VARCHAR(190) NOT NULL,
  avatar            VARCHAR(40)  NOT NULL DEFAULT '',  -- icon id or emoji:<emoji>; uploaded photos stay on the phone
  languages         TEXT         NOT NULL,             -- JSON array
  moods             TEXT         NOT NULL,             -- JSON array
  artists           TEXT         NOT NULL,             -- JSON array
  share_device_info TINYINT(1)   NOT NULL DEFAULT 0,
  device            TEXT         NULL,                 -- JSON; only set when share_device_info = 1
  last_ip           VARCHAR(45)  NULL,                 -- only set when share_device_info = 1
  client_created_at BIGINT       NULL,
  created_at        TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at        TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_token (token_hash),
  KEY idx_email (email)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Per-IP request counter used to rate-limit the API (rows are purged automatically).
CREATE TABLE IF NOT EXISTS api_hits (
  ip_hash CHAR(64)     NOT NULL,        -- sha256 of the caller's IP, never the IP itself
  bucket  INT UNSIGNED NOT NULL,        -- unix time / 600 (a 10-minute window)
  hits    SMALLINT UNSIGNED NOT NULL DEFAULT 0,
  PRIMARY KEY (ip_hash, bucket)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
