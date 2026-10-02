<?php
// Shared by every Samgeet v2 endpoint: config, database, rate limits, and the two checks every app
// request must pass:
//
// 1. It comes from the app. Each request carries
//      X-Samgeet-Device: the install's random 64-hex secret (only its hash is stored)
//      X-Samgeet-Time:   unix seconds
//      X-Samgeet-Sign:   hex HMAC-SHA256(app_key, "<endpoint>\n<time>\n<device>\n" + sha256hex(body))
//    app_key is a secret built into release APKs (never in git) and kept in config.php here. Requests
//    older or newer than 5 minutes are refused, so a captured request can't be replayed later.
// 2. Who is asking. Signed-in calls carry "X-Samgeet-Session: <token>" from auth.php's login; the
//    token's hash is looked up in `sessions`, which says which account (users.id) it belongs to.
//    Everything an account can read or change is selected by that id, never by an id the caller sends.

declare(strict_types=1);

ini_set('display_errors', '0'); // errors go to the server log, never to the caller

const SG_CLOCK_SKEW = 300;            // seconds a signed request may be early or late
const SG_SESSION_DAYS = 120;          // sessions are renewed on use; unused ones expire
const SG_IP_LIMIT = 400;              // requests per IP per 10 minutes (many phones can share one IP)
const SG_DEVICE_LIMIT = 150;          // requests per phone per 10 minutes

function sg_headers(): void
{
    header('Content-Type: application/json; charset=utf-8');
    header('X-Content-Type-Options: nosniff');
    header('Cache-Control: no-store');
    header('X-Robots-Tag: noindex, nofollow');
    header('Referrer-Policy: no-referrer');
}

function sg_respond(int $code, array $body): void
{
    http_response_code($code);
    echo json_encode($body, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    exit;
}

/// Settings: config.php next to this folder (blocked by .htaccess) holds app_key, and may hold the
/// database credentials too; otherwise they come from the samgeet_config.php the first API used,
/// found by looking in the folders above this one.
function sg_config(): array
{
    static $cfg = null;
    if ($cfg !== null) return $cfg;
    $local = dirname(__DIR__) . '/config.php';
    $cfg = is_file($local) ? (require $local) : [];
    if (!is_array($cfg)) $cfg = [];
    if (empty($cfg['name'])) {
        // The first API keeps its login in samgeet_config.php (outside the web folder) or in the
        // config.php next to share.php; look for either in the folders above this one.
        $dir = dirname(__DIR__);
        for ($i = 0; $i < 7 && empty($cfg['name']); $i++) {
            $dir = dirname($dir);
            foreach (['samgeet_config.php', 'config.php'] as $name) {
                $f = $dir . '/' . $name;
                if (!is_file($f)) continue;
                $db = require $f;
                if (is_array($db) && !empty($db['name'])) {
                    $cfg += $db;
                    break;
                }
            }
        }
    }
    return $cfg;
}

function sg_db(): PDO
{
    static $pdo = null;
    if ($pdo !== null) return $pdo;
    $cfg = sg_config();
    if (empty($cfg['name'])) sg_respond(500, ['error' => 'not_configured']);
    try {
        $pdo = new PDO(
            "mysql:host={$cfg['host']};dbname={$cfg['name']};charset=utf8mb4",
            $cfg['user'],
            $cfg['pass'],
            [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION, PDO::ATTR_EMULATE_PREPARES => false, PDO::ATTR_TIMEOUT => 5]
        );
        $pdo->exec("SET time_zone = '+00:00'"); // every DATETIME is UTC
    } catch (Throwable $e) {
        error_log('samgeet db connect: ' . $e->getMessage());
        sg_respond(500, ['error' => 'db']);
    }
    return $pdo;
}

function sg_ip(): string
{
    return substr((string)($_SERVER['REMOTE_ADDR'] ?? ''), 0, 45);
}

/// Counts a request for [who] in the current 10-minute window; 429 once it passes [limit].
function sg_rate(PDO $pdo, string $who, int $limit): void
{
    $key = hash('sha256', $who);
    $bucket = intdiv(time(), 600);
    $pdo->prepare('INSERT INTO api_hits (ip_hash, bucket, hits) VALUES (?, ?, 1)
                   ON DUPLICATE KEY UPDATE hits = LEAST(hits + 1, 65000)')->execute([$key, $bucket]);
    $q = $pdo->prepare('SELECT hits FROM api_hits WHERE ip_hash = ? AND bucket = ?');
    $q->execute([$key, $bucket]);
    if ((int)$q->fetchColumn() > $limit) {
        header('Retry-After: 600');
        sg_respond(429, ['error' => 'slow_down']);
    }
    if (random_int(1, 100) === 1) {
        $pdo->prepare('DELETE FROM api_hits WHERE bucket < ?')->execute([$bucket - 2]);
    }
}

/// Checks that this is a signed request from the app (see the top of this file) and returns
/// [the parsed JSON body, the install key]. Anything else gets a bare 404, so the API doesn't
/// advertise itself to scanners.
function sg_app_request(string $endpoint, int $maxBody = 65536): array
{
    sg_headers();
    if (($_SERVER['REQUEST_METHOD'] ?? '') !== 'POST') sg_respond(404, ['error' => 'no_route']);

    $device = (string)($_SERVER['HTTP_X_SAMGEET_DEVICE'] ?? '');
    $time = (string)($_SERVER['HTTP_X_SAMGEET_TIME'] ?? '');
    $sign = strtolower((string)($_SERVER['HTTP_X_SAMGEET_SIGN'] ?? ''));
    if (!preg_match('/^[a-f0-9]{64}$/', $device) || !preg_match('/^\d{9,11}$/', $time) || !preg_match('/^[a-f0-9]{64}$/', $sign)) {
        sg_respond(404, ['error' => 'no_route']);
    }

    $appKey = (string)(sg_config()['app_key'] ?? '');
    if (strlen($appKey) < 32) sg_respond(500, ['error' => 'not_configured']);

    $raw = file_get_contents('php://input', false, null, 0, $maxBody + 1);
    if ($raw === false || strlen($raw) > $maxBody) sg_respond(413, ['error' => 'too_large']);

    $expect = hash_hmac('sha256', $endpoint . "\n" . $time . "\n" . $device . "\n" . hash('sha256', $raw), $appKey);
    if (!hash_equals($expect, $sign)) sg_respond(404, ['error' => 'no_route']);
    if (abs(time() - (int)$time) > SG_CLOCK_SKEW) sg_respond(401, ['error' => 'clock', 'server_time' => time()]);

    $in = $raw === '' ? [] : json_decode($raw, true);
    if (!is_array($in)) sg_respond(400, ['error' => 'bad_json']);

    $pdo = sg_db();
    try {
        sg_rate($pdo, 'ip:' . sg_ip(), SG_IP_LIMIT);
        sg_rate($pdo, 'dev:' . $device, SG_DEVICE_LIMIT);
    } catch (Throwable $e) {
        error_log('samgeet rate: ' . $e->getMessage());
        sg_respond(500, ['error' => 'server']);
    }
    return [$in, $device];
}

function sg_text($v, int $max): string
{
    if (!is_string($v) && !is_int($v) && !is_float($v)) return '';
    $v = preg_replace('/[\x00-\x1F\x7F]+/u', ' ', (string)$v);
    return mb_substr(trim($v ?? ''), 0, $max);
}

/// The devices row for this install (made on first contact), refreshed with [info] when given.
function sg_device(PDO $pdo, string $installKey, ?array $info = null): int
{
    $hash = hash('sha256', 'samgeet-install:' . $installKey);
    if ($info !== null) {
        $build = isset($info['app_build']) && is_numeric($info['app_build']) ? (int)$info['app_build'] : null;
        $sdk = isset($info['sdk']) && is_numeric($info['sdk']) ? min(65535, max(0, (int)$info['sdk'])) : null;
        $pdo->prepare('INSERT INTO devices (install_hash, brand, model, os_version, sdk, app_version, app_build, locale, timezone, last_ip)
                       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                       ON DUPLICATE KEY UPDATE brand = VALUES(brand), model = VALUES(model), os_version = VALUES(os_version),
                         sdk = VALUES(sdk), app_version = VALUES(app_version), app_build = VALUES(app_build),
                         locale = VALUES(locale), timezone = VALUES(timezone), last_ip = VALUES(last_ip), last_seen_at = UTC_TIMESTAMP()')
            ->execute([
                $hash,
                sg_text($info['brand'] ?? '', 40),
                sg_text($info['model'] ?? '', 80),
                sg_text($info['os'] ?? '', 20),
                $sdk,
                sg_text($info['app_version'] ?? '', 20),
                $build,
                sg_text($info['locale'] ?? '', 20),
                sg_text($info['tz'] ?? '', 40),
                sg_ip(),
            ]);
    } else {
        $pdo->prepare('INSERT INTO devices (install_hash, last_ip) VALUES (?, ?)
                       ON DUPLICATE KEY UPDATE last_seen_at = UTC_TIMESTAMP(), last_ip = VALUES(last_ip)')
            ->execute([$hash, sg_ip()]);
    }
    $q = $pdo->prepare('SELECT id FROM devices WHERE install_hash = ?');
    $q->execute([$hash]);
    return (int)$q->fetchColumn();
}

/// The session token, or null. The app sends it as X-Samgeet-Session (some shared hosts drop the
/// Authorization header before PHP sees it); "Authorization: Bearer" works too.
function sg_bearer(): ?string
{
    $h = (string)($_SERVER['HTTP_X_SAMGEET_SESSION'] ?? '');
    if ($h === '') {
        $auth = (string)($_SERVER['HTTP_AUTHORIZATION'] ?? $_SERVER['REDIRECT_HTTP_AUTHORIZATION'] ?? '');
        if (strncmp($auth, 'Bearer ', 7) === 0) $h = substr($auth, 7);
    }
    return preg_match('/^[A-Za-z0-9_-]{43}$/', $h) ? $h : null;
}

/// The signed-in account for this request: [user id, session id], or null for a guest.
/// A token is only good on the phone it was issued to. With [required], guests get 401.
function sg_user(PDO $pdo, int $deviceId, bool $required): ?array
{
    $token = sg_bearer();
    if ($token !== null) {
        $q = $pdo->prepare('SELECT s.id, s.user_id, u.status FROM sessions s JOIN users u ON u.id = s.user_id
                            WHERE s.token_hash = ? AND s.device_id = ? AND s.revoked_at IS NULL AND s.expires_at > UTC_TIMESTAMP()');
        $q->execute([hash('sha256', $token), $deviceId]);
        $row = $q->fetch(PDO::FETCH_ASSOC);
        if ($row) {
            if ($row['status'] !== 'active') sg_respond(403, ['error' => 'blocked']);
            // Renew at most once an hour, so busy phones don't write on every request.
            $pdo->prepare('UPDATE sessions SET last_used_at = UTC_TIMESTAMP(), expires_at = UTC_TIMESTAMP() + INTERVAL ' . SG_SESSION_DAYS . ' DAY
                           WHERE id = ? AND last_used_at < UTC_TIMESTAMP() - INTERVAL 1 HOUR')->execute([$row['id']]);
            $pdo->prepare('UPDATE users SET last_seen_at = UTC_TIMESTAMP() WHERE id = ? AND (last_seen_at IS NULL OR last_seen_at < UTC_TIMESTAMP() - INTERVAL 5 MINUTE)')
                ->execute([$row['user_id']]);
            return [(int)$row['user_id'], (int)$row['id']];
        }
        if ($required) sg_respond(401, ['error' => 'session']);
    }
    if ($required) sg_respond(401, ['error' => 'sign_in']);
    return null;
}

/// Starts a session for [userId] on [deviceId] and returns the token (shown once, stored hashed).
function sg_new_session(PDO $pdo, int $userId, int $deviceId): string
{
    $token = rtrim(strtr(base64_encode(random_bytes(32)), '+/', '-_'), '=');
    $pdo->prepare('INSERT INTO sessions (user_id, device_id, token_hash, expires_at)
                   VALUES (?, ?, ?, UTC_TIMESTAMP() + INTERVAL ' . SG_SESSION_DAYS . ' DAY)')
        ->execute([$userId, $deviceId, hash('sha256', $token)]);
    $pdo->prepare('UPDATE devices SET user_id = ? WHERE id = ?')->execute([$userId, $deviceId]);
    $pdo->prepare('UPDATE users SET last_seen_at = UTC_TIMESTAMP() WHERE id = ?')->execute([$userId]);
    return $token;
}

/// Runs [fn] and turns any database error into a plain 500 (details go to the server log).
function sg_guard(string $what, callable $fn): void
{
    try {
        $fn();
    } catch (Throwable $e) {
        error_log("samgeet $what: " . $e->getMessage());
        sg_respond(500, ['error' => 'server']);
    }
}
