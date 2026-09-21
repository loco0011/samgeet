<?php
// Samgeet profile API.
//   POST {"action":"save", name, email, avatar, languages, moods, artists, share_device_info, device, created_at}
//   POST {"action":"delete"}
// Every request carries X-Install-Key: a random 64-hex secret made by the app on first run.
// Only its sha256 is stored, so only that install can change or delete its own profile.

ini_set('display_errors', '0'); // errors go to the server log, never to the caller
header('Content-Type: application/json; charset=utf-8');
header('X-Content-Type-Options: nosniff');
header('Cache-Control: no-store');

function respond($code, $body)
{
    http_response_code($code);
    echo json_encode($body, JSON_UNESCAPED_UNICODE);
    exit;
}

function clean_list($v, $maxItems, $maxLen)
{
    if (!is_array($v)) return [];
    $out = [];
    foreach ($v as $item) {
        if (!is_string($item)) continue;
        $item = trim($item);
        if ($item === '' || mb_strlen($item) > $maxLen) continue;
        $out[] = $item;
        if (count($out) >= $maxItems) break;
    }
    return $out;
}

if (($_SERVER['REQUEST_METHOD'] ?? '') !== 'POST') respond(405, ['error' => 'post_only']);

$key = $_SERVER['HTTP_X_INSTALL_KEY'] ?? '';
if (!preg_match('/^[a-f0-9]{64}$/', $key)) respond(401, ['error' => 'bad_key']);
$hash = hash('sha256', $key);

$raw = file_get_contents('php://input', false, null, 0, 16385);
if ($raw === false || strlen($raw) > 16384) respond(413, ['error' => 'too_large']);
$in = json_decode($raw, true);
if (!is_array($in)) respond(400, ['error' => 'bad_json']);

// Prefer credentials kept OUTSIDE the public web folder (three levels up from this file, e.g.
// domains/<site>/samgeet_config.php on Hostinger); fall back to api/config.php, which .htaccess blocks.
$configFile = null;
foreach ([dirname(__DIR__, 3) . '/samgeet_config.php', __DIR__ . '/config.php'] as $candidate) {
    if (is_file($candidate)) { $configFile = $candidate; break; }
}
if ($configFile === null) respond(500, ['error' => 'not_configured']);
$cfg = require $configFile;

try {
    $pdo = new PDO(
        "mysql:host={$cfg['host']};dbname={$cfg['name']};charset=utf8mb4",
        $cfg['user'],
        $cfg['pass'],
        [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION, PDO::ATTR_EMULATE_PREPARES => false, PDO::ATTR_TIMEOUT => 5]
    );
} catch (Throwable $e) {
    error_log('samgeet db connect: ' . $e->getMessage());
    respond(500, ['error' => 'db']);
}

try {
    // Throttle per IP: at most 60 requests per 10 minutes, so nobody can flood the table.
    $ipHash = hash('sha256', (string)($_SERVER['REMOTE_ADDR'] ?? ''));
    $bucket = intdiv(time(), 600);
    $pdo->prepare('INSERT INTO api_hits (ip_hash, bucket, hits) VALUES (?, ?, 1)
                   ON DUPLICATE KEY UPDATE hits = hits + 1')->execute([$ipHash, $bucket]);
    $q = $pdo->prepare('SELECT hits FROM api_hits WHERE ip_hash = ? AND bucket = ?');
    $q->execute([$ipHash, $bucket]);
    if ((int)$q->fetchColumn() > 60) {
        header('Retry-After: 600');
        respond(429, ['error' => 'slow_down']);
    }
    if (random_int(1, 50) === 1) {
        $pdo->prepare('DELETE FROM api_hits WHERE bucket < ?')->execute([$bucket - 2]);
    }

    $action = $in['action'] ?? '';

    if ($action === 'delete') {
        $pdo->prepare('DELETE FROM profiles WHERE token_hash = ?')->execute([$hash]);
        respond(200, ['ok' => true]);
    }

    if ($action !== 'save') respond(400, ['error' => 'bad_action']);

    $name = trim((string)($in['name'] ?? ''));
    if ($name === '' || mb_strlen($name) > 80) respond(422, ['error' => 'bad_name']);

    $email = strtolower(trim((string)($in['email'] ?? '')));
    if (strlen($email) > 190 || !filter_var($email, FILTER_VALIDATE_EMAIL)) respond(422, ['error' => 'bad_email']);

    $avatar = (string)($in['avatar'] ?? '');
    if (mb_strlen($avatar) > 40 || strpos($avatar, 'photo:') === 0) $avatar = '';

    $languages = clean_list($in['languages'] ?? [], 30, 40);
    $moods = clean_list($in['moods'] ?? [], 30, 40);
    $artists = clean_list($in['artists'] ?? [], 80, 80);

    // Device details and IP are kept only when the listener opted in.
    $share = !empty($in['share_device_info']) ? 1 : 0;
    $device = null;
    $ip = null;
    if ($share && isset($in['device']) && is_array($in['device'])) {
        $device = json_encode($in['device'], JSON_UNESCAPED_UNICODE);
        if (strlen($device) > 4000) $device = null;
    }
    if ($share) $ip = substr((string)($_SERVER['REMOTE_ADDR'] ?? ''), 0, 45) ?: null;

    $created = isset($in['created_at']) && is_numeric($in['created_at']) ? (int)$in['created_at'] : null;

    $sql = 'INSERT INTO profiles
              (token_hash, name, email, avatar, languages, moods, artists, share_device_info, device, last_ip, client_created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON DUPLICATE KEY UPDATE
              name = VALUES(name), email = VALUES(email), avatar = VALUES(avatar),
              languages = VALUES(languages), moods = VALUES(moods), artists = VALUES(artists),
              share_device_info = VALUES(share_device_info), device = VALUES(device), last_ip = VALUES(last_ip)';
    $pdo->prepare($sql)->execute([
        $hash, $name, $email, $avatar,
        json_encode($languages, JSON_UNESCAPED_UNICODE),
        json_encode($moods, JSON_UNESCAPED_UNICODE),
        json_encode($artists, JSON_UNESCAPED_UNICODE),
        $share, $device, $ip, $created,
    ]);
    respond(200, ['ok' => true]);
} catch (Throwable $e) {
    error_log('samgeet profile: ' . $e->getMessage());
    respond(500, ['error' => 'server']);
}
