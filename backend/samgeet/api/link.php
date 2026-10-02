<?php
// Makes short share links (https://api.sambitmaity.fun/s/<code>) for signed-in listeners.
// Signed app request + session (see lib/bootstrap.php).
//   {"t":"song", "id", "s", "a", "al", "i"}   -> {"code":"k7qm2xa"}
//   {"t":"playlist", "n", "ids":[...]}         -> {"code":"..."}
// The same song or playlist always gets the same code. Looking a code up stays public (the share
// page and the app read it from /link.php?c=<code> at the site's root).

declare(strict_types=1);
require __DIR__ . '/../lib/bootstrap.php';

const CODE_CHARS = '23456789abcdefghjkmnpqrstuvwxyz'; // no 0/1/i/l/o: easy to read and type
const CODE_LEN = 7;

[$in, $install] = sg_app_request('link', 40000);
$pdo = sg_db();

function valid_id($v): bool
{
    return is_string($v) && preg_match('/^[A-Za-z0-9_-]{1,64}$/', $v) === 1;
}

function cover(string $url): string
{
    $p = parse_url($url);
    if (!$p || ($p['scheme'] ?? '') !== 'https' || isset($p['user']) || isset($p['port'])) return '';
    $host = strtolower($p['host'] ?? '');
    if ($host !== 'saavncdn.com' && substr($host, -13) !== '.saavncdn.com') return '';
    return $url;
}

/// The cleaned-up payload (same shape as the root link.php stores), or null.
function clean(array $in): ?array
{
    if (($in['t'] ?? '') === 'playlist') {
        $ids = [];
        foreach ((is_array($in['ids'] ?? null) ? $in['ids'] : []) as $id) {
            if (valid_id($id)) $ids[] = $id;
            if (count($ids) >= 500) break;
        }
        if (!$ids) return null;
        return ['t' => 'playlist', 'n' => sg_text($in['n'] ?? '', 80) ?: 'Shared playlist', 'ids' => $ids];
    }
    if (!valid_id($in['id'] ?? null)) return null;
    return [
        't' => 'song',
        'id' => $in['id'],
        's' => sg_text($in['s'] ?? '', 120),
        'a' => sg_text($in['a'] ?? '', 160),
        'al' => sg_text($in['al'] ?? '', 120),
        'i' => cover(sg_text($in['i'] ?? '', 400)),
    ];
}

sg_guard('link', function () use ($pdo, $in, $install) {
    $deviceId = sg_device($pdo, $install);
    sg_user($pdo, $deviceId, true); // sharing needs an account

    $payload = clean($in);
    if ($payload === null) sg_respond(422, ['error' => 'bad_link']);
    $json = json_encode($payload, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    $hash = hash('sha256', $json);

    $q = $pdo->prepare('SELECT code FROM short_links WHERE payload_hash = ?');
    $q->execute([$hash]);
    $existing = $q->fetchColumn();
    if ($existing !== false) sg_respond(200, ['code' => $existing]);

    $ins = $pdo->prepare('INSERT IGNORE INTO short_links (code, payload_hash, payload) VALUES (?, ?, ?)');
    for ($try = 0; $try < 5; $try++) {
        $code = '';
        for ($i = 0; $i < CODE_LEN; $i++) $code .= CODE_CHARS[random_int(0, strlen(CODE_CHARS) - 1)];
        $ins->execute([$code, $hash, $json]);
        if ($ins->rowCount() === 1) sg_respond(200, ['code' => $code]);
        $q->execute([$hash]);
        $existing = $q->fetchColumn();
        if ($existing !== false) sg_respond(200, ['code' => $existing]);
    }
    sg_respond(500, ['error' => 'no_code']);
});
