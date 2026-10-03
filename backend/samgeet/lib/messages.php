<?php
// Sending messages, shared by the web admin panel and the admin tools inside the app, so both
// check the same things and target the same phones.
//
// A message goes to an audience (everyone, signed-in listeners, guests, or apps older than a build).
// A follow-up is a fresh copy of an earlier message that only goes to part of that message's
// audience (needs the columns from migrations/2026-10-03-messages.sql):
//   missed    phones that never got the original (installed later, or haven't opened the app since)
//   unopened  phones that got it but didn't open it (closed it, or never answered)
// For update reminders there's a better follow-up: "outdated", a new copy for every app that is still
// older than the newest published version, worked out when it's sent.

declare(strict_types=1);

const RP_FOLLOW_UPS = ['all' => 'Everyone it was meant for', 'missed' => 'Only phones that never got it', 'unopened' => 'Only phones that got it but didn\'t open it', 'outdated' => 'Only phones still on an old version'];

/// Checks and stores a new message. [m]: title, body, image_url, style, action, action_value,
/// action_label, show_as, audience (all | signed_in | guests | outdated | below_build), audience_build,
/// starts_at, ends_at (UTC or null). Returns [new id, null] or [null, error code].
function rp_send(PDO $pdo, array $m, int $adminId, string $source): array
{
    $title = trim((string)($m['title'] ?? ''));
    $body = trim(str_replace("\r", '', (string)($m['body'] ?? '')));
    if ($title === '' || mb_strlen($title) > 120 || $body === '' || mb_strlen($body) > 2000) return [null, 'bad_text'];
    $pick = fn(string $k, array $allowed) => in_array($m[$k] ?? '', $allowed, true) ? $m[$k] : $allowed[0];
    $action = $pick('action', ['none', 'url', 'update', 'search']);
    $value = mb_substr(trim((string)($m['action_value'] ?? '')), 0, 400);
    if ($action === 'url' && !preg_match('~^https://~', $value)) return [null, 'bad_link'];
    if ($action === 'search' && $value === '') return [null, 'bad_search'];
    $image = mb_substr(trim((string)($m['image_url'] ?? '')), 0, 400);
    if ($image !== '' && !preg_match('~^https://~', $image)) return [null, 'bad_image'];
    $audience = $pick('audience', ['all', 'signed_in', 'guests', 'outdated', 'below_build']);
    $build = null;
    if ($audience === 'outdated') {
        $latest = rp_latest($pdo);
        if (!$latest) return [null, 'no_release'];
        [$audience, $build] = ['below_build', $latest['build']];
    } elseif ($audience === 'below_build') {
        $build = max(1, (int)($m['audience_build'] ?? 0));
    }
    $row = [
        'title' => $title, 'body' => $body, 'image_url' => $image, 'style' => $pick('style', ['info', 'celebrate', 'warning']),
        'action' => $action, 'action_value' => $value, 'action_label' => mb_substr(trim((string)($m['action_label'] ?? '')), 0, 40),
        'show_as' => $pick('show_as', ['both', 'popup', 'system']), 'audience' => $audience, 'audience_build' => $build,
        'starts_at' => $m['starts_at'] ?? gmdate('Y-m-d H:i:s'), 'ends_at' => $m['ends_at'] ?? null, 'created_by' => $adminId,
    ];
    if (rp_v21($pdo)) $row['source'] = $source === 'app' ? 'app' : 'web';
    $pdo->prepare('INSERT INTO notifications (' . implode(', ', array_keys($row)) . ') VALUES (' . implode(', ', array_fill(0, count($row), '?')) . ')')
        ->execute(array_values($row));
    return [(int)$pdo->lastInsertId(), null];
}

/// How many phones each follow-up would reach right now, for the choices next to "Send again".
/// (Phones seen in the last 30 days; "missed" also counts phones that match the original audience.)
function rp_follow_up_counts(PDO $pdo, array $n): array
{
    $id = (int)$n['id'];
    $aud = match ($n['audience']) {
        'signed_in' => 'd.user_id IS NOT NULL',
        'guests' => 'd.user_id IS NULL',
        'below_build' => 'COALESCE(d.app_build, 0) < ' . (int)$n['audience_build'],
        default => '1',
    };
    $recent = 'd.last_seen_at > UTC_TIMESTAMP() - INTERVAL 30 DAY';
    $latest = rp_latest($pdo);
    return [
        'all' => (int)rp_scalar($pdo, "SELECT COUNT(*) FROM devices d WHERE $recent AND $aud"),
        'missed' => (int)rp_scalar($pdo, "SELECT COUNT(*) FROM devices d WHERE $recent AND $aud AND NOT EXISTS (SELECT 1 FROM notification_receipts r WHERE r.notification_id = ? AND r.device_id = d.id)", [$id]),
        'unopened' => (int)rp_scalar($pdo, 'SELECT COUNT(*) FROM notification_receipts r WHERE r.notification_id = ? AND r.opened_at IS NULL', [$id]),
        'outdated' => $latest ? (int)rp_scalar($pdo, "SELECT COUNT(*) FROM devices d WHERE $recent AND COALESCE(d.app_build, 0) < ?", [$latest['build']]) : 0,
    ];
}

/// Sends message [id] again as a new message to [who] (see RP_FOLLOW_UPS). The original stops going
/// out but keeps its place in the history and its numbers. Returns [new id, null] or [null, error code].
function rp_resend(PDO $pdo, int $id, string $who, int $adminId, string $source): array
{
    $n = rp_rows($pdo, 'SELECT * FROM notifications WHERE id = ?', [$id])[0] ?? null;
    if (!$n) return [null, 'not_found'];
    if (!isset(RP_FOLLOW_UPS[$who])) $who = 'all';
    if (($who === 'missed' || $who === 'unopened') && !rp_v21($pdo)) return [null, 'needs_update'];
    $m = $n;
    if ($who === 'outdated') {
        $m['audience'] = 'outdated';
    } elseif ($n['audience'] === 'below_build') {
        $m['audience'] = 'below_build';
    }
    // A follow-up starts now and has no stop time, whatever the original had.
    unset($m['starts_at'], $m['ends_at']);
    // Older messages were saved before every check existed: drop a button or picture that wouldn't
    // pass today rather than refuse to send the message again.
    if (($m['action'] === 'search' && trim((string)$m['action_value']) === '') || ($m['action'] === 'url' && !preg_match('~^https://~', (string)$m['action_value']))) $m['action'] = 'none';
    if ($m['image_url'] !== '' && !preg_match('~^https://~', (string)$m['image_url'])) $m['image_url'] = '';
    [$newId, $err] = rp_send($pdo, $m, $adminId, $source);
    if ($newId && ($who === 'missed' || $who === 'unopened')) {
        $pdo->prepare('UPDATE notifications SET follow_up = ?, follow_of = ? WHERE id = ?')->execute([$who, $id, $newId]);
    }
    // The original stops, so nobody gets the same message twice. Its numbers stay in the history.
    if ($newId) $pdo->prepare('UPDATE notifications SET active = 0 WHERE id = ?')->execute([$id]);
    return [$newId, $err];
}

/// Plain words for who a message went to.
function rp_audience_label(array $n): string
{
    $base = match ($n['audience']) {
        'signed_in' => 'Signed-in listeners',
        'guests' => 'Guests',
        'below_build' => 'Apps older than build ' . (int)$n['audience_build'],
        default => 'Everyone',
    };
    return match ($n['follow_up'] ?? null) {
        'missed' => $base . ' who never got #' . (int)$n['follow_of'],
        'unopened' => $base . ' who didn\'t open #' . (int)$n['follow_of'],
        default => $base,
    };
}
