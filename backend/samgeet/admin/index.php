<?php
// Samgeet admin panel: listening reports, accounts, app releases and notifications.
// Lives at <api host>/<private folder>/samgeet/admin/. Sign-in is checked against `admins`
// (bcrypt hashes only); five wrong passwords from one address lock it for 15 minutes.
// Every form carries a CSRF token, the session cookie is HttpOnly + SameSite=Strict + Secure, and the
// page can't be framed or indexed.

declare(strict_types=1);
require __DIR__ . '/../lib/bootstrap.php';

const IDLE_LIMIT = 7200;      // signed out after 2 hours without a click
const ABSOLUTE_LIMIT = 43200; // and after 12 hours in any case
const IST = '+05:30';         // reports are shown in Indian time
const NOTIFY_STYLES = ['info' => 'Info', 'celebrate' => 'Celebrate', 'warning' => 'Warning'];
const NOTIFY_SHOW = ['both' => 'Popup + phone notification', 'popup' => 'Popup in the app only', 'system' => 'Phone notification only'];
const NOTIFY_ACTIONS = ['none' => 'No link', 'update' => 'Update the app', 'url' => 'Open a link', 'search' => 'Search for…'];
const NOTIFY_AUDIENCE = ['all' => 'Everyone', 'signed_in' => 'Signed-in listeners', 'guests' => 'Guests', 'below_build' => 'Older app versions'];

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

function h($s): string
{
    return htmlspecialchars((string)$s, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
}

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

function num($n): string
{
    return number_format((float)$n);
}

function scalar(PDO $pdo, string $sql, array $args = [])
{
    $q = $pdo->prepare($sql);
    $q->execute($args);
    return $q->fetchColumn();
}

function rows(PDO $pdo, string $sql, array $args = []): array
{
    $q = $pdo->prepare($sql);
    $q->execute($args);
    return $q->fetchAll(PDO::FETCH_ASSOC);
}

function ist(?string $utc, string $fmt = 'd M Y, H:i'): string
{
    if (!$utc) return '—';
    $d = new DateTime($utc, new DateTimeZone('UTC'));
    $d->setTimezone(new DateTimeZone('Asia/Kolkata'));
    return $d->format($fmt);
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
        $fails = (int)scalar($pdo, 'SELECT COUNT(*) FROM admin_logins WHERE success = 0 AND created_at > UTC_TIMESTAMP() - INTERVAL 15 MINUTE AND (ip_hash = ? OR email = ?)', [$ipHash, $email]);
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
            $key = scalar($pdo, 'SELECT key_hash FROM users WHERE id = ?', [$id]);
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
            if (!preg_match('/^\d+\.\d+\.\d+$/', $version) || $build < 1) go('releases', [], 'Version must look like 1.4.0 and the build must be a number.');
            if (!empty($_FILES['apk']['tmp_name']) && is_uploaded_file($_FILES['apk']['tmp_name'])) {
                $tmp = $_FILES['apk']['tmp_name'];
                if (file_get_contents($tmp, false, null, 0, 4) !== "PK\x03\x04") go('releases', [], 'That file is not an APK.');
                $dir = dirname(__DIR__) . '/files';
                if (!is_dir($dir)) mkdir($dir, 0755, true);
                $name = 'Samgeet-' . $version . '.apk';
                if (!move_uploaded_file($tmp, "$dir/$name")) go('releases', [], 'Could not save the upload.');
                $sha = hash_file('sha256', "$dir/$name");
                $size = filesize("$dir/$name");
                $url = ($GLOBALS['https'] ? 'https://' : 'http://') . $_SERVER['HTTP_HOST'] . dirname(rtrim($GLOBALS['base'], '/')) . '/files/' . $name;
            } elseif (!empty($_FILES['apk']['name']) && ($_FILES['apk']['error'] ?? 0) !== UPLOAD_ERR_OK) {
                go('releases', [], 'The upload failed (error ' . (int)$_FILES['apk']['error'] . '). The file may be bigger than the server allows; use a link instead.');
            }
            if (!preg_match('~^https://~', $url)) go('releases', [], 'Add an https link to the APK, or upload it.');
            if ($sha !== '' && !preg_match('/^[a-f0-9]{64}$/', $sha)) go('releases', [], 'The SHA-256 should be 64 hex characters.');
            $required = !empty($_POST['required']) ? 1 : 0;
            $publish = !empty($_POST['publish']) ? 1 : 0;
            $pdo->prepare('INSERT INTO releases (version_name, build, notes, apk_url, sha256, size_bytes, required, published, created_by, published_at)
                           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, IF(? = 1, UTC_TIMESTAMP(), NULL))
                           ON DUPLICATE KEY UPDATE version_name = VALUES(version_name), notes = VALUES(notes), apk_url = VALUES(apk_url),
                             sha256 = VALUES(sha256), size_bytes = COALESCE(VALUES(size_bytes), size_bytes), required = VALUES(required),
                             published = VALUES(published), published_at = IF(VALUES(published) = 1, COALESCE(published_at, UTC_TIMESTAMP()), NULL)')
                ->execute([$version, $build, $notes, $url, $sha, $size, $required, $publish, $admin['id'], $publish]);
            go('releases', [], $publish ? "Samgeet $version is live: phones see it the next time they open the app." : "Saved $version as a draft.");
        case 'release_toggle':
            $pdo->prepare('UPDATE releases SET published = 1 - published, published_at = IF(published = 1, COALESCE(published_at, UTC_TIMESTAMP()), published_at) WHERE id = ?')->execute([$id]);
            go('releases', [], 'Updated.');
        case 'release_delete':
            $pdo->prepare('DELETE FROM releases WHERE id = ?')->execute([$id]);
            go('releases', [], 'Deleted.');

        case 'notify_save':
            $title = trim((string)($_POST['title'] ?? ''));
            $body = trim((string)($_POST['body'] ?? ''));
            if ($title === '' || mb_strlen($title) > 120 || $body === '' || mb_strlen($body) > 2000) go('notifications', [], 'A title (up to 120 characters) and a message are needed.');
            $pick = fn($k, $allowed) => in_array($_POST[$k] ?? '', $allowed, true) ? $_POST[$k] : $allowed[0];
            $action = $pick('action', ['none', 'url', 'update', 'search']);
            $value = trim((string)($_POST['action_value'] ?? ''));
            if ($action === 'url' && !preg_match('~^https://~', $value)) go('notifications', [], 'The button link must start with https://');
            $image = trim((string)($_POST['image_url'] ?? ''));
            if ($image !== '' && !preg_match('~^https://~', $image)) go('notifications', [], 'The picture link must start with https://');
            $audience = $pick('audience', ['all', 'signed_in', 'guests', 'below_build']);
            $pdo->prepare('INSERT INTO notifications (title, body, image_url, style, action, action_value, action_label, show_as, audience, audience_build, starts_at, ends_at, created_by)
                           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, COALESCE(?, UTC_TIMESTAMP()), ?, ?)')
                ->execute([
                    $title, $body, $image, $pick('style', ['info', 'celebrate', 'warning']), $action, mb_substr($value, 0, 400),
                    mb_substr(trim((string)($_POST['action_label'] ?? '')), 0, 40), $pick('show_as', ['both', 'popup', 'system']),
                    $audience, $audience === 'below_build' ? max(1, (int)($_POST['audience_build'] ?? 0)) : null,
                    from_ist((string)($_POST['starts_at'] ?? '')), from_ist((string)($_POST['ends_at'] ?? '')), $admin['id'],
                ]);
            go('notifications', [], 'Sent. Phones pick it up when the app opens, or within 30 minutes while it is running.');
        case 'notify_resend':
            $pdo->prepare('INSERT INTO notifications (title, body, image_url, style, action, action_value, action_label, show_as, audience, audience_build, created_by)
                           SELECT title, body, image_url, style, action, action_value, action_label, show_as, audience, audience_build, ?
                           FROM notifications WHERE id = ?')->execute([$admin['id'], $id]);
            go('notifications', [], 'Sent again as a new message. The original stays in the history as it was.');
        case 'notify_toggle':
            $pdo->prepare('UPDATE notifications SET active = 1 - active WHERE id = ?')->execute([$id]);
            go('notification', ['id' => $id], 'Updated.');
        case 'notify_delete':
            $pdo->prepare('DELETE FROM notifications WHERE id = ?')->execute([$id]);
            go('notifications', [], 'Deleted.');

        case 'password':
            $cur = (string)($_POST['current'] ?? '');
            $new = (string)($_POST['new'] ?? '');
            $hash = scalar($pdo, 'SELECT password_hash FROM admins WHERE id = ?', [$admin['id']]);
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

ob_start();
switch ($page) {
    case 'users':
        page_users($pdo);
        break;
    case 'user':
        page_user($pdo, (int)($_GET['id'] ?? 0));
        break;
    case 'releases':
        page_releases($pdo);
        break;
    case 'notifications':
        page_notifications($pdo);
        break;
    case 'notification':
        page_notification($pdo, (int)($_GET['id'] ?? 0));
        break;
    case 'export':
        page_export();
        break;
    case 'account':
        page_account($admin);
        break;
    default:
        $page = 'dashboard';
        page_dashboard($pdo);
}
$content = ob_get_clean();
render_layout($page, $admin, $flash, $content);

// ================================================================ views

/// [from, to) in UTC for a period key, plus the same-length period just before it (for the change %).
function dash_period(string $r): array
{
    $utc = new DateTimeZone('UTC');
    $now = gmdate('Y-m-d H:i:s');
    if ($r === 'all') return ['1970-01-01 00:00:00', $now, null, null];
    if ($r === '1') {
        $today = new DateTime('today', new DateTimeZone('Asia/Kolkata'));
        $from = (clone $today)->setTimezone($utc)->format('Y-m-d H:i:s');
        $prevFrom = (clone $today)->modify('-1 day')->setTimezone($utc)->format('Y-m-d H:i:s');
        // Yesterday up to the same time of day, so a morning isn't compared with a whole day.
        $prevTo = gmdate('Y-m-d H:i:s', time() - 86400);
        return [$from, $now, $prevFrom, $prevTo];
    }
    $len = (int)$r * 86400;
    return [gmdate('Y-m-d H:i:s', time() - $len), $now, gmdate('Y-m-d H:i:s', time() - 2 * $len), gmdate('Y-m-d H:i:s', time() - $len)];
}

/// Listening numbers for [from, to): who listened (signed in vs guests), plays and hours for each.
function dash_listening(PDO $pdo, string $from, string $to): array
{
    $q = $pdo->prepare("SELECT
            COUNT(DISTINCT IF(type = 'play_start' AND user_id IS NOT NULL, user_id, NULL)) AS members,
            COUNT(DISTINCT IF(type = 'play_start' AND user_id IS NULL, device_id, NULL)) AS guests,
            SUM(type = 'play_start' AND user_id IS NOT NULL) AS member_plays,
            SUM(type = 'play_start' AND user_id IS NULL) AS guest_plays,
            COALESCE(SUM(IF(type = 'play_end' AND user_id IS NOT NULL, ms, 0)), 0) AS member_ms,
            COALESCE(SUM(IF(type = 'play_end' AND user_id IS NULL, ms, 0)), 0) AS guest_ms
        FROM events WHERE client_at >= ? AND client_at < ? AND type IN ('play_start', 'play_end')");
    $q->execute([$from, $to]);
    $x = array_map('floatval', $q->fetch(PDO::FETCH_ASSOC));
    $x['listeners'] = $x['members'] + $x['guests'];
    $x['plays'] = $x['member_plays'] + $x['guest_plays'];
    $x['hours'] = ($x['member_ms'] + $x['guest_ms']) / 3600000;
    return $x;
}

/// "+12%" / "−4%" against the previous period, or '' when there's nothing to compare with.
function dash_change(float $now, ?float $before): string
{
    if ($before === null) return '';
    if ($before == 0) return $now > 0 ? '<span class="chg up">new</span>' : '';
    $p = round(100 * ($now - $before) / $before);
    if ($p == 0) return '<span class="chg">±0%</span>';
    return '<span class="chg ' . ($p > 0 ? 'up' : 'down') . '">' . ($p > 0 ? '▲ ' : '▼ ') . abs($p) . '%</span>';
}

/// A tiny line chart as inline SVG (no script needed).
function dash_spark(array $values, string $color = 'var(--accent)'): string
{
    $n = count($values);
    if ($n < 2) return '';
    $max = max(1, max($values));
    $pts = [];
    foreach (array_values($values) as $i => $v) $pts[] = round($i * 100 / ($n - 1), 1) . ',' . round(28 - 26 * $v / $max, 1);
    $line = implode(' ', $pts);
    return '<svg class="spark" viewBox="0 0 100 30" preserveAspectRatio="none" aria-hidden="true">'
        . '<polyline points="0,30 ' . $line . ' 100,30" fill="' . $color . '" fill-opacity=".12" stroke="none"/>'
        . '<polyline points="' . $line . '" fill="none" stroke="' . $color . '" stroke-width="2" vector-effect="non-scaling-stroke"/></svg>';
}

function page_dashboard(PDO $pdo): void
{
    global $nonce;
    $ranges = ['1' => 'Today', '7' => '7 days', '30' => '30 days', '90' => '90 days', 'all' => 'All time'];
    $r = (string)($_GET['r'] ?? '7');
    if (!isset($ranges[$r])) $r = '7';
    [$since, $to, $prevFrom, $prevTo] = dash_period($r);
    $label = $r === 'all' ? 'all time' : ($r === '1' ? 'today' : "the last $r days");
    $vs = $r === 'all' ? '' : ($r === '1' ? 'yesterday' : 'the ' . $r . ' days before');

    // ---- listening, split by signed-in listeners and guests
    $L = dash_listening($pdo, $since, $to);
    $P = $prevFrom ? dash_listening($pdo, $prevFrom, $prevTo) : null;
    $newUsers = (int)scalar($pdo, 'SELECT COUNT(*) FROM users WHERE created_at >= ?', [$since]);
    $prevNewUsers = $prevFrom ? (int)scalar($pdo, 'SELECT COUNT(*) FROM users WHERE created_at >= ? AND created_at < ?', [$prevFrom, $prevTo]) : null;
    // Guests who went on to make an account: phones that played as a guest, now signed in to an
    // account created in this period.
    $converted = (int)scalar($pdo, "SELECT COUNT(DISTINCT d.id) FROM devices d JOIN users u ON u.id = d.user_id
                                    WHERE u.created_at >= ? AND EXISTS (SELECT 1 FROM events e WHERE e.device_id = d.id AND e.user_id IS NULL AND e.type = 'play_start')", [$since]);

    // ---- daily series (for the chart and the sparklines)
    $days = $r === 'all' ? 90 : max(14, min(90, (int)$r));
    $daily = rows($pdo, "SELECT DATE(CONVERT_TZ(client_at, '+00:00', '" . IST . "')) AS d,
                                COUNT(DISTINCT IF(type = 'play_start' AND user_id IS NOT NULL, user_id, NULL)) AS members,
                                COUNT(DISTINCT IF(type = 'play_start' AND user_id IS NULL, device_id, NULL)) AS guests,
                                SUM(type = 'play_start') AS plays,
                                ROUND(SUM(IF(type = 'play_end', ms, 0)) / 3600000, 2) AS hours
                         FROM events WHERE client_at > UTC_TIMESTAMP() - INTERVAL $days DAY AND type IN ('play_start', 'play_end')
                         GROUP BY d ORDER BY d");
    $signups = [];
    foreach (rows($pdo, "SELECT DATE(CONVERT_TZ(created_at, '+00:00', '" . IST . "')) AS d, COUNT(*) AS n FROM users
                         WHERE created_at > UTC_TIMESTAMP() - INTERVAL $days DAY GROUP BY d") as $s) $signups[$s['d']] = (int)$s['n'];
    $col = fn(string $k) => array_map(fn($d) => (float)$d[$k], $daily);
    $sparkListeners = array_map(fn($d) => (float)$d['members'] + (float)$d['guests'], $daily);

    // ---- accounts and phones
    $todayIst = dash_period('1')[0];
    $activeUsers = fn(string $from) => (int)scalar($pdo, 'SELECT COUNT(DISTINCT user_id) FROM events WHERE user_id IS NOT NULL AND client_at >= ?', [$from]);
    $dau = $activeUsers($todayIst);
    $wau = $activeUsers(gmdate('Y-m-d H:i:s', time() - 7 * 86400));
    $mau = $activeUsers(gmdate('Y-m-d H:i:s', time() - 30 * 86400));
    $totalUsers = (int)scalar($pdo, 'SELECT COUNT(*) FROM users');
    $signedInNow = (int)scalar($pdo, 'SELECT COUNT(DISTINCT user_id) FROM sessions WHERE revoked_at IS NULL AND expires_at > UTC_TIMESTAMP()');
    $totalPhones = (int)scalar($pdo, 'SELECT COUNT(*) FROM devices');
    $guestPhonesAll = (int)scalar($pdo, 'SELECT COUNT(*) FROM devices WHERE user_id IS NULL');
    $activePhones = (int)scalar($pdo, 'SELECT COUNT(*) FROM devices WHERE last_seen_at >= ?', [$since]);
    $newPhones = (int)scalar($pdo, 'SELECT COUNT(*) FROM devices WHERE first_seen_at >= ?', [$since]);
    $onlineNow = (int)scalar($pdo, 'SELECT COUNT(*) FROM devices WHERE last_seen_at > UTC_TIMESTAMP() - INTERVAL 15 MINUTE');
    $latest = (int)scalar($pdo, 'SELECT COALESCE(MAX(build), 0) FROM releases WHERE published = 1');
    $recentPhones = (int)scalar($pdo, 'SELECT COUNT(*) FROM devices WHERE last_seen_at > UTC_TIMESTAMP() - INTERVAL 30 DAY');
    $onLatest = $latest ? (int)scalar($pdo, 'SELECT COUNT(*) FROM devices WHERE last_seen_at > UTC_TIMESTAMP() - INTERVAL 30 DAY AND app_build >= ?', [$latest]) : 0;

    // ---- everything else people did in the period
    $ev = [];
    foreach (rows($pdo, 'SELECT type, COUNT(*) AS n, COUNT(DISTINCT device_id) AS phones FROM events WHERE client_at >= ? GROUP BY type', [$since]) as $row) $ev[$row['type']] = $row;
    $n = fn(string $t) => (int)($ev[$t]['n'] ?? 0);
    $ends = [];
    foreach (rows($pdo, "SELECT value, COUNT(*) AS n FROM events WHERE type = 'play_end' AND client_at >= ? GROUP BY value", [$since]) as $e) $ends[$e['value']] = (int)$e['n'];
    $endTotal = array_sum($ends);
    $offline = (int)scalar($pdo, "SELECT COUNT(*) FROM events WHERE type = 'play_start' AND client_at >= ? AND meta LIKE '%\"offline\":true%'", [$since]);
    $songs = (int)scalar($pdo, "SELECT COUNT(DISTINCT track_id) FROM events WHERE type = 'play_start' AND client_at >= ?", [$since]);
    $pct = fn($a, $b) => $b > 0 ? round(100 * $a / $b) . '%' : '—';

    // ---- lists
    $topTracks = rows($pdo, "SELECT t.title, t.image, a.name AS artist, COUNT(*) AS plays, COUNT(DISTINCT e.device_id) AS listeners
                             FROM events e JOIN tracks t ON t.id = e.track_id
                             LEFT JOIN track_artists ta ON ta.track_id = t.id AND ta.position = 0 LEFT JOIN artists a ON a.id = ta.artist_id
                             WHERE e.type = 'play_start' AND e.client_at >= ?
                             GROUP BY t.id, t.title, t.image, a.name ORDER BY plays DESC LIMIT 10", [$since]);
    $topArtists = rows($pdo, "SELECT a.name, COUNT(*) AS plays, COUNT(DISTINCT e.device_id) AS listeners
                              FROM events e JOIN track_artists ta ON ta.track_id = e.track_id AND ta.position = 0 JOIN artists a ON a.id = ta.artist_id
                              WHERE e.type = 'play_start' AND e.client_at >= ?
                              GROUP BY a.id, a.name ORDER BY plays DESC LIMIT 10", [$since]);
    $searches = rows($pdo, "SELECT LOWER(value) AS label, COUNT(*) AS n FROM events WHERE type = 'search' AND value IS NOT NULL
                            AND client_at >= ? GROUP BY LOWER(value) ORDER BY n DESC LIMIT 10", [$since]);
    $topLiked = rows($pdo, "SELECT CONCAT(t.title, IF(a.name IS NULL, '', CONCAT(' · ', a.name))) AS label, COUNT(*) AS n
                            FROM events e JOIN tracks t ON t.id = e.track_id
                            LEFT JOIN track_artists ta ON ta.track_id = t.id AND ta.position = 0 LEFT JOIN artists a ON a.id = ta.artist_id
                            WHERE e.type IN ('like','download') AND e.client_at >= ? GROUP BY t.id, label ORDER BY n DESC LIMIT 10", [$since]);
    $topUsers = rows($pdo, "SELECT u.id, COALESCE(NULLIF(u.name, ''), u.email) AS label, ROUND(SUM(IF(e.type = 'play_end', e.ms, 0)) / 60000) AS n
                            FROM events e JOIN users u ON u.id = e.user_id
                            WHERE e.client_at >= ? AND e.type = 'play_end' GROUP BY u.id, label ORDER BY n DESC LIMIT 10", [$since]);
    $recent = rows($pdo, 'SELECT id, COALESCE(NULLIF(name, \'\'), email) AS label, created_at FROM users ORDER BY created_at DESC LIMIT 10');
    $languages = rows($pdo, "SELECT COALESCE(NULLIF(t.language, ''), 'unknown') AS label, COUNT(*) AS n FROM events e JOIN tracks t ON t.id = e.track_id
                             WHERE e.type = 'play_start' AND e.client_at >= ? GROUP BY label ORDER BY n DESC LIMIT 8", [$since]);
    $sources = rows($pdo, "SELECT COALESCE(NULLIF(value, ''), 'other') AS label, COUNT(*) AS n FROM events
                           WHERE type = 'play_start' AND client_at >= ? GROUP BY label ORDER BY n DESC LIMIT 8", [$since]);
    $hours = array_fill(0, 24, 0);
    foreach (rows($pdo, "SELECT HOUR(CONVERT_TZ(client_at, '+00:00', '" . IST . "')) AS hr, COUNT(*) AS n FROM events
                         WHERE type = 'play_start' AND client_at >= ? GROUP BY hr", [$since]) as $row) $hours[(int)$row['hr']] = (int)$row['n'];
    $tastes = [];
    foreach (rows($pdo, 'SELECT kind, value AS label, COUNT(*) AS n FROM user_tastes GROUP BY kind, value ORDER BY n DESC LIMIT 60') as $t) {
        if (count($tastes[$t['kind']] ?? []) < 6) $tastes[$t['kind']][] = $t;
    }
    $versions = rows($pdo, "SELECT COALESCE(NULLIF(app_version, ''), 'unknown') AS label, COUNT(*) AS n FROM devices WHERE last_seen_at >= ? GROUP BY label ORDER BY n DESC LIMIT 6", [$since]);
    $models = rows($pdo, "SELECT CONCAT(brand, ' ', model) AS label, COUNT(*) AS n FROM devices WHERE model <> '' AND last_seen_at >= ? GROUP BY label ORDER BY n DESC LIMIT 6", [$since]);
    $android = rows($pdo, "SELECT CONCAT('Android ', COALESCE(NULLIF(os_version, ''), '?')) AS label, COUNT(*) AS n FROM devices WHERE last_seen_at >= ? GROUP BY label ORDER BY n DESC LIMIT 6", [$since]);
    $styles = rows($pdo, 'SELECT CONCAT(UPPER(LEFT(player_style, 1)), SUBSTRING(player_style, 2)) AS label, COUNT(*) AS n FROM users GROUP BY player_style ORDER BY n DESC');

    /// A ranked list with a bar showing each row's share of the first.
    $bars = function (array $rows, string $unit = '', ?callable $link = null): void {
        if (!$rows) {
            echo '<p class="empty">Nothing yet.</p>';
            return;
        }
        $max = max(1, (float)$rows[0]['n']);
        echo '<ol class="bars">';
        foreach ($rows as $row) {
            $w = max(2, round(100 * (float)$row['n'] / $max));
            $name = h($row['label']);
            if ($link) $name = '<a href="' . h($link($row)) . '">' . $name . '</a>';
            echo '<li><span class="b" style="width:' . $w . '%"></span><span class="l">' . $name . '</span><span class="v">' . num($row['n']) . h($unit) . '</span></li>';
        }
        echo '</ol>';
    };

    $memberShare = $L['listeners'] > 0 ? round(100 * $L['members'] / $L['listeners']) : 0;
    $hero = [
        ['Listeners', num($L['listeners']), dash_change($L['listeners'], $P['listeners'] ?? null), num($L['members']) . ' signed in · ' . num($L['guests']) . ' guests', $sparkListeners, 'var(--accent)'],
        ['Plays', num($L['plays']), dash_change($L['plays'], $P['plays'] ?? null), num($songs) . ' different songs', $col('plays'), 'var(--accent2)'],
        ['Hours listened', number_format($L['hours'], 1), dash_change($L['hours'], $P['hours'] ?? null), $L['listeners'] ? round($L['hours'] * 60 / $L['listeners']) . ' min per listener' : '—', $col('hours'), 'var(--ok)'],
        ['New accounts', num($newUsers), dash_change($newUsers, $prevNewUsers), ($converted === 1 ? '1 was a guest first' : num($converted) . ' were guests first'), array_map(fn($d) => $signups[$d['d']] ?? 0, $daily), '#8f8cf0'],
    ];
    ?>
    <div class="head-row">
      <div><h1>Overview</h1><p class="sub">Showing <?= h($label) ?><?= $vs ? ', compared with ' . h($vs) : '' ?> · updated <?= ist(gmdate('Y-m-d H:i:s'), 'H:i') ?> IST</p></div>
      <nav class="ranges"><?php foreach ($ranges as $k => $l): ?><a class="<?= (string)$k === $r ? 'on' : '' ?>" href="?p=dashboard&amp;r=<?= h($k) ?>"><?= h($l) ?></a><?php endforeach; ?></nav>
    </div>

    <div class="hero">
      <?php foreach ($hero as [$l, $v, $chg, $sub, $series, $color]): ?>
        <div class="hero-card">
          <div class="hero-top"><span class="hero-l"><?= h($l) ?></span><?= $chg ?></div>
          <div class="hero-v"><?= h($v) ?></div>
          <div class="hero-s"><?= h($sub) ?></div>
          <?= dash_spark($series, $color) ?>
        </div>
      <?php endforeach; ?>
    </div>

    <section class="card who">
      <div class="who-head">
        <h2>Who's listening</h2>
        <span class="muted small">Guests play music without signing in; each phone counts once.</span>
      </div>
      <div class="split" role="img" aria-label="<?= $memberShare ?>% signed in, <?= 100 - $memberShare ?>% guests">
        <span class="s-m" style="width:<?= $L['listeners'] ? $memberShare : 50 ?>%"></span><span class="s-g"></span>
      </div>
      <div class="who-grid">
        <div><span class="dot m"></span><b>Signed in</b>
          <dl><dt>Listeners</dt><dd><?= num($L['members']) ?></dd><dt>Plays</dt><dd><?= num($L['member_plays']) ?></dd><dt>Hours</dt><dd><?= number_format($L['member_ms'] / 3600000, 1) ?></dd>
            <dt>Plays each</dt><dd><?= $L['members'] ? number_format($L['member_plays'] / $L['members'], 1) : '—' ?></dd></dl></div>
        <div><span class="dot g"></span><b>Guests</b>
          <dl><dt>Listeners</dt><dd><?= num($L['guests']) ?></dd><dt>Plays</dt><dd><?= num($L['guest_plays']) ?></dd><dt>Hours</dt><dd><?= number_format($L['guest_ms'] / 3600000, 1) ?></dd>
            <dt>Plays each</dt><dd><?= $L['guests'] ? number_format($L['guest_plays'] / $L['guests'], 1) : '—' ?></dd></dl></div>
        <div><span class="dot c"></span><b>Turning guests into accounts</b>
          <dl><dt>Signed up after listening</dt><dd><?= num($converted) ?></dd><dt>Guest phones (all time)</dt><dd><?= num($guestPhonesAll) ?></dd>
            <dt>Share of listeners signed in</dt><dd><?= $L['listeners'] ? $memberShare . '%' : '—' ?></dd></dl></div>
      </div>
    </section>

    <section class="card"><h2>Daily listeners <small>last <?= $days ?> days, IST</small></h2><div class="chart tall"><canvas id="daily"></canvas></div></section>

    <div class="cols">
      <section class="card">
        <h2>Top songs</h2>
        <?php if (!$topTracks): ?><p class="empty">No plays yet.</p><?php else: ?>
        <ol class="songs">
          <?php foreach ($topTracks as $i => $t): ?>
            <li><span class="rank"><?= $i + 1 ?></span>
              <?php if ($t['image']): ?><img src="<?= h($t['image']) ?>" alt="" loading="lazy"><?php else: ?><span class="noimg">♪</span><?php endif; ?>
              <span class="meta"><b><?= h($t['title']) ?></b><span class="muted"><?= h($t['artist']) ?></span></span>
              <span class="v"><?= num($t['plays']) ?><small><?= num($t['listeners']) ?> listeners</small></span></li>
          <?php endforeach; ?>
        </ol><?php endif; ?>
      </section>
      <section class="card"><h2>Top singers <small>plays</small></h2><?php $bars(array_map(fn($a) => ['label' => $a['name'], 'n' => $a['plays']], $topArtists)); ?></section>
    </div>

    <section class="card">
      <h2>At a glance <small><?= h($label) ?></small></h2>
      <div class="glance">
        <div><h3>Accounts</h3><dl>
          <dt>Total</dt><dd><?= num($totalUsers) ?></dd>
          <dt>Active today</dt><dd><?= num($dau) ?></dd>
          <dt>Active this week</dt><dd><?= num($wau) ?></dd>
          <dt>Active this month</dt><dd><?= num($mau) ?></dd>
          <dt>Come back daily</dt><dd><?= $pct($dau, $mau) ?></dd>
          <dt>Signed in right now</dt><dd><?= num($signedInNow) ?></dd></dl></div>
        <div><h3>Phones</h3><dl>
          <dt>Total installs</dt><dd><?= num($totalPhones) ?></dd>
          <dt>Active</dt><dd><?= num($activePhones) ?></dd>
          <dt>New installs</dt><dd><?= num($newPhones) ?></dd>
          <dt>Online now</dt><dd><?= num($onlineNow) ?></dd>
          <dt>On latest version</dt><dd><?= $latest ? $pct($onLatest, $recentPhones) : '—' ?></dd>
          <dt>App opens</dt><dd><?= num($n('app_open')) ?></dd></dl></div>
        <div><h3>Listening</h3><dl>
          <dt>Heard to the end</dt><dd><?= $pct($ends['complete'] ?? 0, $endTotal) ?></dd>
          <dt>Skipped</dt><dd><?= $pct($ends['skip'] ?? 0, $endTotal) ?></dd>
          <dt>Played offline</dt><dd><?= num($offline) ?></dd>
          <dt>Radios started</dt><dd><?= num($n('radio_start')) ?></dd>
          <dt>Added to queue</dt><dd><?= num($n('queue_add')) ?></dd>
          <dt>Sleep timers</dt><dd><?= num($n('sleep_timer')) ?></dd></dl></div>
        <div><h3>Actions</h3><dl>
          <dt>Likes</dt><dd><?= num($n('like')) ?></dd>
          <dt>Downloads</dt><dd><?= num($n('download')) ?></dd>
          <dt>Shares</dt><dd><?= num($n('share_song') + $n('share_playlist')) ?></dd>
          <dt>Searches</dt><dd><?= num($n('search')) ?></dd>
          <dt>Playlists made</dt><dd><?= num($n('playlist_create')) ?></dd>
          <dt>Messages opened</dt><dd><?= $pct($n('notification_open'), $n('notification_open') + $n('notification_dismiss')) ?></dd></dl></div>
      </div>
    </section>

    <details class="more">
      <summary>More reports <span class="muted">searches, listeners, tastes, phones, times of day</span></summary>
      <div class="cols three">
        <section class="card"><h2>Top searches</h2><?php $bars($searches); ?></section>
        <section class="card"><h2>Most liked and downloaded</h2><?php $bars($topLiked); ?></section>
        <section class="card"><h2>Most active accounts <small>minutes</small></h2><?php $bars($topUsers, '', fn($row) => '?p=user&id=' . (int)$row['id']); ?></section>
        <section class="card"><h2>Languages played</h2><?php $bars($languages); ?></section>
        <section class="card"><h2>Where plays start</h2><?php $bars($sources); ?></section>
        <section class="card"><h2>Newest accounts</h2>
          <?php if (!$recent): ?><p class="empty">Nobody yet.</p><?php else: ?><ul class="plain">
          <?php foreach ($recent as $u): ?><li><a href="?p=user&amp;id=<?= (int)$u['id'] ?>"><?= h($u['label']) ?></a><span class="muted"><?= ist($u['created_at'], 'd M, H:i') ?></span></li><?php endforeach; ?>
          </ul><?php endif; ?></section>
        <section class="card"><h2>Languages picked at sign-up</h2><?php $bars($tastes['language'] ?? []); ?></section>
        <section class="card"><h2>Moods picked</h2><?php $bars($tastes['mood'] ?? []); ?></section>
        <section class="card"><h2>Singers picked</h2><?php $bars($tastes['artist'] ?? []); ?></section>
        <section class="card"><h2>App versions</h2><?php $bars($versions); ?></section>
        <section class="card"><h2>Phones</h2><?php $bars($models); ?></section>
        <section class="card"><h2>Android versions</h2><?php $bars($android); ?></section>
        <section class="card"><h2>Player looks</h2><?php $bars($styles); ?></section>
        <section class="card span2"><h2>When people listen <small>plays by hour, IST</small></h2><div class="chart"><canvas id="hours"></canvas></div></section>
      </div>
    </details>

    <script nonce="<?= h($nonce) ?>" src="https://cdnjs.cloudflare.com/ajax/libs/Chart.js/4.4.1/chart.umd.min.js"></script>
    <script nonce="<?= h($nonce) ?>">
      (function () {
        if (!window.Chart) return;
        const css = getComputedStyle(document.documentElement);
        const v = k => css.getPropertyValue(k).trim();
        Chart.defaults.color = v('--muted'); Chart.defaults.borderColor = v('--line');
        Chart.defaults.font.family = 'Plus Jakarta Sans, system-ui, sans-serif';
        Chart.defaults.plugins.legend.labels.boxWidth = 10; Chart.defaults.plugins.legend.labels.boxHeight = 10;
        const daily = <?= json_encode($daily, JSON_HEX_TAG | JSON_HEX_AMP) ?>;
        new Chart(document.getElementById('daily'), {
          data: { labels: daily.map(d => d.d.slice(5)), datasets: [
            { type: 'bar', label: 'Signed in', data: daily.map(d => +d.members), backgroundColor: v('--accent'), borderRadius: 4, stack: 'l' },
            { type: 'bar', label: 'Guests', data: daily.map(d => +d.guests), backgroundColor: v('--guest'), borderRadius: 4, stack: 'l' },
            { type: 'line', label: 'Plays', data: daily.map(d => +d.plays), borderColor: v('--accent2'), backgroundColor: v('--accent2'), tension: .35, pointRadius: 0, borderWidth: 2, yAxisID: 'y1' } ] },
          options: { maintainAspectRatio: false, interaction: { mode: 'index', intersect: false },
            plugins: { legend: { position: 'top', align: 'end' } },
            scales: { x: { stacked: true, grid: { display: false } }, y: { stacked: true, beginAtZero: true, title: { display: true, text: 'listeners' } },
                      y1: { beginAtZero: true, position: 'right', grid: { display: false }, title: { display: true, text: 'plays' } } } }
        });
        let hoursDone = false;
        const more = document.querySelector('details.more');
        const drawHours = () => {
          if (hoursDone) return; hoursDone = true;
          new Chart(document.getElementById('hours'), {
            type: 'bar', data: { labels: [...Array(24).keys()].map(h => h + ':00'), datasets: [{ label: 'Plays', data: <?= json_encode($hours) ?>, backgroundColor: v('--accent2'), borderRadius: 3 }] },
            options: { maintainAspectRatio: false, plugins: { legend: { display: false } }, scales: { y: { beginAtZero: true }, x: { grid: { display: false } } } }
          });
        };
        more.addEventListener('toggle', () => { if (more.open) drawHours(); });
        try { if (localStorage.getItem('sg-more') === '1') { more.open = true; drawHours(); } } catch (e) {}
        more.addEventListener('toggle', () => { try { localStorage.setItem('sg-more', more.open ? '1' : '0'); } catch (e) {} });
      })();
    </script>
    <?php
}

function page_users(PDO $pdo): void
{
    $search = trim((string)($_GET['q'] ?? ''));
    $pageNo = max(1, (int)($_GET['n'] ?? 1));
    $where = '';
    $args = [];
    if ($search !== '') {
        $where = 'WHERE u.email LIKE ? OR u.name LIKE ?';
        $like = '%' . addcslashes($search, '%_\\') . '%';
        $args = [$like, $like];
    }
    $total = (int)scalar($pdo, "SELECT COUNT(*) FROM users u $where", $args);
    $list = rows($pdo, "SELECT u.id, u.email, u.name, u.status, u.player_style, u.created_at, u.last_seen_at,
                               (SELECT COUNT(*) FROM devices d WHERE d.user_id = u.id) AS phones,
                               (SELECT COUNT(*) FROM events e WHERE e.user_id = u.id AND e.type = 'play_start') AS plays
                        FROM users u $where ORDER BY u.last_seen_at IS NULL, u.last_seen_at DESC LIMIT 50 OFFSET " . (($pageNo - 1) * 50), $args);
    ?>
    <h1>Accounts <small><?= num($total) ?></small></h1>
    <form class="search" method="get"><input type="hidden" name="p" value="users">
      <input name="q" value="<?= h($search) ?>" placeholder="Search by email or name"><button>Search</button></form>
    <section class="card">
      <table>
        <tr><th>Name</th><th>Email</th><th>Joined</th><th>Last seen</th><th class="r">Phones</th><th class="r">Plays</th><th>Player</th></tr>
        <?php foreach ($list as $u): ?>
          <tr class="link"><td><a href="?p=user&amp;id=<?= (int)$u['id'] ?>"><?= h($u['name'] ?: '—') ?></a><?= $u['status'] !== 'active' ? ' <span class="tag warn">blocked</span>' : '' ?></td>
            <td><?= h($u['email']) ?></td><td><?= ist($u['created_at'], 'd M Y') ?></td><td><?= ist($u['last_seen_at']) ?></td>
            <td class="r"><?= num($u['phones']) ?></td><td class="r"><?= num($u['plays']) ?></td><td><?= h($u['player_style']) ?></td></tr>
        <?php endforeach; if (!$list): ?><tr><td colspan="7" class="muted">Nobody yet.</td></tr><?php endif; ?>
      </table>
      <?php if ($total > 50): ?><div class="pager">
        <?php if ($pageNo > 1): ?><a href="?<?= h(http_build_query(['p' => 'users', 'q' => $search, 'n' => $pageNo - 1])) ?>">← Newer</a><?php endif; ?>
        <?php if ($pageNo * 50 < $total): ?><a href="?<?= h(http_build_query(['p' => 'users', 'q' => $search, 'n' => $pageNo + 1])) ?>">Older →</a><?php endif; ?>
      </div><?php endif; ?>
    </section>
    <?php
}

function page_user(PDO $pdo, int $id): void
{
    $u = rows($pdo, 'SELECT * FROM users WHERE id = ?', [$id])[0] ?? null;
    if (!$u) {
        echo '<h1>Not found</h1>';
        return;
    }
    $tastes = rows($pdo, 'SELECT kind, value FROM user_tastes WHERE user_id = ? ORDER BY kind, value', [$id]);
    $devices = rows($pdo, 'SELECT * FROM devices WHERE user_id = ? ORDER BY last_seen_at DESC', [$id]);
    $sessions = (int)scalar($pdo, 'SELECT COUNT(*) FROM sessions WHERE user_id = ? AND revoked_at IS NULL AND expires_at > UTC_TIMESTAMP()', [$id]);
    $stats = rows($pdo, 'SELECT type, COUNT(*) AS n FROM events WHERE user_id = ? GROUP BY type ORDER BY n DESC', [$id]);
    $events = rows($pdo, 'SELECT e.client_at, e.type, e.value, e.ms, t.title FROM events e LEFT JOIN tracks t ON t.id = e.track_id
                          WHERE e.user_id = ? ORDER BY e.id DESC LIMIT 100', [$id]);
    $lib = rows($pdo, 'SELECT rev, LENGTH(data) AS size, updated_at FROM libraries WHERE user_id = ?', [$id])[0] ?? null;
    $by = [];
    foreach ($tastes as $t) $by[$t['kind']][] = $t['value'];
    ?>
    <p><a href="?p=users">← Accounts</a></p>
    <h1><?= h($u['name'] ?: $u['email']) ?> <?= $u['status'] !== 'active' ? '<span class="tag warn">blocked</span>' : '' ?></h1>
    <div class="grid2">
      <section class="card">
        <table>
          <tr><td class="muted">Email</td><td><?= h($u['email']) ?></td></tr>
          <tr><td class="muted">Joined</td><td><?= ist($u['created_at']) ?></td></tr>
          <tr><td class="muted">Last seen</td><td><?= ist($u['last_seen_at']) ?></td></tr>
          <tr><td class="muted">Player look</td><td><?= h($u['player_style']) ?></td></tr>
          <tr><td class="muted">Signed in on</td><td><?= num($sessions) ?> phone(s)</td></tr>
          <tr><td class="muted">Synced library</td><td><?= $lib ? 'rev ' . (int)$lib['rev'] . ', ' . num(round($lib['size'] / 1024)) . ' KB, ' . ist($lib['updated_at']) : 'none' ?></td></tr>
          <?php foreach (['language' => 'Languages', 'mood' => 'Moods', 'artist' => 'Singers'] as $kk => $label): ?>
            <tr><td class="muted"><?= $label ?></td><td><?= h(implode(', ', $by[$kk] ?? []) ?: '—') ?></td></tr>
          <?php endforeach; ?>
        </table>
        <div class="actions">
          <form method="post" action="?p=user"><?= csrf_field() ?><input type="hidden" name="id" value="<?= $id ?>"><button name="do" value="user_signout">Sign out everywhere</button></form>
          <form method="post" action="?p=user"><?= csrf_field() ?><input type="hidden" name="id" value="<?= $id ?>"><button name="do" value="user_block"><?= $u['status'] === 'active' ? 'Block' : 'Unblock' ?></button></form>
          <form method="post" action="?p=user" data-confirm="Delete this account, its synced library and all its listening data? This can't be undone."><?= csrf_field() ?><input type="hidden" name="id" value="<?= $id ?>"><button class="danger" name="do" value="user_delete">Delete account</button></form>
        </div>
      </section>
      <section class="card">
        <h2>Activity</h2>
        <table><?php foreach ($stats as $s): ?><tr><td><?= h($s['type']) ?></td><td class="r"><?= num($s['n']) ?></td></tr><?php endforeach; ?></table>
        <h2 style="margin-top:22px">Phones</h2>
        <table><?php foreach ($devices as $d): ?><tr><td><?= h(trim($d['brand'] . ' ' . $d['model']) ?: 'Unknown') ?> <span class="muted">Android <?= h($d['os_version']) ?></span></td>
          <td>v<?= h($d['app_version']) ?></td><td class="muted"><?= ist($d['last_seen_at']) ?></td></tr><?php endforeach; ?></table>
      </section>
    </div>
    <section class="card"><h2>Latest 100 events</h2>
      <table><tr><th>When (IST)</th><th>What</th><th>Song</th><th>Detail</th></tr>
        <?php foreach ($events as $e): ?><tr><td class="muted"><?= ist($e['client_at'], 'd M H:i:s') ?></td><td><?= h($e['type']) ?></td><td><?= h($e['title']) ?></td>
          <td class="muted"><?= h($e['value']) ?><?= $e['ms'] !== null ? ' · ' . round($e['ms'] / 1000) . ' s' : '' ?></td></tr><?php endforeach; ?>
      </table></section>
    <?php
}

function page_releases(PDO $pdo): void
{
    $list = rows($pdo, 'SELECT r.*, a.email AS by_email FROM releases r LEFT JOIN admins a ON a.id = r.created_by ORDER BY r.build DESC');
    $next = $list ? (int)$list[0]['build'] + 1 : 9;
    $prefill = ['version' => '', 'notes' => '', 'apk_url' => '', 'sha256' => ''];
    if (isset($_GET['github'])) $prefill = github_latest() + $prefill;
    ?>
    <h1>App updates</h1>
    <p class="muted">The app checks here when it opens. It offers the newest published version whose build number is higher than
      the one installed. Tick “Required” for updates people can't skip.</p>
    <div class="grid2">
      <section class="card">
        <h2>Publish a version</h2>
        <p><a href="?p=releases&amp;github=1">Fill in from the latest GitHub release</a></p>
        <form method="post" action="?p=releases" enctype="multipart/form-data" class="form"><?= csrf_field() ?><input type="hidden" name="do" value="release_save">
          <div class="row2"><label>Version<input name="version" required pattern="\d+\.\d+\.\d+" placeholder="1.4.0" value="<?= h($prefill['version']) ?>"></label>
            <label>Build number<input name="build" type="number" min="1" required value="<?= $next ?>"></label></div>
          <label>What's new<textarea name="notes" rows="7" placeholder="- **Bold lead.** What changed."><?= h($prefill['notes']) ?></textarea></label>
          <label>APK file <small>(uploads to this server; or use a link below)</small><input type="file" name="apk" accept=".apk"></label>
          <label>APK link<input name="apk_url" type="url" placeholder="https://github.com/loco0011/samgeet/releases/download/v1.4.0/Samgeet.apk" value="<?= h($prefill['apk_url']) ?>"></label>
          <label>SHA-256 <small>(worked out for you when you upload)</small><input name="sha256" pattern="[a-fA-F0-9]{64}" value="<?= h($prefill['sha256']) ?>"></label>
          <label class="check"><input type="checkbox" name="required" value="1"> Required update (no “Later” button)</label>
          <label class="check"><input type="checkbox" name="publish" value="1" checked> Publish now</label>
          <button class="primary">Save</button>
        </form>
      </section>
      <section class="card">
        <h2>Versions</h2>
        <table><tr><th>Version</th><th>Build</th><th>Status</th><th></th></tr>
          <?php foreach ($list as $r): ?>
            <tr><td><b><?= h($r['version_name']) ?></b><?= $r['required'] ? ' <span class="tag warn">required</span>' : '' ?>
                <div class="muted small"><a href="<?= h($r['apk_url']) ?>" rel="noreferrer">APK</a><?= $r['size_bytes'] ? ' · ' . round($r['size_bytes'] / 1048576, 1) . ' MB' : '' ?> · <?= ist($r['created_at'], 'd M Y') ?></div></td>
              <td><?= (int)$r['build'] ?></td>
              <td><?= $r['published'] ? '<span class="tag ok">live</span>' : '<span class="tag">draft</span>' ?></td>
              <td class="r nowrap">
                <form method="post" action="?p=releases" class="inline"><?= csrf_field() ?><input type="hidden" name="id" value="<?= (int)$r['id'] ?>"><button name="do" value="release_toggle"><?= $r['published'] ? 'Unpublish' : 'Publish' ?></button></form>
                <form method="post" action="?p=releases" class="inline" data-confirm="Delete this version from the list?"><?= csrf_field() ?><input type="hidden" name="id" value="<?= (int)$r['id'] ?>"><button class="danger" name="do" value="release_delete">Delete</button></form>
              </td></tr>
          <?php endforeach; if (!$list): ?><tr><td colspan="4" class="muted">Nothing published yet.</td></tr><?php endif; ?>
        </table>
      </section>
    </div>
    <?php
}

/// The latest GitHub release as form defaults (version, notes, apk_url, sha256).
function github_latest(): array
{
    $ctx = stream_context_create(['http' => ['header' => "User-Agent: samgeet-admin\r\nAccept: application/vnd.github+json\r\n", 'timeout' => 8]]);
    $raw = @file_get_contents('https://api.github.com/repos/loco0011/samgeet/releases/latest', false, $ctx);
    $j = $raw ? json_decode($raw, true) : null;
    if (!is_array($j)) return [];
    $apk = '';
    foreach ($j['assets'] ?? [] as $a) if (str_ends_with(strtolower($a['name'] ?? ''), '.apk')) $apk = $a['browser_download_url'] ?? '';
    $body = (string)($j['body'] ?? '');
    preg_match('/\b[a-f0-9]{64}\b/i', $body, $m);
    $cut = preg_split('/^#+\s*Install/m', $body)[0];
    return ['version' => ltrim((string)($j['tag_name'] ?? ''), 'vV'), 'notes' => trim(str_ireplace('[required]', '', $cut)), 'apk_url' => $apk, 'sha256' => strtolower($m[0] ?? '')];
}


function notify_stats(PDO $pdo, string $where = '1', array $args = [], string $tail = ''): array
{
    return rows($pdo, "SELECT n.*, COUNT(r.device_id) AS delivered, COALESCE(SUM(r.opened_at IS NOT NULL), 0) AS opened,
                              COALESCE(SUM(r.dismissed_at IS NOT NULL), 0) AS dismissed
                       FROM notifications n LEFT JOIN notification_receipts r ON r.notification_id = n.id
                       WHERE $where GROUP BY n.id $tail", $args);
}

/// How a message looks in the app (the same card as the popup).
function notify_preview(array $n): string
{
    $icon = ['celebrate' => '🎉', 'warning' => '📣'][$n['style']] ?? '🔔';
    $img = $n['image_url'] !== '' ? '<img src="' . h($n['image_url']) . '" alt="" loading="lazy">' : '<span class="pv-ic">' . $icon . '</span>';
    $label = $n['action_label'] !== '' ? $n['action_label'] : (['update' => 'Update now', 'search' => 'Search', 'url' => 'Open'][$n['action']] ?? 'Got it');
    return '<div class="pv" data-style="' . h($n['style']) . '"><div class="pv-head">' . $img . '</div><div class="pv-body"><span class="pv-badge">FROM SAMGEET</span>'
        . '<b>' . h($n['title']) . '</b><p>' . nl2br(h($n['body'])) . '</p><span class="pv-cta">' . h($label) . '</span></div></div>';
}

function notify_actions(array $n, bool $withDelete = false): string
{
    $id = (int)$n['id'];
    $f = fn(string $do, string $label, string $cls = '', string $confirm = '') => '<form method="post" action="?p=notifications" class="inline"'
        . ($confirm ? ' data-confirm="' . h($confirm) . '"' : '') . '>' . csrf_field() . '<input type="hidden" name="id" value="' . $id . '">'
        . '<button class="' . $cls . '" name="do" value="' . $do . '">' . $label . '</button></form>';
    return '<div class="n-actions">'
        . '<a class="btn-link" href="?p=notification&amp;id=' . $id . '">View</a>'
        . $f('notify_resend', 'Send again', 'primary-soft', 'Send this message again to ' . strtolower(NOTIFY_AUDIENCE[$n['audience']] ?? 'everyone') . '? It goes out as a new message; this one stays in the list as it is.')
        . '<a class="btn-link" href="?p=notifications&amp;copy=' . $id . '#notify">Edit as new</a>'
        . $f('notify_toggle', $n['active'] ? 'Stop' : 'Resume')
        . ($withDelete ? $f('notify_delete', 'Delete', 'danger', 'Delete this message and its numbers for good?') : '')
        . '</div>';
}

function page_notifications(PDO $pdo): void
{
    $per = 15;
    $pageNo = max(1, (int)($_GET['n'] ?? 1));
    $total = (int)scalar($pdo, 'SELECT COUNT(*) FROM notifications');
    $list = notify_stats($pdo, '1', [], 'ORDER BY n.id DESC LIMIT ' . $per . ' OFFSET ' . (($pageNo - 1) * $per));
    $copy = null;
    if (isset($_GET['copy'])) $copy = rows($pdo, 'SELECT * FROM notifications WHERE id = ?', [(int)$_GET['copy']])[0] ?? null;
    $v = fn(string $k, string $default = '') => h($copy[$k] ?? $default);
    $sel = fn(string $k, string $opt, string $default) => (($copy[$k] ?? $default) === $opt) ? ' selected' : '';
    ?>
    <h1>Notifications <small><?= num($total) ?> sent</small></h1>
    <p class="muted">Shown as a popup inside the app, a notification on the phone, or both. Phones pick new ones up when the app
      opens and every 30 minutes while it runs. Every message stays in the history with its numbers; sending one again makes a new copy.</p>
    <div class="notify-grid">
      <section class="card" id="notify">
        <h2><?= $copy ? 'Edit as a new message' : 'New message' ?></h2>
        <?php if ($copy): ?><p class="muted small">Copied from “<?= h($copy['title']) ?>”. Sending creates a new message; the original stays as it was. <a href="?p=notifications">Start blank</a></p><?php endif; ?>
        <form method="post" action="?p=notifications" class="form" id="notify-form"><?= csrf_field() ?><input type="hidden" name="do" value="notify_save">
          <label>Title<input name="title" maxlength="120" required placeholder="New in Samgeet: offline downloads" value="<?= $v('title') ?>"></label>
          <label>Message<textarea name="body" rows="4" maxlength="2000" required placeholder="Save songs and listen without internet."><?= $v('body') ?></textarea></label>
          <label>Picture link <small>(optional, https)</small><input name="image_url" type="url" placeholder="https://..." value="<?= $v('image_url') ?>"></label>
          <div class="row2">
            <label>Look<select name="style"><?php foreach (NOTIFY_STYLES as $k => $l): ?><option value="<?= $k ?>"<?= $sel('style', $k, 'info') ?>><?= $l ?></option><?php endforeach; ?></select></label>
            <label>Show as<select name="show_as"><?php foreach (NOTIFY_SHOW as $k => $l): ?><option value="<?= $k ?>"<?= $sel('show_as', $k, 'both') ?>><?= $l ?></option><?php endforeach; ?></select></label>
          </div>
          <div class="row2">
            <label>Button<select name="action" id="action"><?php foreach (NOTIFY_ACTIONS as $k => $l): ?><option value="<?= $k ?>"<?= $sel('action', $k, 'none') ?>><?= $l ?></option><?php endforeach; ?></select></label>
            <label>Button text<input name="action_label" maxlength="40" placeholder="Try it" value="<?= $v('action_label') ?>"></label>
          </div>
          <label id="action-value">Link or search text<input name="action_value" maxlength="400" value="<?= $v('action_value') ?>"></label>
          <div class="row2">
            <label>Who<select name="audience" id="audience"><?php foreach (NOTIFY_AUDIENCE as $k => $l): ?><option value="<?= $k ?>"<?= $sel('audience', $k, 'all') ?>><?= $l ?></option><?php endforeach; ?></select></label>
            <label id="audience-build">Older than build<input name="audience_build" type="number" min="1" value="<?= $v('audience_build') ?>"></label>
          </div>
          <div class="row2">
            <label>Start <small>(IST, empty = now)</small><input name="starts_at" type="datetime-local"></label>
            <label>Stop <small>(IST, optional)</small><input name="ends_at" type="datetime-local"></label>
          </div>
          <div class="muted small">How it looks in the app</div>
          <div id="live-preview"><?= notify_preview(['title' => $copy['title'] ?? 'Title', 'body' => $copy['body'] ?? 'Message', 'image_url' => $copy['image_url'] ?? '', 'style' => $copy['style'] ?? 'info', 'action' => $copy['action'] ?? 'none', 'action_label' => $copy['action_label'] ?? '']) ?></div>
          <button class="primary">Send</button>
        </form>
      </section>

      <section class="card">
        <h2>History</h2>
        <?php if (!$list): ?><p class="muted">Nothing sent yet.</p><?php endif; ?>
        <ul class="n-list">
          <?php foreach ($list as $n): $rate = $n['delivered'] ? round(100 * $n['opened'] / $n['delivered']) : null; ?>
            <li class="n-item">
              <a class="n-thumb" href="?p=notification&amp;id=<?= (int)$n['id'] ?>" data-style="<?= h($n['style']) ?>"><?php if ($n['image_url'] !== ''): ?><img src="<?= h($n['image_url']) ?>" alt="" loading="lazy"><?php else: ?><span><?= ['celebrate' => '🎉', 'warning' => '📣'][$n['style']] ?? '🔔' ?></span><?php endif; ?></a>
              <div class="n-main">
                <div class="n-top"><a class="n-title" href="?p=notification&amp;id=<?= (int)$n['id'] ?>"><?= h($n['title']) ?></a>
                  <?= $n['active'] ? '<span class="tag ok">live</span>' : '<span class="tag">stopped</span>' ?></div>
                <div class="n-text"><?= h($n['body']) ?></div>
                <div class="n-meta"><?= ist($n['starts_at'], 'd M Y, H:i') ?> · <?= h(NOTIFY_AUDIENCE[$n['audience']] ?? $n['audience']) ?> · <?= h(NOTIFY_SHOW[$n['show_as']] ?? $n['show_as']) ?></div>
                <div class="n-stats"><span><b><?= num($n['delivered']) ?></b> reached</span><span><b><?= num($n['opened']) ?></b> opened<?= $rate !== null ? ' (' . $rate . '%)' : '' ?></span><span><b><?= num($n['dismissed']) ?></b> closed</span></div>
                <?= notify_actions($n) ?>
              </div>
            </li>
          <?php endforeach; ?>
        </ul>
        <?php if ($total > $per): ?><div class="pager">
          <?php if ($pageNo > 1): ?><a href="?p=notifications&amp;n=<?= $pageNo - 1 ?>">← Newer</a><?php else: ?><span></span><?php endif; ?>
          <span class="muted small">Page <?= $pageNo ?> of <?= (int)ceil($total / $per) ?></span>
          <?php if ($pageNo * $per < $total): ?><a href="?p=notifications&amp;n=<?= $pageNo + 1 ?>">Older →</a><?php else: ?><span></span><?php endif; ?>
        </div><?php endif; ?>
      </section>
    </div>
    <script nonce="<?= h($GLOBALS['nonce']) ?>">
      (function () {
        const f = document.getElementById('notify-form'), $ = id => document.getElementById(id);
        const esc = s => s.replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
        function sync() {
          const a = f.action.value;
          $('action-value').style.display = a === 'url' || a === 'search' ? '' : 'none';
          $('audience-build').style.display = f.audience.value === 'below_build' ? '' : 'none';
          const pv = $('live-preview').querySelector('.pv');
          pv.dataset.style = f.style.value;
          pv.querySelector('b').textContent = f.title.value || 'Title';
          pv.querySelector('p').innerHTML = esc(f.body.value || 'Message').replace(/\n/g, '<br>');
          pv.querySelector('.pv-cta').textContent = f.action_label.value || ({ update: 'Update now', search: 'Search', url: 'Open' }[a] || 'Got it');
          const head = pv.querySelector('.pv-head'), img = f.image_url.value.trim();
          head.innerHTML = /^https:\/\//.test(img) ? '<img alt="" src="' + esc(img) + '">' : '<span class="pv-ic">' + ({ celebrate: '🎉', warning: '📣' }[f.style.value] || '🔔') + '</span>';
        }
        f.addEventListener('input', sync); f.addEventListener('change', sync); sync();
      })();
    </script>
    <?php
}

function page_notification(PDO $pdo, int $id): void
{
    $n = notify_stats($pdo, 'n.id = ?', [$id])[0] ?? null;
    if (!$n) {
        echo '<p><a href="?p=notifications">← Notifications</a></p><h1>Not found</h1>';
        return;
    }
    $copies = rows($pdo, 'SELECT id, starts_at FROM notifications WHERE id <> ? AND title = ? AND body = ? ORDER BY id DESC', [$id, $n['title'], $n['body']]);
    $d = (int)$n['delivered'];
    $silent = max(0, $d - (int)$n['opened'] - (int)$n['dismissed']);
    $bar = fn($x) => $d ? round(100 * $x / $d) : 0;
    $by = scalar($pdo, 'SELECT email FROM admins WHERE id = ?', [(int)$n['created_by']]);
    ?>
    <p><a href="?p=notifications">← Notifications</a></p>
    <h1><?= h($n['title']) ?> <?= $n['active'] ? '<span class="tag ok">live</span>' : '<span class="tag">stopped</span>' ?></h1>
    <div class="grid2">
      <section class="card"><h2>How it looks in the app</h2><?= notify_preview($n) ?></section>
      <section class="card">
        <h2>How it did</h2>
        <div class="funnel">
          <div><span>Reached phones</span><b><?= num($d) ?></b><i style="width:100%"></i></div>
          <div><span>Opened</span><b><?= num($n['opened']) ?> <small><?= $bar($n['opened']) ?>%</small></b><i style="width:<?= $bar($n['opened']) ?>%"></i></div>
          <div><span>Closed</span><b><?= num($n['dismissed']) ?> <small><?= $bar($n['dismissed']) ?>%</small></b><i class="c" style="width:<?= $bar($n['dismissed']) ?>%"></i></div>
          <div><span>No answer yet</span><b><?= num($silent) ?> <small><?= $bar($silent) ?>%</small></b><i class="s" style="width:<?= $bar($silent) ?>%"></i></div>
        </div>
        <table style="margin-top:16px">
          <tr><td class="muted">Sent</td><td><?= ist($n['starts_at']) ?><?= $n['ends_at'] ? ' → ' . ist($n['ends_at']) : '' ?></td></tr>
          <tr><td class="muted">To</td><td><?= h(NOTIFY_AUDIENCE[$n['audience']] ?? $n['audience']) ?><?= $n['audience_build'] ? ' (older than build ' . (int)$n['audience_build'] . ')' : '' ?></td></tr>
          <tr><td class="muted">Shown as</td><td><?= h(NOTIFY_SHOW[$n['show_as']] ?? $n['show_as']) ?></td></tr>
          <tr><td class="muted">Button</td><td><?= h(NOTIFY_ACTIONS[$n['action']] ?? $n['action']) ?><?= $n['action_value'] !== '' ? ': ' . h($n['action_value']) : '' ?></td></tr>
          <tr><td class="muted">Sent by</td><td><?= h($by ?: '—') ?></td></tr>
          <?php if ($copies): ?><tr><td class="muted">Also sent</td><td><?php foreach ($copies as $i => $c): ?><?= $i ? ', ' : '' ?><a href="?p=notification&amp;id=<?= (int)$c['id'] ?>"><?= ist($c['starts_at'], 'd M, H:i') ?></a><?php endforeach; ?></td></tr><?php endif; ?>
        </table>
        <?= notify_actions($n, true) ?>
      </section>
    </div>
    <?php
}

function page_export(): void
{
    $types = ['play_start', 'play_end', 'like', 'unlike', 'download', 'share_song', 'share_playlist', 'search', 'playlist_create', 'playlist_add', 'app_open', 'sign_in', 'player_style', 'notification_open'];
    ?>
    <h1>Export data</h1>
    <section class="card narrow">
      <p class="muted">Download every event in a date range as CSV (opens in Excel or Google Sheets), joined with the account,
        phone and song details. Leave all types unticked for everything.</p>
      <form method="get" class="form"><input type="hidden" name="p" value="export">
        <div class="row2"><label>From<input type="date" name="from" required value="<?= h(date('Y-m-d', time() - 7 * 86400)) ?>"></label>
          <label>To<input type="date" name="to" required value="<?= h(date('Y-m-d')) ?>"></label></div>
        <div class="checks"><?php foreach ($types as $t): ?><label class="check"><input type="checkbox" name="types[]" value="<?= h($t) ?>"> <?= h($t) ?></label><?php endforeach; ?></div>
        <button class="primary">Download CSV</button>
      </form>
    </section>
    <?php
}

function page_account(array $admin): void
{
    ?>
    <h1>Your admin account</h1>
    <section class="card narrow">
      <p>Signed in as <b><?= h($admin['email']) ?></b>.</p>
      <form method="post" action="?p=account" class="form"><?= csrf_field() ?><input type="hidden" name="do" value="password">
        <label>Current password<input type="password" name="current" required autocomplete="current-password"></label>
        <label>New password <small>(12+ characters)</small><input type="password" name="new" required minlength="12" autocomplete="new-password"></label>
        <button class="primary">Change password</button>
      </form>
    </section>
    <?php
}

// ================================================================ chrome

function styles(): string
{
    return <<<'CSS'
:root{--bg:#04040a;--surface:#0f0f1a;--surface2:#181829;--line:rgba(255,255,255,.09);--ink:#f1f1f7;--muted:#9ea1be;--guest:#5b6b9a;
--accent:#d0284f;--accent2:#e0823f;--ok:#3fb27f;--warn:#e0a33f;--danger:#e2475b;color-scheme:dark}
*{box-sizing:border-box}html,body{margin:0}
body{background:var(--bg);color:var(--ink);font:14px/1.5 'Plus Jakarta Sans',system-ui,sans-serif;
background-image:radial-gradient(900px 500px at 85% -10%,rgba(208,40,79,.18),transparent 60%),radial-gradient(700px 400px at -10% 10%,rgba(181,83,26,.12),transparent 60%)}
a{color:inherit}h1{font:800 26px/1.2 Sora,system-ui,sans-serif;letter-spacing:-.5px;margin:6px 0 18px}h1 small{color:var(--muted);font-size:15px;font-weight:600}
h2{font:700 15px Sora,system-ui,sans-serif;margin:0 0 12px}h2 small{color:var(--muted);font-weight:500;font-size:12px}
.top{display:flex;align-items:center;gap:18px;padding:14px 24px;border-bottom:1px solid var(--line);position:sticky;top:0;background:color-mix(in srgb,var(--bg) 85%,transparent);backdrop-filter:blur(12px);z-index:5;flex-wrap:wrap}
.brand{font:800 18px Sora,sans-serif;display:flex;align-items:center;gap:10px;text-decoration:none}
.brand i{width:28px;height:28px;border-radius:9px;background:linear-gradient(135deg,#7a1232,#d0284f 55%,#e0823f);display:grid;place-items:center;font-style:normal;color:#fff;font-size:15px}
nav{display:flex;gap:4px;flex-wrap:wrap;flex:1}nav a{padding:7px 12px;border-radius:10px;text-decoration:none;color:var(--muted);font-weight:600}
nav a.on,nav a:hover{background:var(--surface2);color:var(--ink)}
main{max-width:1240px;margin:0 auto;padding:22px 24px 60px}
.card{background:var(--surface);border:1px solid var(--line);border-radius:18px;padding:18px;margin-bottom:18px;min-width:0}
.card.narrow{max-width:620px}
.grid2{display:grid;grid-template-columns:1fr 1fr;gap:18px}.grid3{display:grid;grid-template-columns:repeat(3,1fr);gap:18px}
.grid2 .wide{grid-column:1/-1}
.head-row{display:flex;align-items:flex-end;justify-content:space-between;gap:14px;flex-wrap:wrap}.head-row h1{margin:6px 0 4px}
.sub{color:var(--muted);margin:0;font-size:13px}
.ranges{display:flex;gap:4px;background:var(--surface);border:1px solid var(--line);border-radius:12px;padding:4px;flex:none}.ranges a{padding:6px 12px;border-radius:9px;text-decoration:none;color:var(--muted);font-weight:700;font-size:13px}.ranges a:hover{color:var(--ink)}.ranges a.on{background:var(--accent);color:#fff}
.hero{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:14px;margin:20px 0 18px}
.hero-card{position:relative;overflow:hidden;background:var(--surface);border:1px solid var(--line);border-radius:20px;padding:18px 18px 54px}
.hero-top{display:flex;justify-content:space-between;align-items:center;gap:8px}.hero-l{color:var(--muted);font-weight:600;font-size:13px}
.hero-v{font:800 34px/1.1 Sora,sans-serif;margin:10px 0 4px;letter-spacing:-1px}.hero-s{color:var(--muted);font-size:12.5px}
.spark{position:absolute;left:0;right:0;bottom:0;width:100%;height:46px}
.chg{font-size:11.5px;font-weight:800;padding:2px 8px;border-radius:20px;background:var(--surface2);color:var(--muted);white-space:nowrap}.chg.up{color:var(--ok);background:rgba(63,178,127,.12)}.chg.down{color:var(--danger);background:rgba(226,71,91,.12)}
.who-head{display:flex;justify-content:space-between;align-items:baseline;gap:10px;flex-wrap:wrap}.who-head h2{margin:0}
.split{display:flex;height:12px;border-radius:8px;overflow:hidden;background:var(--guest);margin:14px 0 20px}.split .s-m{background:var(--accent)}.split .s-g{flex:1}
.who-grid{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:28px}
.dot{display:inline-block;width:10px;height:10px;border-radius:50%;margin-right:8px}.dot.m{background:var(--accent)}.dot.g{background:var(--guest)}.dot.c{background:var(--ok)}
dl{display:grid;grid-template-columns:1fr auto;gap:9px 12px;margin:12px 0 0}dt{color:var(--muted)}dd{margin:0;font-weight:700;text-align:right;font-variant-numeric:tabular-nums}
.chart{position:relative;height:260px}.chart.tall{height:300px}
.cols{display:grid;grid-template-columns:minmax(0,1fr) minmax(0,1fr);gap:18px;margin-bottom:18px}.cols.three{grid-template-columns:repeat(3,minmax(0,1fr))}.cols>.card{margin:0}.span2{grid-column:span 2}
ol.songs{list-style:none;margin:0;padding:0}ol.songs li{display:flex;align-items:center;gap:12px;padding:8px 0;border-bottom:1px solid var(--line)}ol.songs li:last-child{border:0}
.rank{width:18px;flex:none;color:var(--muted);font-weight:700;text-align:right}
ol.songs img,.noimg{width:40px;height:40px;border-radius:10px;object-fit:cover;flex:none}.noimg{display:grid;place-items:center;background:var(--surface2);color:var(--muted)}
.meta{flex:1;min-width:0;display:flex;flex-direction:column}.meta b,.meta span{white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
ol.songs .v{text-align:right;font-weight:800;display:flex;flex-direction:column;font-variant-numeric:tabular-nums}ol.songs .v small{color:var(--muted);font-weight:500;font-size:11px}
ol.bars{list-style:none;margin:0;padding:0;display:grid;gap:5px}ol.bars li{position:relative;display:flex;justify-content:space-between;gap:10px;padding:7px 10px;border-radius:9px;overflow:hidden}
.bars .b{position:absolute;left:0;top:0;bottom:0;background:var(--accent);opacity:.18;border-radius:9px}.bars .l{position:relative;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}.bars .v{position:relative;font-weight:700;font-variant-numeric:tabular-nums}
.empty{color:var(--muted);margin:0}
.glance{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:32px}.glance h3{margin:0;font:700 12px Sora,sans-serif;letter-spacing:1.2px;text-transform:uppercase;color:var(--muted)}
details.more>summary{cursor:pointer;list-style:none;padding:14px 18px;background:var(--surface);border:1px solid var(--line);border-radius:16px;font-weight:700;margin-bottom:18px}
details.more>summary::-webkit-details-marker{display:none}details.more>summary::before{content:'▸  ';color:var(--accent)}details.more[open]>summary::before{content:'▾  '}
ul.plain{list-style:none;margin:0;padding:0}ul.plain li{display:flex;justify-content:space-between;gap:10px;padding:7px 0;border-bottom:1px solid var(--line)}ul.plain li:last-child{border:0}
@media (max-width:1100px){.hero{grid-template-columns:repeat(2,minmax(0,1fr))}.glance{grid-template-columns:repeat(2,minmax(0,1fr))}.cols.three{grid-template-columns:repeat(2,minmax(0,1fr))}}
@media (max-width:700px){.hero-v{font-size:26px}.who-grid,.cols,.cols.three{grid-template-columns:minmax(0,1fr)}.span2{grid-column:auto}.glance{gap:22px}}
table{width:100%;border-collapse:collapse}th{text-align:left;color:var(--muted);font-weight:600;font-size:12px}
td,th{padding:7px 6px;border-bottom:1px solid var(--line);vertical-align:middle}tr:last-child td{border-bottom:0}
.r{text-align:right}.nowrap{white-space:nowrap}.muted{color:var(--muted)}.small{font-size:12px}
.song{display:flex;gap:10px;align-items:center}.song img{width:36px;height:36px;border-radius:8px;object-fit:cover}
.tag{display:inline-block;padding:1px 8px;border-radius:20px;font-size:11px;font-weight:700;background:var(--surface2);color:var(--muted)}
.tag.ok{background:rgba(63,178,127,.15);color:var(--ok)}.tag.warn{background:rgba(224,163,63,.15);color:var(--warn)}
.form{display:grid;gap:12px}.form label{display:grid;gap:5px;font-weight:600;font-size:13px}.form label small{color:var(--muted);font-weight:500}
.row2{display:grid;grid-template-columns:1fr 1fr;gap:12px}
input,textarea,select{font:inherit;color:var(--ink);background:var(--surface2);border:1px solid var(--line);border-radius:10px;padding:9px 11px;width:100%}
input:focus,textarea:focus,select:focus{outline:2px solid var(--accent);outline-offset:1px}
.check{display:flex!important;grid-template-columns:none;align-items:center;gap:8px;font-weight:500!important}.check input{width:auto}
.checks{display:flex;flex-wrap:wrap;gap:6px 16px}
button{font:inherit;font-weight:700;cursor:pointer;border-radius:10px;padding:8px 14px;border:1px solid var(--line);background:var(--surface2);color:var(--ink)}
button:hover{border-color:var(--muted)}button.primary{background:linear-gradient(135deg,#a61f2e,#d0284f 60%,#e0823f);border:0;color:#fff;padding:11px 18px}
button.danger{color:var(--danger)}form.inline{display:inline}.actions{display:flex;gap:8px;flex-wrap:wrap;margin-top:14px}.actions form{margin:0}
.flash{background:rgba(63,178,127,.12);border:1px solid rgba(63,178,127,.35);padding:10px 14px;border-radius:12px;margin-bottom:18px}
.search{display:flex;gap:8px;margin-bottom:14px;max-width:520px}.pager{display:flex;justify-content:space-between;margin-top:12px}
.notify-grid{display:grid;grid-template-columns:minmax(0,5fr) minmax(0,6fr);gap:18px;align-items:start}
.pv{max-width:360px;border-radius:24px;overflow:hidden;background:var(--surface2);border:1px solid var(--line);margin:6px 0 4px}
.pv-head{height:150px;display:grid;place-items:center;background:linear-gradient(135deg,#7a1232,#d0284f 60%,#e0823f)}
.pv[data-style="celebrate"] .pv-head{background:linear-gradient(135deg,#b5531a,#d0284f 60%,#7a1232)}.pv[data-style="warning"] .pv-head{background:linear-gradient(135deg,#8a5a12,#e0a33f 60%,#7a1232)}
.pv-head img{width:100%;height:100%;object-fit:cover}.pv-ic{width:64px;height:64px;border-radius:50%;display:grid;place-items:center;font-size:30px;background:rgba(255,255,255,.18);border:1px solid rgba(255,255,255,.35)}
.pv-body{padding:16px 18px 18px;display:grid;gap:6px}.pv-body b{font:800 17px Sora,sans-serif;color:#fff}.pv-body p{margin:0;color:#d9d9e6;font-size:13.5px;line-height:1.5}
.pv-badge{justify-self:start;font-size:10.5px;font-weight:800;letter-spacing:.8px;padding:2px 9px;border-radius:20px;background:rgba(208,40,79,.18);color:#ff8aa5}
.pv-cta{justify-self:center;margin-top:8px;padding:9px 22px;border-radius:30px;font-weight:800;font-size:13px;background:linear-gradient(135deg,#a61f2e,#d0284f 60%,#e0823f);color:#fff}
.n-list{list-style:none;margin:0;padding:0}.n-item{display:flex;gap:14px;padding:14px 0;border-bottom:1px solid var(--line)}.n-item:last-child{border:0}
.n-thumb{flex:none;width:64px;height:64px;border-radius:14px;overflow:hidden;display:grid;place-items:center;font-size:26px;background:linear-gradient(135deg,#7a1232,#d0284f 60%,#e0823f);text-decoration:none}
.n-thumb[data-style="celebrate"]{background:linear-gradient(135deg,#b5531a,#d0284f)}.n-thumb[data-style="warning"]{background:linear-gradient(135deg,#8a5a12,#e0a33f)}.n-thumb img{width:100%;height:100%;object-fit:cover}
.n-main{flex:1;min-width:0;display:grid;gap:4px}.n-top{display:flex;align-items:center;gap:8px}.n-title{font-weight:800;text-decoration:none;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.n-text{color:#c9c9d8;font-size:13px;display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical;overflow:hidden}
.n-meta{color:var(--muted);font-size:12px}.n-stats{display:flex;gap:14px;font-size:12.5px;color:var(--muted);flex-wrap:wrap}.n-stats b{color:var(--ink)}
.n-actions{display:flex;flex-wrap:wrap;gap:6px;margin-top:6px;align-items:center}.n-actions button,.btn-link{font-size:12.5px;padding:6px 11px;border-radius:9px}
.btn-link{display:inline-block;text-decoration:none;border:1px solid var(--line);background:var(--surface2);font-weight:700}.btn-link:hover{border-color:var(--muted)}
button.primary-soft{background:rgba(208,40,79,.18);border-color:rgba(255,92,127,.45);color:#ffc2cf}
.funnel{display:grid;gap:12px}.funnel div{display:grid;grid-template-columns:1fr auto;gap:4px 12px}.funnel span{color:var(--muted)}.funnel small{color:var(--muted);font-weight:500}
.funnel i{grid-column:1/-1;height:8px;border-radius:6px;background:linear-gradient(90deg,#d0284f,#e0823f)}.funnel i.c{background:#5b6b9a}.funnel i.s{background:rgba(255,255,255,.18)}
@media (max-width:900px){.notify-grid{grid-template-columns:minmax(0,1fr)}}
.preview{display:flex;gap:12px;padding:14px;border-radius:16px;background:linear-gradient(135deg,rgba(122,18,50,.55),rgba(24,24,41,.9));border:1px solid var(--line)}
.preview[data-style="celebrate"]{background:linear-gradient(135deg,rgba(181,83,26,.6),rgba(208,40,79,.45))}
.preview[data-style="warning"]{background:linear-gradient(135deg,rgba(224,163,63,.35),rgba(24,24,41,.9))}
.preview p{margin:4px 0 8px;color:#e6e4ee}.preview b{color:#fff}.pv-icon{width:38px;height:38px;flex:none;border-radius:12px;background:rgba(255,255,255,.15);display:grid;place-items:center;color:#fff}
.pv-btn{display:inline-block;background:#fff;color:#15131c;border-radius:20px;padding:4px 12px;font-weight:700;font-size:12px}
.login{min-height:100vh;display:grid;place-items:center;padding:16px}.login .card{width:100%;max-width:380px;padding:28px}
.err{color:var(--danger);font-weight:600}
.pw{position:relative;display:block}.pw input{padding-right:70px}.pw button{position:absolute;right:6px;top:50%;transform:translateY(-50%);padding:5px 10px;font-size:12px;border-radius:8px}
@media (max-width:900px){body{overflow-x:hidden}main{max-width:100vw}.card{overflow-x:auto}.grid2>*,.grid3>*{min-width:0}.head-row>*{min-width:0}.ranges{overflow-x:auto;max-width:100%}.grid2,.grid3{grid-template-columns:1fr}.row2{grid-template-columns:1fr}main{padding:16px}.top{padding:12px 16px}}
CSS;
}

function head(string $title): void
{
    ?><!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="robots" content="noindex,nofollow"><title><?= h($title) ?></title>
<link rel="preconnect" href="https://fonts.googleapis.com"><link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@400;500;600;700;800&amp;family=Sora:wght@700;800&amp;display=swap" rel="stylesheet">
<style><?= styles() ?></style></head><?php
}

function render_login(?string $error): void
{
    head('Samgeet admin');
    ?><body><div class="login"><div class="card">
      <div class="brand" style="margin-bottom:18px"><i>♪</i> Samgeet admin</div>
      <form method="post" action="?p=login" class="form"><?= csrf_field() ?>
        <label>Email<input type="email" name="email" required autocomplete="username" autofocus></label>
        <label>Password<input type="password" name="password" required autocomplete="current-password"></label>
        <?php if ($error): ?><div class="err"><?= h($error) ?></div><?php endif; ?>
        <button class="primary">Sign in</button>
      </form></div></div><?php password_toggles(); ?></body></html><?php
}

/// A Show / Hide button inside every password box.
function password_toggles(): void
{
    global $nonce;
    ?><script nonce="<?= h($nonce) ?>">
      document.querySelectorAll('input[type=password]').forEach(input => {
        const box = document.createElement('span');
        box.className = 'pw';
        input.replaceWith(box);
        box.appendChild(input);
        const b = document.createElement('button');
        b.type = 'button';
        b.textContent = 'Show';
        b.setAttribute('aria-label', 'Show password');
        b.addEventListener('click', () => {
          const show = input.type === 'password';
          input.type = show ? 'text' : 'password';
          b.textContent = show ? 'Hide' : 'Show';
          b.setAttribute('aria-label', show ? 'Hide password' : 'Show password');
          input.focus();
        });
        box.appendChild(b);
      });
    </script><?php
}

function render_layout(string $page, array $admin, ?string $flash, string $content): void
{
    global $nonce;
    head('Samgeet admin');
    $nav = ['dashboard' => 'Overview', 'users' => 'Accounts', 'releases' => 'App updates', 'notifications' => 'Notifications', 'export' => 'Export', 'account' => 'My account'];
    $active = $page === 'user' ? 'users' : ($page === 'notification' ? 'notifications' : $page);
    ?><body>
    <div class="top"><a class="brand" href="?p=dashboard"><i>♪</i> Samgeet</a>
      <nav><?php foreach ($nav as $k => $label): ?><a class="<?= $k === $active ? 'on' : '' ?>" href="?p=<?= $k ?>"><?= $label ?></a><?php endforeach; ?></nav>
      <form method="post" action="?p=logout" class="inline"><?= csrf_field() ?><button>Sign out</button></form></div>
    <main><?php if ($flash): ?><div class="flash"><?= h($flash) ?></div><?php endif; ?><?= $content ?></main>
    <script nonce="<?= h($nonce) ?>">
      document.querySelectorAll('form[data-confirm]').forEach(f => f.addEventListener('submit', e => { if (!confirm(f.dataset.confirm)) e.preventDefault(); }));
    </script><?php password_toggles(); ?></body></html><?php
}
