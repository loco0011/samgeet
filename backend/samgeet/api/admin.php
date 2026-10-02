<?php
// Admin tools inside the app (signed app request, see lib/bootstrap.php).
//   {"action":"login", "email", "password"}  -> {"token", "expires": unix, "email"}
//        Same admins table and lockout as the web panel: five wrong tries from one address or for
//        one email lock it for 15 minutes.
// Everything else carries X-Samgeet-Admin: <token> from login.
//   {"action":"list", "before": id?}          -> {"notifications": [... with reach / opened / dismissed]}
//   {"action":"send", title, body, image_url?, style, button, action_value?, action_label?, show_as, audience}
//   {"action":"resend", "id"}                 -> a fresh copy of an old message (the original stays as it was)
//   {"action":"toggle", "id"}                 -> stop or resume one
//
// The token is "<admin id>.<expiry>.<HMAC>" keyed with the app key AND that admin's password hash,
// so nobody can make one without the password, and changing the password cancels every token.

declare(strict_types=1);
require __DIR__ . '/../lib/bootstrap.php';

const ADMIN_TOKEN_HOURS = 12;

[$in, $install] = sg_app_request('admin', 20000);
$pdo = sg_db();

function admin_token(array $admin, int $expires): string
{
    $mac = hash_hmac('sha256', $admin['id'] . '|' . $expires, sg_config()['app_key'] . '|' . $admin['password_hash']);
    return $admin['id'] . '.' . $expires . '.' . $mac;
}

/// The admin this request's token belongs to, or a 401.
function require_admin(PDO $pdo): array
{
    $t = (string)($_SERVER['HTTP_X_SAMGEET_ADMIN'] ?? '');
    if (!preg_match('/^(\d+)\.(\d+)\.([a-f0-9]{64})$/', $t, $m) || (int)$m[2] < time()) sg_respond(401, ['error' => 'admin_session']);
    $q = $pdo->prepare('SELECT id, email, password_hash FROM admins WHERE id = ?');
    $q->execute([(int)$m[1]]);
    $admin = $q->fetch(PDO::FETCH_ASSOC);
    if (!$admin || !hash_equals(admin_token($admin, (int)$m[2]), $t)) sg_respond(401, ['error' => 'admin_session']);
    return $admin;
}

function notification_json(array $n): array
{
    return [
        'id' => (int)$n['id'], 'title' => $n['title'], 'body' => $n['body'], 'image' => $n['image_url'], 'style' => $n['style'],
        'action' => $n['action'], 'action_value' => $n['action_value'], 'action_label' => $n['action_label'],
        'show_as' => $n['show_as'], 'audience' => $n['audience'], 'active' => (bool)$n['active'],
        'sent_at' => (int)$n['sent'], 'delivered' => (int)$n['delivered'], 'opened' => (int)$n['opened'], 'dismissed' => (int)$n['dismissed'],
    ];
}

sg_guard('admin', function () use ($pdo, $in) {
    $action = $in['action'] ?? '';

    if ($action === 'login') {
        $email = strtolower(trim((string)($in['email'] ?? '')));
        $pass = (string)($in['password'] ?? '');
        $ipHash = hash('sha256', 'admin:' . sg_ip());
        $q = $pdo->prepare('SELECT COUNT(*) FROM admin_logins WHERE success = 0 AND created_at > UTC_TIMESTAMP() - INTERVAL 15 MINUTE AND (ip_hash = ? OR email = ?)');
        $q->execute([$ipHash, $email]);
        if ((int)$q->fetchColumn() >= 5) sg_respond(429, ['error' => 'locked']);
        $q = $pdo->prepare('SELECT id, email, password_hash FROM admins WHERE email = ?');
        $q->execute([$email]);
        $admin = $q->fetch(PDO::FETCH_ASSOC);
        // A dummy check for unknown emails too, so timing doesn't reveal which emails exist.
        $ok = password_verify($pass, $admin['password_hash'] ?? '$2y$10$Yc0tHdiWtI0u/LfA6eAlSuF6Sp52EKtTC5/YMS3T8wN4lSIieTXAu') && $admin;
        $pdo->prepare('INSERT INTO admin_logins (ip_hash, email, success) VALUES (?, ?, ?)')->execute([$ipHash, mb_substr($email, 0, 190), $ok ? 1 : 0]);
        if (!$ok) {
            usleep(400000);
            sg_respond(403, ['error' => 'wrong_login']);
        }
        $pdo->prepare('UPDATE admins SET last_login_at = UTC_TIMESTAMP() WHERE id = ?')->execute([$admin['id']]);
        $expires = time() + ADMIN_TOKEN_HOURS * 3600;
        sg_respond(200, ['token' => admin_token($admin, $expires), 'expires' => $expires, 'email' => $admin['email']]);
    }

    $admin = require_admin($pdo);

    if ($action === 'list') {
        $before = isset($in['before']) && is_int($in['before']) ? $in['before'] : PHP_INT_MAX;
        $q = $pdo->prepare('SELECT n.*, UNIX_TIMESTAMP(n.starts_at) AS sent, COUNT(r.device_id) AS delivered,
                                   COALESCE(SUM(r.opened_at IS NOT NULL), 0) AS opened, COALESCE(SUM(r.dismissed_at IS NOT NULL), 0) AS dismissed
                            FROM notifications n LEFT JOIN notification_receipts r ON r.notification_id = n.id
                            WHERE n.id < ? GROUP BY n.id ORDER BY n.id DESC LIMIT 30');
        $q->execute([$before]);
        sg_respond(200, ['notifications' => array_map('notification_json', $q->fetchAll(PDO::FETCH_ASSOC))]);
    }

    if ($action === 'resend') {
        // A fresh copy (new id, so phones that saw the original show it again). The original keeps
        // its place in the list and its numbers.
        $id = $in['id'] ?? null;
        if (!is_int($id)) sg_respond(422, ['error' => 'bad_id']);
        $pdo->prepare('INSERT INTO notifications (title, body, image_url, style, action, action_value, action_label, show_as, audience, audience_build, created_by)
                       SELECT title, body, image_url, style, action, action_value, action_label, show_as, audience, audience_build, ?
                       FROM notifications WHERE id = ?')->execute([$admin['id'], $id]);
        if ($pdo->lastInsertId() == 0) sg_respond(404, ['error' => 'not_found']);
        sg_respond(200, ['ok' => true, 'id' => (int)$pdo->lastInsertId()]);
    }

    if ($action === 'toggle') {
        $id = $in['id'] ?? null;
        if (!is_int($id)) sg_respond(422, ['error' => 'bad_id']);
        $pdo->prepare('UPDATE notifications SET active = 1 - active WHERE id = ?')->execute([$id]);
        sg_respond(200, ['ok' => true]);
    }

    if ($action === 'send') {
        $title = sg_text($in['title'] ?? '', 121);
        $body = trim(str_replace("\r", '', (string)($in['body'] ?? '')));
        if ($title === '' || mb_strlen($title) > 120 || $body === '' || mb_strlen($body) > 2000) sg_respond(422, ['error' => 'bad_text']);
        $pick = fn($k, $allowed) => in_array($in[$k] ?? '', $allowed, true) ? $in[$k] : $allowed[0];
        $act = $pick('button', ['none', 'url', 'update', 'search']); // the message's button ('action' picks this API call)
        $value = sg_text($in['action_value'] ?? '', 400);
        if ($act === 'url' && !preg_match('~^https://~', $value)) sg_respond(422, ['error' => 'bad_link']);
        if ($act === 'search' && $value === '') sg_respond(422, ['error' => 'bad_search']);
        $image = sg_text($in['image_url'] ?? '', 400);
        if ($image !== '' && !preg_match('~^https://~', $image)) sg_respond(422, ['error' => 'bad_image']);
        $pdo->prepare('INSERT INTO notifications (title, body, image_url, style, action, action_value, action_label, show_as, audience, created_by)
                       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)')
            ->execute([$title, $body, $image, $pick('style', ['info', 'celebrate', 'warning']), $act, $value,
                sg_text($in['action_label'] ?? '', 40), $pick('show_as', ['both', 'popup', 'system']),
                $pick('audience', ['all', 'signed_in', 'guests']), $admin['id']]);
        sg_respond(200, ['ok' => true, 'id' => (int)$pdo->lastInsertId()]);
    }

    sg_respond(400, ['error' => 'bad_action']);
});
