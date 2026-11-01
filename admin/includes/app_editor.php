<?php
/**
 * The Control Room's live view of the resident app: a phone beside the forms, showing what residents see, built from the same rows the app
 * reads (complaint types and their options, the emergency numbers, the parts of the system, the barangay's name and seal). It changes as
 * the forms are typed in (assets/js/app-editor.js); saving a form is what publishes it, as before: the app already reads all of these.
 * The preview is the app's palette and shape, not a screenshot of the app.
 */
declare(strict_types=1);

/** Which screen of the phone each Control Room tab belongs to ('' = the tab has no screen). */
const APP_EDITOR_SCREENS = ['types' => 'report', 'wording' => 'report', 'hotlines' => 'emergency', 'parts' => 'home', 'brgy' => 'splash', 'rules' => '', 'updates' => ''];

/**
 * @param array $catOpts  category key => its options rows (label_en, label_fil, active)
 * @param array $hlTop    the top-level hotline groups; $hlKids their sub-groups by parent id; $hlNums their numbers by group id
 * @param array $switches the feature switch rows
 */
function render_app_phone(array $catOpts, array $hlTop, array $hlKids, array $hlNums, array $switches): void
{
    $b = barangay();
    $cats = categories_all();
    $firstKey = (string) (array_key_first(array_filter($cats, fn ($c) => !empty($c['active']))) ?? '');
    $screenName = ['report' => t('Report', 'Ulat'), 'emergency' => t('Emergency', 'Emerhensiya'), 'home' => t('Home', 'Tahanan'), 'splash' => t('Splash', 'Simula')];
    $grp = function (array $g, int $depth) use (&$grp, $hlKids, $hlNums): void {
        $gid = (string) $g['id']; $nums = $hlNums[$gid] ?? []; ?>
      <div class="ed-hg<?= empty($g['is_active']) ? ' ed-off' : '' ?><?= $depth ? ' ed-sub' : '' ?>" data-gid="<?= e($gid) ?>" data-display="<?= e((string) ($g['display'] ?? 'inline')) ?>">
        <h4><span class="ed-gname"><?= e((string) $g['name']) ?></span><small class="ed-gcount"></small></h4>
        <ul>
          <?php foreach ($nums as $n): ?>
            <li class="ed-hn<?= empty($n['is_active']) ? ' ed-off' : '' ?>" data-nid="<?= e((string) $n['id']) ?>"><span><b class="ed-nl"><?= e((string) $n['label']) ?></b><small class="ed-nn"><?= e((string) $n['number']) ?></small></span><i class="ed-call" aria-hidden="true"></i></li>
          <?php endforeach; ?>
        </ul>
        <?php foreach ($hlKids[$gid] ?? [] as $k) $grp($k, $depth + 1); ?>
      </div>
    <?php }; ?>
<aside class="ed-phone" id="ed-phone" data-screen="report" aria-label="<?= e(t('Live view of the app', 'Live na tanaw ng app')) ?>">
  <div class="ed-bar"><b><?= e(t('Live view of the app', 'Live na tanaw ng app')) ?></b><small><?= e(t('Changes show here as you type. Saving publishes them.', 'Lumalabas dito ang mga pagbabago habang nagta-type. Ang pag-save ang naglalathala.')) ?></small></div>
  <div class="ed-dev">
    <div class="ed-notch" aria-hidden="true"></div>
    <div class="ed-screen">

      <section class="ed-sc" data-sc="report">
        <header class="ed-head"><small><?= e(t('Report a problem', 'Mag-ulat ng problema')) ?></small><h3><?= e(t('What happened?', 'Ano ang nangyari?')) ?></h3></header>
        <div class="ed-cats" id="ed-cats" data-one="<?= e(t('%d option', '%d opsyon')) ?>" data-many="<?= e(t('%d options', '%d opsyon')) ?>">
          <?php foreach ($cats as $ck => $cc): $opts = $catOpts[$ck] ?? []; $nOn = count(array_filter($opts, fn ($o) => !empty($o['active']))); ?>
            <button type="button" class="ed-cat<?= empty($cc['active']) ? ' ed-off' : '' ?><?= $ck === $firstKey ? ' ed-sel' : '' ?>" data-key="<?= e((string) $ck) ?>" style="--c:<?= e((string) $cc['colour']) ?>">
              <i class="ed-ic"><svg class="cm-ic cmx-ti" data-ic="<?= e(sd_icon_for((string) $ck, (array) $cc)) ?>" viewBox="0 0 24 24" aria-hidden="true"></svg></i>
              <b class="ed-cn"><?= e(t((string) $cc['en'], (string) $cc['fil'])) ?></b><small class="ed-cc"><?= e(sprintf($nOn === 1 ? t('%d option', '%d opsyon') : t('%d options', '%d opsyon'), $nOn)) ?></small>
            </button>
          <?php endforeach; ?>
        </div>
        <?php foreach ($cats as $ck => $cc): ?>
          <div class="ed-opts<?= (string) $ck === $firstKey ? '' : ' ed-hide' ?>" data-for="<?= e((string) $ck) ?>">
            <h5><?= e(t('What kind?', 'Anong uri?')) ?></h5>
            <ul>
              <?php foreach ($catOpts[$ck] ?? [] as $o): ?><li class="ed-opt<?= empty($o['active']) ? ' ed-off' : '' ?>" data-oid="<?= (int) $o['id'] ?>"><span class="ed-ol"><?= e(t((string) $o['label_en'], (string) $o['label_fil'])) ?></span><i class="ed-chev" aria-hidden="true"></i></li><?php endforeach; ?>
              <li class="ed-opt ed-hide ed-new" data-oid="new"><span class="ed-ol"></span><i class="ed-chev" aria-hidden="true"></i></li>
            </ul>
          </div>
        <?php endforeach; ?>
      </section>

      <section class="ed-sc ed-hide" data-sc="emergency">
        <header class="ed-head ed-head-red"><small><?= e(t('Emergency', 'Emerhensiya')) ?></small><h3><?= e(t('Who to call', 'Sino ang tatawagan')) ?></h3></header>
        <div class="ed-hgs"><?php foreach ($hlTop as $g) $grp($g, 0); ?></div>
      </section>

      <section class="ed-sc ed-hide" data-sc="home">
        <header class="ed-head ed-head-brand"><span class="ed-seal"><?= brgy_seal_img('ed-sealimg') ?></span><span><small class="ed-pl"><?= e($b['place']) ?></small><h3 class="ed-bn"><?= e($b['name']) ?></h3></span></header>
        <p class="ed-parts-h"><?= e(t('Parts you can switch on or off', 'Mga bahaging maaaring i-on o i-off')) ?></p>
        <div class="ed-sws">
          <?php foreach ($switches as $sw): ?>
            <div class="ed-sw<?= empty($sw['enabled']) ? ' ed-off' : '' ?>" data-key="<?= e((string) $sw['key']) ?>"><i class="ed-ic ed-ic-n"><?= e(mb_strtoupper(mb_substr((string) $sw['label_en'], 0, 1))) ?></i><b><?= e(t((string) $sw['label_en'], (string) $sw['label_fil'])) ?></b></div>
          <?php endforeach; ?>
        </div>
        <p class="ed-hidden" id="ed-hidden" hidden></p>
      </section>

      <section class="ed-sc ed-hide ed-splash" data-sc="splash">
        <span class="ed-seal ed-seal-lg"><?= brgy_seal_img('ed-sealimg') ?></span>
        <small class="ed-pl"><?= e($b['place']) ?></small><h3 class="ed-bn"><?= e($b['name']) ?></h3>
        <em>SmartSumbong</em>
      </section>

    </div>
  </div>
  <nav class="ed-switch" aria-label="<?= e(t('Screens', 'Mga screen')) ?>">
    <?php foreach ($screenName as $sk => $sl): ?><button type="button" data-go="<?= e($sk) ?>"><?= e($sl) ?></button><?php endforeach; ?>
  </nav>
</aside>
<?php
}

/** The Control Room's page footer: closes the forms' column, adds the phone beside it and starts its script. Called where the page ends. */
function app_editor_end(array $catOpts, array $hlTop, array $hlKids, array $hlNums, array $switches): void
{
    echo '</div>';
    render_app_phone($catOpts, $hlTop, $hlKids, $hlNums, $switches);
    echo '</div><script src="assets/js/app-editor.js?v=' . e(asset_version('../js/app-editor.js')) . '"></script>';
}
