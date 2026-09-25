<?php
// Samgeet library sync API: one saved library per account key.
//   POST {"action":"load"}                          -> {"data":"<base64 gzip JSON>", "rev": n, "updated_at": unix}
//   POST {"action":"save", "data":"...", "base_rev": n|null}
//        base_rev is the rev the phone last saw (null to create). If someone saved in between, the
//        answer is 409 and the phone merges and tries again, so two phones never overwrite each other.
//   POST {"action":"delete"}
//   POST {"action":"check_email", "email_hash":"<sha256 hex>"}  -> {"exists": bool}   (no key needed)
// Saves may carry "email_hash" too, so sign-in can say "wrong password" instead of making a second account.
// Every other request carries X-Restore-Code: the account key, 12 Crockford base32 characters that the
// app derives from the listener's email and password. Only a hash of it is stored. The data is
// opaque to the server: it is stored and returned as-is.

ini_set('display_errors', '0'); // errors go to the server log, never to the caller
header('Content-Type: application/json; charset=utf-8');
header('X-Content-Type-Options: nosniff');
header('Cache-Control: no-store');

const MAX_DATA = 3000000; // base64 characters, about 2.2 MB of compressed data

function respond($code, $body)
{
    http_response_code($code);
    echo json_encode($body, JSON_UNESCAPED_UNICODE);
    exit;
}

if (($_SERVER['REQUEST_METHOD'] ?? '') !== 'POST') respond(405, ['error' => 'post_only']);

$raw = file_get_contents('php://input', false, null, 0, MAX_DATA + 1025);
if ($raw === false || strlen($raw) > MAX_DATA + 1024) respond(413, ['error' => 'too_large']);
$in = json_decode($raw, true);
if (!is_array($in)) respond(400, ['error' => 'bad_json']);
$action = $in['action'] ?? '';

// An email's hash: lets the app tell "wrong password" apart from "new account" at sign-in.
$emailHash = $in['email_hash'] ?? null;
if ($emailHash !== null && !(is_string($emailHash) && preg_match('/^[a-f0-9]{64}$/', $emailHash))) {
    respond(422, ['error' => 'bad_email_hash']);
}

if ($action !== 'check_email') {
    $code = $_SERVER['HTTP_X_RESTORE_CODE'] ?? '';
    if (!preg_match('/^[0-9A-HJKMNP-TV-Z]{12}$/', $code)) respond(401, ['error' => 'bad_code']);
    $hash = hash('sha256', 'samgeet-backup:' . $code);
}

// Same credentials as profile.php: outside the public web folder if possible, else api/config.php.
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
    // Throttle per IP (shared with profile.php): at most 60 requests per 10 minutes. This also
    // makes guessing an account key hopeless.
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

    if ($action === 'check_email') {
        if ($emailHash === null) respond(422, ['error' => 'bad_email_hash']);
        $q = $pdo->prepare('SELECT 1 FROM backups WHERE email_hash = ? LIMIT 1');
        $q->execute([$emailHash]);
        respond(200, ['exists' => (bool)$q->fetchColumn()]);
    }

    if ($action === 'load') {
        $q = $pdo->prepare('SELECT data, rev, UNIX_TIMESTAMP(updated_at) FROM backups WHERE code_hash = ?');
        $q->execute([$hash]);
        $row = $q->fetch(PDO::FETCH_NUM);
        if (!$row) respond(404, ['error' => 'not_found']);
        respond(200, ['data' => $row[0], 'rev' => (int)$row[1], 'updated_at' => (int)$row[2]]);
    }

    if ($action === 'delete') {
        $pdo->prepare('DELETE FROM backups WHERE code_hash = ?')->execute([$hash]);
        respond(200, ['ok' => true]);
    }

    if ($action !== 'save') respond(400, ['error' => 'bad_action']);

    $data = $in['data'] ?? null;
    if (!is_string($data) || $data === '' || strlen($data) > MAX_DATA || !preg_match('/^[A-Za-z0-9+\/]+=*$/', $data)) {
        respond(422, ['error' => 'bad_data']);
    }
    if (!array_key_exists('base_rev', $in) || !($in['base_rev'] === null || is_int($in['base_rev']))) {
        respond(422, ['error' => 'bad_rev']);
    }
    $base = $in['base_rev'];

    if ($base === null) {
        $st = $pdo->prepare('INSERT IGNORE INTO backups (code_hash, data, rev, email_hash) VALUES (?, ?, 1, ?)');
        $st->execute([$hash, $data, $emailHash]);
        if ($st->rowCount() === 1) respond(200, ['ok' => true, 'rev' => 1]);
    } else {
        $st = $pdo->prepare('UPDATE backups SET data = ?, rev = rev + 1, email_hash = COALESCE(?, email_hash) WHERE code_hash = ? AND rev = ?');
        $st->execute([$data, $emailHash, $hash, $base]);
        if ($st->rowCount() === 1) respond(200, ['ok' => true, 'rev' => $base + 1]);
    }
    respond(409, ['error' => 'conflict']); // another phone saved first: load, merge, try again
} catch (Throwable $e) {
    error_log('samgeet backup: ' . $e->getMessage());
    respond(500, ['error' => 'server']);
}
