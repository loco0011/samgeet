<?php
// The admin panel's layout and shared pieces: page frame with the sidebar, styles, and small
// components (stat cards, avatars, tags, ranked bars, charts, tabs) that every page uses, so pages
// look and behave the same. Loaded by admin/index.php only.

declare(strict_types=1);
if (!defined('SG_ADMIN')) exit;

function h($s): string
{
    return htmlspecialchars((string)$s, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
}

function num($n): string
{
    return number_format((float)$n);
}

function ist(?string $utc, string $fmt = 'd M Y, H:i'): string
{
    if (!$utc) return '—';
    $d = new DateTime($utc, new DateTimeZone('UTC'));
    $d->setTimezone(new DateTimeZone('Asia/Kolkata'));
    return $d->format($fmt);
}

/// "just now", "12 min ago", "3 h ago", "Yesterday", "4 d ago", then the date.
function ago(?string $utc): string
{
    if (!$utc) return 'Never';
    $s = time() - strtotime($utc . ' UTC');
    if ($s < 90) return 'Just now';
    if ($s < 3600) return round($s / 60) . ' min ago';
    if ($s < 86400) return round($s / 3600) . ' h ago';
    if ($s < 2 * 86400) return 'Yesterday';
    if ($s < 30 * 86400) return floor($s / 86400) . ' d ago';
    return ist($utc, 'd M Y');
}

/// Minutes as "45 min" or "12.5 h".
function mins(int $m): string
{
    return $m < 120 ? $m . ' min' : number_format($m / 60, 1) . ' h';
}

function url(array $q): string
{
    return '?' . h(http_build_query($q));
}

/// Line icons (24px grid, stroke) used in the sidebar and on buttons.
function icon(string $name, int $size = 18): string
{
    $p = [
        'overview' => '<path d="M3 13h8V3H3zM13 21h8V11h-8zM3 21h8v-6H3zM13 3v6h8V3z"/>',
        'listening' => '<path d="M3 18v-6a9 9 0 0 1 18 0v6"/><path d="M21 19a2 2 0 0 1-2 2h-1v-6h3zM3 19a2 2 0 0 0 2 2h1v-6H3z"/>',
        'users' => '<path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M23 21v-2a4 4 0 0 0-3-3.87M16 3.13a4 4 0 0 1 0 7.75"/>',
        'places' => '<path d="M21 10c0 7-9 13-9 13S3 17 3 10a9 9 0 0 1 18 0z"/><circle cx="12" cy="10" r="3"/>',
        'messages' => '<path d="M18 8A6 6 0 0 0 6 8c0 7-3 9-3 9h18s-3-2-3-9M13.73 21a2 2 0 0 1-3.46 0"/>',
        'releases' => '<path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4M7 10l5 5 5-5M12 15V3"/>',
        'export' => '<path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><path d="M14 2v6h6M8 13h8M8 17h8"/>',
        'account' => '<circle cx="12" cy="8" r="4"/><path d="M4 21a8 8 0 0 1 16 0"/>',
        'logout' => '<path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4M16 17l5-5-5-5M21 12H9"/>',
        'plus' => '<path d="M12 5v14M5 12h14"/>',
        'send' => '<path d="M22 2 11 13M22 2l-7 20-4-9-9-4z"/>',
        'back' => '<path d="M19 12H5M12 19l-7-7 7-7"/>',
        'arrow' => '<path d="M5 12h14M12 5l7 7-7 7"/>',
        'refresh' => '<path d="M23 4v6h-6M1 20v-6h6"/><path d="M3.51 9a9 9 0 0 1 14.85-3.36L23 10M1 14l4.64 4.36A9 9 0 0 0 20.49 15"/>',
        'phone' => '<rect x="5" y="2" width="14" height="20" rx="2"/><path d="M12 18h.01"/>',
        'search' => '<circle cx="11" cy="11" r="7"/><path d="m21 21-4.35-4.35"/>',
        'menu' => '<path d="M3 6h18M3 12h18M3 18h18"/>',
    ][$name] ?? '';
    return '<svg class="ic" width="' . $size . '" height="' . $size . '" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' . $p . '</svg>';
}

/// The round picture for a listener: their emoji, or initials on a colour picked from their id.
function avatar(array $p, int $size = 36): string
{
    $hue = [345, 18, 262, 200, 158, 32][((int)($p['id'] ?? 0)) % 6];
    $style = 'width:' . $size . 'px;height:' . $size . 'px;font-size:' . round($size * ($p['emoji'] !== '' ? .5 : .38)) . 'px;--h:' . $hue;
    return '<span class="av' . ($p['emoji'] !== '' ? ' emoji' : '') . '" style="' . $style . '">' . h($p['emoji'] !== '' ? $p['emoji'] : $p['initials']) . '</span>';
}

/// Avatar, name and a second line, linking to the listener's page.
function person(array $p, string $sub = '', int $size = 36): string
{
    return '<a class="person" href="?p=user&amp;id=' . (int)$p['id'] . '">' . avatar($p, $size)
        . '<span class="pn"><b>' . h($p['name']) . '</b>' . ($sub !== '' ? '<span>' . $sub . '</span>' : '') . '</span></a>';
}

function tag(string $text, string $kind = ''): string
{
    return '<span class="tag ' . $kind . '">' . h($text) . '</span>';
}

/// Last-seen as a coloured dot and words: green today, amber this week, grey after that.
function seen(?string $utc): string
{
    $s = $utc ? time() - strtotime($utc . ' UTC') : PHP_INT_MAX;
    $k = $s < 86400 ? 'on' : ($s < 7 * 86400 ? 'mid' : 'off');
    return '<span class="seen ' . $k . '"><i></i>' . h(ago($utc)) . '</span>';
}

/// "▲ 12%" against the previous period, or '' when there's nothing to compare with.
function change(float $now, ?float $before): string
{
    if ($before === null) return '';
    if ($before == 0) return $now > 0 ? '<span class="chg up">new</span>' : '';
    $p = round(100 * ($now - $before) / $before);
    if ($p == 0) return '<span class="chg">±0%</span>';
    return '<span class="chg ' . ($p > 0 ? 'up' : 'down') . '">' . ($p > 0 ? '▲ ' : '▼ ') . abs($p) . '%</span>';
}

/// A tiny line chart as inline SVG.
function spark(array $values, string $color = 'var(--accent)'): string
{
    $n = count($values);
    if ($n < 2) return '';
    $max = max(1, max($values));
    $pts = [];
    foreach (array_values($values) as $i => $v) $pts[] = round($i * 100 / ($n - 1), 1) . ',' . round(28 - 26 * $v / $max, 1);
    $line = implode(' ', $pts);
    return '<svg class="spark" viewBox="0 0 100 30" preserveAspectRatio="none" aria-hidden="true">'
        . '<polyline points="0,30 ' . $line . ' 100,30" fill="' . $color . '" fill-opacity=".1" stroke="none"/>'
        . '<polyline points="' . $line . '" fill="none" stroke="' . $color . '" stroke-width="1.6" vector-effect="non-scaling-stroke"/></svg>';
}

/// A headline number: label, value, change, a line under it and an optional sparkline.
function kpi(string $label, string $value, string $chg = '', string $sub = '', array $series = [], string $color = 'var(--accent)'): string
{
    return '<div class="kpi"><div class="kpi-top"><span>' . h($label) . '</span>' . $chg . '</div><div class="kpi-v">' . h($value) . '</div>'
        . ($sub !== '' ? '<div class="kpi-s">' . $sub . '</div>' : '') . spark($series, $color) . '</div>';
}

/// A card with a header (title, small note, optional link on the right).
function card_open(string $title, string $note = '', string $link = '', string $cls = ''): string
{
    return '<section class="card ' . $cls . '"><header class="card-h"><h2>' . h($title) . ($note !== '' ? ' <small>' . h($note) . '</small>' : '') . '</h2>' . $link . '</header>';
}

function more_link(string $href, string $text = 'See all'): string
{
    return '<a class="more" href="' . $href . '">' . h($text) . ' ' . icon('arrow', 14) . '</a>';
}

/// A ranked list where each row has a bar for its share of the top row.
function bars(array $rows, string $unit = '', ?callable $link = null): string
{
    if (!$rows) return '<p class="empty">Nothing yet.</p>';
    $max = max(1, max(array_map(fn($r) => (float)$r['n'], $rows)));
    $out = '<ol class="bars">';
    foreach ($rows as $row) {
        $w = max(2, round(100 * (float)$row['n'] / $max));
        $name = h($row['label']);
        if ($link) $name = '<a href="' . h($link($row)) . '">' . $name . '</a>';
        $out .= '<li><span class="b" style="width:' . $w . '%"></span><span class="l">' . $name . '</span><span class="v">' . num($row['n']) . h($unit) . '</span></li>';
    }
    return $out . '</ol>';
}

/// Top songs with cover, title, singer and plays.
function songs(array $list, string $empty = 'No plays yet.'): string
{
    if (!$list) return '<p class="empty">' . h($empty) . '</p>';
    $out = '<ol class="songs">';
    foreach ($list as $i => $t) {
        $out .= '<li><span class="rank">' . ($i + 1) . '</span>'
            . ($t['image'] ? '<img src="' . h($t['image']) . '" alt="" loading="lazy">' : '<span class="noimg">♪</span>')
            . '<span class="meta"><b>' . h($t['title']) . '</b><span>' . h($t['artist']) . '</span></span>'
            . '<span class="v">' . num($t['plays']) . (isset($t['listeners']) ? '<small>' . num($t['listeners']) . ' listening</small>' : '') . '</span></li>';
    }
    return $out . '</ol>';
}

/// A chart drawn by Chart.js from a small config (see the script in render_layout).
/// $cfg: type (bar|line|doughnut), labels, series [[label, data, color, type?, axis?]], stacked?, horizontal?, height?
function chart(array $cfg, int $height = 260): string
{
    return '<div class="chart" style="height:' . $height . 'px"><canvas data-chart="' . h(json_encode($cfg, JSON_UNESCAPED_UNICODE)) . '"></canvas></div>';
}

/// Links that switch between options (date ranges, filters, tabs); [counts] adds a number to each.
function tabs(array $options, string $current, callable $href, array $counts = [], string $cls = 'tabs'): string
{
    $out = '<nav class="' . $cls . '">';
    foreach ($options as $k => $label) {
        $c = array_key_exists($k, $counts) && $counts[$k] !== null ? '<i>' . num($counts[$k]) . '</i>' : '';
        $out .= '<a class="' . ((string)$k === $current ? 'on' : '') . '" href="' . h($href((string)$k)) . '">' . h($label) . $c . '</a>';
    }
    return $out . '</nav>';
}

function page_head(string $title, string $sub = '', string $right = '', string $back = ''): string
{
    return '<div class="page-head"><div>' . ($back !== '' ? '<a class="back" href="' . $back . '">' . icon('back', 15) . ' Back</a>' : '')
        . '<h1>' . $title . '</h1>' . ($sub !== '' ? '<p class="sub">' . $sub . '</p>' : '') . '</div>'
        . ($right !== '' ? '<div class="head-actions">' . $right . '</div>' : '') . '</div>';
}

function post_button(string $do, string $label, array $fields = [], string $cls = 'btn', string $confirm = '', string $page = ''): string
{
    $hidden = '';
    foreach ($fields as $k => $v) $hidden .= '<input type="hidden" name="' . h($k) . '" value="' . h($v) . '">';
    return '<form method="post" action="?p=' . h($page) . '" class="inline"' . ($confirm !== '' ? ' data-confirm="' . h($confirm) . '"' : '') . '>'
        . csrf_field() . $hidden . '<button class="' . $cls . '" name="do" value="' . h($do) . '">' . $label . '</button></form>';
}

// ---------------------------------------------------------------- frame

const NAV = [
    'Insights' => ['dashboard' => ['Overview', 'overview'], 'listening' => ['Listening', 'listening'], 'places' => ['Places', 'places']],
    'People' => ['users' => ['Listeners', 'users']],
    'Reach' => ['notifications' => ['Messages', 'messages'], 'releases' => ['App updates', 'releases']],
    'Data' => ['export' => ['Export', 'export']],
];

function head(string $title): void
{
    ?><!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="robots" content="noindex,nofollow"><title><?= h($title) ?></title>
<link rel="preconnect" href="https://fonts.googleapis.com"><link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@400;500;600;700;800&amp;family=Sora:wght@600;700;800&amp;display=swap" rel="stylesheet">
<style><?= styles() ?></style></head><?php
}

function render_login(?string $error): void
{
    head('Samgeet admin');
    ?><body><div class="login"><div class="card">
      <div class="brand" style="margin-bottom:22px"><i>♪</i><span>Samgeet<small>Admin</small></span></div>
      <form method="post" action="?p=login" class="form"><?= csrf_field() ?>
        <label>Email<input type="email" name="email" required autocomplete="username" autofocus></label>
        <label>Password<input type="password" name="password" required autocomplete="current-password"></label>
        <?php if ($error): ?><div class="err"><?= h($error) ?></div><?php endif; ?>
        <button class="btn primary">Sign in</button>
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

function render_layout(string $page, array $admin, ?string $flash, string $content, string $title): void
{
    global $nonce;
    $active = ['user' => 'users', 'place' => 'places', 'notification' => 'notifications', 'notify_new' => 'notifications', 'release_new' => 'releases'][$page] ?? $page;
    $current = '';
    foreach (NAV as $items) if (isset($items[$active])) $current = $items[$active][0];
    if ($active === 'account') $current = 'My account';
    head(($title !== '' ? $title . ' · ' : '') . 'Samgeet admin');
    ?><body>
    <div class="shell" id="shell">
      <aside class="side" id="side" aria-label="Main menu">
        <a class="brand" href="?p=dashboard"><i>♪</i><span>Samgeet<small>Admin</small></span></a>
        <nav class="side-nav">
          <?php foreach (NAV as $group => $items): ?>
            <div class="grp"><?= h($group) ?></div>
            <?php foreach ($items as $k => [$label, $ic]): ?>
              <a class="<?= $k === $active ? 'on' : '' ?>" href="?p=<?= $k ?>"><?= icon($ic) ?><span><?= h($label) ?></span></a>
            <?php endforeach; ?>
          <?php endforeach; ?>
        </nav>
        <div class="side-foot">
          <a class="me<?= $active === 'account' ? ' on' : '' ?>" href="?p=account"><?= icon('account') ?><span><?= h($admin['email']) ?></span></a>
          <form method="post" action="?p=logout"><?= csrf_field() ?><button class="btn ghost full"><?= icon('logout', 16) ?> Sign out</button></form>
        </div>
      </aside>
      <div class="scrim" id="scrim"></div>
      <div class="main">
        <header class="topbar">
          <button type="button" class="icon-btn" id="menu-btn" aria-label="Open menu" aria-controls="side" aria-expanded="false"><?= icon('menu', 20) ?></button>
          <a class="brand sm" href="?p=dashboard"><i>♪</i></a>
          <span class="here"><?= h($current) ?></span>
        </header>
        <main><?php if ($flash): ?><div class="flash"><?= h($flash) ?></div><?php endif; ?><?= $content ?></main>
      </div>
    </div>
    <script nonce="<?= h($nonce) ?>" src="https://cdnjs.cloudflare.com/ajax/libs/Chart.js/4.4.1/chart.umd.min.js"></script>
    <script nonce="<?= h($nonce) ?>">
      document.querySelectorAll('form[data-confirm]').forEach(f => f.addEventListener('submit', e => { if (!confirm(f.dataset.confirm)) e.preventDefault(); }));
      // Phone menu: the sidebar slides in; tapping outside or pressing Esc closes it.
      (function () {
        const shell = document.getElementById('shell'), btn = document.getElementById('menu-btn');
        const set = open => { shell.classList.toggle('menu-open', open); btn.setAttribute('aria-expanded', String(open)); };
        btn.addEventListener('click', () => set(!shell.classList.contains('menu-open')));
        document.getElementById('scrim').addEventListener('click', () => set(false));
        document.addEventListener('keydown', e => { if (e.key === 'Escape') set(false); });
      })();
      // Rows that open a page when clicked anywhere (links inside still work on their own).
      document.querySelectorAll('tr[data-href]').forEach(tr => tr.addEventListener('click', e => { if (!e.target.closest('a,button,form')) location.href = tr.dataset.href; }));
      // Charts: every <canvas data-chart> is drawn from its config.
      (function () {
        if (!window.Chart) return;
        const css = getComputedStyle(document.documentElement), v = k => css.getPropertyValue(k).trim();
        const col = c => c.startsWith('--') ? v(c) : c;
        Chart.defaults.color = v('--muted'); Chart.defaults.borderColor = v('--line');
        Chart.defaults.font.family = 'Plus Jakarta Sans, system-ui, sans-serif'; Chart.defaults.font.size = 11.5;
        Chart.defaults.plugins.legend.labels.boxWidth = 10; Chart.defaults.plugins.legend.labels.boxHeight = 10;
        Chart.defaults.plugins.tooltip.backgroundColor = v('--surface2'); Chart.defaults.plugins.tooltip.borderColor = v('--line');
        Chart.defaults.plugins.tooltip.borderWidth = 1; Chart.defaults.plugins.tooltip.padding = 10; Chart.defaults.plugins.tooltip.titleColor = v('--ink');
        Chart.defaults.animation = false;
        const draw = () => document.querySelectorAll('canvas[data-chart]').forEach(cv => {
          const c = JSON.parse(cv.dataset.chart);
          const dough = c.type === 'doughnut';
          const sets = c.series.map(s => {
            const color = Array.isArray(s.color) ? s.color.map(col) : col(s.color);
            const line = (s.type || c.type) === 'line';
            return { type: s.type || c.type, label: s.label, data: s.data, backgroundColor: line ? color : color, borderColor: dough ? v('--surface') : color,
              borderWidth: line ? 2 : (dough ? 3 : 0), borderRadius: dough ? 0 : 4, tension: .35, pointRadius: 0, pointHoverRadius: 4,
              fill: !!s.fill, yAxisID: s.axis || 'y', stack: c.stacked ? 's' : undefined, maxBarThickness: 34 };
          });
          const opts = { maintainAspectRatio: false, interaction: { mode: dough ? 'nearest' : 'index', intersect: dough },
            plugins: { legend: { display: sets.length > 1 || dough, position: dough ? 'right' : 'top', align: 'end' } } };
          if (!dough) {
            const ix = c.horizontal ? 'y' : 'x', iy = c.horizontal ? 'x' : 'y';
            opts.indexAxis = ix;
            opts.scales = { [ix]: { stacked: !!c.stacked, grid: { display: false } }, [iy]: { stacked: !!c.stacked, beginAtZero: true, ticks: { precision: 0 } } };
            if (sets.some(s => s.yAxisID === 'y1')) opts.scales.y1 = { beginAtZero: true, position: 'right', grid: { display: false }, ticks: { precision: 0 } };
          } else { opts.cutout = '68%'; }
          new Chart(cv, { type: c.type, data: { labels: c.labels, datasets: sets }, options: opts });
        });
        // Draw once the web fonts are in, so axis labels are measured with the right font.
        (document.fonts && document.fonts.ready ? document.fonts.ready : Promise.resolve()).then(draw);
      })();
    </script><?php password_toggles(); ?></body></html><?php
}

/// How a message looks in the app (the same card as the popup).
function notify_preview(array $n): string
{
    $icon = ['celebrate' => '🎉', 'warning' => '📣'][$n['style']] ?? '🔔';
    $img = ($n['image_url'] ?? '') !== '' ? '<img src="' . h($n['image_url']) . '" alt="" loading="lazy">' : '<span class="pv-ic">' . $icon . '</span>';
    $label = ($n['action_label'] ?? '') !== '' ? $n['action_label'] : (['update' => 'Update now', 'search' => 'Search', 'url' => 'Open'][$n['action'] ?? ''] ?? 'Got it');
    return '<div class="pv" data-style="' . h($n['style']) . '"><div class="pv-head">' . $img . '</div><div class="pv-body"><span class="pv-badge">FROM SAMGEET</span>'
        . '<b>' . h($n['title']) . '</b><p>' . nl2br(h($n['body'])) . '</p><span class="pv-cta">' . h($label) . '</span></div></div>';
}

function styles(): string
{
    return <<<'CSS'
:root{--bg:#06060c;--surface:#0e0e17;--surface2:#171724;--surface3:#1f1f2f;--line:rgba(255,255,255,.08);--line2:rgba(255,255,255,.14);
--ink:#f1f1f7;--muted:#9a9db8;--faint:#6c6f88;--guest:#5b6b9a;--accent:#d0284f;--accent2:#e0823f;--violet:#8f8cf0;
--ok:#3fb27f;--warn:#e0a33f;--danger:#e2475b;--r:16px;color-scheme:dark}
*{box-sizing:border-box}html,body{margin:0}
body{background:var(--bg);color:var(--ink);font:14px/1.5 'Plus Jakarta Sans',system-ui,sans-serif;-webkit-font-smoothing:antialiased}
a{color:inherit;text-decoration:none}a:hover{color:#fff}
h1{font:700 24px/1.2 Sora,system-ui,sans-serif;letter-spacing:-.4px;margin:0}
h2{font:600 14px/1.3 Sora,system-ui,sans-serif;margin:0;letter-spacing:-.1px}h2 small{color:var(--muted);font:500 12px 'Plus Jakarta Sans',sans-serif;margin-left:4px}
.ic{flex:none;display:block}

/* frame */
.shell{display:grid;grid-template-columns:244px minmax(0,1fr);min-height:100vh}
.side{position:sticky;top:0;height:100vh;display:flex;flex-direction:column;gap:8px;padding:18px 14px;border-right:1px solid var(--line);background:#09090f;overflow-y:auto}
.brand{display:flex;align-items:center;gap:11px;padding:4px 8px 14px}
.brand i{width:34px;height:34px;border-radius:10px;background:linear-gradient(135deg,#7a1232,#d0284f 55%,#e0823f);display:grid;place-items:center;font-style:normal;color:#fff;font-size:17px;flex:none}
.brand span{display:flex;flex-direction:column;font:700 16px/1.15 Sora,sans-serif}.brand small{font:600 11px 'Plus Jakarta Sans',sans-serif;color:var(--muted);letter-spacing:.4px}
.side-nav{display:flex;flex-direction:column;gap:2px;flex:1}
.grp{font:700 10.5px 'Plus Jakarta Sans',sans-serif;letter-spacing:1.1px;text-transform:uppercase;color:var(--faint);padding:14px 10px 6px}
.side-nav a,.side-foot .me{display:flex;align-items:center;gap:11px;padding:9px 10px;border-radius:10px;color:var(--muted);font-weight:600;position:relative}
.side-nav a:hover,.side-foot .me:hover{background:var(--surface);color:var(--ink)}
.side-nav a.on,.side-foot .me.on{background:var(--surface2);color:var(--ink)}
.side-nav a.on::before{content:"";position:absolute;left:-14px;top:8px;bottom:8px;width:3px;border-radius:0 3px 3px 0;background:var(--accent)}
.side-nav a.on .ic{color:var(--accent)}
.side-foot{border-top:1px solid var(--line);padding-top:12px;display:grid;gap:8px}.side-foot .me span{overflow:hidden;text-overflow:ellipsis;white-space:nowrap;font-size:13px}
.side-foot form{margin:0}
.main{min-width:0}
.topbar{display:none}
main{max-width:1280px;margin:0 auto;padding:28px 32px 64px}
.scrim{display:none}

/* page head */
.page-head{display:flex;align-items:flex-end;justify-content:space-between;gap:16px 24px;flex-wrap:wrap;margin-bottom:22px}
.page-head>div:first-child{min-width:0}
.sub{color:var(--muted);margin:5px 0 0;font-size:13px}
.head-actions{display:flex;gap:8px;flex-wrap:wrap;align-items:center}
.back{display:inline-flex;align-items:center;gap:6px;color:var(--muted);font-weight:600;font-size:13px;margin-bottom:10px}

/* buttons */
.btn{display:inline-flex;align-items:center;justify-content:center;gap:7px;font:600 13px 'Plus Jakarta Sans',sans-serif;cursor:pointer;border-radius:10px;padding:8px 14px;
border:1px solid var(--line2);background:var(--surface2);color:var(--ink);white-space:nowrap;line-height:1.3}
.btn:hover{border-color:rgba(255,255,255,.28);color:#fff}
.btn.primary{background:linear-gradient(135deg,#a61f2e,#d0284f 60%,#e0823f);border-color:transparent;color:#fff}
.btn.primary:hover{filter:brightness(1.08)}
.btn.soft{background:rgba(208,40,79,.14);border-color:rgba(255,92,127,.35);color:#ffc2cf}
.btn.ghost{background:transparent}.btn.danger{color:var(--danger)}.btn.full{width:100%}.btn.sm{padding:5px 10px;font-size:12px;border-radius:8px}
button{font:inherit}
form.inline{display:inline}

/* cards and grids */
.card{background:var(--surface);border:1px solid var(--line);border-radius:var(--r);padding:18px 20px;min-width:0}
.card-h{display:flex;align-items:center;justify-content:space-between;gap:12px;margin-bottom:14px}
.more{display:inline-flex;align-items:center;gap:5px;color:var(--muted);font-weight:600;font-size:12.5px;white-space:nowrap}.more:hover{color:var(--ink)}
.stack{display:grid;gap:16px}
.g2{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:16px}
.g3{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:16px}
.g-wide{display:grid;grid-template-columns:minmax(0,2fr) minmax(0,1fr);gap:16px}
.section{margin-top:16px}
.section-title{font:700 11px 'Plus Jakarta Sans',sans-serif;letter-spacing:1.1px;text-transform:uppercase;color:var(--faint);margin:30px 0 12px}

/* KPIs */
.kpis{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:16px}
.kpis.five{grid-template-columns:repeat(5,minmax(0,1fr))}.kpis.six{grid-template-columns:repeat(6,minmax(0,1fr))}
.kpi{position:relative;overflow:hidden;background:var(--surface);border:1px solid var(--line);border-radius:var(--r);padding:16px 18px 18px;min-width:0}
.kpi:has(.spark){padding-bottom:50px}
.kpi-top{display:flex;justify-content:space-between;align-items:center;gap:8px;color:var(--muted);font-weight:600;font-size:12.5px}
.kpi-v{font:700 28px/1.15 Sora,sans-serif;letter-spacing:-.8px;margin-top:8px;font-variant-numeric:tabular-nums}
.kpi-s{color:var(--muted);font-size:12px;margin-top:3px}
.spark{position:absolute;left:0;right:0;bottom:0;width:100%;height:40px}
.chg{font-size:11px;font-weight:700;padding:2px 7px;border-radius:20px;background:var(--surface2);color:var(--muted);white-space:nowrap}
.chg.up{color:var(--ok);background:rgba(63,178,127,.12)}.chg.down{color:var(--danger);background:rgba(226,71,91,.12)}
.strip{display:grid;grid-template-columns:repeat(6,minmax(0,1fr));background:var(--surface);border:1px solid var(--line);border-radius:var(--r);margin-top:16px}
.strip>div{padding:14px 18px;border-left:1px solid var(--line)}.strip>div:first-child{border-left:0}
.strip b{display:block;font:700 19px Sora,sans-serif;font-variant-numeric:tabular-nums}.strip span{color:var(--muted);font-size:12px}
.strip b.live{display:flex;align-items:center;gap:8px}.live::before{content:"";width:7px;height:7px;border-radius:50%;background:var(--ok);box-shadow:0 0 0 3px rgba(63,178,127,.2)}

/* tabs and ranges */
.tabs,.seg{display:flex;gap:4px;flex-wrap:wrap}
.seg{background:var(--surface);border:1px solid var(--line);border-radius:11px;padding:3px;flex-wrap:nowrap}
.seg a{padding:6px 12px;border-radius:8px;color:var(--muted);font-weight:600;font-size:12.5px;white-space:nowrap}.seg a:hover{color:var(--ink)}
.seg a.on{background:var(--surface3);color:var(--ink);box-shadow:inset 0 0 0 1px var(--line2)}
.tabs{border-bottom:1px solid var(--line);gap:2px;margin-bottom:16px;flex-wrap:nowrap;overflow-x:auto}
.tabs a{padding:10px 12px;color:var(--muted);font-weight:600;border-bottom:2px solid transparent;margin-bottom:-1px;white-space:nowrap;display:flex;align-items:center;gap:7px}
.tabs a.on{color:var(--ink);border-color:var(--accent)}
.tabs i,.seg i{font-style:normal;font-size:11px;font-weight:700;background:var(--surface2);color:var(--muted);padding:1px 7px;border-radius:20px}
.tabs a.on i{background:rgba(208,40,79,.18);color:#ffb3c2}

/* lists */
ol.songs{list-style:none;margin:0;padding:0}ol.songs li{display:flex;align-items:center;gap:12px;padding:8px 0;border-bottom:1px solid var(--line)}ol.songs li:last-child{border:0}
.rank{width:16px;flex:none;color:var(--faint);font-weight:700;text-align:right;font-size:12px}
ol.songs img,.noimg{width:38px;height:38px;border-radius:9px;object-fit:cover;flex:none}.noimg{display:grid;place-items:center;background:var(--surface2);color:var(--muted)}
.meta{flex:1;min-width:0;display:flex;flex-direction:column}.meta b,.meta span{white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.meta b{font-weight:600}.meta span{color:var(--muted);font-size:12.5px}
ol.songs .v{text-align:right;font-weight:700;display:flex;flex-direction:column;font-variant-numeric:tabular-nums}ol.songs .v small{color:var(--muted);font-weight:500;font-size:11px}
ol.bars{list-style:none;margin:0;padding:0;display:grid;gap:4px}ol.bars li{position:relative;display:flex;justify-content:space-between;gap:10px;padding:7px 10px;border-radius:8px;overflow:hidden}
.bars .b{position:absolute;left:0;top:0;bottom:0;background:var(--accent);opacity:.16;border-radius:8px}.bars .l{position:relative;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.bars .v{position:relative;font-weight:700;font-variant-numeric:tabular-nums}.bars a:hover{text-decoration:underline}
.empty{color:var(--muted);margin:0;padding:6px 0}
ul.plain{list-style:none;margin:0;padding:0}ul.plain li{display:flex;justify-content:space-between;align-items:center;gap:10px;padding:9px 0;border-bottom:1px solid var(--line)}ul.plain li:last-child{border:0}
dl.kv{display:grid;grid-template-columns:auto 1fr;gap:10px 16px;margin:0}dl.kv dt{color:var(--muted)}dl.kv dd{margin:0;text-align:right;font-weight:600;font-variant-numeric:tabular-nums;min-width:0;overflow-wrap:anywhere}
.dot{display:inline-block;width:8px;height:8px;border-radius:50%;margin-right:8px;vertical-align:1px}
.chips{display:flex;flex-wrap:wrap;gap:6px}.chip{padding:4px 10px;border-radius:20px;background:var(--surface2);border:1px solid var(--line);font-size:12.5px;font-weight:600}

/* people */
.av{display:inline-grid;place-items:center;border-radius:50%;flex:none;font-weight:700;color:#fff;letter-spacing:-.3px;
background:linear-gradient(135deg,hsl(var(--h) 60% 42%),hsl(calc(var(--h) + 30) 70% 32%));line-height:1}
.av.emoji{background:var(--surface2);box-shadow:inset 0 0 0 1px var(--line2)}
.person{display:flex;align-items:center;gap:11px;min-width:0}.pn{display:flex;flex-direction:column;min-width:0}
.pn b{font-weight:600;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.pn span{color:var(--muted);font-size:12px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
a.person:hover b{text-decoration:underline}
.seen{display:inline-flex;align-items:center;gap:7px;white-space:nowrap}.seen i{width:7px;height:7px;border-radius:50%;background:var(--faint)}
.seen.on i{background:var(--ok)}.seen.mid i{background:var(--warn)}
.tag{display:inline-block;padding:1px 8px;border-radius:20px;font-size:11px;font-weight:700;background:var(--surface2);color:var(--muted);white-space:nowrap;vertical-align:middle}
.tag.ok{background:rgba(63,178,127,.14);color:var(--ok)}.tag.warn{background:rgba(224,163,63,.14);color:var(--warn)}
.tag.danger{background:rgba(226,71,91,.14);color:var(--danger)}.tag.accent{background:rgba(208,40,79,.16);color:#ff9db3}.tag.violet{background:rgba(143,140,240,.16);color:#b9b7ff}

/* tables */
.tbl-wrap{overflow-x:auto;margin:0 -20px;padding:0 20px}
table{width:100%;border-collapse:collapse}
th{text-align:left;color:var(--faint);font:700 10.5px 'Plus Jakarta Sans',sans-serif;letter-spacing:.8px;text-transform:uppercase;padding:0 10px 10px;white-space:nowrap}
td{padding:11px 10px;border-top:1px solid var(--line);vertical-align:middle}
th:first-child,td:first-child{padding-left:0}th:last-child,td:last-child{padding-right:0}
tr[data-href]{cursor:pointer}tr[data-href]:hover td{background:rgba(255,255,255,.02)}
.r{text-align:right}.nowrap{white-space:nowrap}.muted{color:var(--muted)}.small{font-size:12px}.num{font-variant-numeric:tabular-nums}
.toolbar{display:flex;gap:10px;align-items:center;justify-content:space-between;flex-wrap:wrap;margin-bottom:14px}
.search{display:flex;gap:8px;flex:1;max-width:420px}.search input{flex:1}
.pager{display:flex;justify-content:space-between;align-items:center;margin-top:14px;gap:10px}

/* profile */
.profile{display:flex;gap:20px;align-items:center;flex-wrap:wrap}
.profile .who{flex:1;min-width:220px}.profile h1{display:flex;align-items:center;gap:10px;flex-wrap:wrap}
.facts span{display:inline-flex;align-items:center;gap:5px}
.facts{display:flex;flex-wrap:wrap;gap:6px 18px;color:var(--muted);font-size:13px;margin-top:8px}.facts b{color:var(--ink);font-weight:600}
.timeline{list-style:none;margin:0;padding:0}.timeline li{display:grid;grid-template-columns:96px 1fr;gap:12px;padding:8px 0;border-top:1px solid var(--line)}
.timeline li:first-child{border:0}.timeline time{color:var(--muted);font-size:12px;font-variant-numeric:tabular-nums}.timeline .what b{font-weight:600}.timeline .what span{color:var(--muted)}

/* charts */
.chart{position:relative}

/* callouts */
.callout{display:flex;align-items:center;gap:16px;justify-content:space-between;flex-wrap:wrap;padding:16px 20px;border-radius:var(--r);
background:linear-gradient(135deg,rgba(208,40,79,.14),rgba(224,130,63,.08));border:1px solid rgba(255,92,127,.25);margin-bottom:16px}
.callout b{font:600 15px Sora,sans-serif}.callout p{margin:3px 0 0;color:#d6d3e2;font-size:13px}
.progress{height:8px;border-radius:6px;background:var(--surface3);overflow:hidden}.progress i{display:block;height:100%;background:linear-gradient(90deg,#d0284f,#e0823f)}

/* forms */
.form{display:grid;gap:14px}.form label{display:grid;gap:6px;font-weight:600;font-size:13px}.form label small{color:var(--muted);font-weight:500}
.row2{display:grid;grid-template-columns:1fr 1fr;gap:12px}
input,textarea,select{font:inherit;color:var(--ink);background:var(--surface2);border:1px solid var(--line2);border-radius:10px;padding:9px 11px;width:100%}
input:focus,textarea:focus,select:focus{outline:2px solid var(--accent);outline-offset:1px}
.check{display:flex!important;align-items:center;gap:8px;font-weight:500!important}.check input{width:auto}
.checks{display:flex;flex-wrap:wrap;gap:6px 16px}
.flash{background:rgba(63,178,127,.12);border:1px solid rgba(63,178,127,.35);padding:10px 14px;border-radius:12px;margin-bottom:18px}
.err{color:var(--danger);font-weight:600}
.pw{position:relative;display:block}.pw input{padding-right:70px}.pw button{position:absolute;right:6px;top:50%;transform:translateY(-50%);padding:5px 10px;font-size:12px;border-radius:8px;
border:1px solid var(--line2);background:var(--surface3);color:var(--ink);cursor:pointer}
.login{min-height:100vh;display:grid;place-items:center;padding:16px}.login .card{width:100%;max-width:380px;padding:28px}
.narrow{max-width:640px}
.compose{display:grid;grid-template-columns:minmax(0,1fr) 380px;gap:16px;align-items:start}
.sticky{position:sticky;top:20px}

/* message cards */
.pv{max-width:360px;border-radius:24px;overflow:hidden;background:var(--surface2);border:1px solid var(--line)}
.pv-head{height:150px;display:grid;place-items:center;background:linear-gradient(135deg,#7a1232,#d0284f 60%,#e0823f)}
.pv[data-style="celebrate"] .pv-head{background:linear-gradient(135deg,#b5531a,#d0284f 60%,#7a1232)}.pv[data-style="warning"] .pv-head{background:linear-gradient(135deg,#8a5a12,#e0a33f 60%,#7a1232)}
.pv-head img{width:100%;height:100%;object-fit:cover}.pv-ic{width:64px;height:64px;border-radius:50%;display:grid;place-items:center;font-size:30px;background:rgba(255,255,255,.18);border:1px solid rgba(255,255,255,.35)}
.pv-body{padding:16px 18px 18px;display:grid;gap:6px}.pv-body b{font:700 17px Sora,sans-serif;color:#fff}.pv-body p{margin:0;color:#d9d9e6;font-size:13.5px;line-height:1.5}
.pv-badge{justify-self:start;font-size:10.5px;font-weight:800;letter-spacing:.8px;padding:2px 9px;border-radius:20px;background:rgba(208,40,79,.18);color:#ff8aa5}
.pv-cta{justify-self:center;margin-top:8px;padding:9px 22px;border-radius:30px;font-weight:700;font-size:13px;background:linear-gradient(135deg,#a61f2e,#d0284f 60%,#e0823f);color:#fff}
.n-list{list-style:none;margin:0;padding:0}.n-item{display:flex;gap:14px;padding:14px 0;border-top:1px solid var(--line)}.n-item:first-child{border:0;padding-top:0}
.n-thumb{flex:none;width:56px;height:56px;border-radius:14px;overflow:hidden;display:grid;place-items:center;font-size:24px;background:linear-gradient(135deg,#7a1232,#d0284f 60%,#e0823f)}
.n-thumb[data-style="celebrate"]{background:linear-gradient(135deg,#b5531a,#d0284f)}.n-thumb[data-style="warning"]{background:linear-gradient(135deg,#8a5a12,#e0a33f)}.n-thumb img{width:100%;height:100%;object-fit:cover}
.n-main{flex:1;min-width:0;display:grid;gap:4px}.n-top{display:flex;align-items:center;gap:8px;flex-wrap:wrap}.n-title{font-weight:700;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;max-width:100%}
.n-text{color:#c9c9d8;font-size:13px;display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical;overflow:hidden}
.n-meta{color:var(--muted);font-size:12px}.n-stats{display:flex;gap:14px;font-size:12.5px;color:var(--muted);flex-wrap:wrap}.n-stats b{color:var(--ink)}
.n-actions{display:flex;flex-wrap:wrap;gap:6px;margin-top:6px;align-items:center}
.funnel{display:grid;gap:12px}.funnel div{display:grid;grid-template-columns:1fr auto;gap:4px 12px}.funnel span{color:var(--muted)}.funnel small{color:var(--muted);font-weight:500}
.funnel i{grid-column:1/-1;height:8px;border-radius:6px;background:linear-gradient(90deg,#d0284f,#e0823f)}.funnel i.c{background:#5b6b9a}.funnel i.s{background:rgba(255,255,255,.18)}

/* responsive */
@media (max-width:1180px){.kpis.six{grid-template-columns:repeat(3,minmax(0,1fr))}.kpis.five{grid-template-columns:repeat(3,minmax(0,1fr))}
  .strip{grid-template-columns:repeat(3,minmax(0,1fr))}.strip>div:nth-child(4){border-left:0}.strip>div:nth-child(n+4){border-top:1px solid var(--line)}
  .g3{grid-template-columns:repeat(2,minmax(0,1fr))}.compose{grid-template-columns:minmax(0,1fr)}.sticky{position:static}}
@media (max-width:960px){
  .shell{grid-template-columns:minmax(0,1fr)}
  .side{position:fixed;left:0;top:0;bottom:0;width:272px;z-index:30;transform:translateX(-100%);transition:transform .22s ease;box-shadow:20px 0 40px rgba(0,0,0,.5)}
  .menu-open .side{transform:none}
  .scrim{display:block;position:fixed;inset:0;background:rgba(0,0,0,.55);z-index:20;opacity:0;pointer-events:none;transition:opacity .2s}
  .menu-open .scrim{opacity:1;pointer-events:auto}
  .topbar{display:flex;align-items:center;gap:12px;position:sticky;top:0;z-index:10;padding:10px 16px;background:rgba(6,6,12,.88);backdrop-filter:blur(12px);border-bottom:1px solid var(--line)}
  .brand.sm{padding:0}.brand.sm i{width:30px;height:30px;font-size:15px}
  .here{font:600 15px Sora,sans-serif;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
  .icon-btn{width:40px;height:40px;display:grid;place-items:center;border-radius:11px;border:1px solid var(--line2);background:var(--surface2);color:var(--ink);cursor:pointer;flex:none}
  main{padding:18px 16px 48px}
  .kpis{grid-template-columns:repeat(2,minmax(0,1fr))}.g2,.g3,.g-wide{grid-template-columns:minmax(0,1fr)}
  .page-head{align-items:flex-start}.head-actions{width:100%}.seg{width:100%;overflow-x:auto}.seg a{flex:1;text-align:center}
}
@media (max-width:560px){.kpis,.kpis.five,.kpis.six{gap:10px}.kpi{padding:14px 14px 16px}.kpi:has(.spark){padding-bottom:44px}.kpi-v{font-size:23px}
  .strip{grid-template-columns:repeat(2,minmax(0,1fr))}.strip>div:nth-child(odd){border-left:0}.strip>div:nth-child(4){border-left:1px solid var(--line)}.strip>div:nth-child(n+3){border-top:1px solid var(--line)}
  .row2{grid-template-columns:1fr}h1{font-size:21px}.card{padding:16px}.tbl-wrap{margin:0 -16px;padding:0 16px}
  .hide-sm{display:none}.timeline li{grid-template-columns:78px 1fr}}
@media (min-width:961px){.icon-btn,.brand.sm{display:none}}
CSS;
}
