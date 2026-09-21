<?php
// Samgeet share page: what a friend sees when they open a shared song or playlist link.
//   share.php?t=song&id=<song id>&s=<title>&a=<artist>&al=<album>&i=<cover url>
//   share.php?t=playlist&n=<name>&c=<song count>#p=<playlist code>
// It shows only text the link itself carries, plus the cover art hotlinked from the catalogue's CDN.
// It has no database, stores nothing, plays no audio and offers no song files: it is a link
// preview with a "get the app" button. (The #p= playlist code stays in the browser and is never
// sent to this server.)

ini_set('display_errors', '0');

const APK_URL = 'https://github.com/loco0011/samgeet/releases/latest/download/Samgeet.apk';
const RELEASES_URL = 'https://github.com/loco0011/samgeet/releases/latest';
const REPO_URL = 'https://github.com/loco0011/samgeet';

function param($name, $max)
{
    $v = $_GET[$name] ?? '';
    if (!is_string($v)) return '';
    $v = preg_replace('/[\x00-\x1F\x7F]+/u', ' ', $v);
    $v = trim($v === null ? '' : $v);
    return mb_substr($v, 0, $max);
}

function e($s)
{
    return htmlspecialchars($s, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
}

// Only cover art from the catalogue's own CDN is ever embedded.
function cover($url)
{
    $p = parse_url($url);
    if (!$p || ($p['scheme'] ?? '') !== 'https' || isset($p['user']) || isset($p['port'])) return '';
    $host = strtolower($p['host'] ?? '');
    if ($host !== 'saavncdn.com' && substr($host, -12) !== '.saavncdn.com') return '';
    return $url;
}

$type = ($_GET['t'] ?? '') === 'playlist' ? 'playlist' : 'song';
$image = '';

if ($type === 'playlist') {
    $title = param('n', 80) ?: 'A playlist';
    $count = max(0, min(500, (int)($_GET['c'] ?? 0)));
    $sub = $count > 0 ? "Playlist · $count songs" : 'Playlist';
    $ogTitle = "$title — playlist on Samgeet";
    $ogDesc = ($count > 0 ? "$count songs. " : '') . 'Get Samgeet, the ad-free music player, and import this playlist.';
} else {
    $title = param('s', 120) ?: 'A song';
    $artist = param('a', 160);
    $album = param('al', 120);
    $image = cover(param('i', 400));
    $sub = $artist;
    $ogTitle = $artist !== '' ? "$title — $artist" : $title;
    $ogDesc = ($album !== '' ? "From $album. " : '') . 'Listen on Samgeet, the ad-free music player.';
}

$nonce = base64_encode(random_bytes(12));
header('Content-Type: text/html; charset=utf-8');
header('X-Content-Type-Options: nosniff');
header('Referrer-Policy: no-referrer');
header('Cache-Control: public, max-age=300');
header("Content-Security-Policy: default-src 'none'; img-src 'self' https://*.saavncdn.com data:; style-src 'nonce-$nonce'; script-src 'nonce-$nonce'; base-uri 'none'; form-action 'none'");
?>
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title><?= e($ogTitle) ?></title>
<meta name="robots" content="noindex">
<meta name="theme-color" content="#0b0b12">
<meta property="og:site_name" content="Samgeet">
<meta property="og:type" content="website">
<meta property="og:title" content="<?= e($ogTitle) ?>">
<meta property="og:description" content="<?= e($ogDesc) ?>">
<?php if ($image !== ''): ?>
<meta property="og:image" content="<?= e($image) ?>">
<meta name="twitter:card" content="summary_large_image">
<?php else: ?>
<meta name="twitter:card" content="summary">
<?php endif; ?>
<style nonce="<?= e($nonce) ?>">
  :root { color-scheme: dark; }
  * { box-sizing: border-box; }
  body { margin: 0; min-height: 100vh; display: grid; place-items: center; padding: 20px;
    font-family: system-ui, -apple-system, "Segoe UI", Roboto, sans-serif; color: #f3f3f8;
    background: radial-gradient(900px 500px at 15% -10%, #12c2d633, transparent),
                radial-gradient(800px 500px at 100% 110%, #d61fa233, transparent), #0b0b12; }
  main { width: 100%; max-width: 420px; text-align: center; }
  .brand { font-weight: 800; letter-spacing: .04em; font-size: 15px; color: #b9b9c9; margin-bottom: 18px; }
  .card { background: #ffffff0d; border: 1px solid #ffffff1a; border-radius: 24px; padding: 22px; }
  .art { width: 100%; aspect-ratio: 1; border-radius: 18px; object-fit: cover; background: #1a1a26; display: block; margin-bottom: 18px; }
  .ph { width: 100%; aspect-ratio: 1; border-radius: 18px; margin-bottom: 18px; display: grid; place-items: center; font-size: 64px;
    background: linear-gradient(135deg, #12c2d6, #7c4dff 55%, #d61fa2); }
  h1 { font-size: 22px; line-height: 1.25; margin: 0 0 6px; overflow-wrap: anywhere; }
  .sub { color: #b9b9c9; margin: 0; overflow-wrap: anywhere; }
  .btn { display: block; margin-top: 22px; padding: 15px; border-radius: 999px; font-weight: 700; text-decoration: none; color: #fff;
    background: linear-gradient(90deg, #12c2d6, #7c4dff 55%, #d61fa2); border: 0; width: 100%; font-size: 16px; cursor: pointer; }
  .btn.ghost { background: transparent; border: 1px solid #ffffff33; margin-top: 12px; }
  #open { display: none; }
  .alt { display: block; margin-top: 12px; color: #b9b9c9; font-size: 14px; }
  .steps { text-align: left; color: #b9b9c9; font-size: 14px; line-height: 1.55; margin: 20px 0 0; padding-left: 20px; }
  .steps b { color: #f3f3f8; }
  .fine { color: #8b8b9c; font-size: 12px; line-height: 1.5; margin-top: 22px; }
  .fine a, .alt a { color: #b9b9c9; }
  #import { display: none; }
</style>
</head>
<body>
<main>
  <div class="brand">SAMGEET</div>
  <div class="card">
<?php if ($image !== ''): ?>
    <img class="art" src="<?= e($image) ?>" alt="" referrerpolicy="no-referrer">
<?php else: ?>
    <div class="ph"><?= $type === 'playlist' ? '🎧' : '🎵' ?></div>
<?php endif; ?>
    <h1><?= e($title) ?></h1>
<?php if ($sub !== ''): ?>
    <p class="sub"><?= e($sub) ?></p>
<?php endif; ?>
    <a class="btn" id="open" href="#">Open in Samgeet</a>
    <a class="btn ghost" href="<?= e(APK_URL) ?>">Download Samgeet for Android</a>
    <span class="alt">Free · ad-free · <a href="<?= e(RELEASES_URL) ?>">all versions</a></span>
<?php if ($type === 'playlist'): ?>
    <ol class="steps">
      <li>Install Samgeet from the button above.</li>
      <li>Open <b>Library → Import</b>.</li>
      <li>Paste this link (or the whole message you received).</li>
    </ol>
    <button class="btn" id="import" type="button">Copy playlist link</button>
<?php else: ?>
    <ol class="steps">
      <li>Install Samgeet from the button above.</li>
      <li>Search for <b><?= e($title) ?></b> and press play.</li>
    </ol>
<?php endif; ?>
  </div>
  <p class="fine">
    Samgeet is a free, open-source music player by Sambit Maity (<a href="<?= e(REPO_URL) ?>">source</a>).
    It doesn't host any music: songs are streamed from a third-party catalogue and belong to their rights holders.
    Not affiliated with any label or streaming service. Personal, non-commercial use only.
  </p>
</main>
<script nonce="<?= e($nonce) ?>">
  // On Android, hand this same link to the app (needs Samgeet installed; otherwise nothing happens).
  var o = document.getElementById('open');
  if (o && /Android/i.test(navigator.userAgent)) {
    o.href = 'samgeet://share' + location.search + location.hash;
    o.style.display = 'block';
  }
  var b = document.getElementById('import');
  if (b && location.hash.indexOf('#p=') === 0) {
    b.style.display = 'block';
    b.addEventListener('click', function () {
      var done = function () { b.textContent = 'Copied ✓'; };
      if (navigator.clipboard) navigator.clipboard.writeText(location.href).then(done, function () {});
    });
  }
</script>
</body>
</html>
