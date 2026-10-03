<?php
// What the app asks for when it opens (and every so often while it runs). Signed app request; the
// session is optional.
//   {"action":"config", "device":{brand, model, os, sdk, app_version, app_build, locale, tz}}
//        -> {"update": {...} | null, "notifications": [...], "server_time": unix}
//   {"action":"receipt", "id": n, "what": "opened" | "dismissed"}
// Updates and notifications are published from the admin panel (../admin/).

declare(strict_types=1);
require __DIR__ . '/../lib/bootstrap.php';

[$in, $install] = sg_app_request('app');
$pdo = sg_db();

sg_guard('app', function () use ($pdo, $in, $install) {
    $action = $in['action'] ?? '';
    $info = is_array($in['device'] ?? null) ? $in['device'] : null;
    $deviceId = sg_device($pdo, $install, $action === 'config' ? $info : null);
    $user = sg_user($pdo, $deviceId, false);

    if ($action === 'receipt') {
        $id = $in['id'] ?? null;
        $what = $in['what'] ?? '';
        if (!is_int($id) || !in_array($what, ['opened', 'dismissed'], true)) sg_respond(422, ['error' => 'bad_receipt']);
        $col = $what === 'opened' ? 'opened_at' : 'dismissed_at';
        $pdo->prepare("INSERT INTO notification_receipts (notification_id, device_id, $col)
                       SELECT id, ?, UTC_TIMESTAMP() FROM notifications WHERE id = ?
                       ON DUPLICATE KEY UPDATE $col = COALESCE($col, UTC_TIMESTAMP())")->execute([$deviceId, $id]);
        sg_respond(200, ['ok' => true]);
    }

    if ($action !== 'config') sg_respond(400, ['error' => 'bad_action']);
    $build = isset($info['app_build']) && is_numeric($info['app_build']) ? (int)$info['app_build'] : 0;

    $update = null;
    $q = $pdo->prepare('SELECT version_name, build, notes, apk_url, sha256, size_bytes, required FROM releases
                        WHERE published = 1 AND build > ? ORDER BY build DESC LIMIT 1');
    $q->execute([$build]);
    if ($r = $q->fetch(PDO::FETCH_ASSOC)) {
        // A newer version is required if the newest one is, or any skipped-over one was.
        $req = $pdo->prepare('SELECT MAX(required) FROM releases WHERE published = 1 AND build > ?');
        $req->execute([$build]);
        $update = [
            'version' => $r['version_name'],
            'build' => (int)$r['build'],
            'notes' => $r['notes'],
            'url' => $r['apk_url'],
            'sha256' => $r['sha256'],
            'size' => $r['size_bytes'] === null ? null : (int)$r['size_bytes'],
            'required' => (bool)$req->fetchColumn(),
        ];
    }

    $audience = $user ? "('all','signed_in')" : "('all','guests')";
    $sql = "SELECT n.id, n.title, n.body, n.image_url, n.style, n.action, n.action_value, n.action_label, n.show_as,
                   UNIX_TIMESTAMP(n.starts_at) AS starts
            FROM notifications n
            LEFT JOIN notification_receipts r ON r.notification_id = n.id AND r.device_id = ?
            WHERE n.active = 1 AND n.starts_at <= UTC_TIMESTAMP() AND (n.ends_at IS NULL OR n.ends_at > UTC_TIMESTAMP())
              AND (n.audience IN $audience OR (n.audience = 'below_build' AND ? < n.audience_build))
              AND r.opened_at IS NULL AND r.dismissed_at IS NULL %s
            ORDER BY n.starts_at DESC LIMIT 5";
    // Follow-ups go to part of an earlier message's audience: phones that never got it, or got it
    // and didn't open it (see lib/messages.php). Before the database has those columns, the plain
    // query still works.
    $followUps = "AND (n.follow_up IS NULL
                   OR (n.follow_up = 'missed' AND NOT EXISTS (SELECT 1 FROM notification_receipts x WHERE x.notification_id = n.follow_of AND x.device_id = ?))
                   OR (n.follow_up = 'unopened' AND EXISTS (SELECT 1 FROM notification_receipts x WHERE x.notification_id = n.follow_of AND x.device_id = ? AND x.opened_at IS NULL)))";
    try {
        $q = $pdo->prepare(sprintf($sql, $followUps));
        $q->execute([$deviceId, $build, $deviceId, $deviceId]);
    } catch (PDOException $e) {
        $q = $pdo->prepare(sprintf($sql, ''));
        $q->execute([$deviceId, $build]);
    }
    $list = [];
    $mark = $pdo->prepare('INSERT IGNORE INTO notification_receipts (notification_id, device_id) VALUES (?, ?)');
    foreach ($q->fetchAll(PDO::FETCH_ASSOC) as $n) {
        $mark->execute([$n['id'], $deviceId]);
        $list[] = [
            'id' => (int)$n['id'],
            'title' => $n['title'],
            'body' => $n['body'],
            'image' => $n['image_url'],
            'style' => $n['style'],
            'action' => $n['action'],
            'action_value' => $n['action_value'],
            'action_label' => $n['action_label'],
            'show_as' => $n['show_as'],
            'at' => (int)$n['starts'],
        ];
    }

    sg_respond(200, ['update' => $update, 'notifications' => $list, 'server_time' => time()]);
});
