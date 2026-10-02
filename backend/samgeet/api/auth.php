<?php
// Samgeet accounts. Every request is signed by the app (see lib/bootstrap.php).
//   {"action":"check_email", "email"}                  -> {"exists": bool}
//   {"action":"login", "email", "key", "device":{...}}  -> {"token", "user":{...}}
//        404 no_account, 403 wrong_password, 403 blocked
//   {"action":"register", "email", "key", "name", "device":{...}} -> {"token", "user"}   409 exists
//   {"action":"profile", name, avatar, languages, moods, artists, player_style}  (signed in)
//   {"action":"logout"}                                 (signed in: ends this phone's session)
//   {"action":"delete_account"}                         (signed in: removes the account and its data)
// The account key is derived on the phone from email + password (PBKDF2); the password never comes
// here and only a hash of the key is stored. Accounts made with app 1.3.x (the `backups` table)
// move into `users` + `libraries` the first time they sign in here.

declare(strict_types=1);
require __DIR__ . '/../lib/bootstrap.php';

[$in, $install] = sg_app_request('auth');
$pdo = sg_db();
$action = $in['action'] ?? '';

const PLAYER_STYLES = ['disc', 'cover', 'immersive', 'minimal'];

function email_of(array $in): string
{
    $e = strtolower(trim((string)($in['email'] ?? '')));
    if (strlen($e) > 190 || !filter_var($e, FILTER_VALIDATE_EMAIL)) sg_respond(422, ['error' => 'bad_email']);
    return $e;
}

function key_hash_of(array $in): string
{
    $k = (string)($in['key'] ?? '');
    if (!preg_match('/^[0-9A-HJKMNP-TV-Z]{12}$/', $k)) sg_respond(422, ['error' => 'bad_key']);
    return hash('sha256', 'samgeet-backup:' . $k); // same as app 1.3.x, so old accounts match
}

function list_of($v, int $maxItems, int $maxLen): array
{
    $out = [];
    foreach (is_array($v) ? $v : [] as $item) {
        $item = sg_text($item, $maxLen + 1);
        if ($item === '' || mb_strlen($item) > $maxLen || in_array($item, $out, true)) continue;
        $out[] = $item;
        if (count($out) >= $maxItems) break;
    }
    return $out;
}

function user_json(PDO $pdo, int $id): array
{
    $q = $pdo->prepare('SELECT u.id, u.email, u.name, u.avatar, u.player_style, UNIX_TIMESTAMP(u.created_at) AS created,
                               l.rev FROM users u LEFT JOIN libraries l ON l.user_id = u.id WHERE u.id = ?');
    $q->execute([$id]);
    $u = $q->fetch(PDO::FETCH_ASSOC);
    return [
        'id' => (int)$u['id'],
        'email' => $u['email'],
        'name' => $u['name'],
        'avatar' => $u['avatar'],
        'player_style' => $u['player_style'],
        'created_at' => (int)$u['created'],
        'library_rev' => $u['rev'] === null ? null : (int)$u['rev'],
    ];
}

function save_tastes(PDO $pdo, int $userId, array $in): void
{
    $pdo->prepare('DELETE FROM user_tastes WHERE user_id = ?')->execute([$userId]);
    $ins = $pdo->prepare('INSERT IGNORE INTO user_tastes (user_id, kind, value) VALUES (?, ?, ?)');
    foreach (['language' => 'languages', 'mood' => 'moods', 'artist' => 'artists'] as $kind => $field) {
        foreach (list_of($in[$field] ?? [], 80, 80) as $v) $ins->execute([$userId, $kind, $v]);
    }
}

/// An account from app 1.3.x with this key: copy it into the new tables. Returns the new user id.
function migrate_legacy(PDO $pdo, string $keyHash, string $email, string $emailHash): ?int
{
    try {
        $q = $pdo->prepare('SELECT data, rev FROM backups WHERE code_hash = ?');
        $q->execute([$keyHash]);
        $old = $q->fetch(PDO::FETCH_ASSOC);
    } catch (Throwable $e) {
        return null; // no legacy table on this server
    }
    if (!$old) return null;
    $name = '';
    $avatar = '';
    try {
        $p = $pdo->prepare('SELECT name, avatar FROM profiles WHERE email = ? ORDER BY updated_at DESC LIMIT 1');
        $p->execute([$email]);
        if ($row = $p->fetch(PDO::FETCH_ASSOC)) {
            $name = (string)$row['name'];
            $avatar = (string)$row['avatar'];
        }
    } catch (Throwable $e) {
    }
    $pdo->beginTransaction();
    $pdo->prepare('INSERT INTO users (email, email_hash, key_hash, name, avatar) VALUES (?, ?, ?, ?, ?)')
        ->execute([$email, $emailHash, $keyHash, $name, $avatar]);
    $id = (int)$pdo->lastInsertId();
    $pdo->prepare('INSERT INTO libraries (user_id, data, rev) VALUES (?, ?, ?)')->execute([$id, $old['data'], (int)$old['rev']]);
    $pdo->commit();
    return $id;
}

function email_taken(PDO $pdo, string $emailHash): bool
{
    $q = $pdo->prepare('SELECT 1 FROM users WHERE email_hash = ?');
    $q->execute([$emailHash]);
    if ($q->fetchColumn()) return true;
    try {
        $q = $pdo->prepare('SELECT 1 FROM backups WHERE email_hash = ? LIMIT 1');
        $q->execute([$emailHash]);
        return (bool)$q->fetchColumn();
    } catch (Throwable $e) {
        return false;
    }
}

sg_guard('auth', function () use ($pdo, $in, $install, $action) {
    $deviceInfo = is_array($in['device'] ?? null) ? $in['device'] : null;
    $deviceId = sg_device($pdo, $install, $deviceInfo);

    if ($action === 'check_email') {
        $email = email_of($in);
        sg_respond(200, ['exists' => email_taken($pdo, hash('sha256', 'samgeet-email:' . $email))]);
    }

    if ($action === 'login' || $action === 'register') {
        // Password guessing: at most 20 sign-in tries per phone per 10 minutes (on top of the API limit).
        sg_rate($pdo, 'login:' . $install, 20);
        $email = email_of($in);
        $emailHash = hash('sha256', 'samgeet-email:' . $email);
        $keyHash = key_hash_of($in);

        $q = $pdo->prepare('SELECT id, status FROM users WHERE key_hash = ?');
        $q->execute([$keyHash]);
        $row = $q->fetch(PDO::FETCH_ASSOC);
        $userId = $row ? (int)$row['id'] : migrate_legacy($pdo, $keyHash, $email, $emailHash);
        if ($row && $row['status'] !== 'active') sg_respond(403, ['error' => 'blocked']);

        if ($userId === null) {
            if (email_taken($pdo, $emailHash)) sg_respond(403, ['error' => 'wrong_password']);
            if ($action === 'login') sg_respond(404, ['error' => 'no_account']);
            $name = sg_text($in['name'] ?? '', 80);
            if ($name === '') sg_respond(422, ['error' => 'bad_name']);
            $pdo->prepare('INSERT INTO users (email, email_hash, key_hash, name) VALUES (?, ?, ?, ?)')
                ->execute([$email, $emailHash, $keyHash, $name]);
            $userId = (int)$pdo->lastInsertId();
        }
        // (Registering with the key of an existing account is just signing in.)
        $token = sg_new_session($pdo, $userId, $deviceId);
        sg_respond(200, ['token' => $token, 'user' => user_json($pdo, $userId)]);
    }

    [$userId, $sessionId] = sg_user($pdo, $deviceId, true);

    if ($action === 'logout') {
        $pdo->prepare('UPDATE sessions SET revoked_at = UTC_TIMESTAMP() WHERE id = ?')->execute([$sessionId]);
        sg_respond(200, ['ok' => true]);
    }

    if ($action === 'me') {
        sg_respond(200, ['user' => user_json($pdo, $userId)]);
    }

    if ($action === 'profile') {
        $sets = [];
        $args = [];
        if (array_key_exists('name', $in)) {
            $name = sg_text($in['name'], 80);
            if ($name === '') sg_respond(422, ['error' => 'bad_name']);
            $sets[] = 'name = ?';
            $args[] = $name;
        }
        if (array_key_exists('avatar', $in)) {
            $avatar = sg_text($in['avatar'], 40);
            if (strpos($avatar, 'photo:') === 0) $avatar = ''; // photos stay on the phone
            $sets[] = 'avatar = ?';
            $args[] = $avatar;
        }
        if (array_key_exists('player_style', $in)) {
            if (!in_array($in['player_style'], PLAYER_STYLES, true)) sg_respond(422, ['error' => 'bad_style']);
            $sets[] = 'player_style = ?';
            $args[] = $in['player_style'];
        }
        $pdo->beginTransaction();
        if ($sets) {
            $args[] = $userId;
            $pdo->prepare('UPDATE users SET ' . implode(', ', $sets) . ' WHERE id = ?')->execute($args);
        }
        if (isset($in['languages']) || isset($in['moods']) || isset($in['artists'])) save_tastes($pdo, $userId, $in);
        $pdo->commit();
        sg_respond(200, ['user' => user_json($pdo, $userId)]);
    }

    if ($action === 'delete_account') {
        // Sessions, library, tastes and listening history go with it (ON DELETE CASCADE). The 1.3.x copy
        // goes too, or the next sign-in would bring the account back.
        $q = $pdo->prepare('SELECT key_hash FROM users WHERE id = ?');
        $q->execute([$userId]);
        $keyHash = (string)$q->fetchColumn();
        $pdo->prepare('DELETE FROM users WHERE id = ?')->execute([$userId]);
        try {
            $pdo->prepare('DELETE FROM backups WHERE code_hash = ?')->execute([$keyHash]);
        } catch (Throwable $e) {
        }
        sg_respond(200, ['ok' => true]);
    }

    sg_respond(400, ['error' => 'bad_action']);
});
