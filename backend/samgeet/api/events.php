<?php
// Listening data from the app, sent in batches (signed app request; the session is optional, guests
// count too). Body: {"events":[{...}, ...]} with up to 200 events, each
//   {"t": type, "at": unix ms on the phone, "track": {id, title, album, album_id, lang, year, dur, img,
//    artists:[{id,name}]}?, "ms": int?, "v": "short text"?, "m": {small JSON}?}
// Songs and singers are added to `tracks` / `artists` / `track_artists` as they first appear, so the
// events table only holds the song id.

declare(strict_types=1);
require __DIR__ . '/../lib/bootstrap.php';

const TYPES = [
    'app_open', 'app_close', 'play_start', 'play_end', 'like', 'unlike', 'download', 'download_remove',
    'share_song', 'share_playlist', 'search', 'playlist_create', 'playlist_add', 'queue_add', 'radio_start',
    'sign_in', 'sign_out', 'sign_up', 'player_style', 'eq', 'sleep_timer', 'device_info', 'notification_open',
    'notification_dismiss', 'update_open', 'update_later', 'error', 'screen',
];
const MAX_EVENTS = 200;

[$in, $install] = sg_app_request('events', 400000);
$pdo = sg_db();

function track_id($v): ?string
{
    return is_string($v) && preg_match('/^[A-Za-z0-9_-]{1,64}$/', $v) ? $v : null;
}

function cover_url($v): string
{
    $url = sg_text($v, 400);
    $p = parse_url($url);
    if (!$p || ($p['scheme'] ?? '') !== 'https') return '';
    $host = strtolower($p['host'] ?? '');
    return ($host === 'saavncdn.com' || substr($host, -13) === '.saavncdn.com') ? $url : '';
}

sg_guard('events', function () use ($pdo, $in, $install) {
    $deviceId = sg_device($pdo, $install);
    $user = sg_user($pdo, $deviceId, false);
    $userId = $user[0] ?? null;

    $list = $in['events'] ?? null;
    if (!is_array($list) || count($list) > MAX_EVENTS) sg_respond(422, ['error' => 'bad_events']);

    $upTrack = $pdo->prepare('INSERT INTO tracks (id, title, album, album_id, language, year, duration_sec, image)
                              VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                              ON DUPLICATE KEY UPDATE title = IF(VALUES(title) = \'\', title, VALUES(title)),
                                image = IF(VALUES(image) = \'\', image, VALUES(image))');
    $upArtist = $pdo->prepare('INSERT INTO artists (id, name) VALUES (?, ?) ON DUPLICATE KEY UPDATE name = VALUES(name)');
    $link = $pdo->prepare('INSERT IGNORE INTO track_artists (track_id, artist_id, position) VALUES (?, ?, ?)');
    $ins = $pdo->prepare('INSERT INTO events (device_id, user_id, type, track_id, ms, value, meta, client_at)
                          VALUES (?, ?, ?, ?, ?, ?, ?, FROM_UNIXTIME(?))');

    $now = time();
    $seen = [];
    $stored = 0;
    $pdo->beginTransaction();
    foreach ($list as $e) {
        if (!is_array($e) || !in_array($e['t'] ?? null, TYPES, true)) continue;
        $at = isset($e['at']) && is_numeric($e['at']) ? intdiv((int)$e['at'], 1000) : $now;
        $at = max($now - 30 * 86400, min($now + 3600, $at)); // phones with wrong clocks

        $trackId = null;
        $tr = $e['track'] ?? null;
        if (is_array($tr) && ($tid = track_id($tr['id'] ?? null)) !== null) {
            $trackId = $tid;
            if (!isset($seen[$tid])) {
                $seen[$tid] = true;
                $year = isset($tr['year']) && is_numeric($tr['year']) && $tr['year'] > 1900 && $tr['year'] < 2100 ? (int)$tr['year'] : null;
                $dur = isset($tr['dur']) && is_numeric($tr['dur']) ? min(65535, max(0, (int)$tr['dur'])) : null;
                $upTrack->execute([$tid, sg_text($tr['title'] ?? '', 200), sg_text($tr['album'] ?? '', 200), track_id($tr['album_id'] ?? null) ?? '',
                    sg_text($tr['lang'] ?? '', 30), $year, $dur, cover_url($tr['img'] ?? '')]);
                $pos = 0;
                foreach (is_array($tr['artists'] ?? null) ? array_slice($tr['artists'], 0, 8) : [] as $a) {
                    if (!is_array($a)) continue;
                    $name = sg_text($a['name'] ?? '', 160);
                    if ($name === '') continue;
                    $aid = track_id($a['id'] ?? null) ?? ('name:' . mb_substr(mb_strtolower($name), 0, 58));
                    $upArtist->execute([$aid, $name]);
                    $link->execute([$tid, $aid, $pos++]);
                }
            }
        }

        $ms = isset($e['ms']) && is_numeric($e['ms']) ? min(86400000, max(0, (int)$e['ms'])) : null;
        $value = isset($e['v']) ? sg_text($e['v'], 255) : null;
        $meta = null;
        if (isset($e['m']) && is_array($e['m'])) {
            $meta = json_encode($e['m'], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
            if ($meta === false || strlen($meta) > 2000) $meta = null;
        }
        $ins->execute([$deviceId, $userId, $e['t'], $trackId, $ms, $value === '' ? null : $value, $meta, $at]);
        $stored++;
    }
    $pdo->commit();
    sg_respond(200, ['ok' => true, 'stored' => $stored]);
});
