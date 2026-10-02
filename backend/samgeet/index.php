<?php
// Samgeet's download page: what the app is, the newest version to download, and how to install it.
// The download is the newest version published from the admin panel, or the latest GitHub release.

declare(strict_types=1);
require __DIR__ . '/lib/bootstrap.php';

const GITHUB_APK = 'https://github.com/loco0011/samgeet/releases/latest/download/Samgeet.apk';
const GITHUB_REPO = 'https://github.com/loco0011/samgeet';

header('Content-Type: text/html; charset=utf-8');
header('X-Content-Type-Options: nosniff');
header('Referrer-Policy: strict-origin-when-cross-origin');
header('X-Frame-Options: DENY');
header("Content-Security-Policy: default-src 'self'; style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; font-src https://fonts.gstatic.com; img-src 'self' data:; script-src 'none'; frame-ancestors 'none'; base-uri 'none'");
header('Cache-Control: public, max-age=300');

function e($s): string
{
    return htmlspecialchars((string)$s, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
}

$release = null;
try {
    $cfg = sg_config();
    if (!empty($cfg['name'])) {
        $pdo = new PDO("mysql:host={$cfg['host']};dbname={$cfg['name']};charset=utf8mb4", $cfg['user'], $cfg['pass'],
            [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION, PDO::ATTR_TIMEOUT => 3]);
        $release = $pdo->query('SELECT version_name, apk_url, sha256, size_bytes, published_at FROM releases
                                WHERE published = 1 ORDER BY build DESC LIMIT 1')->fetch(PDO::FETCH_ASSOC) ?: null;
    }
} catch (Throwable $err) {
    error_log('samgeet site: ' . $err->getMessage());
}
$apk = $release && preg_match('~^https://~', $release['apk_url']) ? $release['apk_url'] : GITHUB_APK;
$version = $release['version_name'] ?? null;
$size = !empty($release['size_bytes']) ? round($release['size_bytes'] / 1048576) . ' MB' : 'about 58 MB';
$sha = $release['sha256'] ?? '';
?><!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Samgeet: free, ad-free music for Android</title>
<meta name="description" content="Samgeet is a free, ad-free music player for Android: Hindi, Bengali, Punjabi, English and more, offline downloads, a daily mix made for you, and your library on every phone.">
<meta property="og:title" content="Samgeet: free, ad-free music for Android">
<meta property="og:description" content="Millions of songs, no ads, offline downloads and a daily mix made for you.">
<meta name="theme-color" content="#04040a">
<link rel="icon" type="image/png" href="site/app-icon.png">
<link rel="apple-touch-icon" href="site/app-icon.png">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@400;500;600;700;800&amp;family=Sora:wght@700;800&amp;display=swap" rel="stylesheet">
<style>
:root{--bg:#04040a;--surface:#0f0f1a;--surface2:#181829;--line:rgba(255,255,255,.09);--ink:#f1f1f7;--muted:#9ea1be;--accent:#d0284f;--accent2:#e0823f;color-scheme:dark}
*{box-sizing:border-box}html,body{margin:0}
body{background:var(--bg);color:var(--ink);font:16px/1.6 'Plus Jakarta Sans',system-ui,sans-serif;overflow-x:hidden;
background-image:radial-gradient(900px 560px at 85% -10%,rgba(208,40,79,.28),transparent 60%),radial-gradient(700px 500px at -10% 20%,rgba(181,83,26,.18),transparent 60%)}
a{color:inherit}
.wrap{max-width:1120px;margin:0 auto;padding:0 20px}
header{display:flex;align-items:center;justify-content:space-between;padding:20px 0}
.brand{display:flex;align-items:center;gap:10px;font:800 20px Sora,sans-serif;text-decoration:none}.brand img{width:36px;height:36px;border-radius:10px}
.top-link{color:var(--muted);text-decoration:none;font-weight:600;font-size:14px}.top-link:hover{color:var(--ink)}
.hero{display:grid;grid-template-columns:1.05fr .95fr;gap:40px;align-items:center;padding:36px 0 56px}
.pill{display:inline-block;padding:5px 12px;border-radius:30px;background:rgba(208,40,79,.15);color:#ff8aa5;font-weight:700;font-size:13px;margin-bottom:18px}
h1{font:800 clamp(38px,6vw,64px)/1.03 Sora,sans-serif;letter-spacing:-2px;margin:0 0 18px}
h1 span{background:linear-gradient(90deg,#ff5c7f,#e0823f);-webkit-background-clip:text;background-clip:text;color:transparent}
.lead{color:#cfd0e2;font-size:18px;max-width:540px;margin:0 0 28px}
.cta{display:flex;flex-wrap:wrap;gap:12px;align-items:center}
.btn{display:inline-flex;align-items:center;gap:10px;padding:16px 26px;border-radius:40px;font-weight:800;text-decoration:none;font-size:16px}
.btn.main{background:linear-gradient(135deg,#a61f2e,#d0284f 60%,#e0823f);color:#fff;box-shadow:0 12px 34px rgba(208,40,79,.4)}
.btn.main:hover{transform:translateY(-1px)}
.btn.ghost{border:1px solid var(--line);background:var(--surface)}
.meta{color:var(--muted);font-size:13px;margin-top:14px}
.phones{position:relative;height:560px}
/* A soft glow that breathes behind the phones. */
.phones::before{content:"";position:absolute;inset:8% 4%;border-radius:50%;background:radial-gradient(closest-side,rgba(208,40,79,.55),rgba(224,130,63,.25) 55%,transparent);filter:blur(30px);animation:glow 5s ease-in-out infinite}
.phone{position:absolute;width:250px;border-radius:30px;overflow:hidden;border:6px solid #1a1a28;box-shadow:0 30px 60px rgba(0,0,0,.55);will-change:transform}
.phone img{display:block;width:100%;height:auto}
/* A light sheen that sweeps across each screen now and then. */
.phone::after{content:"";position:absolute;top:0;bottom:0;left:-60%;width:45%;background:linear-gradient(105deg,transparent,rgba(255,255,255,.16),transparent);transform:skewX(-12deg);animation:sheen 6s ease-in-out 1.6s infinite}
.phone.b::after{animation-delay:3.4s}
/* In from below when the page opens, then a gentle float, the two phones out of step. */
.phone.a{left:6%;top:30px;transform:rotate(-6deg);animation:inA 1s cubic-bezier(.2,.8,.2,1) both,floatA 6s ease-in-out 1s infinite}
.phone.b{right:6%;top:0;transform:rotate(5deg);z-index:2;animation:inB 1s cubic-bezier(.2,.8,.2,1) .15s both,floatB 7s ease-in-out 1.15s infinite}
@keyframes inA{from{opacity:0;transform:translateY(70px) rotate(-14deg)}to{opacity:1;transform:translateY(0) rotate(-6deg)}}
@keyframes inB{from{opacity:0;transform:translateY(90px) rotate(12deg)}to{opacity:1;transform:translateY(0) rotate(5deg)}}
@keyframes floatA{0%,100%{transform:translateY(0) rotate(-6deg)}50%{transform:translateY(-16px) rotate(-4.5deg)}}
@keyframes floatB{0%,100%{transform:translateY(0) rotate(5deg)}50%{transform:translateY(-22px) rotate(3.5deg)}}
@keyframes glow{0%,100%{opacity:.75;transform:scale(1)}50%{opacity:1;transform:scale(1.08)}}
@keyframes sheen{0%{left:-60%}30%,100%{left:130%}}
/* A little "now playing" card with dancing equalizer bars. */
.chip{position:absolute;left:50%;bottom:6%;z-index:3;display:flex;align-items:center;gap:10px;padding:10px 16px;border-radius:40px;background:rgba(15,15,26,.82);border:1px solid var(--line);backdrop-filter:blur(10px);font-weight:700;font-size:14px;line-height:1.3;white-space:nowrap;box-shadow:0 12px 30px rgba(0,0,0,.45);transform:translateX(-50%);animation:chipIn .8s cubic-bezier(.2,.8,.2,1) .7s both}
.chip small{display:block;color:var(--muted);font-weight:500;font-size:12px}
.eq{display:flex;align-items:flex-end;gap:3px;height:18px}.eq i{display:block;width:4px;height:5px;border-radius:2px;background:linear-gradient(#ff5c7f,#e0823f);animation:eq 1s ease-in-out infinite}
.eq i:nth-child(2){animation-delay:-.4s}.eq i:nth-child(3){animation-delay:-.7s}.eq i:nth-child(4){animation-delay:-.2s}
@keyframes eq{0%,100%{height:5px}50%{height:18px}}
@keyframes chipIn{from{opacity:0;transform:translate(-50%,20px)}to{opacity:1;transform:translate(-50%,0)}}
@media (prefers-reduced-motion:reduce){.phone,.phone::after,.phones::before,.chip,.eq i{animation:none!important}.phone::after{display:none}}
section{padding:56px 0}
h2{font:800 clamp(26px,3.5vw,36px)/1.15 Sora,sans-serif;letter-spacing:-1px;margin:0 0 10px}
.sub{color:var(--muted);margin:0 0 30px;max-width:620px}
.features{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:16px}
.f{background:var(--surface);border:1px solid var(--line);border-radius:22px;padding:22px}
.f .i{width:44px;height:44px;border-radius:14px;display:grid;place-items:center;font-size:22px;background:linear-gradient(135deg,rgba(208,40,79,.25),rgba(224,130,63,.2));margin-bottom:14px}
.f h3{margin:0 0 6px;font:700 17px Sora,sans-serif}.f p{margin:0;color:var(--muted);font-size:14.5px}
.looks{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:16px}
.look{text-align:center}.look img{width:100%;border-radius:22px;border:1px solid var(--line);display:block}
.look b{display:block;margin-top:10px}.look span{color:var(--muted);font-size:13px}
.steps{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:16px;counter-reset:s}
.step{background:var(--surface);border:1px solid var(--line);border-radius:22px;padding:22px;position:relative}
.step::before{counter-increment:s;content:counter(s);display:grid;place-items:center;width:34px;height:34px;border-radius:50%;background:var(--accent);font-weight:800;margin-bottom:12px}
.step h3{margin:0 0 6px;font:700 16px Sora,sans-serif}.step p{margin:0;color:var(--muted);font-size:14.5px}
.final{text-align:center;background:linear-gradient(135deg,rgba(122,18,50,.55),rgba(24,24,41,.9));border:1px solid var(--line);border-radius:30px;padding:44px 22px}
.final .cta{justify-content:center}
.sha{font:12px ui-monospace,Consolas,monospace;color:var(--muted);word-break:break-all;margin-top:16px}
footer{color:var(--muted);font-size:13px;padding:30px 0 50px;border-top:1px solid var(--line);margin-top:30px}
footer a{color:var(--muted)}
@media (max-width:900px){.hero{grid-template-columns:1fr;padding-top:10px}.phones{height:440px}.phone{width:200px}.features,.steps{grid-template-columns:1fr}.looks{grid-template-columns:repeat(2,minmax(0,1fr))}}
@media (max-width:480px){.phones{height:380px}.phone{width:170px}.phone.a{left:0}.phone.b{right:0}.btn{width:100%;justify-content:center}}
</style>
</head>
<body>
<div class="wrap">
  <header>
    <a class="brand" href="./"><img src="site/app-icon.png" alt="">Samgeet</a>
    <a class="top-link" href="<?= e(GITHUB_REPO) ?>" rel="noopener">Open source on GitHub</a>
  </header>

  <div class="hero">
    <div>
      <span class="pill">Free · No ads · Android</span>
      <h1>All your music.<br><span>None of the ads.</span></h1>
      <p class="lead">Samgeet plays millions of songs in Hindi, Bengali, Punjabi, English and more, learns what you love,
        and keeps your playlists on every phone you sign in on. No ads, no subscription.</p>
      <div class="cta">
        <a class="btn main" href="<?= e($apk) ?>" rel="noopener">⬇&nbsp; Download Samgeet<?= $version ? ' ' . e($version) : '' ?></a>
        <a class="btn ghost" href="#install">How to install</a>
      </div>
      <p class="meta">For Android 7.0 and newer · <?= e($size) ?> · free forever</p>
    </div>
    <div class="phones" aria-hidden="true">
      <div class="phone a"><img src="site/disc.jpg" alt=""></div>
      <div class="phone b"><img src="site/immersive.jpg" alt=""></div>
      <div class="chip"><span class="eq"><i></i><i></i><i></i><i></i></span><span>Kesariya<small>Arijit Singh · Now playing</small></span></div>
    </div>
  </div>
</div>

<section>
  <div class="wrap">
    <h2>Everything you want from a music app</h2>
    <p class="sub">Made by one developer, for listeners. Here's what you get.</p>
    <div class="features">
      <div class="f"><div class="i">🎧</div><h3>Millions of songs</h3><p>Bollywood, Bengali, Punjabi, Tamil, Telugu, English, K-pop and more, up to 320 kbps.</p></div>
      <div class="f"><div class="i">✨</div><h3>Your Daily Mix</h3><p>A fresh mix of 40 songs every day, built from your likes, plays and favourite singers.</p></div>
      <div class="f"><div class="i">⬇️</div><h3>Offline downloads</h3><p>Save songs and whole albums, then listen on a flight or with no signal at all.</p></div>
      <div class="f"><div class="i">🔎</div><h3>Search that forgives typos</h3><p>Find a song from a misspelling, part of the name, or a line from the lyrics.</p></div>
      <div class="f"><div class="i">🎚️</div><h3>Equalizer and boost</h3><p>Shape the sound with presets or your own curve, and save the sounds you like.</p></div>
      <div class="f"><div class="i">☁️</div><h3>Your library everywhere</h3><p>Sign in and your playlists, likes and history follow you to any phone.</p></div>
    </div>
  </div>
</section>

<section>
  <div class="wrap">
    <h2>Pick how your player looks</h2>
    <p class="sub">Four looks for the now-playing screen. Switch any time.</p>
    <div class="looks">
      <div class="look"><img src="site/disc.jpg" alt="The Disc player look" loading="lazy"><b>Disc</b><span>The spinning record</span></div>
      <div class="look"><img src="site/cover.jpg" alt="The Cover player look" loading="lazy"><b>Cover</b><span>Big artwork, classic bar</span></div>
      <div class="look"><img src="site/immersive.jpg" alt="The Immersive player look" loading="lazy"><b>Immersive</b><span>Art behind frosted glass</span></div>
      <div class="look"><img src="site/minimal.jpg" alt="The Minimal player look" loading="lazy"><b>Minimal</b><span>Big type, nothing else</span></div>
    </div>
  </div>
</section>

<section id="install">
  <div class="wrap">
    <h2>Install in a minute</h2>
    <p class="sub">Samgeet isn't on the Play Store yet, so you install it straight from here.</p>
    <div class="steps">
      <div class="step"><h3>Download</h3><p>Tap <b>Download Samgeet</b>. Your browser saves <code>Samgeet.apk</code>.</p></div>
      <div class="step"><h3>Allow the install</h3><p>Open the file. Android may ask you to let your browser install apps the first time: turn that on.</p></div>
      <div class="step"><h3>Open and play</h3><p>Tap <b>Install</b>, open Samgeet and start listening. Updates come inside the app.</p></div>
    </div>
  </div>
</section>

<section>
  <div class="wrap">
    <div class="final">
      <h2>Ready to listen?</h2>
      <p class="sub" style="margin:0 auto 24px">Free, ad-free, and yours.</p>
      <div class="cta"><a class="btn main" href="<?= e($apk) ?>" rel="noopener">⬇&nbsp; Download Samgeet<?= $version ? ' ' . e($version) : '' ?></a></div>
      <?php if ($sha !== ''): ?><div class="sha">SHA-256: <?= e($sha) ?></div><?php endif; ?>
    </div>
  </div>
</section>

<div class="wrap">
  <footer>
    © <?= date('Y') ?> Sambit Maity · <a href="<?= e(GITHUB_REPO) ?>" rel="noopener">Source code (MIT)</a> ·
    <a href="https://www.linkedin.com/in/sambitmaity/" rel="noopener">Author</a><br>
    Samgeet does not host or own any music; songs are streamed from a third-party catalogue and belong to their rights holders.
    Signing in records how the app is used to improve it; details are in the app under Settings › About.
  </footer>
</div>
</body>
</html>
