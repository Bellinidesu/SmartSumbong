<?php
/**
 * The side panel of the signed-out pages, "At a glance" (15 Nov 2026, Ace): the barangay seal in the middle of a sky that is lived in by the real weather and
 * the hour, with the reading, the warning, the flood advisory, the hotlines, two Pasay headlines and the SMARTengine mark under it. Public information only
 * (includes/glance.php); the picture is drawn here and by assets/css/signin.css, the numbers and words are filled in by assets/js/glance.js from glance.php.
 *
 * The scene is the seal's own picture drawn again in our style: the Philippine sun (the flag's: eight primary rays, each with a shorter ray at its sides),
 * the Shrine of St. Therese in front (terracotta, four stepped arches, two blue-domed towers: the same landmark Spatial Distribution knows), Newport Mall's
 * long roof, the towers and the hill. Clouds keep the Smart Sumbong speech-bubble shape, with the warning badge in a warning.
 */
declare(strict_types=1);

require_once __DIR__ . '/barangay.php';
require_once __DIR__ . '/glance.php';

/** The stylesheet and script of the signed-out pages' new look, for the head. */
function signin_head(): string
{
    return '<link href="assets/css/signin.css?v=' . e(asset_version('signin.css')) . '" rel="stylesheet">';
}

/** The script that fills the panel; at the foot of the page. */
function signin_foot(): string
{
    return '<script src="assets/js/glance.js?v=' . e(asset_version('../js/glance.js')) . '" defer></script>';
}

/** One ray of the Philippine sun: a tapered point, drawn pointing up and turned. */
function signin_ray(float $deg, float $r1, float $half): string
{
    return '<path d="M' . (-$half) . ',-34L0,' . (-$r1) . 'L' . $half . ',-34Z" transform="rotate(' . $deg . ')"/>';
}

/**
 * The words and rows of the panel from what the server already holds (glance_peek), the same sentences assets/js/glance.js writes, so the page arrives drawn and
 * the script only refreshes it. Keep the two in step.
 *
 * @return array{kind:string, when:string, temp:string, cond:string, sub:string, warn:?array, flood:?string, hot:string, hotT:string, news:string}
 */
function signin_parts(?array $g, string $phase): array
{
    $o = ['kind' => 'clear', 'when' => '', 'temp' => '--°', 'cond' => '', 'sub' => '', 'warn' => null, 'flood' => null, 'hot' => '', 'hotT' => '', 'news' => ''];
    if (!$g) return $o;
    if (!empty($g['now'])) {
        $n = $g['now']; $k = (string) $n['kind']; $o['kind'] = $k;
        $o['when'] = t('NOW', 'NGAYON') . (!empty($g['when']) ? ' · ' . $g['when'] : '');
        $o['temp'] = $n['temp'] . '°';
        $o['cond'] = $k === 'clear' ? ($phase === 'night' ? t('Clear night', 'Maaliwalas na gabi') : ($phase === 'day' ? t('Sunny', 'Maaraw') : t('Clear', 'Maaliwalas')))
            : (['cloudy' => t('Cloudy', 'Maulap'), 'rain' => t('Heavy rain', 'Malakas na ulan'), 'storm' => t('Thunderstorm', 'Pagkulog at pagkidlat')][$k] ?? '');
        $o['sub'] = t('Feels like ', 'Pakiramdam ') . $n['feels'] . '° · ' . t('wind ', 'hangin ') . $n['wind'] . ' km/h';
    } else {
        $o['cond'] = t('Weather unavailable', 'Walang datos sa panahon');
    }
    if (!empty($g['warn'])) {
        $w = $g['warn'];
        if (($w['kind'] ?? '') === 'wind') {
            $title = t('Wind signal no. ', 'Wind signal blg. ') . ($w['signal'] ?? '');
        } else {
            $lv = [1 => t('Yellow', 'Dilaw'), 2 => t('Orange', 'Kahel'), 3 => t('Red', 'Pula')][(int) ($w['level'] ?? 0)] ?? '';
            $title = ($w['kind'] ?? '') === 'thunder' ? $lv . ' ' . t('thunderstorm warning', 'babala sa pagkulog') : $lv . ' ' . t('rainfall warning', 'babala sa ulan');
        }
        $until = 'PAGASA';
        if (!empty($w['until']) && ($ts = strtotime((string) $w['until'])) !== false) {
            $until = 'PAGASA · ' . t('until ', 'hanggang ') . (new DateTimeImmutable('@' . $ts))->setTimezone(new DateTimeZone('Asia/Manila'))->format('g:i A');
        }
        $o['warn'] = [$title, $until];
    }
    if (array_key_exists('flood', $g) && $g['flood'] !== null) {
        $o['flood'] = $g['flood'] ? t('Flood advisory in effect', 'May flood advisory') : t('No flood advisory', 'Walang flood advisory');
    }
    $hot = (array) ($g['hot'] ?? []);
    if ($hot) {
        $o['hotT'] = implode(' · ', array_map(static fn ($x) => (string) $x['name'], array_slice($hot, 0, 3)));
        foreach ($hot as $grp) {
            $o['hot'] .= '<div class="g">' . e(mb_strtoupper((string) $grp['name'])) . '</div>';
            foreach ((array) ($grp['numbers'] ?? []) as $num) {
                $o['hot'] .= '<div class="n"><span><b>' . e((string) (($num['label'] ?? '') !== '' ? $num['label'] : $grp['name'])) . '</b><em>' . e((string) $num['number']) . '</em></span>'
                    . (!empty($num['tel']) ? '<a href="tel:' . e((string) $num['tel']) . '">' . e(t('Call', 'Tawag')) . '</a>' : '') . '</div>';
            }
        }
    }
    foreach ((array) ($g['news'] ?? []) as $nw) {
        if (!preg_match('#^https://#i', (string) ($nw['url'] ?? ''))) continue;
        $o['news'] .= '<a href="' . e((string) $nw['url']) . '" target="_blank" rel="noopener noreferrer">' . e((string) $nw['t']) . (!empty($nw['src']) ? ' <em>' . e((string) $nw['src']) . '</em>' : '') . '</a>';
    }
    return $o;
}

function signin_rail(): string
{
    // the picture and the words from what the server already holds; from the clock when nothing is kept yet
    $g = glance_peek();
    $phase = (string) ($g['phase'] ?? glance_phase(null, new DateTimeImmutable('now', new DateTimeZone('Asia/Manila'))));
    $P = signin_parts($g, $phase);
    $rays = '';
    for ($k = 0; $k < 8; $k++) {
        $rays .= signin_ray($k * 45, 104, 6) . signin_ray($k * 45 - 11, 80, 4) . signin_ray($k * 45 + 11, 80, 4);
    }
    $stars = '';
    foreach ([0, 1, 2] as $g) {
        $stars .= '<b class="g' . $g . '">';
        for ($i = 0; $i < 12; $i++) {
            $n = $g * 12 + $i;
            $x = (($n * 9301 + 49297) % 233280) / 233280 * 98;
            $y = ((($n + 19) * 9301 + 49297) % 233280) / 233280 * 190;
            $stars .= '<i style="left:' . round($x, 1) . '%;top:' . round($y) . 'px;width:' . (1 + ($n % 3)) . 'px;height:' . (1 + ($n % 3)) . 'px"></i>';
        }
        $stars .= '</b>';
    }
    // the towers on the left, with their windows
    $towers = '';
    foreach ([46, 62, 40, 72, 54] as $i => $h) {
        $x = $i * 24 - 8; $top = 150 - $h;
        $towers .= '<rect class="tw" x="' . $x . '" y="' . $top . '" width="22" height="' . ($h + 30) . '" rx="2"/>';
        for ($k = 0; $k < min(6, intdiv($h, 14)); $k++) {
            if (($i + $k) % 3 === 0) continue;
            $towers .= '<rect class="lt" x="' . ($x + 5 + ($k % 2) * 9) . '" y="' . ($top + 7 + intdiv($k, 2) * 14) . '" width="4" height="5" rx="1"/>';
        }
    }
    $cols = '';
    foreach ([108, 116, 124, 190, 198, 206] as $x) { $cols .= '<rect class="col" x="' . $x . '" y="134" width="3" height="26"/>'; }
    // the barangay's own name and place (Control Room > Barangay): "Barangay 183, Zone 20" over "Villamor, Pasay City"
    [$zone, $rest] = array_pad(explode(',', (string) barangay()['place'], 2), 2, '');
    $nameLine = barangay()['name'] . (trim($zone) !== '' ? ', ' . trim($zone) : '');
    $placeLine = trim($rest);
    ob_start(); ?>
<aside class="login-rail gl" id="gl" data-phase="<?= e($phase) ?>" data-wx="<?= e($P['kind']) ?>" aria-label="<?= e(t('At a glance', 'Sa isang tingin')) ?>">
  <div class="gl-scene" id="gl-scene" role="img" aria-label="<?= e(t('The sky over Villamor', 'Ang langit sa Villamor')) ?>">
    <div class="gl-sky"></div>
    <div class="gl-stars" aria-hidden="true"><?= $stars ?></div>
    <div class="gl-sun" aria-hidden="true"><svg class="gl-rays" viewBox="-110 -110 220 220"><?= $rays ?></svg><i class="gl-disc"></i></div>
    <div class="gl-moon" aria-hidden="true"></div>
    <div class="gl-cloud c1" aria-hidden="true"><i class="b"></i><i class="p1"></i><i class="p2"></i><i class="p3"></i><i class="t"></i></div>
    <div class="gl-cloud c2" aria-hidden="true"><i class="b"></i><i class="p1"></i><i class="p2"></i><i class="p3"></i><i class="t"></i><b class="bd">!</b></div>
    <div class="gl-cloud c3" aria-hidden="true"><i class="b"></i><i class="p1"></i><i class="p2"></i><i class="p3"></i><i class="t"></i></div>
    <div class="gl-rain" aria-hidden="true"><i class="r1"></i><i class="r2"></i></div>
    <div class="gl-bolt" aria-hidden="true"></div>
    <div class="gl-veil" aria-hidden="true"></div>
    <svg class="gl-city" viewBox="0 0 330 150" preserveAspectRatio="xMidYMax slice" aria-hidden="true">
      <ellipse class="hill" cx="338" cy="156" rx="100" ry="60"/>
      <rect class="arena" x="150" y="110" width="190" height="70" rx="40"/>
      <path class="lights" d="M162,122H328" fill="none" stroke-width="3" stroke-dasharray="5 7"/>
      <?= $towers ?>
      <rect class="sh-base" x="100" y="124" width="130" height="40" rx="4"/>
      <rect class="sh-a1" x="126" y="106" width="78" height="40" rx="39"/>
      <rect class="sh-a2" x="133" y="113" width="64" height="40" rx="32"/>
      <rect class="sh-a3" x="140" y="120" width="50" height="40" rx="25"/>
      <rect class="sh-door" x="148" y="127" width="34" height="40" rx="17"/>
      <rect class="sh-base" x="163" y="88" width="4" height="20"/><rect class="sh-base" x="157" y="94" width="16" height="4"/>
      <rect class="sh-tower" x="104" y="96" width="18" height="34"/><path class="sh-dome" d="M100,102a13,13 0 0 1 26,0z"/>
      <rect class="sh-tower" x="208" y="96" width="18" height="34"/><path class="sh-dome" d="M204,102a13,13 0 0 1 26,0z"/>
      <?= $cols ?>
      <rect class="tw" x="18" y="134" width="36" height="15" rx="6"/><circle class="tw" cx="26" cy="150" r="4.5"/><circle class="tw" cx="46" cy="150" r="4.5"/>
    </svg>
    <div class="gl-foot" aria-hidden="true"></div>
  </div>

  <?= brgy_seal_img('gl-seal') ?>
  <div class="gl-name"><b><?= e($nameLine) ?></b><?php if ($placeLine !== ''): ?><span><?= e($placeLine) ?></span><?php endif; ?></div>
  <div class="gl-read" aria-live="polite"><small class="gl-when" id="gl-when"><?= e($P['when']) ?></small><div><b id="gl-temp"><?= e($P['temp']) ?></b><span id="gl-cond"><?= e($P['cond']) ?></span></div><small id="gl-sub"><?= e($P['sub']) ?></small></div>

  <div class="gl-rows">
    <div class="gl-warn" id="gl-warn"<?= $P['warn'] ? '' : ' hidden' ?>>
      <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12 3 2.5 20h19L12 3zM12 10v4M12 17.2h.01"/></svg>
      <div><b id="gl-warn-t"><?= e((string) ($P['warn'][0] ?? '')) ?></b><span id="gl-warn-s"><?= e((string) ($P['warn'][1] ?? '')) ?></span></div>
    </div>
    <div class="gl-row gl-flood" id="gl-flood"<?= $P['flood'] !== null ? '' : ' hidden' ?>>
      <svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M3 15c2 0 2-1.5 4.5-1.5S10 15 12 15s2.5-1.5 4.5-1.5S19 15 21 15M3 19c2 0 2-1.5 4.5-1.5S10 19 12 19s2.5-1.5 4.5-1.5S19 19 21 19M12 3c3 3.5 4.5 5.7 4.5 7.5a4.5 4.5 0 0 1-9 0C7.5 8.7 9 6.5 12 3z"/></svg>
      <div><small><?= e(t('FLOOD WATCH', 'BABALA SA BAHA')) ?></small><b id="gl-flood-t"><?= e((string) $P['flood']) ?></b></div>
    </div>
    <div class="gl-hot" id="gl-hot"<?= $P['hot'] !== '' ? '' : ' hidden' ?>>
      <button type="button" class="gl-hotbtn" id="gl-hotbtn" aria-expanded="false" aria-controls="gl-hotlist">
        <svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M5 4h4l2 5-2.5 1.5a11 11 0 0 0 5 5L15 13l5 2v4a2 2 0 0 1-2 2A16 16 0 0 1 3 6a2 2 0 0 1 2-2z"/></svg>
        <span><small><?= e(t('HOTLINES', 'MGA HOTLINE')) ?></small><b id="gl-hot-t"><?= e($P['hotT']) ?></b></span>
        <svg class="chev" viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M6 9l6 6 6-6"/></svg>
      </button>
      <div class="gl-hotlist" id="gl-hotlist" hidden><?= $P['hot'] ?></div>
    </div>
    <div class="gl-row gl-news" id="gl-news"<?= $P['news'] !== '' ? '' : ' hidden' ?>>
      <div><small><svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M5 4h11a2 2 0 0 1 2 2v13H7a2 2 0 0 1-2-2V4zM18 8h2v9a2 2 0 0 1-2 2M8.5 8h6M8.5 11.5h6M8.5 15h3"/></svg> <?= e(t('NEWS FOR PASAY', 'BALITA SA PASAY')) ?></small><span id="gl-news-l"><?= $P['news'] ?></span></div>
    </div>
  </div>
  <p class="gl-note"><?= e(t('Public information · PAGASA, Open-Meteo, news', 'Pampublikong impormasyon · PAGASA, Open-Meteo, balita')) ?></p>
  <p class="gl-powered"><span><?= e(t('Powered by', 'Pinapagana ng')) ?></span><i></i><img src="assets/img/smart-engine-md.webp" width="105" height="41" alt="SMART engine" decoding="async"></p>
</aside>
<?php
    return (string) ob_get_clean();
}
