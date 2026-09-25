<?php
// Samgeet short links: https://api.sambitmaity.fun/s/<code> instead of a long share.php?... URL.
//   POST {"t":"song", "id", "s", "a", "al", "i"}   -> {"code":"k7qm2xa"}
//   POST {"t":"playlist", "n", "ids":[...]}         -> {"code":"..."}
//   GET  link.php?c=<code>                          -> the stored {"t":...} object
// The same song or playlist always gets the same code. Stored: only what the long link carried
// (song id/title/artist/album/cover, or a playlist's name and song ids). No personal data.

ini_set('display_errors', '0');
header('Content-Type: application/json; charset=utf-8');
header('X-Content-Type-Options: nosniff');

const CODE_CHARS = '23456789abcdefghjkmnpqrstuvwxyz'; // no 0/1/i/l/o: easy to read and type
const CODE_LEN = 7;

function respond($code, $body)
{
    http_response_code($code);
    echo json_encode($body, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    exit;
}

function text($v, $max)
{
    if (!is_string($v)) return '';
    $v = preg_replace('/[\x00-\x1F\x7F]+/u', ' ', $v);
    return mb_substr(trim($v === null ? '' : $v), 0, $max);
}

function valid_id($v)
{
    return is_string($v) && preg_match('/^[A-Za-z0-9_-]{1,64}$/', $v);
}

// Only cover art from the catalogue's own CDN is kept.
function cover($url)
{
    $p = parse_url($url);
    if (!$p || ($p['scheme'] ?? '') !== 'https' || isset($p['user']) || isset($p['port'])) return '';
    $host = strtolower($p['host'] ?? '');
    if ($host !== 'saavncdn.com' && substr($host, -13) !== '.saavncdn.com') return '';
    return $url;
}

/// The cleaned-up payload, or null if it isn't a song or playlist we can show.
function clean($in)
{
    if (!is_array($in)) return null;
    if (($in['t'] ?? '') === 'playlist') {
        $ids = [];
        foreach ((is_array($in['ids'] ?? null) ? $in['ids'] : []) as $id) {
            if (valid_id($id)) $ids[] = $id;
            if (count($ids) >= 500) break;
        }
        if (!$ids) return null;
        return ['t' => 'playlist', 'n' => text($in['n'] ?? '', 80) ?: 'Shared playlist', 'ids' => $ids];
    }
    if (!valid_id($in['id'] ?? null)) return null;
    return [
        't' => 'song',
        'id' => $in['id'],
        's' => text($in['s'] ?? '', 120),
        'a' => text($in['a'] ?? '', 160),
        'al' => text($in['al'] ?? '', 120),
        'i' => cover(text($in['i'] ?? '', 400)),
    ];
}

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
    // Looking a link up: cheap, cacheable, not rate limited (people tap links a lot).
    if (($_SERVER['REQUEST_METHOD'] ?? '') === 'GET') {
        $c = $_GET['c'] ?? '';
        if (!is_string($c) || !preg_match('/^[' . CODE_CHARS . ']{' . CODE_LEN . '}$/', $c)) respond(404, ['error' => 'not_found']);
        $q = $pdo->prepare('SELECT payload FROM short_links WHERE code = ?');
        $q->execute([$c]);
        $p = $q->fetchColumn();
        if ($p === false) respond(404, ['error' => 'not_found']);
        header('Cache-Control: public, max-age=86400');
        echo $p;
        exit;
    }

    if (($_SERVER['REQUEST_METHOD'] ?? '') !== 'POST') respond(405, ['error' => 'get_or_post']);
    header('Cache-Control: no-store');

    // Making links: at most 60 requests per IP every 10 minutes (shared with the other endpoints).
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

    $raw = file_get_contents('php://input', false, null, 0, 40001);
    if ($raw === false || strlen($raw) > 40000) respond(413, ['error' => 'too_large']);
    $payload = clean(json_decode($raw, true));
    if ($payload === null) respond(422, ['error' => 'bad_link']);

    $json = json_encode($payload, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    $hash = hash('sha256', $json);

    $q = $pdo->prepare('SELECT code FROM short_links WHERE payload_hash = ?');
    $q->execute([$hash]);
    $existing = $q->fetchColumn();
    if ($existing !== false) respond(200, ['code' => $existing]);

    $ins = $pdo->prepare('INSERT IGNORE INTO short_links (code, payload_hash, payload) VALUES (?, ?, ?)');
    for ($try = 0; $try < 5; $try++) {
        $code = '';
        for ($i = 0; $i < CODE_LEN; $i++) $code .= CODE_CHARS[random_int(0, strlen(CODE_CHARS) - 1)];
        $ins->execute([$code, $hash, $json]);
        if ($ins->rowCount() === 1) respond(200, ['code' => $code]);
        // Taken code, or someone just stored the same link: use theirs if so.
        $q->execute([$hash]);
        $existing = $q->fetchColumn();
        if ($existing !== false) respond(200, ['code' => $existing]);
    }
    respond(500, ['error' => 'no_code']);
} catch (Throwable $e) {
    error_log('samgeet link: ' . $e->getMessage());
    respond(500, ['error' => 'server']);
}
