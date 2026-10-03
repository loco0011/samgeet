<?php
// The admin panel's pages. Each view_* prints its page and returns the page title. Numbers come
// from lib/reports.php; layout pieces from lib/admin_ui.php. Loaded by admin/index.php only.

declare(strict_types=1);
if (!defined('SG_ADMIN')) exit;

function range_seg(string $page, string $r, array $extra = []): string
{
    return tabs(RP_RANGES, $r, fn($k) => '?' . http_build_query(['p' => $page, 'r' => $k] + $extra), [], 'seg');
}

function range_words(string $r): array
{
    $label = $r === 'all' ? 'all time' : ($r === '1' ? 'today' : "the last $r days");
    $vs = $r === 'all' ? '' : ($r === '1' ? 'yesterday' : "the $r days before");
    return [$label, $vs];
}

// ================================================================ overview

function view_dashboard(PDO $pdo): string
{
    $r = rp_range($_GET['r'] ?? '7');
    $o = rp_overview($pdo, $r);
    [$label, $vs] = range_words($r);
    $k = $o['kpi'];
    $a = $o['active'];
    $daily = $o['daily'];
    $col = fn(string $key) => array_map(fn($d) => (float)$d[$key], $daily);
    $share = $k['listeners'][0] > 0 ? round(100 * $k['members'] / $k['listeners'][0]) : 0;

    echo page_head('Overview', 'Showing ' . h($label) . ($vs ? ', compared with ' . h($vs) : '') . ' · times in IST', range_seg('dashboard', $r));
    echo '<div class="kpis">'
        . kpi('Listeners', num($k['listeners'][0]), change($k['listeners'][0], $k['listeners'][1]), num($k['members']) . ' signed in · ' . num($k['guests']) . ' guests', array_map(fn($d) => $d['members'] + $d['guests'], $daily))
        . kpi('Plays', num($k['plays'][0]), change($k['plays'][0], $k['plays'][1]), num($k['songs']) . ' different songs', $col('plays'), 'var(--accent2)')
        . kpi('Hours listened', number_format($k['hours'][0], 1), change($k['hours'][0], $k['hours'][1]), $k['listeners'][0] ? round($k['hours'][0] * 60 / $k['listeners'][0]) . ' min per listener' : '—', $col('hours'), 'var(--ok)')
        . kpi('New accounts', num($k['new_users'][0]), change($k['new_users'][0], $k['new_users'][1]), num($k['converted']) . ' were guests first', $col('signups'), 'var(--violet)')
        . '</div>';
    echo '<div class="strip">'
        . '<div><b class="live">' . num($a['online_now']) . '</b><span>Online now</span></div>'
        . '<div><b>' . num($a['today']) . '</b><span>Accounts active today</span></div>'
        . '<div><b>' . num($a['week']) . '</b><span>Active this week</span></div>'
        . '<div><b>' . num($a['month']) . '</b><span>Active this month</span></div>'
        . '<div><b>' . num($a['accounts']) . '</b><span>Accounts in total</span></div>'
        . '<div><b>' . num($a['phones']) . '</b><span>Installs (' . num($a['guest_phones']) . ' guests)</span></div>'
        . '</div>';

    echo '<div class="g-wide section">';
    echo card_open('Daily listeners', 'signed in and guests, with plays') . chart([
        'type' => 'bar', 'stacked' => true, 'labels' => array_map(fn($d) => date('j M', strtotime($d['d'])), $daily),
        'series' => [
            ['label' => 'Signed in', 'data' => array_column($daily, 'members'), 'color' => '--accent'],
            ['label' => 'Guests', 'data' => array_column($daily, 'guests'), 'color' => '--guest'],
            ['label' => 'Plays', 'data' => array_column($daily, 'plays'), 'color' => '--accent2', 'type' => 'line', 'axis' => 'y1'],
        ],
    ], 290) . '</section>';
    echo card_open("Who's listening", $label)
        . chart(['type' => 'doughnut', 'labels' => ['Signed in', 'Guests'], 'series' => [['label' => 'Listeners', 'data' => [$k['members'], $k['guests']], 'color' => ['--accent', '--guest']]]], 150)
        . '<table style="margin-top:14px"><thead><tr><th></th><th class="r">People</th><th class="r">Plays</th><th class="r">Hours</th></tr></thead><tbody>'
        . '<tr><td><span class="dot" style="background:var(--accent)"></span>Signed in</td><td class="r num">' . num($k['members']) . '</td><td class="r num">' . num($k['member_plays']) . '</td><td class="r num">' . $k['member_hours'] . '</td></tr>'
        . '<tr><td><span class="dot" style="background:var(--guest)"></span>Guests</td><td class="r num">' . num($k['guests']) . '</td><td class="r num">' . num($k['guest_plays']) . '</td><td class="r num">' . $k['guest_hours'] . '</td></tr>'
        . '</tbody></table><p class="small muted" style="margin:12px 0 0">' . ($k['listeners'][0] ? $share . '% signed in' : 'No listening yet') . ' · ' . num($k['converted']) . ' guests made an account</p></section>';
    echo '</div>';

    echo '<div class="g2 section">';
    echo card_open('Top songs', $label, more_link('?p=listening&amp;r=' . h($r), 'Listening')) . songs($o['top_songs']) . '</section>';
    echo '<div class="stack">';
    echo card_open('Most active listeners', 'minutes, ' . $label, more_link('?p=users&amp;sort=listening')) ;
    if (!$o['top_listeners']) echo '<p class="empty">Nobody yet.</p>';
    else {
        echo '<ul class="plain">';
        foreach ($o['top_listeners'] as $p) echo '<li>' . person($p, h($p['place'] ?: $p['email'])) . '<span class="num nowrap"><b>' . mins($p['minutes']) . '</b> <span class="muted small">· ' . num($p['plays']) . ' plays</span></span></li>';
        echo '</ul>';
    }
    echo '</section>';
    echo card_open('Top singers', 'plays') . bars(array_slice($o['top_artists'], 0, 6)) . '</section>';
    echo '</div></div>';

    $ad = $o['adoption'];
    echo '<div class="g3 section">';
    echo card_open('Top cities', 'accounts', more_link('?p=places', 'Places'))
        . bars(array_map(fn($c) => ['label' => $c['city'] . ($c['country'] !== 'India' ? ', ' . $c['country'] : ''), 'n' => $c['accounts'] ?: $c['phones'], 'city' => $c['city'], 'country' => $c['country']], $o['top_cities']), '',
            fn($c) => '?p=place&city=' . rawurlencode($c['city']) . '&country=' . rawurlencode($c['country'])) . '</section>';
    echo card_open('App versions', 'active phones', more_link('?p=releases', 'Updates'));
    if ($ad['latest']) {
        echo '<p style="margin:0 0 10px"><b class="num">' . $ad['on_latest_pct'] . '%</b> <span class="muted">on ' . h($ad['latest']['version']) . ' · ' . num($ad['behind']) . ' phones behind</span></p>'
            . '<div class="progress"><i style="width:' . $ad['on_latest_pct'] . '%"></i></div><div style="height:12px"></div>';
    }
    echo bars(array_map(fn($v) => ['label' => $v['version'] . ($v['latest'] ? ' (latest)' : ''), 'n' => $v['phones']], array_slice($ad['versions'], 0, 5))) . '</section>';
    $hb = $o['habits'];
    echo card_open('Listening habits', $label) . '<dl class="kv">'
        . '<dt>Heard to the end</dt><dd>' . ($hb['completed_pct'] ?? '—') . ($hb['completed_pct'] !== null ? '%' : '') . '</dd>'
        . '<dt>Skipped</dt><dd>' . ($hb['skipped_pct'] ?? '—') . ($hb['skipped_pct'] !== null ? '%' : '') . '</dd>'
        . '<dt>Played offline</dt><dd>' . num($hb['offline']) . '</dd>'
        . '<dt>Likes · downloads</dt><dd>' . num($hb['likes']) . ' · ' . num($hb['downloads']) . '</dd>'
        . '<dt>Searches</dt><dd>' . num($hb['searches']) . '</dd>'
        . '<dt>Shares · playlists</dt><dd>' . num($hb['shares']) . ' · ' . num($hb['playlists']) . '</dd>'
        . '<dt>App opens</dt><dd>' . num($hb['opens']) . '</dd></dl></section>';
    echo '</div>';
    return 'Overview';
}

// ================================================================ listening

function view_listening(PDO $pdo): string
{
    $r = rp_range($_GET['r'] ?? '30');
    $l = rp_listening($pdo, $r);
    [$label] = range_words($r);
    $hourLabels = array_map(fn($h) => $h === 0 ? '12a' : ($h < 12 ? $h . 'a' : ($h === 12 ? '12p' : ($h - 12) . 'p')), range(0, 23));
    $peak = array_search(max($l['hours']), $l['hours'], true);
    $days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    $busiest = $days[array_search(max($l['weekdays']), $l['weekdays'], true)];

    echo page_head('Listening', 'What people play, when and how · ' . h($label), range_seg('listening', $r));
    echo '<div class="g-wide">';
    echo card_open('When people listen', 'plays by hour, IST · busiest around ' . $hourLabels[$peak]) . chart(['type' => 'bar', 'labels' => $hourLabels,
            'series' => [['label' => 'Plays', 'data' => $l['hours'], 'color' => '--accent2']]], 240) . '</section>';
    echo card_open('By day of the week', 'busiest: ' . $busiest) . chart(['type' => 'bar', 'labels' => $days,
            'series' => [['label' => 'Plays', 'data' => $l['weekdays'], 'color' => '--accent']]], 240) . '</section>';
    echo '</div>';
    echo '<div class="g3 section">';
    echo card_open('Languages played') . bars($l['languages']) . '</section>';
    echo card_open('Where plays start', 'screen or feature') . bars($l['sources']) . '</section>';
    echo card_open('Top searches') . bars($l['searches']) . '</section>';
    echo card_open('Most liked') . bars($l['liked']) . '</section>';
    echo card_open('Most downloaded') . bars($l['downloaded']) . '</section>';
    echo card_open('Player looks', 'all accounts') . bars($l['styles']) . '</section>';
    echo '</div>';
    echo '<div class="section-title">What people said they like, at sign-up</div><div class="g3">';
    echo card_open('Languages') . bars($l['tastes']['language'] ?? []) . '</section>';
    echo card_open('Moods') . bars($l['tastes']['mood'] ?? []) . '</section>';
    echo card_open('Singers') . bars($l['tastes']['artist'] ?? []) . '</section>';
    echo '</div>';
    echo '<div class="section-title">Phones</div><div class="g2">';
    echo card_open('Models', 'active in the period') . bars($l['models']) . '</section>';
    echo card_open('Android versions') . bars($l['android']) . '</section>';
    echo '</div>';
    return 'Listening';
}

// ================================================================ listeners

function view_users(PDO $pdo): string
{
    $f = (string)($_GET['f'] ?? 'all');
    $q = trim((string)($_GET['q'] ?? ''));
    $sort = in_array($_GET['sort'] ?? '', ['recent', 'listening', 'joined', 'name'], true) ? $_GET['sort'] : 'recent';
    $pg = max(1, (int)($_GET['n'] ?? 1));
    $d = rp_users($pdo, $f, $q, $sort, $pg);
    $link = fn(array $over) => '?' . http_build_query(array_filter(['p' => 'users', 'f' => $d['filter'], 'q' => $q, 'sort' => $sort] + $over, fn($v) => $v !== '' && $v !== null));

    echo page_head('Listeners', num($d['counts']['all']) . ' accounts · listening numbers cover the last 30 days');
    echo tabs(RP_USER_FILTERS, $d['filter'], fn($k) => $link(['f' => $k, 'n' => null]), $d['counts']);
    echo '<div class="toolbar"><form class="search" method="get"><input type="hidden" name="p" value="users"><input type="hidden" name="f" value="' . h($d['filter']) . '">'
        . '<input type="hidden" name="sort" value="' . h($sort) . '"><input name="q" value="' . h($q) . '" placeholder="Search by name or email"><button class="btn">' . icon('search', 15) . '</button></form>'
        . tabs(['recent' => 'Last seen', 'listening' => 'Most listening', 'joined' => 'Newest', 'name' => 'Name'], $sort, fn($k) => $link(['sort' => $k, 'n' => null]), [], 'seg') . '</div>';
    echo '<section class="card"><div class="tbl-wrap"><table><thead><tr><th>Listener</th><th class="hide-sm">Place</th><th class="hide-sm">Phone</th><th class="r hide-sm">Plays</th><th class="r">Listening</th><th>Last seen</th><th class="hide-sm">Joined</th></tr></thead><tbody>';
    foreach ($d['users'] as $u) {
        $badges = ($u['status'] !== 'active' ? ' ' . tag('blocked', 'danger') : '');
        echo '<tr data-href="?p=user&amp;id=' . $u['id'] . '"><td>' . person($u, h($u['email']) . $badges) . '</td>'
            . '<td class="hide-sm">' . ($u['place'] !== '' ? h($u['place']) : '<span class="muted">Not shared</span>') . '</td>'
            . '<td class="hide-sm"><span class="nowrap">' . h($u['device'] ?: '—') . '</span>' . ($u['version'] !== '' ? '<div class="small muted">v' . h($u['version']) . ($u['outdated'] ? ' ' . tag('old', 'warn') : '') . '</div>' : '') . '</td>'
            . '<td class="r num hide-sm">' . num($u['plays']) . '</td><td class="r num nowrap">' . mins($u['minutes']) . '</td>'
            . '<td>' . seen($u['last_seen']) . '</td><td class="hide-sm muted nowrap">' . ist($u['joined'], 'd M Y') . '</td></tr>';
    }
    if (!$d['users']) echo '<tr><td colspan="7" class="muted">Nobody here.</td></tr>';
    echo '</tbody></table></div>';
    $pages = (int)ceil($d['total'] / $d['per']);
    if ($pages > 1) {
        echo '<div class="pager">' . ($d['page'] > 1 ? '<a class="btn sm" href="' . h($link(['n' => $d['page'] - 1])) . '">← Previous</a>' : '<span></span>')
            . '<span class="muted small">Page ' . $d['page'] . ' of ' . $pages . ' · ' . num($d['total']) . ' listeners</span>'
            . ($d['page'] < $pages ? '<a class="btn sm" href="' . h($link(['n' => $d['page'] + 1])) . '">Next →</a>' : '<span></span>') . '</div>';
    }
    echo '</section>';
    return 'Listeners';
}

function view_user(PDO $pdo, int $id): string
{
    $u = rp_user($pdo, $id);
    if (!$u) {
        echo page_head('Not found', 'This account no longer exists.', '', '?p=users');
        return 'Not found';
    }
    $t = $u['totals'];
    $s = (int)(time() - strtotime(($u['last_seen'] ?? '1970-01-01') . ' UTC'));
    $state = $u['status'] !== 'active' ? tag('blocked', 'danger') : ($s < 86400 ? tag('active today', 'ok') : ($s < 7 * 86400 ? tag('active this week', 'warn') : tag('away', '')));
    echo '<a class="back" href="?p=users">' . icon('back', 15) . ' Listeners</a>';
    echo '<section class="card profile">' . avatar($u, 72)
        . '<div class="who"><h1>' . h($u['name']) . ' ' . $state . '</h1>'
        . '<div class="facts"><span>' . h($u['email']) . '</span><span>Joined <b>' . ist($u['joined'], 'd M Y') . '</b></span>'
        . '<span>Last seen <b>' . h(ago($u['last_seen'])) . '</b></span>'
        . '<span>' . icon('places', 13) . ' <b>' . ($u['place_label'] !== '' ? h($u['place_label']) . ($u['place']['country'] !== 'India' ? '' : ', India') : 'Place not shared') . '</b></span>'
        . '<span>Player look <b>' . h(ucfirst($u['player_style'])) . '</b></span></div></div>'
        . '<div class="head-actions">'
        . post_button('user_signout', 'Sign out everywhere', ['id' => $id], 'btn', 'Sign this account out on every phone?', 'user')
        . post_button('user_block', $u['status'] === 'active' ? 'Block' : 'Unblock', ['id' => $id], 'btn', $u['status'] === 'active' ? 'Block this account? They are signed out and can\'t sign in again until you unblock them.' : '', 'user')
        . post_button('user_delete', 'Delete', ['id' => $id], 'btn danger', 'Delete this account, its synced library and all its listening data? This can\'t be undone.', 'user')
        . '</div></section>';

    echo '<div class="kpis six section">'
        . kpi('Plays', num($t['plays']), '', $t['skip_pct'] !== null ? $t['skip_pct'] . '% skipped' : '')
        . kpi('Hours listened', number_format($t['hours'], 1), '', $t['days'] ? round($t['hours'] * 60 / $t['days']) . ' min a day when listening' : '')
        . kpi('Days listened', num($t['days']), '', 'since ' . ist($t['first_at'], 'd M'))
        . kpi('Likes', num($t['likes']), '', num($t['downloads']) . ' downloads')
        . kpi('Searches', num($t['searches']), '', num($t['shares']) . ' shares')
        . kpi('Messages', num($u['messages']['got']), '', num($u['messages']['opened']) . ' opened')
        . '</div>';

    echo '<div class="g-wide section">';
    echo card_open('Listening, last 30 days', 'minutes a day') . chart(['type' => 'bar', 'labels' => array_map(fn($d) => date('j M', strtotime($d['d'])), $u['daily']),
            'series' => [['label' => 'Minutes', 'data' => array_column($u['daily'], 'minutes'), 'color' => '--accent']]], 230) . '</section>';
    $hourLabels = array_map(fn($h) => $h === 0 ? '12a' : ($h < 12 ? $h . 'a' : ($h === 12 ? '12p' : ($h - 12) . 'p')), range(0, 23));
    echo card_open('Time of day', 'all time, IST') . chart(['type' => 'bar', 'labels' => $hourLabels, 'series' => [['label' => 'Plays', 'data' => $u['hours'], 'color' => '--accent2']]], 230) . '</section>';
    echo '</div>';

    echo '<div class="g3 section">';
    echo card_open('Their top songs', 'all time') . songs(array_map(function ($s) { unset($s['listeners']); return $s; }, $u['top_songs'])) . '</section>';
    echo '<div class="stack">' . card_open('Their top singers') . bars($u['top_artists']) . '</section>'
        . card_open('Languages played') . bars($u['languages']) . '</section></div>';
    echo '<div class="stack">';
    echo card_open('Recent searches');
    echo $u['searches'] ? '<div class="chips">' . implode('', array_map(fn($x) => '<span class="chip" title="' . h(ist($x['at'])) . '">' . h($x['text']) . '</span>', $u['searches'])) . '</div>' : '<p class="empty">No searches yet.</p>';
    echo '</section>' . card_open('Picked at sign-up');
    $any = false;
    foreach (['language' => 'Languages', 'mood' => 'Moods', 'artist' => 'Singers'] as $kk => $lab) {
        if (empty($u['tastes'][$kk])) continue;
        $any = true;
        echo '<div class="small muted" style="margin:4px 0 6px">' . $lab . '</div><div class="chips" style="margin-bottom:8px">' . implode('', array_map(fn($v) => '<span class="chip">' . h($v) . '</span>', $u['tastes'][$kk])) . '</div>';
    }
    if (!$any) echo '<p class="empty">Nothing picked.</p>';
    echo '</section></div></div>';

    echo '<div class="g-wide section">';
    echo card_open('Activity', 'latest 60 things they did, IST') . '<ul class="timeline">';
    foreach ($u['timeline'] as $e) {
        $what = '<b>' . h($e['label']) . '</b>';
        if ($e['title'] !== '') $what .= ' ' . h($e['title']) . ($e['artist'] !== '' ? ' <span>· ' . h($e['artist']) . '</span>' : '');
        elseif ($e['detail'] !== '') $what .= ' <span>“' . h($e['detail']) . '”</span>';
        echo '<li><time>' . ist($e['at'], 'd M, H:i') . '</time><div class="what">' . $what . '</div></li>';
    }
    if (!$u['timeline']) echo '<li><span></span><span class="muted">Nothing yet.</span></li>';
    echo '</ul></section>';
    echo '<div class="stack">';
    echo card_open('Liked songs', 'latest');
    if (!$u['liked']) echo '<p class="empty">No likes yet.</p>';
    else {
        echo '<ol class="songs">';
        foreach ($u['liked'] as $x) echo '<li>' . ($x['image'] ? '<img src="' . h($x['image']) . '" alt="" loading="lazy">' : '<span class="noimg">♥</span>') . '<span class="meta"><b>' . h($x['title']) . '</b><span>' . h($x['artist']) . '</span></span><span class="muted small nowrap">' . h(ago($x['at'])) . '</span></li>';
        echo '</ol>';
    }
    echo '</section>' . card_open('Phones', num($u['sessions']) . ' signed in now') . '<ul class="plain">';
    foreach ($u['devices'] as $dv) {
        echo '<li><span class="pn"><b>' . h($dv['name']) . '</b><span>Android ' . h($dv['android']) . ' · v' . h($dv['version']) . ($dv['outdated'] ? ' · update waiting' : '') . '</span></span><span class="muted small nowrap">' . h(ago($dv['last_seen'])) . '</span></li>';
    }
    if (!$u['devices']) echo '<li class="muted">No phone on record.</li>';
    echo '</ul></section>';
    echo card_open('Account') . '<dl class="kv">'
        . '<dt>Synced library</dt><dd>' . ($u['library'] ? 'v' . $u['library']['rev'] . ' · ' . num($u['library']['kb']) . ' KB · ' . h(ago($u['library']['updated'])) : 'None') . '</dd>'
        . '<dt>Playlists made</dt><dd>' . num($t['playlists']) . '</dd>'
        . '<dt>App opens</dt><dd>' . num($t['opens']) . '</dd>'
        . '<dt>Messages</dt><dd>' . num($u['messages']['got']) . ' got · ' . num($u['messages']['opened']) . ' opened · ' . num($u['messages']['closed']) . ' closed</dd>'
        . '</dl></section>';
    echo '</div></div>';
    return $u['name'];
}

// ================================================================ places

function view_places(PDO $pdo): string
{
    $p = rp_places($pdo);
    echo page_head('Places', 'From listeners who chose to share device details when signing in. Everyone else shows as “not shared”.');
    echo '<div class="kpis">'
        . kpi('Countries', num(count($p['countries'])))
        . kpi('Cities', num(count($p['cities'])))
        . kpi('Accounts with a place', num($p['located_accounts']), '', $p['coverage_pct'] . '% of ' . num($p['accounts']) . ' accounts')
        . kpi('Phones with a place', num($p['located_phones']))
        . '</div>';
    echo '<div class="g-wide section">';
    echo card_open('Cities', 'click one to see who listens there') . '<div class="tbl-wrap"><table><thead><tr><th>City</th><th class="hide-sm">Region</th><th class="r">Accounts</th><th class="r">Phones</th><th class="r hide-sm">Active this week</th><th class="r">Plays, 30 days</th></tr></thead><tbody>';
    $max = max(1, ...array_map(fn($c) => $c['accounts'], $p['cities'] ?: [['accounts' => 1]]));
    foreach ($p['cities'] as $c) {
        $href = '?p=place&amp;city=' . rawurlencode($c['city']) . '&amp;country=' . rawurlencode($c['country']);
        echo '<tr data-href="' . $href . '"><td><a href="' . $href . '"><b>' . h($c['city']) . '</b></a>' . ($c['country'] !== 'India' ? ' <span class="muted small">' . h($c['country']) . '</span>' : '')
            . '<div class="progress" style="margin-top:6px;max-width:180px;height:5px"><i style="width:' . round(100 * $c['accounts'] / $max) . '%"></i></div></td>'
            . '<td class="hide-sm muted">' . h($c['region']) . '</td><td class="r num">' . num($c['accounts']) . '</td><td class="r num">' . num($c['phones']) . '</td>'
            . '<td class="r num hide-sm">' . num($c['active']) . '</td><td class="r num">' . num($c['plays']) . '</td></tr>';
    }
    if (!$p['cities']) echo '<tr><td colspan="6" class="muted">Nobody has shared a place yet.</td></tr>';
    echo '</tbody></table></div></section>';
    echo '<div class="stack">';
    echo card_open('Countries') . bars(array_map(fn($c) => ['label' => $c['country'] . ' · ' . $c['cities'] . ($c['cities'] === 1 ? ' city' : ' cities'), 'n' => $c['accounts']], $p['countries'])) . '</section>';
    echo card_open('Phone region', 'every install, from its language setting') . bars($p['phone_regions'])
        . '<p class="small muted" style="margin:10px 0 0">Covers guests too, but only says which country the phone is set up for.</p></section>';
    echo '</div></div>';
    return 'Places';
}

function view_place(PDO $pdo, string $city, string $country): string
{
    $c = rp_place($pdo, $city, $country);
    echo page_head(h($c['city']), h(implode(', ', array_filter([$c['region'], $c['country']]))) . ' · ' . num(count($c['people'])) . ' accounts, ' . num($c['guest_phones']) . ' guest phones', '', '?p=places');
    echo '<div class="g-wide">';
    echo card_open('Who listens here', 'last 30 days') . '<div class="tbl-wrap"><table><thead><tr><th>Listener</th><th class="r">Plays</th><th class="r">Listening</th><th>Last seen</th></tr></thead><tbody>';
    foreach ($c['people'] as $u) {
        echo '<tr data-href="?p=user&amp;id=' . $u['id'] . '"><td>' . person($u, h($u['email']) . ($u['status'] !== 'active' ? ' ' . tag('blocked', 'danger') : '')) . '</td>'
            . '<td class="r num">' . num($u['plays']) . '</td><td class="r num nowrap">' . mins($u['minutes']) . '</td><td>' . seen($u['last_seen']) . '</td></tr>';
    }
    if (!$c['people']) echo '<tr><td colspan="4" class="muted">Only guests here.</td></tr>';
    echo '</tbody></table></div></section>';
    echo '<div class="stack">' . card_open('Top songs here', '30 days') . songs($c['top_songs']) . '</section>'
        . card_open('Top singers here') . bars($c['top_artists']) . '</section></div>';
    echo '</div>';
    return $c['city'];
}

// ================================================================ messages

function message_item(array $n): string
{
    $rate = $n['delivered'] ? round(100 * $n['opened'] / $n['delivered']) : null;
    $id = (int)$n['id'];
    $badges = ($n['active'] ? tag('live', 'ok') : tag('stopped'))
        . (($n['src'] ?? 'web') === 'app' ? ' ' . tag('from the app', 'violet') : '')
        . ($n['action'] === 'update' ? ' ' . tag('update reminder', 'accent') : '')
        . (!empty($n['follow_up']) ? ' ' . tag('follow-up', 'warn') : '');
    return '<li class="n-item"><a class="n-thumb" href="?p=notification&amp;id=' . $id . '" data-style="' . h($n['style']) . '">'
        . ($n['image_url'] !== '' ? '<img src="' . h($n['image_url']) . '" alt="" loading="lazy">' : '<span>' . (['celebrate' => '🎉', 'warning' => '📣'][$n['style']] ?? '🔔') . '</span>') . '</a>'
        . '<div class="n-main"><div class="n-top"><a class="n-title" href="?p=notification&amp;id=' . $id . '">' . h($n['title']) . '</a>' . $badges . '</div>'
        . '<div class="n-text">' . h($n['body']) . '</div>'
        . '<div class="n-meta">#' . $id . ' · ' . ist($n['starts_at'], 'd M Y, H:i') . ' · ' . h(rp_audience_label($n)) . ' · ' . h(NOTIFY_SHOW[$n['show_as']] ?? $n['show_as']) . '</div>'
        . '<div class="n-stats"><span><b>' . num($n['delivered']) . '</b> reached</span><span><b>' . num($n['opened']) . '</b> opened' . ($rate !== null ? ' (' . $rate . '%)' : '') . '</span><span><b>' . num($n['dismissed']) . '</b> closed</span></div>'
        . '</div></li>';
}

function view_messages(PDO $pdo): string
{
    $tab = isset(RP_MESSAGE_TABS[$_GET['t'] ?? '']) ? $_GET['t'] : 'all';
    $pg = max(1, (int)($_GET['n'] ?? 1));
    $m = rp_messages($pdo, $tab, $pg);
    $rem = rp_update_reminder($pdo);
    echo page_head('Messages', 'Popups in the app and phone notifications. Phones pick new ones up when the app opens, and every 30 minutes while it runs.',
        '<a class="btn" href="?p=notify_new&amp;preset=update">' . icon('releases', 15) . ' Update reminder</a><a class="btn primary" href="?p=notify_new">' . icon('plus', 15) . ' New message</a>');
    if ($rem['latest'] && $rem['behind'] > 0) {
        echo '<div class="callout"><div><b>' . num($rem['behind']) . ' of ' . num($rem['active_phones']) . ' active phones aren’t on ' . h($rem['latest']['version']) . ' yet</b>'
            . '<p>Send a reminder that only goes to apps older than the latest version, with an “Update now” button.</p></div>'
            . '<a class="btn primary" href="?p=notify_new&amp;preset=update">' . icon('send', 15) . ' Remind them</a></div>';
    }
    $counts = $m['counts'];
    $labels = RP_MESSAGE_TABS;
    if (!$m['has_source']) unset($labels['web'], $labels['app']);
    echo tabs($labels, $tab, fn($k) => '?p=notifications&t=' . $k, $counts);
    if (!$m['has_source'] && in_array($tab, ['web', 'app'], true)) echo '<p class="muted">Run migrations/2026-10-03-messages.sql to split messages by where they were sent from.</p>';
    echo '<section class="card">';
    if (!$m['list']) echo '<p class="empty">Nothing here yet.</p>';
    echo '<ul class="n-list">' . implode('', array_map('message_item', $m['list'])) . '</ul>';
    $pages = (int)ceil($m['total'] / $m['per']);
    if ($pages > 1) {
        echo '<div class="pager">' . ($pg > 1 ? '<a class="btn sm" href="?p=notifications&amp;t=' . h($tab) . '&amp;n=' . ($pg - 1) . '">← Newer</a>' : '<span></span>')
            . '<span class="muted small">Page ' . $pg . ' of ' . $pages . '</span>'
            . ($pg < $pages ? '<a class="btn sm" href="?p=notifications&amp;t=' . h($tab) . '&amp;n=' . ($pg + 1) . '">Older →</a>' : '<span></span>') . '</div>';
    }
    echo '</section>';
    return 'Messages';
}

function view_message_new(PDO $pdo): string
{
    $copy = null;
    if (isset($_GET['copy'])) $copy = rp_rows($pdo, 'SELECT * FROM notifications WHERE id = ?', [(int)$_GET['copy']])[0] ?? null;
    $rem = rp_update_reminder($pdo);
    $isUpdate = ($_GET['preset'] ?? '') === 'update';
    if ($isUpdate && $rem['latest']) {
        $copy = ['title' => $rem['title'], 'body' => $rem['body'], 'image_url' => '', 'style' => 'celebrate', 'show_as' => 'both', 'action' => 'update',
            'action_label' => 'Update now', 'action_value' => '', 'audience' => 'outdated', 'audience_build' => ''];
    }
    $v = fn(string $k, string $default = '') => h($copy[$k] ?? $default);
    $sel = fn(string $k, string $opt, string $default) => (($copy[$k] ?? $default) === $opt) ? ' selected' : '';
    $sub = $isUpdate
        ? ($rem['latest'] ? 'Goes only to apps older than ' . h($rem['latest']['version']) . ' (about ' . num($rem['behind']) . ' active phones). Edit the words if you like.' : 'Publish a version first.')
        : ($copy ? 'Copied from “' . h($copy['title']) . '”. Sending creates a new message; the original stays as it was.' : 'Write it once; see how it looks on the right.');
    echo page_head($isUpdate ? 'Update reminder' : ($copy ? 'Edit as a new message' : 'New message'), $sub, '', '?p=notifications');
    $latestNote = $rem['latest'] ? ' (' . h($rem['latest']['version']) . ', ' . num($rem['behind']) . ' phones)' : '';
    ?>
    <div class="compose">
      <section class="card">
        <form method="post" action="?p=notifications" class="form" id="notify-form"><?= csrf_field() ?><input type="hidden" name="do" value="notify_save">
          <?php if (isset($_GET['copy'])): ?><input type="hidden" name="copy" value="<?= (int)$_GET['copy'] ?>"><?php endif; ?>
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
            <label>Who gets it<select name="audience" id="audience"><?php foreach (NOTIFY_AUDIENCE as $k => $l): ?><option value="<?= $k ?>"<?= $sel('audience', $k, 'all') ?>><?= $l ?><?= $k === 'outdated' ? $latestNote : '' ?></option><?php endforeach; ?></select></label>
            <label id="audience-build">Older than build<input name="audience_build" type="number" min="1" value="<?= $v('audience_build') ?>"></label>
          </div>
          <div class="row2">
            <label>Start <small>(IST, empty = now)</small><input name="starts_at" type="datetime-local"></label>
            <label>Stop <small>(IST, optional)</small><input name="ends_at" type="datetime-local"></label>
          </div>
          <div><button class="btn primary"><?= icon('send', 15) ?> Send</button></div>
        </form>
      </section>
      <div class="sticky"><section class="card"><header class="card-h"><h2>How it looks in the app</h2></header>
        <div id="live-preview"><?= notify_preview(['title' => $copy['title'] ?? 'Title', 'body' => $copy['body'] ?? 'Message', 'image_url' => $copy['image_url'] ?? '', 'style' => $copy['style'] ?? 'info', 'action' => $copy['action'] ?? 'none', 'action_label' => $copy['action_label'] ?? '']) ?></div>
      </section></div>
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
    return 'New message';
}

function view_message(PDO $pdo, int $id): string
{
    $n = rp_rows($pdo, 'SELECT n.*, ' . (rp_v21($pdo) ? 'n.source' : "'web'") . " AS src, COUNT(r.device_id) AS delivered, COALESCE(SUM(r.opened_at IS NOT NULL), 0) AS opened,
                               COALESCE(SUM(r.dismissed_at IS NOT NULL), 0) AS dismissed
                        FROM notifications n LEFT JOIN notification_receipts r ON r.notification_id = n.id WHERE n.id = ? GROUP BY n.id", [$id])[0] ?? null;
    if (!$n) {
        echo page_head('Not found', '', '', '?p=notifications');
        return 'Not found';
    }
    $d = (int)$n['delivered'];
    $silent = max(0, $d - (int)$n['opened'] - (int)$n['dismissed']);
    $pct = fn($x) => $d ? round(100 * $x / $d) : 0;
    $by = rp_scalar($pdo, 'SELECT email FROM admins WHERE id = ?', [(int)$n['created_by']]);
    $copies = rp_rows($pdo, 'SELECT id, starts_at FROM notifications WHERE id <> ? AND title = ? AND body = ? ORDER BY id DESC LIMIT 8', [$id, $n['title'], $n['body']]);
    $counts = rp_follow_up_counts($pdo, $n);
    $v21 = rp_v21($pdo);

    echo page_head(h($n['title']) . ' ' . ($n['active'] ? tag('live', 'ok') : tag('stopped')), '#' . $id . ' · sent ' . ist($n['starts_at']) . ' by ' . h($by ?: 'unknown') . (($n['src'] ?? 'web') === 'app' ? ' from the app' : ''),
        '<a class="btn" href="?p=notify_new&amp;copy=' . $id . '">Edit as new</a>' . post_button('notify_toggle', $n['active'] ? 'Stop' : 'Resume', ['id' => $id], 'btn', '', 'notifications')
        . post_button('notify_delete', 'Delete', ['id' => $id], 'btn danger', 'Delete this message and its numbers for good?', 'notifications'), '?p=notifications');
    echo '<div class="g2">';
    echo card_open('How it did') . '<div class="funnel">'
        . '<div><span>Reached phones</span><b>' . num($d) . '</b><i style="width:100%"></i></div>'
        . '<div><span>Opened</span><b>' . num($n['opened']) . ' <small>' . $pct($n['opened']) . '%</small></b><i style="width:' . $pct($n['opened']) . '%"></i></div>'
        . '<div><span>Closed</span><b>' . num($n['dismissed']) . ' <small>' . $pct($n['dismissed']) . '%</small></b><i class="c" style="width:' . $pct($n['dismissed']) . '%"></i></div>'
        . '<div><span>No answer yet</span><b>' . num($silent) . ' <small>' . $pct($silent) . '%</small></b><i class="s" style="width:' . $pct($silent) . '%"></i></div>'
        . '</div><dl class="kv" style="margin-top:18px">'
        . '<dt>To</dt><dd>' . h(rp_audience_label($n)) . '</dd>'
        . '<dt>Shown as</dt><dd>' . h(NOTIFY_SHOW[$n['show_as']] ?? $n['show_as']) . '</dd>'
        . '<dt>Button</dt><dd>' . h(NOTIFY_ACTIONS[$n['action']] ?? $n['action']) . ($n['action_value'] !== '' ? ': ' . h($n['action_value']) : '') . '</dd>'
        . '<dt>Stops</dt><dd>' . ($n['ends_at'] ? ist($n['ends_at']) : 'When you stop it') . '</dd>'
        . ($copies ? '<dt>Also sent</dt><dd>' . implode(', ', array_map(fn($c) => '<a href="?p=notification&amp;id=' . (int)$c['id'] . '">' . ist($c['starts_at'], 'd M, H:i') . '</a>', $copies)) . '</dd>' : '')
        . '</dl></section>';
    echo card_open('How it looks in the app') . notify_preview($n) . '</section>';
    echo '</div>';

    // Send it again: to everyone, or only to the people it didn't reach or didn't move.
    $opts = ['missed' => [$counts['missed'], 'Phones that match who it was for but never got it: new installs, and people who haven’t opened the app since.'],
        'unopened' => [$counts['unopened'], 'Phones that got it but closed it or never answered.']];
    if ($n['action'] === 'update') $opts = ['outdated' => [$counts['outdated'], 'Apps still older than the newest version, whatever they did with this message.']] + $opts;
    $opts['all'] = [$counts['all'], 'A fresh copy for everyone it was meant for, even people who already opened it.'];
    echo '<section class="card section"><header class="card-h"><h2>Send it again <small>as a new message; this one stops, so nobody gets it twice, and keeps its numbers</small></h2></header><div class="g' . (count($opts) === 4 ? '2' : '3') . '">';
    foreach ($opts as $who => [$count, $desc]) {
        $needs = ($who === 'missed' || $who === 'unopened') && !$v21;
        echo '<div class="card" style="background:var(--surface2)"><b>' . h(RP_FOLLOW_UPS[$who]) . '</b><p class="small muted" style="margin:6px 0 12px">' . h($desc) . '</p>'
            . '<div style="display:flex;align-items:center;justify-content:space-between;gap:10px"><span><b class="num">' . num($count) . '</b> <span class="muted small">phones' . ($who === 'unopened' ? '' : ' (active in 30 days)') . '</span></span>'
            . ($needs ? '<span class="muted small">Needs the database update</span>'
                : post_button('notify_resend', icon('send', 14) . ' Send', ['id' => $id, 'who' => $who], $who === array_key_first($opts) ? 'btn primary sm' : 'btn sm',
                    'Send “' . $n['title'] . '” again to: ' . mb_strtolower(RP_FOLLOW_UPS[$who]) . ' (about ' . $count . ' phones)?', 'notifications'))
            . '</div></div>';
    }
    echo '</div></section>';
    return $n['title'];
}

// ================================================================ app updates

function view_releases(PDO $pdo): string
{
    $a = rp_adoption($pdo);
    $list = rp_rows($pdo, "SELECT r.*, a.email AS by_email,
                                  (SELECT COUNT(*) FROM devices d WHERE d.app_build = r.build AND d.last_seen_at > UTC_TIMESTAMP() - INTERVAL 30 DAY) AS phones
                           FROM releases r LEFT JOIN admins a ON a.id = r.created_by ORDER BY r.build DESC");
    $right = '<a class="btn" href="?p=notify_new&amp;preset=update">' . icon('send', 15) . ' Remind older phones</a><a class="btn primary" href="?p=release_new">' . icon('plus', 15) . ' Publish a version</a>';
    echo page_head('App updates', 'Phones check here when the app opens and offer the newest published version with a higher build number.', $right);
    $l = $a['latest'];
    echo '<div class="kpis">'
        . kpi('Latest version', $l ? $l['version'] : '—', '', $l ? 'build ' . $l['build'] . ($l['required'] ? ' · required' : '') . ' · ' . h(ago($l['published_at'])) : 'nothing published')
        . kpi('On the latest', $a['on_latest_pct'] . '%', '', num($a['on_latest']) . ' of ' . num($a['active_phones']) . ' active phones')
        . kpi('Still to update', num($a['behind']), '', 'phones seen in 30 days')
        . kpi('Versions in use', num(count($a['versions'])))
        . '</div>';
    echo '<div class="g-wide section">';
    echo card_open('Versions in use', 'active phones, last 30 days') . chart(['type' => 'bar', 'horizontal' => true,
            'labels' => array_map(fn($v) => $v['version'] . ($v['latest'] ? ' (latest)' : ''), $a['versions']),
            'series' => [['label' => 'Phones', 'data' => array_column($a['versions'], 'phones'), 'color' => '--accent']]], max(160, 46 * count($a['versions']) + 40)) . '</section>';
    echo card_open('Share by version') . chart(['type' => 'doughnut', 'labels' => array_column($a['versions'], 'version'),
            'series' => [['label' => 'Phones', 'data' => array_column($a['versions'], 'phones'), 'color' => ['--accent', '--accent2', '--violet', '--guest', '--ok', '--warn']]]], 200) . '</section>';
    echo '</div>';
    echo card_open('Published versions', '', '', 'section') . '<div class="tbl-wrap"><table><thead><tr><th>Version</th><th>Status</th><th class="r">Phones on it</th><th class="hide-sm">Published</th><th></th></tr></thead><tbody>';
    foreach ($list as $r) {
        echo '<tr><td><b>' . h($r['version_name']) . '</b> <span class="muted small">build ' . (int)$r['build'] . '</span>' . ($r['required'] ? ' ' . tag('required', 'warn') : '')
            . '<div class="small muted"><a href="' . h($r['apk_url']) . '" rel="noreferrer">APK</a>' . ($r['size_bytes'] ? ' · ' . round($r['size_bytes'] / 1048576, 1) . ' MB' : '') . '</div></td>'
            . '<td>' . ($r['published'] ? tag('live', 'ok') : tag('draft')) . '</td><td class="r num">' . num($r['phones']) . '</td>'
            . '<td class="hide-sm muted nowrap">' . ist($r['published_at'] ?? $r['created_at'], 'd M Y') . '</td>'
            . '<td class="r nowrap">' . post_button('release_toggle', $r['published'] ? 'Unpublish' : 'Publish', ['id' => (int)$r['id']], 'btn sm', '', 'releases')
            . ' ' . post_button('release_delete', 'Delete', ['id' => (int)$r['id']], 'btn sm danger', 'Delete this version from the list?', 'releases') . '</td></tr>';
    }
    if (!$list) echo '<tr><td colspan="5" class="muted">Nothing published yet.</td></tr>';
    echo '</tbody></table></div></section>';
    return 'App updates';
}

function view_release_new(PDO $pdo): string
{
    $next = (int)rp_scalar($pdo, 'SELECT COALESCE(MAX(build), 8) + 1 FROM releases');
    $prefill = ['version' => '', 'notes' => '', 'apk_url' => '', 'sha256' => ''];
    if (isset($_GET['github'])) $prefill = github_latest() + $prefill;
    echo page_head('Publish a version', 'Phones offer it the next time they open the app. Tick “Required” for updates people can’t skip.',
        '<a class="btn" href="?p=release_new&amp;github=1">Fill in from GitHub</a>', '?p=releases');
    ?>
    <section class="card narrow">
      <form method="post" action="?p=releases" enctype="multipart/form-data" class="form"><?= csrf_field() ?><input type="hidden" name="do" value="release_save">
        <div class="row2"><label>Version<input name="version" required pattern="\d+\.\d+\.\d+" placeholder="1.4.0" value="<?= h($prefill['version']) ?>"></label>
          <label>Build number<input name="build" type="number" min="1" required value="<?= $next ?>"></label></div>
        <label>What's new<textarea name="notes" rows="8" placeholder="- **Bold lead.** What changed."><?= h($prefill['notes']) ?></textarea></label>
        <label>APK file <small>(uploads to this server; or use a link below)</small><input type="file" name="apk" accept=".apk"></label>
        <label>APK link<input name="apk_url" type="url" placeholder="https://github.com/loco0011/samgeet/releases/download/v1.4.0/Samgeet.apk" value="<?= h($prefill['apk_url']) ?>"></label>
        <label>SHA-256 <small>(worked out for you when you upload)</small><input name="sha256" pattern="[a-fA-F0-9]{64}" value="<?= h($prefill['sha256']) ?>"></label>
        <label class="check"><input type="checkbox" name="required" value="1"> Required update (no “Later” button)</label>
        <label class="check"><input type="checkbox" name="publish" value="1" checked> Publish now</label>
        <div><button class="btn primary">Save</button></div>
      </form>
    </section>
    <?php
    return 'Publish a version';
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

// ================================================================ data and account

function view_export(): string
{
    $types = ['play_start', 'play_end', 'like', 'unlike', 'download', 'share_song', 'share_playlist', 'search', 'playlist_create', 'playlist_add', 'app_open', 'sign_in', 'player_style', 'device_info', 'notification_open'];
    echo page_head('Export data', 'Every event in a date range as CSV (opens in Excel or Google Sheets), with the account, phone and song details.');
    ?>
    <section class="card narrow">
      <form method="get" class="form"><input type="hidden" name="p" value="export">
        <div class="row2"><label>From<input type="date" name="from" required value="<?= h(date('Y-m-d', time() - 7 * 86400)) ?>"></label>
          <label>To<input type="date" name="to" required value="<?= h(date('Y-m-d')) ?>"></label></div>
        <div><div class="small muted" style="margin-bottom:8px">Types <span>(leave all unticked for everything)</span></div>
          <div class="checks"><?php foreach ($types as $t): ?><label class="check"><input type="checkbox" name="types[]" value="<?= h($t) ?>"> <?= h($t) ?></label><?php endforeach; ?></div></div>
        <div><button class="btn primary"><?= icon('export', 15) ?> Download CSV</button></div>
      </form>
    </section>
    <?php
    return 'Export';
}

function view_account(array $admin): string
{
    echo page_head('My account', 'Signed in as ' . h($admin['email']) . '. The same email and password open the admin tools in the app (Settings → tap the version line 7 times).');
    ?>
    <section class="card narrow">
      <header class="card-h"><h2>Change password</h2></header>
      <form method="post" action="?p=account" class="form"><?= csrf_field() ?><input type="hidden" name="do" value="password">
        <label>Current password<input type="password" name="current" required autocomplete="current-password"></label>
        <label>New password <small>(12+ characters; signs the app's admin tools out too)</small><input type="password" name="new" required minlength="12" autocomplete="new-password"></label>
        <div><button class="btn primary">Change password</button></div>
      </form>
    </section>
    <?php
    return 'My account';
}
