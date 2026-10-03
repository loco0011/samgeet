<?php
// Reports shared by the web admin panel (admin/index.php) and the admin tools inside the app
// (api/admin.php), so both always show the same numbers. Every function only reads.
//
// Times in the database are UTC; days and hours in reports are Indian time (IST).
// Where people are comes from the `device_info` event, which the app sends only when the listener
// agreed to share device details (city, region and country, worked out on the phone). Everyone else
// shows as "Not shared". The phone's language setting (devices.locale, e.g. en_IN) gives a rough
// country for every phone, guests included.

declare(strict_types=1);

const RP_IST = '+05:30';
const RP_RANGES = ['1' => 'Today', '7' => '7 days', '30' => '30 days', '90' => '90 days', 'all' => 'All time'];

function rp_rows(PDO $pdo, string $sql, array $args = []): array
{
    $q = $pdo->prepare($sql);
    $q->execute($args);
    return $q->fetchAll(PDO::FETCH_ASSOC);
}

function rp_scalar(PDO $pdo, string $sql, array $args = [])
{
    $q = $pdo->prepare($sql);
    $q->execute($args);
    return $q->fetchColumn();
}

function rp_utc(int $ts): string
{
    return gmdate('Y-m-d H:i:s', $ts);
}

/// Midnight today in India, as UTC.
function rp_today(): string
{
    return (new DateTime('today', new DateTimeZone('Asia/Kolkata')))->setTimezone(new DateTimeZone('UTC'))->format('Y-m-d H:i:s');
}

/// A range key ('1', '7', '30', '90', 'all') as [from, to, prevFrom, prevTo] in UTC. The previous
/// period is the same length just before, for the change %. "Today" is compared with yesterday up
/// to the same time of day.
function rp_period(string $r): array
{
    $now = rp_utc(time());
    if ($r === 'all') return ['1970-01-01 00:00:00', $now, null, null];
    if ($r === '1') {
        $today = rp_today();
        return [$today, $now, rp_utc(strtotime($today . ' UTC') - 86400), rp_utc(time() - 86400)];
    }
    $len = max(1, (int)$r) * 86400;
    return [rp_utc(time() - $len), $now, rp_utc(time() - 2 * $len), rp_utc(time() - $len)];
}

function rp_range(?string $r): string
{
    return isset(RP_RANGES[(string)$r]) ? (string)$r : '7';
}

/// The newest published version: ['version' => '1.4.1', 'build' => 10, 'notes' => ...], or null.
function rp_latest(PDO $pdo): ?array
{
    $r = rp_rows($pdo, 'SELECT version_name, build, notes, required, published_at FROM releases WHERE published = 1 ORDER BY build DESC LIMIT 1')[0] ?? null;
    return $r ? ['version' => $r['version_name'], 'build' => (int)$r['build'], 'notes' => $r['notes'], 'required' => (bool)$r['required'], 'published_at' => $r['published_at']] : null;
}

/// The bold lead of each bullet in release notes ("**Offline downloads.**" -> "Offline downloads").
function rp_headlines(string $notes, int $max = 4): array
{
    preg_match_all('/\*\*(.+?)\*\*/u', $notes, $m);
    return array_slice(array_map(fn($s) => rtrim(trim($s), '.'), $m[1]), 0, $max);
}

/// Whether notifications has the columns from migrations/2026-10-03-messages.sql (source,
/// follow_up, follow_of). Until the owner runs it everything still works; messages just aren't split
/// into web and app, and follow-ups to part of an audience can't be sent.
function rp_v21(PDO $pdo): bool
{
    static $has = null;
    if ($has === null) {
        try {
            $has = (bool)rp_rows($pdo, "SHOW COLUMNS FROM notifications LIKE 'follow_of'");
        } catch (Throwable $e) {
            $has = false;
        }
    }
    return $has;
}

/// What a listener picked as their picture, as text the panel can show: an emoji, or '' for initials.
/// (Photos never leave the phone.)
function rp_avatar(string $avatar): string
{
    if (strncmp($avatar, 'emoji:', 6) === 0) return mb_substr(substr($avatar, 6), 0, 8);
    $icons = ['headphones' => '🎧', 'guitar' => '🎵', 'mic' => '🎤', 'piano' => '🎹', 'album' => '💿', 'star' => '⭐',
        'heart' => '❤️', 'bolt' => '⚡', 'moon' => '🌙', 'sun' => '☀️', 'flower' => '🌸', 'fire' => '🔥'];
    return $icons[$avatar] ?? '';
}

function rp_initials(string $name, string $email): string
{
    $words = preg_split('/\s+/u', trim($name)) ?: [];
    $words = array_values(array_filter($words, fn($w) => $w !== ''));
    if (!$words) return mb_strtoupper(mb_substr($email, 0, 1));
    $first = mb_substr($words[0], 0, 1);
    $last = count($words) > 1 ? mb_substr($words[count($words) - 1], 0, 1) : '';
    return mb_strtoupper($first . $last);
}

/// A user row's public face: id, name (or the email's name part), email, picture, initials.
function rp_person(array $u): array
{
    $name = trim((string)($u['name'] ?? ''));
    $email = (string)($u['email'] ?? '');
    return [
        'id' => (int)$u['id'],
        'name' => $name !== '' ? $name : (strstr($email, '@', true) ?: $email),
        'email' => $email,
        'emoji' => rp_avatar((string)($u['avatar'] ?? '')),
        'initials' => rp_initials($name, $email),
        'avatar' => (string)($u['avatar'] ?? ''),
    ];
}

/// Country name for a two-letter code from the phone's language setting (en_IN -> India).
function rp_country_name(string $code): string
{
    $code = strtoupper($code);
    $known = ['IN' => 'India', 'US' => 'United States', 'GB' => 'United Kingdom', 'AE' => 'United Arab Emirates', 'NZ' => 'New Zealand',
        'AU' => 'Australia', 'CA' => 'Canada', 'BD' => 'Bangladesh', 'NP' => 'Nepal', 'PK' => 'Pakistan', 'LK' => 'Sri Lanka',
        'SG' => 'Singapore', 'SA' => 'Saudi Arabia', 'QA' => 'Qatar', 'KW' => 'Kuwait', 'OM' => 'Oman', 'DE' => 'Germany', 'FR' => 'France',
        'MY' => 'Malaysia', 'ID' => 'Indonesia', 'PH' => 'Philippines', 'IE' => 'Ireland', 'NL' => 'Netherlands', 'JP' => 'Japan'];
    if (isset($known[$code])) return $known[$code];
    if (class_exists('Locale') && $code !== '') {
        $n = Locale::getDisplayRegion('-' . $code, 'en');
        if ($n && $n !== $code) return $n;
    }
    return $code !== '' ? $code : 'Unknown';
}

/// A rough country for a phone, for every install (guests too). The time zone comes first: many
/// phones in India are set to English (US) or (UK), so the language setting alone says the wrong
/// country. The phone sends its time zone's short name ("IST") or an offset ("GMT+05:30").
function rp_phone_country(string $tz, string $locale): string
{
    $tz = strtoupper(trim($tz));
    $byName = ['IST' => 'India', 'PKT' => 'Pakistan', 'NPT' => 'Nepal', 'GST' => 'United Arab Emirates',
        'SGT' => 'Singapore', 'MYT' => 'Malaysia', 'NZST' => 'New Zealand', 'NZDT' => 'New Zealand', 'AEST' => 'Australia', 'AEDT' => 'Australia',
        'EST' => 'United States', 'EDT' => 'United States', 'CDT' => 'United States', 'MST' => 'United States',
        'MDT' => 'United States', 'PST' => 'United States', 'PDT' => 'United States', 'JST' => 'Japan'];
    $byOffset = ['+05:30' => 'India', '+05:45' => 'Nepal', '+05:00' => 'Pakistan', '+06:00' => 'Bangladesh', '+04:00' => 'United Arab Emirates',
        '+03:00' => 'Saudi Arabia', '+08:00' => 'Singapore', '+12:00' => 'New Zealand', '+13:00' => 'New Zealand'];
    if (isset($byName[$tz])) return $byName[$tz];
    if (preg_match('/^(?:GMT|UTC)?([+-])(\d{1,2}):?(\d{2})$/', $tz, $m)) {
        $off = $m[1] . str_pad($m[2], 2, '0', STR_PAD_LEFT) . ':' . $m[3];
        if (isset($byOffset[$off])) return $byOffset[$off];
    }
    $cc = strtoupper((string)preg_replace('/^.*[_-]/', '', $locale));
    return preg_match('/^[A-Z]{2}$/', $cc) ? rp_country_name($cc) : 'Unknown';
}

/// The last place each phone shared (opt-in), keyed by device id:
/// [device_id => ['user_id', 'city', 'region', 'country']].
function rp_device_places(PDO $pdo): array
{
    $out = [];
    $rows = rp_rows($pdo, "SELECT e.device_id, e.user_id, e.meta FROM events e
                           JOIN (SELECT device_id, MAX(id) AS mid FROM events WHERE type = 'device_info' GROUP BY device_id) x ON x.mid = e.id");
    foreach ($rows as $r) {
        $m = json_decode((string)$r['meta'], true);
        if (!is_array($m)) continue;
        $city = trim((string)($m['city'] ?? ''));
        $country = trim((string)($m['country'] ?? ''));
        if ($city === '' && $country === '') continue;
        $out[(int)$r['device_id']] = [
            'user_id' => $r['user_id'] !== null ? (int)$r['user_id'] : null,
            'city' => $city !== '' ? $city : 'Unknown city',
            'region' => trim((string)($m['region'] ?? '')),
            'country' => $country !== '' ? $country : 'Unknown',
        ];
    }
    return $out;
}

/// The last place each account shared: [user_id => ['city', 'region', 'country']].
function rp_user_places(PDO $pdo, array $userIds = []): array
{
    $sql = "SELECT e.user_id, e.meta FROM events e
            JOIN (SELECT user_id, MAX(id) AS mid FROM events WHERE type = 'device_info' AND user_id IS NOT NULL"
        . ($userIds ? ' AND user_id IN (' . implode(',', array_map('intval', $userIds)) . ')' : '') . ' GROUP BY user_id) x ON x.mid = e.id';
    $out = [];
    foreach (rp_rows($pdo, $sql) as $r) {
        $m = json_decode((string)$r['meta'], true);
        if (!is_array($m) || (trim((string)($m['city'] ?? '')) === '' && trim((string)($m['country'] ?? '')) === '')) continue;
        $out[(int)$r['user_id']] = ['city' => trim((string)($m['city'] ?? '')), 'region' => trim((string)($m['region'] ?? '')), 'country' => trim((string)($m['country'] ?? ''))];
    }
    return $out;
}

function rp_place_label(?array $p): string
{
    if (!$p) return '';
    return implode(', ', array_filter([$p['city'] ?? '', ($p['country'] ?? '') === 'India' ? ($p['region'] ?? '') : ($p['country'] ?? '')]));
}

// ================================================================ overview

/// Listening for [from, to): listeners (signed in and guests), plays and hours for each.
function rp_listening_totals(PDO $pdo, string $from, string $to): array
{
    $x = rp_rows($pdo, "SELECT
            COUNT(DISTINCT IF(type = 'play_start' AND user_id IS NOT NULL, user_id, NULL)) AS members,
            COUNT(DISTINCT IF(type = 'play_start' AND user_id IS NULL, device_id, NULL)) AS guests,
            SUM(type = 'play_start' AND user_id IS NOT NULL) AS member_plays,
            SUM(type = 'play_start' AND user_id IS NULL) AS guest_plays,
            COALESCE(SUM(IF(type = 'play_end' AND user_id IS NOT NULL, ms, 0)), 0) AS member_ms,
            COALESCE(SUM(IF(type = 'play_end' AND user_id IS NULL, ms, 0)), 0) AS guest_ms,
            COUNT(DISTINCT IF(type = 'play_start', track_id, NULL)) AS songs
        FROM events WHERE client_at >= ? AND client_at < ? AND type IN ('play_start', 'play_end')", [$from, $to])[0];
    $x = array_map('floatval', $x);
    $x['listeners'] = $x['members'] + $x['guests'];
    $x['plays'] = $x['member_plays'] + $x['guest_plays'];
    $x['hours'] = ($x['member_ms'] + $x['guest_ms']) / 3600000;
    return $x;
}

/// Per-day numbers for the last [days] days (IST): signed-in and guest listeners, plays, hours, sign-ups.
function rp_daily(PDO $pdo, int $days): array
{
    $byDay = [];
    for ($i = $days - 1; $i >= 0; $i--) {
        $d = (new DateTime("-$i day", new DateTimeZone('Asia/Kolkata')))->format('Y-m-d');
        $byDay[$d] = ['d' => $d, 'members' => 0, 'guests' => 0, 'plays' => 0, 'hours' => 0.0, 'signups' => 0];
    }
    $from = rp_utc(strtotime(array_key_first($byDay) . ' 00:00:00 +05:30'));
    foreach (rp_rows($pdo, "SELECT DATE(CONVERT_TZ(client_at, '+00:00', '" . RP_IST . "')) AS d,
                                   COUNT(DISTINCT IF(type = 'play_start' AND user_id IS NOT NULL, user_id, NULL)) AS members,
                                   COUNT(DISTINCT IF(type = 'play_start' AND user_id IS NULL, device_id, NULL)) AS guests,
                                   SUM(type = 'play_start') AS plays, SUM(IF(type = 'play_end', ms, 0)) / 3600000 AS hours
                            FROM events WHERE client_at >= ? AND type IN ('play_start', 'play_end') GROUP BY d", [$from]) as $r) {
        if (!isset($byDay[$r['d']])) continue;
        $byDay[$r['d']] = ['d' => $r['d'], 'members' => (int)$r['members'], 'guests' => (int)$r['guests'], 'plays' => (int)$r['plays'], 'hours' => round((float)$r['hours'], 2), 'signups' => 0];
    }
    foreach (rp_rows($pdo, "SELECT DATE(CONVERT_TZ(created_at, '+00:00', '" . RP_IST . "')) AS d, COUNT(*) AS n FROM users WHERE created_at >= ? GROUP BY d", [$from]) as $r) {
        if (isset($byDay[$r['d']])) $byDay[$r['d']]['signups'] = (int)$r['n'];
    }
    return array_values($byDay);
}

function rp_top_songs(PDO $pdo, string $from, int $limit = 10, ?string $extraWhere = null, array $extraArgs = []): array
{
    return array_map(fn($t) => ['title' => $t['title'], 'artist' => (string)$t['artist'], 'image' => $t['image'], 'plays' => (int)$t['plays'], 'listeners' => (int)$t['listeners']],
        rp_rows($pdo, "SELECT t.title, t.image, a.name AS artist, COUNT(*) AS plays, COUNT(DISTINCT e.device_id) AS listeners
                       FROM events e JOIN tracks t ON t.id = e.track_id
                       LEFT JOIN track_artists ta ON ta.track_id = t.id AND ta.position = 0 LEFT JOIN artists a ON a.id = ta.artist_id
                       WHERE e.type = 'play_start' AND e.client_at >= ?" . ($extraWhere ? " AND $extraWhere" : '') . "
                       GROUP BY t.id, t.title, t.image, a.name ORDER BY plays DESC LIMIT $limit", array_merge([$from], $extraArgs)));
}

function rp_top_artists(PDO $pdo, string $from, int $limit = 10, ?string $extraWhere = null, array $extraArgs = []): array
{
    return array_map(fn($a) => ['label' => $a['name'], 'n' => (int)$a['plays'], 'listeners' => (int)$a['listeners']],
        rp_rows($pdo, "SELECT a.name, COUNT(*) AS plays, COUNT(DISTINCT e.device_id) AS listeners
                       FROM events e JOIN track_artists ta ON ta.track_id = e.track_id AND ta.position = 0 JOIN artists a ON a.id = ta.artist_id
                       WHERE e.type = 'play_start' AND e.client_at >= ?" . ($extraWhere ? " AND $extraWhere" : '') . "
                       GROUP BY a.id, a.name ORDER BY plays DESC LIMIT $limit", array_merge([$from], $extraArgs)));
}

/// Active phones (seen in 30 days) per app version, newest first, with the newest published version.
function rp_adoption(PDO $pdo): array
{
    $latest = rp_latest($pdo);
    $rows = rp_rows($pdo, "SELECT COALESCE(app_build, 0) AS build, MAX(app_version) AS version, COUNT(*) AS phones,
                                  SUM(user_id IS NOT NULL) AS signed_in
                           FROM devices WHERE last_seen_at > UTC_TIMESTAMP() - INTERVAL 30 DAY GROUP BY COALESCE(app_build, 0) ORDER BY build DESC");
    $total = array_sum(array_map(fn($r) => (int)$r['phones'], $rows));
    $behind = 0;
    $list = [];
    foreach ($rows as $r) {
        $b = (int)$r['build'];
        $old = $latest && $b < $latest['build'];
        if ($old) $behind += (int)$r['phones'];
        $list[] = ['build' => $b, 'version' => $r['version'] !== '' && $r['version'] !== null ? $r['version'] : 'unknown', 'phones' => (int)$r['phones'],
            'signed_in' => (int)$r['signed_in'], 'share' => $total ? round(100 * $r['phones'] / $total) : 0, 'latest' => $latest && $b >= $latest['build']];
    }
    return ['latest' => $latest, 'versions' => $list, 'active_phones' => $total, 'behind' => $behind, 'on_latest' => $total - $behind,
        'on_latest_pct' => $total ? round(100 * ($total - $behind) / $total) : 0];
}

function rp_overview(PDO $pdo, string $r): array
{
    [$from, $to, $prevFrom, $prevTo] = rp_period($r);
    $L = rp_listening_totals($pdo, $from, $to);
    $P = $prevFrom ? rp_listening_totals($pdo, $prevFrom, $prevTo) : null;
    $newUsers = (int)rp_scalar($pdo, 'SELECT COUNT(*) FROM users WHERE created_at >= ?', [$from]);
    $prevNew = $prevFrom ? (int)rp_scalar($pdo, 'SELECT COUNT(*) FROM users WHERE created_at >= ? AND created_at < ?', [$prevFrom, $prevTo]) : null;
    $converted = (int)rp_scalar($pdo, "SELECT COUNT(DISTINCT d.id) FROM devices d JOIN users u ON u.id = d.user_id
                                       WHERE u.created_at >= ? AND EXISTS (SELECT 1 FROM events e WHERE e.device_id = d.id AND e.user_id IS NULL AND e.type = 'play_start')", [$from]);
    $active = fn(string $since) => (int)rp_scalar($pdo, 'SELECT COUNT(*) FROM users WHERE last_seen_at >= ?', [$since]);
    $ev = [];
    foreach (rp_rows($pdo, 'SELECT type, COUNT(*) AS n FROM events WHERE client_at >= ? GROUP BY type', [$from]) as $row) $ev[$row['type']] = (int)$row['n'];
    $ends = [];
    foreach (rp_rows($pdo, "SELECT value, COUNT(*) AS n FROM events WHERE type = 'play_end' AND client_at >= ? GROUP BY value", [$from]) as $e) $ends[(string)$e['value']] = (int)$e['n'];
    $endTotal = array_sum($ends);
    $days = $r === 'all' ? 90 : max(14, min(90, (int)$r));

    // Most active listeners in the period, with their picture and town.
    $top = rp_rows($pdo, "SELECT u.id, u.name, u.email, u.avatar, ROUND(SUM(IF(e.type = 'play_end', e.ms, 0)) / 60000) AS minutes,
                                 SUM(e.type = 'play_start') AS plays
                          FROM events e JOIN users u ON u.id = e.user_id
                          WHERE e.client_at >= ? AND e.type IN ('play_start', 'play_end') GROUP BY u.id, u.name, u.email, u.avatar ORDER BY minutes DESC LIMIT 8", [$from]);
    $places = rp_user_places($pdo, array_column($top, 'id'));
    $topListeners = array_map(fn($u) => rp_person($u) + ['minutes' => (int)$u['minutes'], 'plays' => (int)$u['plays'], 'place' => rp_place_label($places[(int)$u['id']] ?? null)], $top);

    $cities = array_slice(rp_places($pdo)['cities'], 0, 6);

    return [
        'range' => $r,
        'kpi' => [
            'listeners' => [$L['listeners'], $P['listeners'] ?? null],
            'members' => $L['members'], 'guests' => $L['guests'],
            'plays' => [$L['plays'], $P['plays'] ?? null], 'songs' => $L['songs'],
            'hours' => [round($L['hours'], 1), isset($P) ? round($P['hours'], 1) : null],
            'new_users' => [$newUsers, $prevNew], 'converted' => $converted,
            'member_plays' => $L['member_plays'], 'guest_plays' => $L['guest_plays'],
            'member_hours' => round($L['member_ms'] / 3600000, 1), 'guest_hours' => round($L['guest_ms'] / 3600000, 1),
        ],
        'active' => [
            'online_now' => (int)rp_scalar($pdo, 'SELECT COUNT(*) FROM devices WHERE last_seen_at > UTC_TIMESTAMP() - INTERVAL 15 MINUTE'),
            'today' => $active(rp_today()),
            'week' => $active(rp_utc(time() - 7 * 86400)),
            'month' => $active(rp_utc(time() - 30 * 86400)),
            'accounts' => (int)rp_scalar($pdo, 'SELECT COUNT(*) FROM users'),
            'phones' => (int)rp_scalar($pdo, 'SELECT COUNT(*) FROM devices'),
            'guest_phones' => (int)rp_scalar($pdo, 'SELECT COUNT(*) FROM devices WHERE user_id IS NULL'),
            'new_phones' => (int)rp_scalar($pdo, 'SELECT COUNT(*) FROM devices WHERE first_seen_at >= ?', [$from]),
        ],
        'habits' => [
            'completed_pct' => $endTotal ? round(100 * ($ends['complete'] ?? 0) / $endTotal) : null,
            'skipped_pct' => $endTotal ? round(100 * ($ends['skip'] ?? 0) / $endTotal) : null,
            'offline' => (int)rp_scalar($pdo, "SELECT COUNT(*) FROM events WHERE type = 'play_start' AND client_at >= ? AND meta LIKE '%\"offline\":true%'", [$from]),
            'likes' => $ev['like'] ?? 0, 'downloads' => $ev['download'] ?? 0,
            'shares' => ($ev['share_song'] ?? 0) + ($ev['share_playlist'] ?? 0), 'searches' => $ev['search'] ?? 0,
            'playlists' => $ev['playlist_create'] ?? 0, 'radios' => $ev['radio_start'] ?? 0, 'opens' => $ev['app_open'] ?? 0,
        ],
        'daily' => rp_daily($pdo, $days),
        'top_songs' => rp_top_songs($pdo, $from, 10),
        'top_artists' => rp_top_artists($pdo, $from, 10),
        'top_listeners' => $topListeners,
        'top_cities' => $cities,
        'adoption' => rp_adoption($pdo),
    ];
}

// ================================================================ listening habits

function rp_listening(PDO $pdo, string $r): array
{
    [$from] = rp_period($r);
    $hours = array_fill(0, 24, 0);
    foreach (rp_rows($pdo, "SELECT HOUR(CONVERT_TZ(client_at, '+00:00', '" . RP_IST . "')) AS h, COUNT(*) AS n FROM events
                            WHERE type = 'play_start' AND client_at >= ? GROUP BY h", [$from]) as $x) $hours[(int)$x['h']] = (int)$x['n'];
    $week = array_fill(0, 7, 0); // Monday first
    foreach (rp_rows($pdo, "SELECT WEEKDAY(CONVERT_TZ(client_at, '+00:00', '" . RP_IST . "')) AS w, COUNT(*) AS n FROM events
                            WHERE type = 'play_start' AND client_at >= ? GROUP BY w", [$from]) as $x) $week[(int)$x['w']] = (int)$x['n'];
    $bars = fn(string $sql) => array_map(fn($x) => ['label' => (string)$x['label'], 'n' => (int)$x['n']], rp_rows($pdo, $sql, [$from]));
    $tastes = [];
    foreach (rp_rows($pdo, 'SELECT kind, value AS label, COUNT(*) AS n FROM user_tastes GROUP BY kind, value ORDER BY n DESC') as $t) {
        if (count($tastes[$t['kind']] ?? []) < 8) $tastes[$t['kind']][] = ['label' => $t['label'], 'n' => (int)$t['n']];
    }
    $sessions = rp_rows($pdo, "SELECT COUNT(*) AS opens, COUNT(DISTINCT device_id) AS phones FROM events WHERE type = 'app_open' AND client_at >= ?", [$from])[0];
    $plays = (int)rp_scalar($pdo, "SELECT COUNT(*) FROM events WHERE type = 'play_start' AND client_at >= ?", [$from]);
    return [
        'range' => $r,
        'hours' => $hours,
        'weekdays' => $week,
        'plays_per_open' => (int)$sessions['opens'] ? round($plays / (int)$sessions['opens'], 1) : null,
        'languages' => $bars("SELECT COALESCE(NULLIF(t.language, ''), 'unknown') AS label, COUNT(*) AS n FROM events e JOIN tracks t ON t.id = e.track_id
                             WHERE e.type = 'play_start' AND e.client_at >= ? GROUP BY label ORDER BY n DESC LIMIT 8"),
        'sources' => $bars("SELECT COALESCE(NULLIF(value, ''), 'other') AS label, COUNT(*) AS n FROM events
                           WHERE type = 'play_start' AND client_at >= ? GROUP BY label ORDER BY n DESC LIMIT 8"),
        'searches' => $bars("SELECT LOWER(value) AS label, COUNT(*) AS n FROM events WHERE type = 'search' AND value IS NOT NULL
                            AND client_at >= ? GROUP BY LOWER(value) ORDER BY n DESC LIMIT 10"),
        'liked' => $bars("SELECT CONCAT(t.title, IF(a.name IS NULL, '', CONCAT(' · ', a.name))) AS label, COUNT(*) AS n
                         FROM events e JOIN tracks t ON t.id = e.track_id
                         LEFT JOIN track_artists ta ON ta.track_id = t.id AND ta.position = 0 LEFT JOIN artists a ON a.id = ta.artist_id
                         WHERE e.type = 'like' AND e.client_at >= ? GROUP BY t.id, label ORDER BY n DESC LIMIT 8"),
        'downloaded' => $bars("SELECT CONCAT(t.title, IF(a.name IS NULL, '', CONCAT(' · ', a.name))) AS label, COUNT(*) AS n
                              FROM events e JOIN tracks t ON t.id = e.track_id
                              LEFT JOIN track_artists ta ON ta.track_id = t.id AND ta.position = 0 LEFT JOIN artists a ON a.id = ta.artist_id
                              WHERE e.type = 'download' AND e.client_at >= ? GROUP BY t.id, label ORDER BY n DESC LIMIT 8"),
        'tastes' => $tastes,
        'styles' => array_map(fn($x) => ['label' => ucfirst((string)$x['label']), 'n' => (int)$x['n']],
            rp_rows($pdo, 'SELECT player_style AS label, COUNT(*) AS n FROM users GROUP BY player_style ORDER BY n DESC')),
        'models' => $bars("SELECT CONCAT(brand, ' ', model) AS label, COUNT(*) AS n FROM devices WHERE model <> '' AND last_seen_at >= ? GROUP BY label ORDER BY n DESC LIMIT 8"),
        'android' => $bars("SELECT CONCAT('Android ', COALESCE(NULLIF(os_version, ''), '?')) AS label, COUNT(*) AS n FROM devices WHERE last_seen_at >= ? GROUP BY label ORDER BY n DESC LIMIT 8"),
    ];
}

// ================================================================ listeners

const RP_USER_FILTERS = ['all' => 'All', 'today' => 'Active today', 'week' => 'Active this week', 'inactive' => 'Away 30+ days', 'blocked' => 'Blocked'];

function rp_user_filter_sql(string $f): string
{
    return match ($f) {
        'today' => "u.last_seen_at >= '" . rp_today() . "'",
        'week' => "u.last_seen_at >= '" . rp_utc(time() - 7 * 86400) . "'",
        'inactive' => "(u.last_seen_at IS NULL OR u.last_seen_at < '" . rp_utc(time() - 30 * 86400) . "')",
        'blocked' => "u.status = 'blocked'",
        default => '1',
    };
}

/// Accounts for the list: filter, search, sort, page. Each row has the picture, place, phone,
/// app version and the last 30 days of listening.
function rp_users(PDO $pdo, string $filter = 'all', string $search = '', string $sort = 'recent', int $page = 1, int $per = 30): array
{
    if (!isset(RP_USER_FILTERS[$filter])) $filter = 'all';
    $where = [rp_user_filter_sql($filter)];
    $args = [];
    if ($search !== '') {
        $where[] = '(u.email LIKE ? OR u.name LIKE ?)';
        $like = '%' . addcslashes($search, '%_\\') . '%';
        array_push($args, $like, $like);
    }
    $w = implode(' AND ', $where);
    $since = rp_utc(time() - 30 * 86400);
    $order = match ($sort) {
        'listening' => 'minutes DESC, u.last_seen_at DESC',
        'joined' => 'u.created_at DESC',
        'name' => "COALESCE(NULLIF(u.name, ''), u.email) ASC",
        default => 'u.last_seen_at IS NULL, u.last_seen_at DESC',
    };
    $total = (int)rp_scalar($pdo, "SELECT COUNT(*) FROM users u WHERE $w", $args);
    $list = rp_rows($pdo, "SELECT u.id, u.email, u.name, u.avatar, u.status, u.created_at, u.last_seen_at,
                                  (SELECT COUNT(*) FROM events e WHERE e.user_id = u.id AND e.type = 'play_start' AND e.client_at >= '$since') AS plays,
                                  (SELECT COALESCE(ROUND(SUM(e.ms) / 60000), 0) FROM events e WHERE e.user_id = u.id AND e.type = 'play_end' AND e.client_at >= '$since') AS minutes,
                                  (SELECT CONCAT(d.brand, ' ', d.model, '|', d.app_version, '|', COALESCE(d.app_build, 0)) FROM devices d WHERE d.user_id = u.id ORDER BY d.last_seen_at DESC LIMIT 1) AS phone
                           FROM users u WHERE $w ORDER BY $order LIMIT $per OFFSET " . (max(1, $page) - 1) * $per, $args);
    $places = rp_user_places($pdo, array_column($list, 'id'));
    $latest = rp_latest($pdo);
    $counts = [];
    foreach (array_keys(RP_USER_FILTERS) as $f) $counts[$f] = (int)rp_scalar($pdo, 'SELECT COUNT(*) FROM users u WHERE ' . rp_user_filter_sql($f));
    $rows = [];
    foreach ($list as $u) {
        [$device, $version, $build] = array_pad(explode('|', (string)$u['phone']), 3, '');
        $rows[] = rp_person($u) + [
            'status' => $u['status'],
            'joined' => $u['created_at'], 'last_seen' => $u['last_seen_at'],
            'plays' => (int)$u['plays'], 'minutes' => (int)$u['minutes'],
            'place' => rp_place_label($places[(int)$u['id']] ?? null),
            'device' => trim($device), 'version' => $version,
            'outdated' => $latest && $build !== '' && (int)$build > 0 && (int)$build < $latest['build'],
        ];
    }
    return ['filter' => $filter, 'search' => $search, 'sort' => $sort, 'page' => max(1, $page), 'per' => $per, 'total' => $total, 'counts' => $counts, 'users' => $rows];
}

/// Plain-words names for event types.
function rp_event_label(string $type, ?string $value): string
{
    return match ($type) {
        'play_start' => 'Played', 'play_end' => $value === 'skip' ? 'Skipped' : 'Finished',
        'like' => 'Liked', 'unlike' => 'Unliked', 'download' => 'Downloaded', 'share_song' => 'Shared a song', 'share_playlist' => 'Shared a playlist',
        'search' => 'Searched', 'app_open' => 'Opened the app', 'sign_in' => 'Signed in', 'sign_up' => 'Made an account', 'sign_out' => 'Signed out',
        'playlist_create' => 'Made a playlist', 'playlist_add' => 'Added to a playlist', 'radio_start' => 'Started a radio', 'queue_add' => 'Added to the queue',
        'sleep_timer' => 'Set a sleep timer', 'player_style' => 'Changed the player look', 'eq' => 'Changed the sound', 'device_info' => 'Shared device details',
        'notification_open' => 'Opened a message', 'notification_dismiss' => 'Closed a message', 'update_open' => 'Opened an update', 'update_later' => 'Put off an update',
        'error' => 'Hit an error', 'screen' => 'Opened a screen',
        default => ucfirst(str_replace('_', ' ', $type)),
    };
}

/// Everything about one account, for its page.
function rp_user(PDO $pdo, int $id): ?array
{
    $u = rp_rows($pdo, 'SELECT * FROM users WHERE id = ?', [$id])[0] ?? null;
    if (!$u) return null;
    $since30 = rp_utc(time() - 30 * 86400);
    $latest = rp_latest($pdo);

    $tot = rp_rows($pdo, "SELECT SUM(type = 'play_start') AS plays, COALESCE(SUM(IF(type = 'play_end', ms, 0)), 0) AS ms,
                                 SUM(type = 'like') AS likes, SUM(type = 'download') AS downloads, SUM(type = 'search') AS searches,
                                 SUM(type IN ('share_song', 'share_playlist')) AS shares, SUM(type = 'playlist_create') AS playlists,
                                 SUM(type = 'app_open') AS opens, SUM(type = 'play_end' AND value = 'skip') AS skips, SUM(type = 'play_end') AS ends,
                                 COUNT(DISTINCT IF(type = 'play_start', DATE(CONVERT_TZ(client_at, '+00:00', '" . RP_IST . "')), NULL)) AS days,
                                 MIN(client_at) AS first_at
                          FROM events WHERE user_id = ?", [$id])[0];
    $daily = [];
    for ($i = 29; $i >= 0; $i--) {
        $d = (new DateTime("-$i day", new DateTimeZone('Asia/Kolkata')))->format('Y-m-d');
        $daily[$d] = ['d' => $d, 'minutes' => 0, 'plays' => 0];
    }
    foreach (rp_rows($pdo, "SELECT DATE(CONVERT_TZ(client_at, '+00:00', '" . RP_IST . "')) AS d, ROUND(SUM(IF(type = 'play_end', ms, 0)) / 60000) AS minutes,
                                   SUM(type = 'play_start') AS plays
                            FROM events WHERE user_id = ? AND client_at >= ? AND type IN ('play_start', 'play_end') GROUP BY d", [$id, $since30]) as $r) {
        if (isset($daily[$r['d']])) $daily[$r['d']] = ['d' => $r['d'], 'minutes' => (int)$r['minutes'], 'plays' => (int)$r['plays']];
    }
    $hours = array_fill(0, 24, 0);
    foreach (rp_rows($pdo, "SELECT HOUR(CONVERT_TZ(client_at, '+00:00', '" . RP_IST . "')) AS h, COUNT(*) AS n FROM events
                            WHERE user_id = ? AND type = 'play_start' GROUP BY h", [$id]) as $x) $hours[(int)$x['h']] = (int)$x['n'];

    $devices = array_map(fn($d) => [
        'name' => trim($d['brand'] . ' ' . $d['model']) ?: 'Unknown phone', 'android' => $d['os_version'], 'version' => $d['app_version'],
        'build' => (int)$d['app_build'], 'outdated' => $latest && (int)$d['app_build'] > 0 && (int)$d['app_build'] < $latest['build'],
        'locale' => $d['locale'], 'first_seen' => $d['first_seen_at'], 'last_seen' => $d['last_seen_at'],
    ], rp_rows($pdo, 'SELECT * FROM devices WHERE user_id = ? ORDER BY last_seen_at DESC', [$id]));

    $tastes = [];
    foreach (rp_rows($pdo, 'SELECT kind, value FROM user_tastes WHERE user_id = ? ORDER BY kind, value', [$id]) as $t) $tastes[$t['kind']][] = $t['value'];

    $searches = array_map(fn($s) => ['text' => $s['v'], 'at' => $s['at']],
        rp_rows($pdo, "SELECT LOWER(value) AS v, MAX(client_at) AS at FROM events WHERE user_id = ? AND type = 'search' AND value IS NOT NULL
                       GROUP BY LOWER(value) ORDER BY at DESC LIMIT 12", [$id]));
    $liked = array_map(fn($s) => ['title' => $s['title'], 'artist' => (string)$s['artist'], 'image' => $s['image'], 'at' => $s['at']],
        rp_rows($pdo, "SELECT t.title, t.image, a.name AS artist, MAX(e.client_at) AS at FROM events e JOIN tracks t ON t.id = e.track_id
                       LEFT JOIN track_artists ta ON ta.track_id = t.id AND ta.position = 0 LEFT JOIN artists a ON a.id = ta.artist_id
                       WHERE e.user_id = ? AND e.type = 'like' GROUP BY t.id, t.title, t.image, a.name ORDER BY at DESC LIMIT 10", [$id]));
    $languages = array_map(fn($x) => ['label' => $x['label'], 'n' => (int)$x['n']],
        rp_rows($pdo, "SELECT COALESCE(NULLIF(t.language, ''), 'unknown') AS label, COUNT(*) AS n FROM events e JOIN tracks t ON t.id = e.track_id
                       WHERE e.user_id = ? AND e.type = 'play_start' GROUP BY label ORDER BY n DESC LIMIT 6", [$id]));
    $msg = rp_rows($pdo, 'SELECT COUNT(*) AS got, SUM(r.opened_at IS NOT NULL) AS opened, SUM(r.dismissed_at IS NOT NULL) AS closed
                          FROM notification_receipts r JOIN devices d ON d.id = r.device_id WHERE d.user_id = ?', [$id])[0];
    $timeline = array_map(fn($e) => [
        'at' => $e['client_at'], 'type' => $e['type'], 'label' => rp_event_label($e['type'], $e['value']),
        'title' => (string)$e['title'], 'artist' => (string)$e['artist'],
        'detail' => in_array($e['type'], ['search', 'player_style', 'radio_start'], true) ? (string)$e['value'] : '',
    ], rp_rows($pdo, "SELECT e.client_at, e.type, e.value, t.title, a.name AS artist FROM events e
                      LEFT JOIN tracks t ON t.id = e.track_id
                      LEFT JOIN track_artists ta ON ta.track_id = e.track_id AND ta.position = 0 LEFT JOIN artists a ON a.id = ta.artist_id
                      WHERE e.user_id = ? AND e.type NOT IN ('play_end', 'screen') ORDER BY e.client_at DESC, e.id DESC LIMIT 60", [$id]));
    $lib = rp_rows($pdo, 'SELECT rev, LENGTH(data) AS size, updated_at FROM libraries WHERE user_id = ?', [$id])[0] ?? null;
    $place = rp_user_places($pdo, [$id])[$id] ?? null;
    $ends = (int)$tot['ends'];

    return rp_person($u) + [
        'status' => $u['status'], 'joined' => $u['created_at'], 'last_seen' => $u['last_seen_at'], 'player_style' => $u['player_style'],
        'place' => $place, 'place_label' => rp_place_label($place),
        'sessions' => (int)rp_scalar($pdo, 'SELECT COUNT(*) FROM sessions WHERE user_id = ? AND revoked_at IS NULL AND expires_at > UTC_TIMESTAMP()', [$id]),
        'totals' => [
            'plays' => (int)$tot['plays'], 'hours' => round((float)$tot['ms'] / 3600000, 1), 'days' => (int)$tot['days'],
            'likes' => (int)$tot['likes'], 'downloads' => (int)$tot['downloads'], 'searches' => (int)$tot['searches'],
            'shares' => (int)$tot['shares'], 'playlists' => (int)$tot['playlists'], 'opens' => (int)$tot['opens'],
            'skip_pct' => $ends ? round(100 * (int)$tot['skips'] / $ends) : null, 'first_at' => $tot['first_at'],
        ],
        'daily' => array_values($daily),
        'hours' => $hours,
        'top_songs' => rp_top_songs($pdo, '1970-01-01 00:00:00', 8, 'e.user_id = ?', [$id]),
        'top_artists' => rp_top_artists($pdo, '1970-01-01 00:00:00', 8, 'e.user_id = ?', [$id]),
        'languages' => $languages,
        'searches' => $searches,
        'liked' => $liked,
        'tastes' => $tastes,
        'devices' => $devices,
        'messages' => ['got' => (int)$msg['got'], 'opened' => (int)$msg['opened'], 'closed' => (int)$msg['closed']],
        'library' => $lib ? ['rev' => (int)$lib['rev'], 'kb' => (int)round($lib['size'] / 1024), 'updated' => $lib['updated_at']] : null,
        'timeline' => $timeline,
    ];
}

// ================================================================ places

/// Where listeners are: countries and cities (from phones that shared their place), with accounts,
/// phones, plays in the last 30 days and phones active this week; plus a rough country for every
/// phone from its language setting.
function rp_places(PDO $pdo): array
{
    $byDevice = rp_device_places($pdo);
    $plays = [];
    foreach (rp_rows($pdo, "SELECT device_id, COUNT(*) AS n FROM events WHERE type = 'play_start' AND client_at > UTC_TIMESTAMP() - INTERVAL 30 DAY GROUP BY device_id") as $r) {
        $plays[(int)$r['device_id']] = (int)$r['n'];
    }
    $recent = [];
    foreach (rp_rows($pdo, 'SELECT id FROM devices WHERE last_seen_at > UTC_TIMESTAMP() - INTERVAL 7 DAY') as $r) $recent[(int)$r['id']] = true;

    $cities = [];
    $countries = [];
    foreach ($byDevice as $dev => $p) {
        $ck = mb_strtolower($p['city'] . '|' . $p['country']);
        $cities[$ck] ??= ['city' => $p['city'], 'region' => $p['region'], 'country' => $p['country'], 'users' => [], 'phones' => 0, 'plays' => 0, 'active' => 0];
        $countries[$p['country']] ??= ['country' => $p['country'], 'users' => [], 'phones' => 0, 'plays' => 0, 'cities' => []];
        foreach ([&$cities[$ck], &$countries[$p['country']]] as &$bucket) {
            $bucket['phones']++;
            $bucket['plays'] += $plays[$dev] ?? 0;
            if ($p['user_id']) $bucket['users'][$p['user_id']] = true;
        }
        unset($bucket);
        if (isset($recent[$dev])) $cities[$ck]['active']++;
        $countries[$p['country']]['cities'][$ck] = true;
    }
    $fin = function (array $x): array {
        $x['accounts'] = count($x['users']);
        unset($x['users']);
        if (isset($x['cities'])) $x['cities'] = count($x['cities']);
        return $x;
    };
    $cities = array_map($fin, array_values($cities));
    $countries = array_map($fin, array_values($countries));
    usort($cities, fn($a, $b) => [$b['accounts'], $b['phones'], $b['plays']] <=> [$a['accounts'], $a['phones'], $a['plays']]);
    usort($countries, fn($a, $b) => [$b['accounts'], $b['phones']] <=> [$a['accounts'], $a['phones']]);

    $counts = [];
    foreach (rp_rows($pdo, 'SELECT timezone, locale, COUNT(*) AS n, SUM(user_id IS NULL) AS guests FROM devices GROUP BY timezone, locale') as $r) {
        $country = rp_phone_country((string)$r['timezone'], (string)$r['locale']);
        $counts[$country] ??= ['label' => $country, 'n' => 0, 'guests' => 0];
        $counts[$country]['n'] += (int)$r['n'];
        $counts[$country]['guests'] += (int)$r['guests'];
    }
    usort($counts, fn($a, $b) => $b['n'] <=> $a['n']);
    $regions = array_slice(array_values($counts), 0, 12);
    $accounts = (int)rp_scalar($pdo, 'SELECT COUNT(*) FROM users');
    $located = count(rp_user_places($pdo));
    return [
        'cities' => $cities,
        'countries' => $countries,
        'phone_regions' => $regions,
        'accounts' => $accounts,
        'located_accounts' => $located,
        'located_phones' => count($byDevice),
        'coverage_pct' => $accounts ? round(100 * $located / $accounts) : 0,
    ];
}

/// One city: who listens there (accounts with their numbers), guest phones, and what they play.
function rp_place(PDO $pdo, string $city, string $country): array
{
    $devices = [];
    $userIds = [];
    foreach (rp_device_places($pdo) as $dev => $p) {
        if (mb_strtolower($p['city']) !== mb_strtolower($city) || mb_strtolower($p['country']) !== mb_strtolower($country)) continue;
        $devices[] = $dev;
        if ($p['user_id']) $userIds[$p['user_id']] = true;
        $region = $p['region'];
    }
    $people = [];
    if ($userIds) {
        $ids = implode(',', array_map('intval', array_keys($userIds)));
        $since = rp_utc(time() - 30 * 86400);
        foreach (rp_rows($pdo, "SELECT u.id, u.name, u.email, u.avatar, u.status, u.last_seen_at, u.created_at,
                                       (SELECT COUNT(*) FROM events e WHERE e.user_id = u.id AND e.type = 'play_start' AND e.client_at >= '$since') AS plays,
                                       (SELECT COALESCE(ROUND(SUM(e.ms) / 60000), 0) FROM events e WHERE e.user_id = u.id AND e.type = 'play_end' AND e.client_at >= '$since') AS minutes
                                FROM users u WHERE u.id IN ($ids) ORDER BY minutes DESC") as $u) {
            $people[] = rp_person($u) + ['status' => $u['status'], 'last_seen' => $u['last_seen_at'], 'joined' => $u['created_at'], 'plays' => (int)$u['plays'], 'minutes' => (int)$u['minutes']];
        }
    }
    $in = $devices ? 'e.device_id IN (' . implode(',', array_map('intval', $devices)) . ')' : '0';
    $since = rp_utc(time() - 30 * 86400);
    return [
        'city' => $city, 'region' => $region ?? '', 'country' => $country,
        'people' => $people,
        'phones' => count($devices),
        'guest_phones' => count($devices) - (int)rp_scalar($pdo, 'SELECT COUNT(*) FROM devices WHERE user_id IS NOT NULL AND id IN (' . ($devices ? implode(',', array_map('intval', $devices)) : '0') . ')'),
        'top_songs' => rp_top_songs($pdo, $since, 8, $in),
        'top_artists' => rp_top_artists($pdo, $since, 8, $in),
    ];
}

// ================================================================ messages

const RP_MESSAGE_TABS = ['all' => 'All', 'web' => 'From the web panel', 'app' => 'From the app', 'update' => 'Update reminders'];

/// Sent messages with their numbers, newest first. [tab]: all, web, app (needs the source column) or
/// update (messages whose button updates the app).
function rp_messages(PDO $pdo, string $tab = 'all', int $page = 1, int $per = 15, ?int $before = null): array
{
    $hasSource = rp_v21($pdo);
    $where = ['1'];
    $args = [];
    if ($tab === 'update') $where[] = "n.action = 'update'";
    if ($hasSource && ($tab === 'web' || $tab === 'app')) {
        $where[] = 'n.source = ?';
        $args[] = $tab;
    }
    if ($before !== null) {
        $where[] = 'n.id < ?';
        $args[] = $before;
    }
    $w = implode(' AND ', $where);
    $total = (int)rp_scalar($pdo, "SELECT COUNT(*) FROM notifications n WHERE $w", $args);
    $offset = $before === null ? ' OFFSET ' . (max(1, $page) - 1) * $per : '';
    $list = rp_rows($pdo, "SELECT n.*, " . ($hasSource ? 'n.source' : "'web'") . " AS src, a.email AS by_email, UNIX_TIMESTAMP(n.starts_at) AS sent,
                                  COUNT(r.device_id) AS delivered, COALESCE(SUM(r.opened_at IS NOT NULL), 0) AS opened,
                                  COALESCE(SUM(r.dismissed_at IS NOT NULL), 0) AS dismissed
                           FROM notifications n LEFT JOIN notification_receipts r ON r.notification_id = n.id LEFT JOIN admins a ON a.id = n.created_by
                           WHERE $w GROUP BY n.id ORDER BY n.id DESC LIMIT $per$offset", $args);
    $counts = [];
    foreach (array_keys(RP_MESSAGE_TABS) as $t) {
        $counts[$t] = match ($t) {
            'update' => (int)rp_scalar($pdo, "SELECT COUNT(*) FROM notifications WHERE action = 'update'"),
            'web', 'app' => $hasSource ? (int)rp_scalar($pdo, 'SELECT COUNT(*) FROM notifications WHERE source = ?', [$t]) : null,
            default => (int)rp_scalar($pdo, 'SELECT COUNT(*) FROM notifications'),
        };
    }
    return ['tab' => $tab, 'page' => max(1, $page), 'per' => $per, 'total' => $total, 'counts' => $counts, 'has_source' => $hasSource, 'list' => $list];
}

/// What an update reminder needs: the newest version, how many active phones are older, and a
/// ready title and text for the message.
function rp_update_reminder(PDO $pdo): array
{
    $a = rp_adoption($pdo);
    $latest = $a['latest'];
    if (!$latest) return ['latest' => null, 'behind' => 0, 'title' => '', 'body' => ''];
    $heads = rp_headlines((string)$latest['notes'], 3);
    $body = $heads ? 'New: ' . implode(', ', array_map(fn($h) => mb_strtolower(mb_substr($h, 0, 1)) . mb_substr($h, 1), $heads)) . '. Tap to update, it only takes a minute.'
        : 'A new version of Samgeet is ready. Tap to update, it only takes a minute.';
    return [
        'latest' => $latest,
        'behind' => $a['behind'],
        'active_phones' => $a['active_phones'],
        'title' => 'Samgeet ' . $latest['version'] . ' is here',
        'body' => $body,
    ];
}
