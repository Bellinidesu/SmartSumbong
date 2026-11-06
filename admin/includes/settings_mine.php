<?php
/**
 * Settings for a Kagawad or a staff member (Ace, 4 Nov 2026): only what their rung may see and change. Appearance (their own
 * theme, sidebar, language and map surfaces, kept in their browser), My committee (read only: the super admins set it up in
 * Administrative Services) and SMART (their module of the engine, 0165: what it watches and what it reads right now).
 */
declare(strict_types=1);

/** My committee: its banner, logo, colour, names, the kinds of complaint it sees and its people, read only. */
function render_my_committee_pane(Supabase $db): void
{
    $ck = (string) (current_admin()['committee'] ?? '');
    $c = committees_all()[$ck] ?? null; ?>
<section class="st-pane" data-pane="committee" hidden>
  <?php if (!$c): ?>
    <div class="p-card p-card-pad"><p class="st-note" style="margin:0"><?= e(t('You are not in a committee yet. A super admin puts you in one in Administrative Services.', 'Wala ka pa sa komite. Ilalagay ka ng isang super admin sa Administrative Services.')) ?></p></div>
  <?php else:
    $sdTypes = committee_sd_types($db);
    $catAll = categories_all();
    $cats = []; $people = []; $nT = 0;
    try {
        $got = $db->selectMany([
            'cats'   => ['committee_categories', ['select' => 'category', 'committee' => 'eq.' . $ck], true],
            'people' => ['users', ['select' => 'id,full_name,admin_tier,official_role', 'role' => 'eq.admin', 'committee' => 'eq.' . $ck, 'is_test' => 'is.false', 'removed_at' => 'is.null', 'order' => 'admin_tier.asc,full_name.asc'], true],
            'tc'     => ['rpc/personnel_committees', [], true],
        ]);
        $cats = array_column((array) ($got['cats'] ?? []), 'category');
        $people = (array) ($got['people'] ?? []);
        foreach ((array) ($got['tc'] ?? []) as $row) {
            foreach ((array) ($row['committees'] ?? []) as $x) { if (($x['key'] ?? '') === $ck && ($x['status'] ?? '') === 'approved') { $nT++; } }
        }
    } catch (SupabaseError) { /* the card shows what it has */ }
    $hex = committee_colour($ck); ?>
  <div class="p-card my-com">
    <div class="cm-chips cmx-banner" aria-hidden="true"><a class="cm-chip cm-sd" tabindex="-1" style="<?= e(cm_banner_style($ck, $sdTypes)) ?>"><?= cm_sym_tag($ck, $sdTypes, (string) $c['short_en']) ?><span class="cm-n"><?= e((string) $c['short_en']) ?></span><b><?= $nT ?></b></a></div>
    <div class="my-com-body">
      <div class="my-com-id">
        <?= committee_logo_html($ck, 'my-com-logo') ?>
        <dl class="my-com-dl">
          <div><dt><?= e(t('Full name', 'Buong pangalan')) ?></dt><dd><?= e((string) $c['name_en']) ?></dd></div>
          <div><dt><?= e(t('In Tagalog', 'Sa Tagalog')) ?></dt><dd><?= e((string) $c['name_fil']) ?></dd></div>
          <div><dt><?= e(t('Sidebar colour', 'Kulay ng sidebar')) ?></dt><dd><span class="my-com-sw" style="--cc:<?= e($hex) ?>"></span><code><?= e($hex) ?></code></dd></div>
        </dl>
      </div>
      <div class="my-com-sec">
        <p class="p-eyebrow"><?= e(t('Kinds of complaint it sees', 'Mga uri ng reklamong nakikita nito')) ?></p>
        <?php if (!$cats): ?><p class="st-note"><?= e(t('None yet. Until a super admin connects some, your committee sees no new complaints.', 'Wala pa. Hangga\'t walang ikinokonekta ang super admin, walang bagong reklamong makikita ang komite mo.')) ?></p><?php endif; ?>
        <div class="cmx-chips"><?php foreach (category_pairs() as $cv => $cl): if (!in_array($cv, $cats, true)) continue; $col = (string) ($catAll[$cv]['colour'] ?? '#78909C'); ?>
          <span class="cmx-t cmx-t-ro" style="--tc:<?= e($col) ?>;--tk:<?= e(ink_on_bold([$col])) ?>"><svg class="cm-ic cmx-ti" data-ic="<?= e(sd_icon_for((string) $cv, (array) ($catAll[$cv] ?? []))) ?>" viewBox="0 0 24 24" aria-hidden="true"></svg><span><?= e(t($cl[0], $cl[1])) ?></span></span>
        <?php endforeach; ?></div>
      </div>
      <div class="my-com-sec">
        <p class="p-eyebrow"><?= e(t('Its people', 'Ang mga tao nito')) ?></p>
        <ul class="my-com-people">
          <?php foreach ($people as $p): ?>
            <li><?= admin_avatar_html(['full_name' => $p['full_name'], 'avatar_url' => null]) ?><b><?= e(formal_name((string) $p['full_name'])) ?></b><?= rank_chip(($p['admin_tier'] ?? '') === 'committee' ? 'kagawad' : ($p['official_role'] ?? null)) ?></li>
          <?php endforeach; ?>
          <li class="my-com-tanods"><?= p_icon('i-users', 18) ?><span><?= e($nT === 1 ? t('1 tanod', 'Isang tanod') : sprintf(t('%d tanods', '%d tanod'), $nT)) ?></span><a href="personnel.php"><?= e(t('See them in Personnel', 'Tingnan sa Personnel')) ?></a></li>
        </ul>
      </div>
      <p class="st-note my-com-note"><?= e(t('A super admin sets these up in Administrative Services: the names, the logo, the colour, the kinds of complaint and who is in the committee.', 'Ang super admin ang nag-aayos nito sa Administrative Services: ang mga pangalan, logo, kulay, mga uri ng reklamo at kung sino ang nasa komite.')) ?></p>
    </div>
  </div>
  <?php endif; ?>
</section>
<?php
}

/** SMART: the person's module of the engine (0165), what it watches, what it gives them and what it reads right now. */
function render_my_module_pane(Supabase $db): void
{
    $m = null;
    try { $m = $db->rpc('smart_module'); } catch (SupabaseError) { $m = null; }
    $isCom = is_committee();
    $catAll = categories_all();
    $name = $isCom ? t('Committee module', 'Module ng komite') : t('Staff module', 'Module ng kawani');
    $signals = [
        [t('Deadline risk', 'Panganib sa deadline'), t('Cases likely to miss their deadline, from how long the same kind of case usually takes', 'Mga kasong maaaring lumampas sa deadline, batay sa karaniwang tagal ng ganitong kaso')],
        [t('Quiet cases', 'Mga tahimik na kaso'), t('Open cases nobody has touched for days', 'Mga bukas na kasong ilang araw nang walang galaw')],
        [t('Spikes', 'Biglang dami'), t('A kind of complaint coming in far more than usual this week', 'Isang uri ng reklamong mas marami kaysa karaniwan ngayong linggo')],
        [t('Recurring problems', 'Paulit-ulit na problema'), t('The same problem reported at the same spot week after week', 'Iisang problema sa iisang lugar linggo-linggo')],
        [t('Tanods', 'Mga tanod'), t('Who of the committee\'s tanods is free, busy, on a break or off', 'Sino sa mga tanod ng komite ang bakante, abala, nagpapahinga o wala')],
    ];
    if ($isCom) { array_unshift($signals, [t('Needs your decision', 'Kailangan ng desisyon mo'), t('Escalations to approve, tanods to pick, cases forwarded to you, your staff\'s flags', 'Mga eskalasyong aaprubahan, tanod na pipiliin, mga kasong ipinasa sa iyo, mga flag ng kawani mo')]); }
    $tile = fn (string $label, $n, string $tone = '') => '<div class="sm-tile' . ($tone !== '' && (int) $n > 0 ? ' sm-' . $tone : '') . '"><span>' . e($label) . '</span><b class="p-num">' . ($n === null ? '—' : (int) $n) . '</b></div>'; ?>
<section class="st-pane" data-pane="module" hidden>
  <div class="p-card p-card-pad my-mod">
    <div class="my-mod-head"><span class="my-mod-brain" aria-hidden="true"><?= smart_brain(26) ?></span>
      <div><p class="p-eyebrow" style="margin:0"><?= e(t('Your SMART module', 'Ang SMART module mo')) ?></p><h2><?= e($name) ?></h2></div></div>
    <p class="st-note"><?= e($isCom
        ? t('The engine reads every case your committee may open and tells you what needs you: what to decide, what is at risk, what has gone quiet. It is the same engine the super admins use, kept to your committee.', 'Binabasa ng engine ang bawat kasong mabubuksan ng komite mo at sinasabi kung ano ang kailangan ka: ano ang dapat pagpasyahan, ano ang nanganganib, ano ang natahimik. Ito rin ang engine ng mga super admin, para sa komite mo lamang.')
        : t('The engine reads every case your committee may open and tells you what needs handling: your own cases, the ones nobody has taken, what is at risk and what has gone quiet. Decisions stay with your Kagawad.', 'Binabasa ng engine ang bawat kasong mabubuksan ng komite mo at sinasabi kung ano ang dapat asikasuhin: ang mga kaso mo, ang mga walang humahawak, ano ang nanganganib at ano ang natahimik. Nasa Kagawad mo ang mga desisyon.')) ?></p>
    <?php if (!is_array($m)): ?>
      <p class="st-note sm-wait"><?= e(t('The engine could not be read just now. Try again in a moment.', 'Hindi mabasa ang engine ngayon. Subukan muli mamaya.')) ?></p>
    <?php else: $cn = (array) ($m['counts'] ?? []); $dc = is_array($m['decisions'] ?? null) ? $m['decisions'] : null; $tn = (array) ($m['tanods'] ?? []); ?>
      <?php if ($isCom && $dc !== null): ?>
        <p class="p-eyebrow sm-h"><?= e(t('Needs your decision', 'Kailangan ng desisyon mo')) ?></p>
        <div class="sm-tiles sm-four">
          <?= $tile(t('Escalations to approve', 'Eskalasyong aaprubahan'), $dc['escalations'] ?? 0, 'hot') ?>
          <?= $tile(t('Tanods to pick', 'Tanod na pipiliin'), $dc['reroute'] ?? 0, 'hot') ?>
          <?= $tile(t('Forwarded to you', 'Ipinasa sa iyo'), $dc['forwarded'] ?? 0, 'warm') ?>
          <?= $tile(t('Staff flags', 'Mga flag ng kawani'), $dc['flags'] ?? 0, 'warm') ?>
        </div>
      <?php endif; ?>
      <p class="p-eyebrow sm-h"><?= e(t('Right now', 'Ngayon')) ?></p>
      <div class="sm-tiles">
        <?= $tile(t('Open cases', 'Bukas na kaso'), $cn['open'] ?? 0) ?>
        <?= $tile(t('Urgent, no tanod yet', 'Urgent, wala pang tanod'), $cn['urgent_waiting'] ?? 0, 'hot') ?>
        <?= $tile(t('Overdue', 'Lampas-oras'), $cn['overdue'] ?? 0, 'hot') ?>
        <?= $tile(t('Due in 24 hours', 'Deadline sa loob ng 24 oras'), $cn['due_24h'] ?? 0, 'warm') ?>
        <?= $tile(t('Nobody has taken', 'Walang humahawak'), $cn['untaken'] ?? 0, 'warm') ?>
        <?= $tile(t('Yours', 'Hawak mo'), $cn['mine'] ?? 0) ?>
        <?= $tile(t('At risk of the deadline', 'Nanganganib sa deadline'), count((array) ($m['deadline_risk'] ?? [])), 'warm') ?>
        <?= $tile(t('Quiet cases', 'Mga tahimik na kaso'), count((array) ($m['quiet'] ?? [])), 'warm') ?>
        <?= $tile(t('Tanods free', 'Bakanteng tanod'), $tn['on_duty'] ?? 0) ?>
        <?= $tile(t('Tanods on a case', 'Tanod na may kaso'), $tn['busy'] ?? 0) ?>
      </div>
    <?php endif; ?>
  </div>
  <div class="p-card p-card-pad my-mod-what">
    <div>
      <p class="p-eyebrow"><?= e(t('What it watches', 'Ano ang binabantayan nito')) ?></p>
      <div class="cmx-chips"><?php foreach ((array) ($m['categories'] ?? []) as $cv): $col = (string) ($catAll[$cv]['colour'] ?? '#78909C'); $cl = category_pairs()[$cv] ?? [$cv, $cv]; ?>
        <span class="cmx-t cmx-t-ro" style="--tc:<?= e($col) ?>;--tk:<?= e(ink_on_bold([$col])) ?>"><svg class="cm-ic cmx-ti" data-ic="<?= e(sd_icon_for((string) $cv, (array) ($catAll[$cv] ?? []))) ?>" viewBox="0 0 24 24" aria-hidden="true"></svg><span><?= e(t($cl[0], $cl[1])) ?></span></span>
      <?php endforeach; ?></div>
      <p class="st-note"><?= e(t('Your committee\'s cases, and the cases forwarded to it. The kinds above are the ones a super admin connected to your committee.', 'Ang mga kaso ng komite mo, at ang mga kasong ipinasa rito. Ang mga uri sa itaas ay ang ikinonekta ng super admin sa komite mo.')) ?></p>
    </div>
    <div>
      <p class="p-eyebrow"><?= e(t('What it gives you', 'Ano ang ibinibigay nito sa iyo')) ?></p>
      <ul class="my-mod-sig"><?php foreach ($signals as [$h, $d]): ?><li><b><?= e($h) ?></b><span><?= e($d) ?></span></li><?php endforeach; ?></ul>
    </div>
  </div>
</section>
<?php
}
