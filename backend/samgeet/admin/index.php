<?php
// Samgeet admin panel: listening reports, listeners, places, messages, app releases and data export.
// Lives at <api host>/<private folder>/samgeet/admin/. Sign-in is checked against `admins`
// (bcrypt hashes only); five wrong passwords from one address lock it for 15 minutes.
// Every form carries a CSRF token, the session cookie is HttpOnly + SameSite=Strict + Secure, and the
// page can't be framed or indexed.
//
// This file: security, sign-in, form actions and routing. The pages are in lib/admin_views.php, the
// layout and shared pieces in lib/admin_ui.php, and every number comes from lib/reports.php (the
// same code the admin tools inside the app use).

declare(strict_types=1);
const SG_ADMIN = true;
require __DIR__ . '/../lib/bootstrap.php';
require __DIR__ . '/../lib/reports.php';
require __DIR__ . '/../lib/messages.php';
require __DIR__ . '/../lib/admin_ui.php';
require __DIR__ . '/../lib/admin_views.php';

const IDLE_LIMIT = 7200;      // signed out after 2 hours without a click
const ABSOLUTE_LIMIT = 43200; // and after 12 hours in any case
const NOTIFY_STYLES = ['info' => 'Info', 'celebrate' => 'Celebrate', 'warning' => 'Warning'];
const NOTIFY_SHOW = ['both' => 'Popup + phone notification', 'popup' => 'Popup in the app only', 'system' => 'Phone notification only'];
const NOTIFY_ACTIONS = ['none' => 'No link', 'update' => 'Update the app', 'url' => 'Open a link', 'search' => 'Search for…'];
const NOTIFY_AUDIENCE = ['all' => 'Everyone', 'signed_in' => 'Signed-in listeners', 'guests' => 'Guests', 'outdated' => 'Not on the latest version', 'below_build' => 'Apps older than a build…'];

$https = ($_SERVER['HTTPS'] ?? '') !== '' && ($_SERVER['HTTPS'] ?? '') !== 'off'
    || ($_SERVER['HTTP_X_FORWARDED_PROTO'] ?? '') === 'https';
$base = rtrim(str_replace('\\', '/', dirname($_SERVER['SCRIPT_NAME'] ?? '/admin/index.php')), '/') . '/';
$nonce = base64_encode(random_bytes(16));

header('Content-Type: text/html; charset=utf-8');
header('X-Frame-Options: DENY');
header('X-Content-Type-Options: nosniff');
header('Referrer-Policy: no-referrer');
header('X-Robots-Tag: noindex, nofollow');
header('Cache-Control: no-store');
header("Content-Security-Policy: default-src 'self'; script-src 'nonce-$nonce' https://cdnjs.cloudflare.com; "
    . "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; font-src https://fonts.gstatic.com; img-src 'self' https: data:; "
    . "connect-src 'self'; frame-ancestors 'none'; form-action 'self'; base-uri 'none'");

session_name('sg_admin');
session_set_cookie_params(['lifetime' => 0, 'path' => $base, 'secure' => $https, 'httponly' => true, 'samesite' => 'Strict']);
ini_set('session.use_strict_mode', '1');
session_start();

$pdo = sg_db();
$pdo->exec("SET time_zone = '+00:00'");

function csrf(): string
{
    if (empty($_SESSION['csrf'])) $_SESSION['csrf'] = bin2hex(random_bytes(32));
    return $_SESSION['csrf'];
}

function csrf_field(): string
{
    return '<input type="hidden" name="csrf" value="' . h(csrf()) . '">';
}

function check_csrf(): void
{
    if (!hash_equals(csrf(), (string)($_POST['csrf'] ?? ''))) {
        http_response_code(400);
        exit('This form expired. Go back, reload the page and try again.');
    }
}

function go(string $page, array $q = [], ?string $flash = null): void
{
    if ($flash !== null) $_SESSION['flash'] = $flash;
    global $base;
    header('Location: ' . $base . '?' . http_build_query(['p' => $page] + $q));
    exit;
}

function message_error(string $code): string
{
    return match ($code) {
        'bad_text' => 'A title (up to 120 characters) and a message are needed.',
        'bad_link' => 'The button link must start with https://',
        'bad_search' => 'Add what the button should search for.',
        'bad_image' => 'The picture link must start with https://',
        'no_release' => 'There is no published version yet, so nobody is out of date.',
        'needs_update' => 'Sending to part of the audience needs the database update in migrations/2026-10-03-messages.sql. Run it in phpMyAdmin first.',
        'not_found' => 'That message no longer exists.',
        default => 'Couldn’t send it. Try again.',
    };
}

/// A datetime-local value (IST) as a UTC DATETIME string, or null.
function from_ist(string $v): ?string
{
    if (trim($v) === '') return null;
    try {
        $d = new DateTime($v, new DateTimeZone('Asia/Kolkata'));
    } catch (Throwable $e) {
        return null;
    }
    $d->setTimezone(new DateTimeZone('UTC'));
    return $d->format('Y-m-d H:i:s');
}

// ---------------------------------------------------------------- session
$admin = null;
if (!empty($_SESSION['admin_id'])) {
    $now = time();
    if ($now - ($_SESSION['seen'] ?? 0) > IDLE_LIMIT || $now - ($_SESSION['since'] ?? 0) > ABSOLUTE_LIMIT) {
        $_SESSION = [];
        session_regenerate_id(true);
    } else {
        $_SESSION['seen'] = $now;
        $q = $pdo->prepare('SELECT id, email FROM admins WHERE id = ?');
        $q->execute([$_SESSION['admin_id']]);
        $admin = $q->fetch(PDO::FETCH_ASSOC) ?: null;
    }
}

$page = (string)($_GET['p'] ?? 'dashboard');

// ---------------------------------------------------------------- sign in / out
if ($page === 'logout' && $_SERVER['REQUEST_METHOD'] === 'POST') {
    check_csrf();
    $_SESSION = [];
    session_regenerate_id(true);
    go('login');
}

$loginError = null;
if (!$admin) {
    if ($_SERVER['REQUEST_METHOD'] === 'POST' && $page === 'login') {
        check_csrf();
        $email = strtolower(trim((string)($_POST['email'] ?? '')));
        $pass = (string)($_POST['password'] ?? '');
        $ipHash = hash('sha256', 'admin:' . sg_ip());
        $pdo->exec('DELETE FROM admin_logins WHERE created_at < UTC_TIMESTAMP() - INTERVAL 30 DAY');
        $fails = (int)rp_scalar($pdo, 'SELECT COUNT(*) FROM admin_logins WHERE success = 0 AND created_at > UTC_TIMESTAMP() - INTERVAL 15 MINUTE AND (ip_hash = ? OR email = ?)', [$ipHash, $email]);
        if ($fails >= 5) {
            $loginError = 'Too many wrong tries. Wait 15 minutes and try again.';
        } else {
            $q = $pdo->prepare('SELECT id, password_hash FROM admins WHERE email = ?');
            $q->execute([$email]);
            $row = $q->fetch(PDO::FETCH_ASSOC);
            // Check a dummy hash for unknown emails too, so timing doesn't reveal which emails exist.
            $ok = password_verify($pass, $row['password_hash'] ?? '$2y$10$Yc0tHdiWtI0u/LfA6eAlSuF6Sp52EKtTC5/YMS3T8wN4lSIieTXAu') && $row;
            $pdo->prepare('INSERT INTO admin_logins (ip_hash, email, success) VALUES (?, ?, ?)')->execute([$ipHash, substr($email, 0, 190), $ok ? 1 : 0]);
            if ($ok) {
                if (password_needs_rehash($row['password_hash'], PASSWORD_DEFAULT)) {
                    $pdo->prepare('UPDATE admins SET password_hash = ? WHERE id = ?')->execute([password_hash($pass, PASSWORD_DEFAULT), $row['id']]);
                }
                $pdo->prepare('UPDATE admins SET last_login_at = UTC_TIMESTAMP() WHERE id = ?')->execute([$row['id']]);
                session_regenerate_id(true);
                $_SESSION = ['admin_id' => (int)$row['id'], 'since' => time(), 'seen' => time(), 'csrf' => bin2hex(random_bytes(32))];
                go('dashboard');
            }
            $loginError = 'Wrong email or password.';
            usleep(400000);
        }
    }
    render_login($loginError);
    exit;
}

// ---------------------------------------------------------------- actions (POST)
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    check_csrf();
    $do = (string)($_POST['do'] ?? '');
    $id = (int)($_POST['id'] ?? 0);

    switch ($do) {
        case 'user_block':
            $pdo->prepare("UPDATE users SET status = IF(status = 'active', 'blocked', 'active') WHERE id = ?")->execute([$id]);
            $pdo->prepare('UPDATE sessions SET revoked_at = UTC_TIMESTAMP() WHERE user_id = ? AND revoked_at IS NULL')->execute([$id]);
            go('user', ['id' => $id], 'Updated.');
        case 'user_signout':
            $pdo->prepare('UPDATE sessions SET revoked_at = UTC_TIMESTAMP() WHERE user_id = ? AND revoked_at IS NULL')->execute([$id]);
            go('user', ['id' => $id], 'Signed out on every phone.');
        case 'user_delete':
            $key = rp_scalar($pdo, 'SELECT key_hash FROM users WHERE id = ?', [$id]);
            $pdo->prepare('DELETE FROM users WHERE id = ?')->execute([$id]);
            try {
                $pdo->prepare('DELETE FROM backups WHERE code_hash = ?')->execute([(string)$key]);
            } catch (Throwable $e) {
            }
            go('users', [], 'Account and its data deleted.');

        case 'release_save':
            $version = trim((string)($_POST['version'] ?? ''));
            $build = (int)($_POST['build'] ?? 0);
            $notes = trim((string)($_POST['notes'] ?? ''));
            $url = trim((string)($_POST['apk_url'] ?? ''));
            $sha = strtolower(trim((string)($_POST['sha256'] ?? '')));
            $size = null;
            if (!preg_match('/^\d+\.\d+\.\d+$/', $version) || $build < 1) go('release_new', [], 'Version must look like 1.4.0 and the build must be a number.');
            if (!empty($_FILES['apk']['tmp_name']) && is_uploaded_file($_FILES['apk']['tmp_name'])) {
                $tmp = $_FILES['apk']['tmp_name'];
                if (file_get_contents($tmp, false, null, 0, 4) !== "PK\x03\x04") go('release_new', [], 'That file is not an APK.');
                $dir = dirname(__DIR__) . '/files';
                if (!is_dir($dir)) mkdir($dir, 0755, true);
                $name = 'Samgeet-' . $version . '.apk';
                if (!move_uploaded_file($tmp, "$dir/$name")) go('release_new', [], 'Could not save the upload.');
                $sha = hash_file('sha256', "$dir/$name");
                $size = filesize("$dir/$name");
                $url = ($GLOBALS['https'] ? 'https://' : 'http://') . $_SERVER['HTTP_HOST'] . dirname(rtrim($GLOBALS['base'], '/')) . '/files/' . $name;
            } elseif (!empty($_FILES['apk']['name']) && ($_FILES['apk']['error'] ?? 0) !== UPLOAD_ERR_OK) {
                go('release_new', [], 'The upload failed (error ' . (int)$_FILES['apk']['error'] . '). The file may be bigger than the server allows; use a link instead.');
            }
            if (!preg_match('~^https://~', $url)) go('release_new', [], 'Add an https link to the APK, or upload it.');
            if ($sha !== '' && !preg_match('/^[a-f0-9]{64}$/', $sha)) go('release_new', [], 'The SHA-256 should be 64 hex characters.');
            $required = !empty($_POST['required']) ? 1 : 0;
            $publish = !empty($_POST['publish']) ? 1 : 0;
            $pdo->prepare('INSERT INTO releases (version_name, build, notes, apk_url, sha256, size_bytes, required, published, created_by, published_at)
                           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, IF(? = 1, UTC_TIMESTAMP(), NULL))
                           ON DUPLICATE KEY UPDATE version_name = VALUES(version_name), notes = VALUES(notes), apk_url = VALUES(apk_url),
                             sha256 = VALUES(sha256), size_bytes = COALESCE(VALUES(size_bytes), size_bytes), required = VALUES(required),
                             published = VALUES(published), published_at = IF(VALUES(published) = 1, COALESCE(published_at, UTC_TIMESTAMP()), NULL)')
                ->execute([$version, $build, $notes, $url, $sha, $size, $required, $publish, $admin['id'], $publish]);
            go('releases', [], $publish ? "Samgeet $version is live: phones see it the next time they open the app. Use “Remind older phones” to nudge everyone else." : "Saved $version as a draft.");
        case 'release_toggle':
            $pdo->prepare('UPDATE releases SET published = 1 - published, published_at = IF(published = 1, COALESCE(published_at, UTC_TIMESTAMP()), published_at) WHERE id = ?')->execute([$id]);
            go('releases', [], 'Updated.');
        case 'release_delete':
            $pdo->prepare('DELETE FROM releases WHERE id = ?')->execute([$id]);
            go('releases', [], 'Deleted.');

        case 'notify_save':
            [$newId, $err] = rp_send($pdo, [
                'title' => $_POST['title'] ?? '', 'body' => $_POST['body'] ?? '', 'image_url' => $_POST['image_url'] ?? '',
                'style' => $_POST['style'] ?? '', 'action' => $_POST['action'] ?? '', 'action_value' => $_POST['action_value'] ?? '',
                'action_label' => $_POST['action_label'] ?? '', 'show_as' => $_POST['show_as'] ?? '', 'audience' => $_POST['audience'] ?? '',
                'audience_build' => $_POST['audience_build'] ?? 0,
                'starts_at' => from_ist((string)($_POST['starts_at'] ?? '')), 'ends_at' => from_ist((string)($_POST['ends_at'] ?? '')),
            ], (int)$admin['id'], 'web');
            if ($err) go('notify_new', isset($_POST['copy']) ? ['copy' => (int)$_POST['copy']] : [], message_error($err));
            go('notification', ['id' => $newId], 'Sent. Phones pick it up when the app opens, or within 30 minutes while it is running.');
        case 'notify_resend':
            $who = (string)($_POST['who'] ?? 'all');
            [$newId, $err] = rp_resend($pdo, $id, $who, (int)$admin['id'], 'web');
            if ($err) go('notification', ['id' => $id], message_error($err));
            go('notification', ['id' => $newId], 'Sent again as a new message (' . mb_strtolower(RP_FOLLOW_UPS[$who] ?? RP_FOLLOW_UPS['all']) . '). The original has stopped and keeps its numbers in the history.');
        case 'notify_toggle':
            $pdo->prepare('UPDATE notifications SET active = 1 - active WHERE id = ?')->execute([$id]);
            go('notification', ['id' => $id], 'Updated.');
        case 'notify_delete':
            $pdo->prepare('DELETE FROM notifications WHERE id = ?')->execute([$id]);
            go('notifications', [], 'Deleted.');

        case 'password':
            $cur = (string)($_POST['current'] ?? '');
            $new = (string)($_POST['new'] ?? '');
            $hash = rp_scalar($pdo, 'SELECT password_hash FROM admins WHERE id = ?', [$admin['id']]);
            if (!password_verify($cur, (string)$hash)) go('account', [], 'The current password is wrong.');
            if (strlen($new) < 12) go('account', [], 'Use at least 12 characters.');
            $pdo->prepare('UPDATE admins SET password_hash = ? WHERE id = ?')->execute([password_hash($new, PASSWORD_DEFAULT), $admin['id']]);
            go('account', [], 'Password changed.');
    }
    go('dashboard');
}

// ---------------------------------------------------------------- CSV export
if ($page === 'export' && isset($_GET['from'], $_GET['to'])) {
    $from = from_ist($_GET['from'] . ' 00:00') ?? gmdate('Y-m-d H:i:s', time() - 7 * 86400);
    $to = from_ist($_GET['to'] . ' 23:59:59') ?? gmdate('Y-m-d H:i:s');
    $types = array_values(array_filter((array)($_GET['types'] ?? []), fn($t) => preg_match('/^[a-z_]{1,24}$/', (string)$t)));
    header('Content-Type: text/csv; charset=utf-8');
    header('Content-Disposition: attachment; filename="samgeet-events-' . preg_replace('/[^0-9-]/', '', (string)$_GET['from']) . '.csv"');
    $out = fopen('php://output', 'w');
    fputcsv($out, ['event_id', 'time_ist', 'type', 'user_id', 'email', 'device_id', 'device', 'app_version', 'track_id', 'title', 'main_artist', 'album', 'language', 'ms', 'value', 'meta']);
    $sql = 'SELECT e.id, e.client_at, e.type, e.user_id, u.email, e.device_id, CONCAT(d.brand, " ", d.model) AS device, d.app_version,
                   e.track_id, t.title, a.name AS artist, t.album, t.language, e.ms, e.value, e.meta
            FROM events e
            JOIN devices d ON d.id = e.device_id
            LEFT JOIN users u ON u.id = e.user_id
            LEFT JOIN tracks t ON t.id = e.track_id
            LEFT JOIN track_artists ta ON ta.track_id = e.track_id AND ta.position = 0
            LEFT JOIN artists a ON a.id = ta.artist_id
            WHERE e.client_at BETWEEN ? AND ?' . ($types ? ' AND e.type IN (' . implode(',', array_fill(0, count($types), '?')) . ')' : '') . '
            ORDER BY e.id';
    $q = $pdo->prepare($sql, [PDO::MYSQL_ATTR_USE_BUFFERED_QUERY => false]);
    $q->execute(array_merge([$from, $to], $types));
    while ($r = $q->fetch(PDO::FETCH_ASSOC)) {
        $r['client_at'] = ist($r['client_at'], 'Y-m-d H:i:s');
        // Cells starting with = + - @ would run as formulas in a spreadsheet.
        fputcsv($out, array_map(fn($v) => is_string($v) && preg_match('/^[=+\-@\t\r]/', $v) ? "'" . $v : $v, $r));
    }
    exit;
}

// ---------------------------------------------------------------- pages
$flash = $_SESSION['flash'] ?? null;
unset($_SESSION['flash']);

$pages = [
    'dashboard' => fn() => view_dashboard($pdo),
    'listening' => fn() => view_listening($pdo),
    'users' => fn() => view_users($pdo),
    'user' => fn() => view_user($pdo, (int)($_GET['id'] ?? 0)),
    'places' => fn() => view_places($pdo),
    'place' => fn() => view_place($pdo, (string)($_GET['city'] ?? ''), (string)($_GET['country'] ?? '')),
    'notifications' => fn() => view_messages($pdo),
    'notify_new' => fn() => view_message_new($pdo),
    'notification' => fn() => view_message($pdo, (int)($_GET['id'] ?? 0)),
    'releases' => fn() => view_releases($pdo),
    'release_new' => fn() => view_release_new($pdo),
    'export' => fn() => view_export(),
    'account' => fn() => view_account($admin),
];
if (!isset($pages[$page])) $page = 'dashboard';
ob_start();
$title = $pages[$page]();
$content = ob_get_clean();
render_layout($page, $admin, $flash, $content, is_string($title) ? $title : '');
