<?php
/**
 * The hall display (SMART Iteration 4, 0143): a page for a television in the barangay hall. Counts only, the same for
 * whoever looks: what was filed today, what is open, what was finished, how many tanods are on duty, and, while a
 * command-center mode is on, its counts and how far its checklist has come. No names, no places, no tracking numbers.
 *
 * A television has no account, so the page opens with a display link (hall.php?k=...) made in Settings -> SMART. The
 * database keeps only a hash of the link's secret and answers nothing to a wrong or turned-off one (command_hall). The
 * page reloads itself every 30 seconds (one line of script; a meta refresh fails the accessibility check).
 */
declare(strict_types=1);

require_once __DIR__ . '/includes/config.php';
require_once __DIR__ . '/includes/supabase.php';
require_once __DIR__ . '/includes/i18n.php';

send_security_policy();
header('Referrer-Policy: no-referrer');
header('X-Robots-Tag: noindex, nofollow');
header('Cache-Control: no-store');

$k = (string) ($_GET['k'] ?? '');
$h = null;
if (preg_match('/^[0-9a-f]{48}$/', $k)) {
    try { $h = (new Supabase(null))->rpc('command_hall', ['p_token' => $k]); } catch (SupabaseError) { $h = false; }
}
$e = static fn ($v): string => htmlspecialchars((string) $v, ENT_QUOTES, 'UTF-8');
$at = static fn (?string $iso): string => $iso ? (new DateTimeImmutable($iso))->setTimezone(new DateTimeZone('Asia/Manila'))->format('g:i A') : '';
$mode = is_array($h) ? ($h['mode'] ?? null) : null;
$col = ['fire' => '#E5383B', 'quake' => '#8D6E63', 'flood' => '#1E88E5', 'typhoon' => '#6A4FD3'][$mode['mode'] ?? ''] ?? '#356CF9';
if (!is_array($h)) http_response_code($h === false ? 503 : 404);
?><!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>SmartSumbong · Hall display</title>
<link href="assets/css/fonts.css?v=<?= $e(asset_version('fonts.css')) ?>" rel="stylesheet">
<style>
  :root { --bg: #0B1630; --panel: #13224A; --line: #22356A; --ink: #F3F6FF; --muted: #A9B6DC; --cc: <?= $e($col) ?>; color-scheme: dark; }
  * { box-sizing: border-box; }
  body { margin: 0; min-height: 100vh; background: var(--bg); color: var(--ink); font: 400 18px/1.35 Urbanist, system-ui, sans-serif; display: grid; grid-template-rows: auto 1fr auto; padding: clamp(16px, 3vw, 40px); gap: clamp(16px, 2.4vw, 32px); }
  header { display: flex; justify-content: space-between; align-items: baseline; gap: 16px; flex-wrap: wrap; }
  header b { font-size: clamp(22px, 2.6vw, 40px); letter-spacing: .01em; }
  header span { color: var(--muted); font-size: clamp(16px, 1.6vw, 24px); font-variant-numeric: tabular-nums; }
  .band { display: flex; align-items: center; gap: 18px; padding: clamp(14px, 2vw, 26px) clamp(16px, 2.4vw, 32px); border-radius: 22px; background: var(--cc); color: #fff; }
  .band b { font-size: clamp(28px, 4vw, 64px); text-transform: uppercase; letter-spacing: .03em; line-height: 1; }
  .band span { font-size: clamp(16px, 1.8vw, 28px); opacity: .92; }
  main { display: grid; gap: clamp(16px, 2vw, 28px); align-content: start; }
  .tiles { display: grid; grid-template-columns: repeat(auto-fit, minmax(min(100%, 220px), 1fr)); gap: clamp(12px, 1.6vw, 24px); }
  .tile { background: var(--panel); border: 1px solid var(--line); border-radius: 22px; padding: clamp(16px, 2vw, 28px); display: grid; gap: 4px; }
  .tile b { font-size: clamp(44px, 5.6vw, 104px); line-height: 1; font-variant-numeric: tabular-nums; }
  /* with a mode on, today's counts are the second thing on the screen, and smaller, so it all fits one television */
  .tiles.small .tile { padding: clamp(10px, 1.2vw, 18px) clamp(14px, 1.6vw, 24px); }
  .tiles.small .tile b { font-size: clamp(30px, 3.4vw, 60px); }
  .tiles.small .tile span { font-size: clamp(14px, 1.2vw, 20px); }
  .tile span { color: var(--muted); font-size: clamp(16px, 1.6vw, 26px); }
  h2 { margin: 8px 0 0; font-size: clamp(16px, 1.5vw, 22px); color: var(--muted); text-transform: uppercase; letter-spacing: .08em; font-weight: 700; }
  ul { list-style: none; margin: 0; padding: 0; display: grid; grid-template-columns: repeat(auto-fit, minmax(min(100%, 300px), 1fr)); gap: 12px; }
  li { background: var(--panel); border: 1px solid var(--line); border-left: 6px solid var(--cc); border-radius: 14px; padding: 14px 18px; display: flex; justify-content: space-between; gap: 12px; font-size: clamp(18px, 1.8vw, 28px); }
  li b { font-variant-numeric: tabular-nums; }
  footer { color: var(--muted); font-size: clamp(13px, 1.1vw, 17px); display: flex; justify-content: space-between; gap: 16px; flex-wrap: wrap; }
  .gone { place-self: center; text-align: center; max-width: 34rem; }
  .gone b { display: block; font-size: 28px; margin-bottom: 8px; }
</style>
</head>
<body>
<?php if (!is_array($h)): ?>
  <header><b>SmartSumbong</b><span></span></header>
  <main class="gone">
    <?php if ($h === false): ?>
      <p><b><?= $e(t('The display could not be read just now.', 'Hindi mabasa ang display ngayon.')) ?></b><?= $e(t('It tries again by itself every 30 seconds.', 'Susubukan itong muli kada 30 segundo.')) ?></p>
    <?php else: ?>
      <p><b><?= $e(t('This display link is not valid, or it was turned off.', 'Hindi tama ang display link na ito, o naka-off na.')) ?></b><?= $e(t('An administrator makes a new one in Settings → SMART → Command center.', 'Gumagawa ng bago ang administrator sa Settings → SMART → Sentro ng Pamamahala.')) ?></p>
    <?php endif; ?>
  </main>
  <footer><span>SmartSumbong · SMART</span></footer>
<?php else: $today = (array) ($h['today'] ?? []); ?>
  <header><b><?= $e($h['barangay'] ?? 'Barangay 183') ?></b><span><?= $e(t('As of', 'As of')) ?> <?= $e($at($h['as_of'] ?? null)) ?></span></header>
  <main>
    <?php if ($mode): ?>
      <div class="band"><b><?= $e(t((string) $mode['en'], (string) $mode['fil'])) ?></b><span><?= $e(t('On since', 'Naka-on mula')) ?> <?= $e($at($mode['since'] ?? null)) ?></span></div>
      <div class="tiles">
        <div class="tile"><b><?= (int) $mode['reports'] ?></b><span><?= $e(t('Reports', 'Ulat')) ?></span></div>
        <div class="tile"><b><?= (int) $mode['open'] ?></b><span><?= $e(t('Still open', 'Bukas pa')) ?></span></div>
        <div class="tile"><b><?= (int) $mode['resolved'] ?></b><span><?= $e(t('Finished', 'Natapos')) ?></span></div>
        <div class="tile"><b><?= (int) $mode['checklist_done'] ?>/<?= (int) $mode['checklist_total'] ?></b><span><?= $e(t('Checklist done', 'Tapos sa checklist')) ?></span></div>
      </div>
      <?php if (!empty($mode['tags'])): ?>
        <h2><?= $e(t('What residents reported', 'Ang iniulat ng mga residente')) ?></h2>
        <ul><?php foreach ((array) $mode['tags'] as $tg): ?><li><span><?= $e(t((string) $tg['en'], (string) $tg['fil'])) ?></span><b><?= (int) $tg['reports'] ?></b></li><?php endforeach; ?></ul>
      <?php endif; ?>
      <h2><?= $e(t('Today', 'Ngayong araw')) ?></h2>
    <?php endif; ?>
    <div class="tiles<?= $mode ? ' small' : '' ?>">
      <div class="tile"><b><?= (int) ($today['filed'] ?? 0) ?></b><span><?= $e(t('Filed today', 'Naisampa ngayon')) ?></span></div>
      <div class="tile"><b><?= (int) ($today['open'] ?? 0) ?></b><span><?= $e(t('Open now', 'Bukas ngayon')) ?></span></div>
      <div class="tile"><b><?= (int) ($today['resolved'] ?? 0) ?></b><span><?= $e(t('Finished today', 'Natapos ngayon')) ?></span></div>
      <div class="tile"><b><?= (int) ($h['tanods_on_duty'] ?? 0) ?></b><span><?= $e(t('Tanods on duty', 'Tanod na naka-duty')) ?></span></div>
    </div>
  </main>
  <footer><span><?= $e(t('Counts only. Reports stay private.', 'Mga bilang lamang. Pribado ang mga ulat.')) ?></span><span>SmartSumbong · SMART</span></footer>
<?php endif; ?>
<?php if (is_array($h) || $h === false): ?><script>setTimeout(function () { location.reload(); }, 30000);</script><?php endif; ?>
</body>
</html>
