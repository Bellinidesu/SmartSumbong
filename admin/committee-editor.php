<?php
/**
 * The committee editor (16 Nov 2026, Ace): making a committee, or editing one, on a page of its own.
 *
 * It is a focus mode. The portal's own sidebar is replaced by the sidebar the committee's people will have, drawn live as the committee is edited
 * (its colour, its logo faded behind, its name under the seal; layout.php, $GLOBALS['ss_side_override']), and the editor takes the whole page, so the rest of the
 * portal cannot be opened from here. A person leaving with changes is asked first (committee-editor.js); the notice before entering, with its "do not show
 * this again", is on the committees list (committee-gate.js).
 *
 * It saves through the action the old per-committee forms used (committee_save in settings.php, posted to administrative-services.php): the same fields,
 * the same database functions, nothing new on the backend. A kind of complaint may be seen by several committees (committee_categories has one row per pair),
 * so connecting a kind another committee has shares it; it does not move it. Who leads a committee stays on Administrative Services > Roles.
 *
 *   committee-editor.php          a new committee
 *   committee-editor.php?key=...  edit one
 */
declare(strict_types=1);

require_once __DIR__ . '/includes/auth.php';
require_once __DIR__ . '/includes/layout.php';
require_once __DIR__ . '/includes/forwarding.php';
require_once __DIR__ . '/includes/issues.php';

$admin = require_admin();   // a super admin's page (PAGE_TIERS): anyone else is sent to their own landing page
$db    = db();
session_start_once();

$key = (string) ($_GET['key'] ?? '');
$cc  = $key !== '' ? (committees_all()[$key] ?? null) : null;
if ($key !== '' && $cc === null) { header('Location: administrative-services.php#access', true, 303); exit; }
$isNew = $cc === null;

$freeHex = '#78909C';
foreach (COMMITTEE_PALETTE as $ph) { if (colour_clash($ph, $isNew ? null : $key) === null) { $freeHex = $ph; break; } }
$hex     = $isNew ? $freeHex : committee_colour($key);
$logo    = $isNew ? '' : (string) ($cc['logo_url'] ?? '');
$catAll  = categories_all();
$opts    = category_options();
$ticked  = $isNew ? [] : (array) (committee_categories_all()[$key] ?? []);
$sdTypes = $isNew ? [] : committee_sd_types($db);

// who else already sees each kind (shared, not moved)
$seenBy = [];
foreach (committees_all() as $ck0 => $c0) {
    if ((string) $ck0 === $key || empty($c0['active'])) continue;
    foreach ((array) (committee_categories_all()[$ck0] ?? []) as $cv0) { $seenBy[(string) $cv0][] = (string) $c0['short_en']; }
}

// the first kind's symbol is what the sidebar's faded mark is until a logo is uploaded (layout.php side_colour_style)
$firstSym = 'other';
foreach ($catAll as $ckey => $cat) { if (in_array($ckey, $ticked, true) && !empty($cat['active'])) { $firstSym = sd_icon_for((string) $ckey, (array) $cat); break; } }
$label = $isNew ? t('New committee', 'Bagong komite') : (string) ($cc['short_en'] ?: $cc['name_en']);
$GLOBALS['ss_side_override'] = ['hex' => $hex, 'label' => $label, 'logo' => $logo, 'symbol' => $firstSym];

$stFlash = $_SESSION['st_flash'] ?? null; unset($_SESSION['st_flash']);
$bannerCols = array_slice(array_column($sdTypes[$key] ?? [], 0), 0, 3) ?: [$hex];
$bannerStyle = '--cc:' . $hex . ';--ct:' . ink_on_bold($bannerCols) . ';--g1:' . $bannerCols[0] . ';--g2:' . ($bannerCols[1] ?? $bannerCols[0]) . ';--g3:' . ($bannerCols[2] ?? ($bannerCols[1] ?? $bannerCols[0]));

layout_head($isNew ? t('New committee', 'Bagong komite') : t('Edit committee', 'I-edit ang komite'), 'administrative-services.php'); ?>
<?php if ($stFlash && !empty($stFlash['text'])): ?><div class="p-flash p-flash--<?= ($stFlash['level'] ?? '') === 'error' ? 'error' : 'ok' ?>" role="<?= ($stFlash['level'] ?? '') === 'error' ? 'alert' : 'status' ?>"><?= e((string) $stFlash['text']) ?></div><?php endif; ?>
<div class="ce" id="ce" data-hex="<?= e($hex) ?>" data-new="<?= $isNew ? '1' : '0' ?>"
     data-s-none="<?= e(t('Nothing yet. With nothing connected, this committee sees no complaints.', 'Wala pa. Kapag walang nakakonekta, walang reklamong makikita ang komiteng ito.')) ?>"
     data-s-kind="<?= e(t('1 kind connected', '1 uri ang nakakonekta')) ?>" data-s-kinds="<?= e(t('%d kinds connected', '%d uri ang nakakonekta')) ?>"
     data-s-steps="<?= e(t('%d of 2 steps done', '%d sa 2 hakbang ang tapos')) ?>" data-s-ok="<?= e(t('You can add its staff after it is saved.', 'Maaari mong idagdag ang mga kawani nito pagkatapos i-save.')) ?>"
     data-s-need="<?= e(t('Give it a name (at least 3 letters) to save it.', 'Bigyan ito ng pangalan (hindi bababa sa 3 titik) para ma-save.')) ?>"
     data-s-logo-bad="<?= e(t('That file cannot be used. Choose a PNG, JPG or WebP under 4 MB.', 'Hindi magagamit ang file na iyon. Pumili ng PNG, JPG o WebP na wala pang 4 MB.')) ?>">
  <div class="ce-mode" role="note"><?= p_icon('i-shield', 18) ?><span><?= e(t('Editor mode: the rest of the portal is paused so the sidebar can show this committee live. Save it, or leave, to go back.', 'Editor mode: naka-pause ang iba pang bahagi ng portal para maipakita ng sidebar ang komiteng ito nang live. I-save ito, o umalis, para bumalik.')) ?></span></div>
  <div class="p-topbar ce-top">
    <a class="p-btn p-btn-ghost" href="administrative-services.php#access" data-ce-leave><svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="m15 5-7 7 7 7"/></svg><?= e(t('Committees', 'Mga komite')) ?></a>
    <h1><?= e($isNew ? t('New committee', 'Bagong komite') : t('Edit committee', 'I-edit ang komite')) ?></h1>
  </div>
  <datalist id="cm-palette"><?php foreach (COMMITTEE_PALETTE as $ph): ?><option value="<?= e(strtolower($ph)) ?>"></option><?php endforeach; ?></datalist>

  <div class="ce-grid">
    <form method="post" action="administrative-services.php" enctype="multipart/form-data" id="ce-form" class="ce-steps">
      <input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>"><input type="hidden" name="action" value="committee_save"><input type="hidden" name="key" value="<?= e($key) ?>">

      <section class="p-card p-card-pad ce-step" aria-labelledby="ce-h1">
        <div class="ce-sh"><span class="ce-sb" data-step="1">1</span><div><h2 id="ce-h1"><?= e(t('Name it', 'Pangalanan')) ?></h2><p class="p-hint"><?= e(t('The short name is what the sidebar, the banner and the filters show.', 'Ang maikling pangalan ang makikita sa sidebar, banner at mga filter.')) ?></p></div></div>
        <div class="ce-f2">
          <label class="ty-f" for="ce-name"><span><?= e(t('Full name', 'Buong pangalan')) ?></span>
            <input class="p-input-plain" id="ce-name" name="name_en" value="<?= e((string) ($cc['name_en'] ?? '')) ?>" required minlength="3" maxlength="120" placeholder="<?= e(t('For example: Committee on Senior Citizens', 'Halimbawa: Komite sa mga Nakatatanda')) ?>"></label>
          <label class="ty-f" for="ce-fil"><span><?= e(t('In Tagalog', 'Sa Tagalog')) ?></span>
            <input class="p-input-plain" id="ce-fil" name="name_fil" value="<?= e((string) ($cc['name_fil'] ?? '')) ?>" maxlength="120"></label>
        </div>
        <label class="ty-f" for="ce-short"><span><?= e(t('Short name', 'Maikling pangalan')) ?></span>
          <input class="p-input-plain" id="ce-short" name="short_en" value="<?= e((string) ($cc['short_en'] ?? '')) ?>" maxlength="40"></label>

        <div class="ty-f cmx-logo-f"><span><?= e(t('Sidebar logo', 'Logo sa sidebar')) ?></span>
          <span class="cmx-logo">
            <label class="cmx-lg" title="<?= e(t('The logo beside the barangay seal in this committee\'s sidebar', 'Ang logo sa tabi ng selyo ng barangay sa sidebar ng komiteng ito')) ?>">
              <span class="cmx-lgi ce-lgi" id="ce-lgi" style="--cc:<?= e($hex) ?>;--ci:<?= e(ink_on($hex)) ?>"><?php if ($logo !== ''): ?><img src="<?= e(cld_thumb($logo, 96)) ?>" alt=""><?php else: ?><svg class="cmx-ti" data-ic="<?= e($firstSym) ?>" viewBox="0 0 24 24" aria-hidden="true"></svg><?php endif; ?></span>
              <span class="cmx-lgt" id="ce-lgt" data-have="<?= e(t('Change logo', 'Palitan ang logo')) ?>" data-none="<?= e(t('Upload logo', 'Mag-upload ng logo')) ?>"><?= e($logo !== '' ? t('Change logo', 'Palitan ang logo') : t('Upload logo', 'Mag-upload ng logo')) ?></span>
              <input type="file" name="logo[]" id="ce-logo" accept="image/png,image/jpeg,image/webp"></label>
            <?php if ($logo !== ''): ?><label class="cmx-lgx"><input type="checkbox" name="logo_clear" value="1" id="ce-logo-clear"><span><?= e(t('Use the symbol instead', 'Gamitin ang simbolo')) ?></span></label><?php endif; ?>
          </span>
          <small class="p-hint" id="ce-logo-msg"><?= e(t('It shows faded behind the sidebar. PNG, JPG or WebP.', 'Lumalabas itong malabo sa likod ng sidebar. PNG, JPG o WebP.')) ?></small>
        </div>

        <div class="ty-f"><span><?= e(t('Sidebar colour', 'Kulay ng sidebar')) ?></span>
          <span class="ce-cols" id="ce-cols">
            <?php foreach (COMMITTEE_PALETTE as $ph): $clash = colour_clash($ph, $isNew ? null : $key); ?>
              <button type="button" class="ce-swatch<?= strtolower($ph) === strtolower($hex) ? ' on' : '' ?>" data-hex="<?= e(strtolower($ph)) ?>" style="--sw:<?= e($ph) ?>"<?= $clash ? ' disabled title="' . e(sprintf(t('Too close to %s', 'Masyadong malapit sa %s'), $clash)) . '"' : '' ?> aria-label="<?= e($ph) ?>" aria-pressed="<?= strtolower($ph) === strtolower($hex) ? 'true' : 'false' ?>"></button>
            <?php endforeach; ?>
            <input type="color" name="colour" id="ce-colour" value="<?= e(strtolower($hex)) ?>" list="cm-palette" aria-label="<?= e(t('Pick another colour', 'Pumili ng ibang kulay')) ?>">
          </span>
          <small class="p-hint"><?= e(t('Greyed colours are too close to the super admin colour or another committee; the database refuses them.', 'Ang mga kulay na naka-grey ay masyadong malapit sa kulay ng super admin o ng ibang komite; tinatanggihan ito ng database.')) ?></small>
        </div>
      </section>

      <section class="p-card p-card-pad ce-step" aria-labelledby="ce-h2">
        <div class="ce-sh"><span class="ce-sb" data-step="2">2</span><div class="ce-grow"><h2 id="ce-h2"><?= e(t('What it sees', 'Ano ang nakikita nito')) ?></h2><p class="p-hint"><?= e(t('The kinds of complaint that reach this committee. A kind another committee also sees is shared, not moved.', 'Ang mga uri ng reklamong makararating sa komiteng ito. Ang uring nakikita rin ng ibang komite ay ibinabahagi, hindi inililipat.')) ?></p></div>
          <button type="button" class="p-btn p-btn-primary p-btn-sm" id="ce-kinds-open"><?= e(t('Choose what it sees', 'Piliin ang nakikita nito')) ?></button></div>
        <div class="ce-ksum" id="ce-ksum" aria-live="polite"></div>
      </section>

      <div class="p-card p-card-pad ce-go">
        <div class="ce-prog" id="ce-prog" aria-live="polite"></div>
        <div class="ce-goact">
          <?php if (!$isNew): ?><label class="cmx-sw" title="<?= e(t('Turning a committee off keeps its history, but nobody can be put in it.', 'Kapag in-off ang komite, nananatili ang kasaysayan nito pero walang maidadagdag dito.')) ?>"><input type="checkbox" name="active" value="1" <?= !empty($cc['active']) ? 'checked' : '' ?>><i aria-hidden="true"></i><span><?= e(t('On', 'Naka-on')) ?></span></label><?php endif; ?>
          <a class="p-btn p-btn-ghost" href="administrative-services.php#access" data-ce-leave><?= e(t('Cancel', 'Kanselahin')) ?></a>
          <button class="p-btn p-btn-primary" type="submit" id="ce-save"><?= e($isNew ? t('Make committee', 'Gumawa ng komite') : t('Save changes', 'I-save ang mga pagbabago')) ?></button>
        </div>
      </div>

      <dialog class="ce-dlg ce-kinds" id="ce-kinds" aria-labelledby="ce-kt">
        <div class="ce-dh"><div><h2 id="ce-kt"><?= e(t('What this committee sees', 'Ang nakikita ng komiteng ito')) ?></h2><p class="p-hint"><?= e(t('Tap a kind to connect it. Open a kind to see the options residents pick under it.', 'Pindutin ang isang uri para ikonekta ito. Buksan ang uri para makita ang mga opsyong pinipili ng residente rito.')) ?></p></div>
          <button type="button" class="p-btn p-btn-ghost p-btn-sm" data-ce-close aria-label="<?= e(t('Close', 'Isara')) ?>"><svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M6 6l12 12M18 6 6 18"/></svg></button></div>
        <div class="ce-db">
          <?php foreach (category_pairs() as $cv => $cl): $col = (string) ($catAll[$cv]['colour'] ?? '#78909C'); $icn = sd_icon_for((string) $cv, (array) ($catAll[$cv] ?? [])); $os = array_filter($opts[$cv] ?? [], fn ($o) => $o['active']); $by = $seenBy[$cv] ?? []; ?>
            <div class="ce-k" style="--tc:<?= e($col) ?>;--tk:<?= e(ink_on_bold([$col])) ?>">
              <div class="ce-kh">
                <label class="ce-kl"><input type="checkbox" name="cats[]" value="<?= e((string) $cv) ?>" data-name="<?= e(t($cl[0], $cl[1])) ?>" data-c="<?= e($col) ?>" data-ic="<?= e($icn) ?>"<?= in_array($cv, $ticked, true) ? ' checked' : '' ?>>
                  <span class="ce-kb"><svg class="cmx-ti" data-ic="<?= e($icn) ?>" viewBox="0 0 24 24" aria-hidden="true"></svg></span>
                  <span class="ce-kt"><b><?= e(t($cl[0], $cl[1])) ?></b><small class="<?= $by ? '' : 'ce-warn' ?>"><?= $by ? e(sprintf(t('Also seen by %s', 'Nakikita rin ng %s'), implode(', ', $by))) : e(t('Nobody else sees it yet', 'Wala pang ibang nakakakita nito')) ?></small></span>
                  <span class="ce-sw" aria-hidden="true"></span></label>
                <?php if ($os): ?><details class="ce-ko"><summary><?= e(sprintf(t('See inside (%d)', 'Tingnan ang loob (%d)'), count($os))) ?></summary>
                  <ul><?php foreach ($os as $o): ?><li><?= e(t($o['en'], $o['fil'])) ?></li><?php endforeach; ?></ul></details><?php endif; ?>
              </div>
            </div>
          <?php endforeach; ?>
        </div>
        <div class="ce-df"><span class="p-hint" id="ce-kcount"></span><button type="button" class="p-btn p-btn-primary" data-ce-close><?= e(t('Done', 'Tapos na')) ?></button></div>
      </dialog>
    </form>

    <aside class="p-card p-card-pad ce-aside" aria-label="<?= e(t('Also shows up as', 'Lumalabas din bilang')) ?>">
      <h2><?= e(t('Also shows up as', 'Lumalabas din bilang')) ?></h2>
      <p class="p-hint"><?= e(t('The same look as in the portal. It changes as you type.', 'Kapareho ng itsura sa portal. Nagbabago ito habang nagta-type ka.')) ?></p>
      <p class="p-eyebrow"><?= e(t('Personnel and the committee list', 'Personnel at ang listahan ng komite')) ?></p>
      <div class="cm-chips ce-banner"><a class="cm-chip cm-sd" tabindex="-1" id="ce-banner" style="<?= e($bannerStyle) ?>"><i class="cm-sym cm-sym-sd"></i><span class="cm-n" id="ce-banner-n"><?= e($label) ?></span><b>0</b></a></div>
      <p class="p-eyebrow"><?= e(t('Case page, the Committee row', 'Pahina ng kaso, ang hanay ng Komite')) ?></p>
      <div class="ce-crow"><span class="p-flabel"><?= e(t('Committee', 'Komite')) ?></span><b><i id="ce-crow-i" style="--c:<?= e($hex) ?>"></i><span id="ce-crow-n"><?= e($label) ?></span></b></div>
      <p class="p-eyebrow"><?= e(t('Personnel, the committee filter', 'Personnel, ang filter ng komite')) ?></p>
      <div class="ce-filt"><span class="ce-chip"><i style="--c:#8A93AE"></i><?= e(t('All', 'Lahat')) ?></span><span class="ce-chip"><i id="ce-chip-i" style="--c:<?= e($hex) ?>"></i><span id="ce-chip-n"><?= e($label) ?></span><em>0</em></span></div>
    </aside>
  </div>

  <dialog class="ce-dlg ce-leave" id="ce-leave" aria-labelledby="ce-lt">
    <h2 id="ce-lt"><?= e(t('Leave the committee editor?', 'Aalis ka ba sa editor ng komite?')) ?></h2>
    <p><?= e(t('What you have entered here will not be saved.', 'Hindi mase-save ang mga inilagay mo rito.')) ?></p>
    <div class="ce-df"><button type="button" class="p-btn p-btn-ghost" data-ce-stay><?= e(t('Keep editing', 'Ituloy ang pag-edit')) ?></button><a class="p-btn p-btn-danger-solid" href="administrative-services.php#access" id="ce-leave-go"><?= e(t('Leave without saving', 'Umalis nang hindi nagse-save')) ?></a></div>
  </dialog>
</div>
<script nonce="<?= csp_nonce() ?>" src="assets/js/sd-icons.js?v=<?= e(asset_version('../js/sd-icons.js')) ?>" defer></script>
<script nonce="<?= csp_nonce() ?>" src="assets/js/committee-editor.js?v=<?= e(asset_version('../js/committee-editor.js')) ?>" defer></script>
<?php layout_foot();
