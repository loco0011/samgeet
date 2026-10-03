<?php
// Admin tools inside the app (signed app request, see lib/bootstrap.php). Everything the web panel
// shows, from the same report code (lib/reports.php) and the same sending code (lib/messages.php).
//
//   {"action":"login", "email", "password"}  -> {"token", "expires": unix, "email"}
//        Same admins table and lockout as the web panel: five wrong tries from one address or for
//        one email lock it for 15 minutes.
// Everything else carries X-Samgeet-Admin: <token> from login.
//   overview {r}                    numbers for a range ('1', '7', '30', '90', 'all')
//   listening {r}                   habits: hours, weekdays, languages, searches, likes...
//   users {filter, q, sort, page}   listeners, 30 a page
//   user {id}                       one listener, everything about them
//   user_signout {id}, user_block {id}
//   places {} / place {city, country}
//   list {before?, tab?}            sent messages, newest first (tab: all | web | app | update)
//   message {id}                    one message with how many phones each follow-up would reach
//   send {title, body, image_url?, style, button, action_value?, action_label?, show_as, audience}
//                                   audience: all | signed_in | guests | outdated
//   resend {id, who?}               who: all | missed | unopened | outdated (lib/messages.php)
//   toggle {id}                     stop or resume a message
//   releases {}                     versions, phones on each, and the update reminder text
//   release_toggle {id}             publish or unpublish a version
//
// Times are UTC "YYYY-MM-DD HH:MM:SS". The token is "<admin id>.<expiry>.<HMAC>" keyed with the app
// key AND that admin's password hash, so nobody can make one without the password, and changing the
// password cancels every token.

declare(strict_types=1);
require __DIR__ . '/../lib/bootstrap.php';
require __DIR__ . '/../lib/reports.php';
require __DIR__ . '/../lib/messages.php';

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
        'show_as' => $n['show_as'], 'audience' => $n['audience'], 'audience_label' => rp_audience_label($n), 'active' => (bool)$n['active'],
        'source' => $n['src'] ?? 'web', 'follow_up' => $n['follow_up'] ?? null, 'by' => $n['by_email'] ?? null,
        'sent_at' => (int)$n['sent'], 'delivered' => (int)$n['delivered'], 'opened' => (int)$n['opened'], 'dismissed' => (int)$n['dismissed'],
    ];
}

function int_in(array $in, string $k): int
{
    $v = $in[$k] ?? null;
    if (!is_int($v)) sg_respond(422, ['error' => 'bad_' . $k]);
    return $v;
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
    $id = fn() => int_in($in, 'id');

    switch ($action) {
        case 'overview':
            sg_respond(200, rp_overview($pdo, rp_range($in['r'] ?? '7')));
        case 'listening':
            sg_respond(200, rp_listening($pdo, rp_range($in['r'] ?? '30')));
        case 'users':
            sg_respond(200, rp_users($pdo, (string)($in['filter'] ?? 'all'), sg_text($in['q'] ?? '', 100),
                in_array($in['sort'] ?? '', ['recent', 'listening', 'joined', 'name'], true) ? $in['sort'] : 'recent', max(1, (int)($in['page'] ?? 1))));
        case 'user':
            $u = rp_user($pdo, $id());
            if (!$u) sg_respond(404, ['error' => 'not_found']);
            sg_respond(200, $u);
        case 'user_signout':
            $pdo->prepare('UPDATE sessions SET revoked_at = UTC_TIMESTAMP() WHERE user_id = ? AND revoked_at IS NULL')->execute([$id()]);
            sg_respond(200, ['ok' => true]);
        case 'user_block':
            $uid = $id();
            $pdo->prepare("UPDATE users SET status = IF(status = 'active', 'blocked', 'active') WHERE id = ?")->execute([$uid]);
            $pdo->prepare('UPDATE sessions SET revoked_at = UTC_TIMESTAMP() WHERE user_id = ? AND revoked_at IS NULL')->execute([$uid]);
            sg_respond(200, ['ok' => true, 'status' => rp_scalar($pdo, 'SELECT status FROM users WHERE id = ?', [$uid])]);
        case 'places':
            sg_respond(200, rp_places($pdo));
        case 'place':
            sg_respond(200, rp_place($pdo, sg_text($in['city'] ?? '', 120), sg_text($in['country'] ?? '', 120)));

        case 'list':
            $before = isset($in['before']) && is_int($in['before']) ? $in['before'] : null;
            $tab = isset(RP_MESSAGE_TABS[$in['tab'] ?? '']) ? $in['tab'] : 'all';
            $m = rp_messages($pdo, $tab, 1, 30, $before);
            $rem = rp_update_reminder($pdo);
            sg_respond(200, ['notifications' => array_map('notification_json', $m['list']), 'counts' => $m['counts'], 'split' => $m['has_source'],
                'reminder' => ['version' => $rem['latest']['version'] ?? null, 'behind' => $rem['behind'], 'title' => $rem['title'], 'body' => $rem['body']]]);
        case 'message':
            $mid = $id();
            $n = rp_rows($pdo, 'SELECT n.*, ' . (rp_v21($pdo) ? 'n.source' : "'web'") . " AS src, a.email AS by_email, UNIX_TIMESTAMP(n.starts_at) AS sent,
                                       COUNT(r.device_id) AS delivered, COALESCE(SUM(r.opened_at IS NOT NULL), 0) AS opened, COALESCE(SUM(r.dismissed_at IS NOT NULL), 0) AS dismissed
                                FROM notifications n LEFT JOIN notification_receipts r ON r.notification_id = n.id LEFT JOIN admins a ON a.id = n.created_by
                                WHERE n.id = ? GROUP BY n.id", [$mid])[0] ?? null;
            if (!$n) sg_respond(404, ['error' => 'not_found']);
            sg_respond(200, ['message' => notification_json($n), 'follow_ups' => rp_follow_up_counts($pdo, $n), 'split' => rp_v21($pdo)]);
        case 'send':
            // 'button' is the message's button ('action' picks this API call).
            [$newId, $err] = rp_send($pdo, [
                'title' => sg_text($in['title'] ?? '', 121), 'body' => (string)($in['body'] ?? ''), 'image_url' => sg_text($in['image_url'] ?? '', 400),
                'style' => $in['style'] ?? '', 'action' => $in['button'] ?? '', 'action_value' => sg_text($in['action_value'] ?? '', 400),
                'action_label' => sg_text($in['action_label'] ?? '', 40), 'show_as' => $in['show_as'] ?? '',
                'audience' => in_array($in['audience'] ?? '', ['all', 'signed_in', 'guests', 'outdated'], true) ? $in['audience'] : 'all',
            ], (int)$admin['id'], 'app');
            if ($err) sg_respond(422, ['error' => $err]);
            sg_respond(200, ['ok' => true, 'id' => $newId]);
        case 'resend':
            [$newId, $err] = rp_resend($pdo, $id(), (string)($in['who'] ?? 'all'), (int)$admin['id'], 'app');
            if ($err) sg_respond($err === 'not_found' ? 404 : 422, ['error' => $err]);
            sg_respond(200, ['ok' => true, 'id' => $newId]);
        case 'toggle':
            $pdo->prepare('UPDATE notifications SET active = 1 - active WHERE id = ?')->execute([$id()]);
            sg_respond(200, ['ok' => true]);

        case 'releases':
            $list = rp_rows($pdo, "SELECT r.id, r.version_name, r.build, r.notes, r.required, r.published, r.size_bytes, r.published_at, r.created_at,
                                          (SELECT COUNT(*) FROM devices d WHERE d.app_build = r.build AND d.last_seen_at > UTC_TIMESTAMP() - INTERVAL 30 DAY) AS phones
                                   FROM releases r ORDER BY r.build DESC");
            $rem = rp_update_reminder($pdo);
            sg_respond(200, [
                'adoption' => rp_adoption($pdo),
                'releases' => array_map(fn($r) => ['id' => (int)$r['id'], 'version' => $r['version_name'], 'build' => (int)$r['build'], 'required' => (bool)$r['required'],
                    'published' => (bool)$r['published'], 'mb' => $r['size_bytes'] ? round($r['size_bytes'] / 1048576, 1) : null, 'phones' => (int)$r['phones'],
                    'at' => $r['published_at'] ?? $r['created_at'], 'headlines' => rp_headlines((string)$r['notes'])], $list),
                'reminder' => ['version' => $rem['latest']['version'] ?? null, 'behind' => $rem['behind'], 'title' => $rem['title'], 'body' => $rem['body']],
            ]);
        case 'release_toggle':
            $pdo->prepare('UPDATE releases SET published = 1 - published, published_at = IF(published = 1, COALESCE(published_at, UTC_TIMESTAMP()), published_at) WHERE id = ?')->execute([$id()]);
            sg_respond(200, ['ok' => true]);
    }

    sg_respond(400, ['error' => 'bad_action']);
});
