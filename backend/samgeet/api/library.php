<?php
// The signed-in listener's synced library (signed app request + session, see lib/bootstrap.php).
//   {"action":"load"}                               -> {"data":"<base64 gzip JSON>", "rev": n, "updated_at": unix}  (404 if none yet)
//   {"action":"save", "data":"...", "base_rev": n|null}
//        base_rev is the rev the phone last saw (null to create). If another phone saved in between,
//        the answer is 409 and the phone merges and tries again, so phones never overwrite each other.
// The data is opaque to the server: stored and returned as-is.

declare(strict_types=1);
require __DIR__ . '/../lib/bootstrap.php';

const MAX_DATA = 3000000; // base64 characters, about 2.2 MB of compressed data

[$in, $install] = sg_app_request('library', MAX_DATA + 1024);
$pdo = sg_db();

sg_guard('library', function () use ($pdo, $in, $install) {
    $deviceId = sg_device($pdo, $install);
    [$userId] = sg_user($pdo, $deviceId, true);
    $action = $in['action'] ?? '';

    if ($action === 'load') {
        $q = $pdo->prepare('SELECT data, rev, UNIX_TIMESTAMP(updated_at) FROM libraries WHERE user_id = ?');
        $q->execute([$userId]);
        $row = $q->fetch(PDO::FETCH_NUM);
        if (!$row) sg_respond(404, ['error' => 'not_found']);
        sg_respond(200, ['data' => $row[0], 'rev' => (int)$row[1], 'updated_at' => (int)$row[2]]);
    }

    if ($action !== 'save') sg_respond(400, ['error' => 'bad_action']);

    $data = $in['data'] ?? null;
    if (!is_string($data) || $data === '' || strlen($data) > MAX_DATA || !preg_match('/^[A-Za-z0-9+\/]+=*$/', $data)) {
        sg_respond(422, ['error' => 'bad_data']);
    }
    if (!array_key_exists('base_rev', $in) || !($in['base_rev'] === null || is_int($in['base_rev']))) {
        sg_respond(422, ['error' => 'bad_rev']);
    }
    $base = $in['base_rev'];

    if ($base === null) {
        $st = $pdo->prepare('INSERT IGNORE INTO libraries (user_id, data, rev) VALUES (?, ?, 1)');
        $st->execute([$userId, $data]);
        if ($st->rowCount() === 1) sg_respond(200, ['ok' => true, 'rev' => 1]);
    } else {
        $st = $pdo->prepare('UPDATE libraries SET data = ?, rev = rev + 1 WHERE user_id = ? AND rev = ?');
        $st->execute([$data, $userId, $base]);
        if ($st->rowCount() === 1) sg_respond(200, ['ok' => true, 'rev' => $base + 1]);
    }
    sg_respond(409, ['error' => 'conflict']); // another phone saved first: load, merge, try again
});
