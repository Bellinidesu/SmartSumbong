<?php
/**
 * Forwarding a case between committees (0152; docs/ROLES_AND_PAGES.md, "Case Reports: forwarding").
 *
 * A super admin forwards a case to a committee; a Kagawad forwards to another committee or to the super admins to place it;
 * a staff member (moderator) flags it with the reason and their Kagawad decides. The database does the work and keeps the log
 * (forward_case, flag_case_for_forward, dismiss_forward_flag, the case_forwards table); this file draws it.
 *
 *   committee_pill($key)         the committee a case is with, as a pill in its colour ("No committee" in red)
 *   can_forward()                a super admin or a Kagawad (staff flag instead)
 *   forward_dialog()             the one dialog the list's Forward and Flag buttons open
 *   forwarding_pins($db)         what waits on this person, for the top of Notifications
 */
declare(strict_types=1);

/** Who forwards: a super admin or a Kagawad. Staff flag; a captain only reads. */
function can_forward(): bool
{
    return in_array(my_tier(), ['super', 'committee'], true);
}

/** A committee's symbol: the first letters of its first two main words ("Peace and Order" is PO), in a tile in its colour. */
function cm_mono(string $name): string
{
    $stop = ['and', 'of', 'the', 'at', '&', 'ng', 'sa', 'ang'];
    $w = array_values(array_filter(preg_split('/[\s\-]+/u', trim($name)) ?: [], fn ($x) => $x !== '' && !in_array(mb_strtolower($x), $stop, true)));
    return mb_strtoupper(mb_substr($w[0] ?? '?', 0, 1) . (isset($w[1]) ? mb_substr($w[1], 0, 1) : ''));
}

/** The committee a case is with, as a pill; $awaiting: forwarded to the super admins to place. */
function committee_pill(?string $key, bool $awaiting = false): string
{
    if ($awaiting) {
        return '<span class="cm-pill cm-await" title="' . e(t('With the super admins', 'Nasa mga super admin')) . '" style="--cc:' . e(barangay()['super_colour'] ?? SUPER_BLUE) . '"><i></i>' . e(t('With the super admins', 'Nasa mga super admin')) . '</span>';
    }
    if ($key === null || $key === '' || !isset(committees_all()[$key])) {
        return '<span class="cm-pill cm-none" title="' . e(t('No committee', 'Walang komite')) . '"><i></i>' . e(t('No committee', 'Walang komite')) . '</span>';
    }
    return '<span class="cm-pill" title="' . e((string) committees_all()[$key]['short_en']) . '" style="--cc:' . e(committee_colour($key)) . '"><i></i>' . e((string) committees_all()[$key]['short_en']) . '</span>';
}

/** 0156: a small dot in the committee's colour before a notification about one of its cases. */
function notification_dot(array $n): string
{
    $k = (string) ($n['notification_committee'] ?? '');
    if ($k === '' || !isset(committees_all()[$k])) return '';
    $name = (string) committees_all()[$k]['short_en'];
    return '<span class="nf-dot" style="--cc:' . e(committee_colour($k)) . '" title="' . e($name) . '"><span class="p-sr">' . e($name) . '</span></span>';
}

/** "Forwarded from Peace and Order" under a forwarded case's category; $forwards newest first. */
function forwarded_tag(array $forwards): string
{
    foreach ($forwards as $f) {
        if (($f['kind'] ?? '') !== 'forward') continue;
        $from = $f['from_committee'] ?? null;
        $name = $from && isset(committees_all()[$from]) ? (string) committees_all()[$from]['short_en'] : t('the super admins', 'ang mga super admin');
        $txt = e(sprintf(t('Forwarded from %s', 'Ipinasa mula sa %s'), $name));
        return '<div class="cm-fwd" title="' . $txt . '">' . $txt . '</div>';
    }
    return '';
}

/** The options of the "to" pick list: the active committees, and for a Kagawad the super admins. */
function forward_options(?string $except = null): string
{
    $o = '';
    if (my_tier() === 'committee') {
        $o .= '<option value="__super">' . e(t('The super admins, to place it', 'Ang mga super admin, para ilagay')) . '</option>';
    }
    foreach (committees_active() as $k => $label) {
        if ($k === $except) continue;
        $o .= '<option value="' . e($k) . '">' . e($label) . '</option>';
    }
    return $o;
}

/** The one dialog the Forward and Flag buttons open. $back: the list address to return to. */
function forward_dialog(string $back): string
{
    $mod = my_tier() === 'moderator';
    ob_start(); ?>
<dialog class="fw-dlg" id="fw-dlg" aria-labelledby="fw-title">
  <form method="post" class="fw-form">
    <input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>">
    <input type="hidden" name="action" value="<?= $mod ? 'flag_list' : 'forward_list' ?>">
    <input type="hidden" name="ids" id="fw-ids" value="">
    <input type="hidden" name="back" value="<?= e($back) ?>">
    <h2 id="fw-title"><?= e($mod ? t('Flag for forwarding', 'I-flag para ipasa') : t('Forward to a committee', 'Ipasa sa isang komite')) ?></h2>
    <p class="p-hint" id="fw-what"></p>
    <label class="p-cfield"><span class="p-flabel"><?= e($mod ? t('Suggest a committee (your Kagawad decides)', 'Magmungkahi ng komite (ang Kagawad mo ang magpapasya)') : t('Forward to', 'Ipasa sa')) ?></span>
      <select class="p-input-plain" name="to" id="fw-to" <?= $mod ? '' : 'required' ?>>
        <?php if ($mod): ?><option value=""><?= e(t('No suggestion', 'Walang mungkahi')) ?></option><?php else: ?><option value="" disabled selected><?= e(t('Choose', 'Pumili')) ?></option><?php endif; ?>
        <?= forward_options() ?>
      </select></label>
    <label class="p-cfield"><span class="p-flabel"><?= e($mod ? t('Why should it be forwarded? Your Kagawad reads this.', 'Bakit ito dapat ipasa? Babasahin ito ng Kagawad mo.') : t('Note for the committee (optional)', 'Paalala para sa komite (opsyonal)')) ?></span>
      <textarea class="p-input-plain" name="note" rows="3" maxlength="500" <?= $mod ? 'required minlength="5"' : '' ?>></textarea></label>
    <div class="fw-act">
      <button type="button" class="p-btn p-btn-ghost p-btn-sm" data-fw-close><?= e(t('Cancel', 'Kanselahin')) ?></button>
      <button type="submit" class="p-btn p-btn-primary p-btn-sm"><?= e($mod ? t('Send to my Kagawad', 'Ipadala sa Kagawad ko') : t('Forward', 'Ipasa')) ?></button>
    </div>
  </form>
</dialog>
<?php
    return (string) ob_get_clean();
}

/**
 * What waits on this person, pinned at the top of Notifications (Ace: "pinned at the top because they're urgent"): for a super
 * admin, the cases handed to the super admins to place; for a Kagawad, the cases their staff flagged and the cases forwarded to
 * their committee that they have not opened yet.
 *
 * @return list<array{report:string, tracking:string, text:string, at:string, kind:string, href?:?string}>
 */
function forwarding_pins(Supabase $db): array
{
    $pins = [];
    $tier = my_tier();
    $me = current_admin() ?? [];
    try {
        if ($tier === 'super') {
            foreach ((array) $db->select('reports', ['select' => 'id,tracking_id,updated_at', 'awaiting_placement' => 'is.true', 'deleted_at' => 'is.null', 'order' => 'updated_at.asc', 'limit' => '20']) as $r) {
                $pins[] = ['report' => (string) $r['id'], 'tracking' => (string) $r['tracking_id'], 'kind' => 'place', 'at' => (string) $r['updated_at'],
                           'text' => t('Forwarded to the super admins: place it with a committee.', 'Ipinasa sa mga super admin: ilagay ito sa isang komite.')];
            }
        }
        // 0155: a reroute waiting on this Kagawad (or, for a super admin, on any): pick a tanod before the wait runs out
        if ($tier === 'super' || ($tier === 'committee' && !empty($me['committee']))) {
            $rq = ['select' => 'id,report_id,due_at,report:reports!reroute_questions_report_id_fkey(tracking_id)', 'state' => 'eq.open', 'order' => 'due_at.asc', 'limit' => '20'];
            if ($tier === 'committee') { $rq['committee'] = 'eq.' . $me['committee']; }
            foreach ((array) $db->select('reroute_questions', $rq) as $q) {
                $msg = (array) $db->select('inbox_messages', ['select' => 'id', 'question_id' => 'eq.' . (int) $q['id'], 'recipient' => 'eq.' . ($me['id'] ?? '0'), 'limit' => '1']);
                $pins[] = ['report' => (string) $q['report_id'], 'tracking' => (string) ($q['report']['tracking_id'] ?? ''), 'kind' => 'reroute', 'at' => (string) $q['due_at'],
                           'href' => $msg ? 'inbox.php?m=' . (int) $msg[0]['id'] : null,
                           'text' => sprintf(t('No tanod of the committee is free. Pick one by %s, or the nearest from any committee is sent.', 'Walang bakanteng tanod ang komite. Pumili bago mag-%s, o ipapadala ang pinakamalapit mula sa kahit anong komite.'),
                                             (new DateTimeImmutable((string) $q['due_at']))->setTimezone(new DateTimeZone('Asia/Manila'))->format('g:i A'))];
            }
        }
        if ($tier === 'committee' && !empty($me['committee'])) {
            $flags = (array) $db->select('case_forward_flags', ['select' => 'id,report_id,note,created_at', 'from_committee' => 'eq.' . $me['committee'], 'order' => 'created_at.asc', 'limit' => '20']);
            $fwd = (array) $db->select('notifications', ['select' => 'report_id,message,created_at', 'user_id' => 'eq.' . $me['id'], 'kind' => 'eq.case_forwarded', 'is_read' => 'is.false', 'order' => 'created_at.asc', 'limit' => '20']);
            $ids = array_values(array_unique(array_filter(array_merge(array_column($flags, 'report_id'), array_column($fwd, 'report_id')))));
            $track = [];
            if ($ids) {
                foreach ((array) $db->select('reports', ['select' => 'id,tracking_id', 'id' => 'in.(' . implode(',', $ids) . ')']) as $r) { $track[(string) $r['id']] = (string) $r['tracking_id']; }
            }
            foreach ($flags as $f) {
                $pins[] = ['report' => (string) $f['report_id'], 'tracking' => $track[(string) $f['report_id']] ?? '', 'kind' => 'flag', 'at' => (string) $f['created_at'],
                           'text' => sprintf(t('Staff flagged it for forwarding: %s', 'In-flag ng kawani para ipasa: %s'), (string) $f['note'])];
            }
            foreach ($fwd as $n) {
                $pins[] = ['report' => (string) $n['report_id'], 'tracking' => $track[(string) $n['report_id']] ?? '', 'kind' => 'fwd', 'at' => (string) $n['created_at'], 'text' => (string) $n['message']];
            }
        }
    } catch (SupabaseError) {}
    // most urgent first: a reroute question has a clock on it, then a staff flag, then cases to place or forwarded to us
    $rank = ['reroute' => 0, 'flag' => 1, 'fwd' => 2, 'place' => 3];
    usort($pins, fn ($a, $b) => [$rank[$a['kind']] ?? 9, $a['at']] <=> [$rank[$b['kind']] ?? 9, $b['at']]);
    return $pins;
}

/** The Spatial Distribution symbol a complaint type wears (the map's own icon family, assets/js/sd-icons.js). */
function sd_icon_for(string $catKey, array $cat = []): string
{
    $iconOf = ['street_obstruction' => 'obstruction', 'public_safety_infrastructure' => 'infra', 'environmental_waste_hazard' => 'waste', 'animal_welfare' => 'animal',
               'traffic_violation' => 'traffic', 'barangay_service' => 'service', 'peace_order_nuisance' => 'noise', 'other' => 'other'];
    return $iconOf[(string) ($cat['icon'] ?? $catKey)] ?? ($iconOf[$catKey] ?? 'other');
}

/**
 * Spatial Distribution leads: a committee is connected to the complaint types its creator ticked, so it wears their colours and
 * their symbols (the map's own icon family, assets/js/sd-icons.js). committee key => list of [colour, SD icon name], in the complaint types' order.
 */
function committee_sd_types(Supabase $db): array
{
    $out = [];
    try {
        $tick = [];
        foreach ((array) $db->select('committee_categories', ['select' => 'committee,category']) as $x) { $tick[(string) $x['committee']][(string) $x['category']] = true; }
        foreach ($tick as $ckey => $cats) {
            foreach (categories_all() as $catKey => $cat) {
                if (!isset($cats[$catKey]) || empty($cat['active'])) continue;
                $out[$ckey][] = [(string) $cat['colour'], sd_icon_for((string) $catKey, (array) $cat)];
            }
        }
    } catch (Throwable) { /* the banners fall back to the committee's own colour */ }
    return $out;
}

/** The custom properties of a committee's banner: its own colour, the washes of its (up to three) complaint types and a lettering colour that reads on them. */
function cm_banner_style(string $ck, array $sdTypes): string
{
    $sd = array_slice($sdTypes[$ck] ?? [], 0, 3);
    $cols = $sd ? array_column($sd, 0) : [committee_colour($ck)];
    return '--cc:' . committee_colour($ck) . ';--ct:' . ink_on_bold($cols) . ';--g1:' . $cols[0] . ';--g2:' . ($cols[1] ?? $cols[0]) . ';--g3:' . ($cols[2] ?? ($cols[1] ?? $cols[0]));
}

/** The symbol element of a committee's banner: its types' SD icons (filled in by committee_banner_script), "+N" for more than three, or its initials. */
function cm_sym_tag(string $ck, array $sdTypes, string $label): string
{
    $all = $sdTypes[$ck] ?? [];
    if (!$all) { return '<i class="cm-sym">' . e(cm_mono($label)) . '</i>'; }
    $o = '<i class="cm-sym cm-sym-sd">';
    foreach (array_slice($all, 0, 3) as [, $icn]) { $o .= '<svg class="cm-ic" data-ic="' . e($icn) . '" viewBox="0 0 24 24" aria-hidden="true"></svg>'; }
    if (count($all) > 3) { $o .= '<b class="cm-more">+' . (count($all) - 3) . '</b>'; }
    return $o . '</i>';
}

/** Draws the banners' symbols from the Spatial Distribution icon family, and the large faint symbol at the right of each banner (the app's DHero). */
function committee_banner_script(): string
{
    return '<script src="assets/js/sd-icons.js?v=' . e(asset_version('../js/sd-icons.js')) . '"></script>' . <<<'JS'
<script>
(function () {   // each committee symbol is drawn from the Spatial Distribution icon family
  var I = window.SD_ICONS || {};
  document.querySelectorAll('.cm-chips .cm-ic').forEach(function (s) {
    s.setAttribute('fill', 'none'); s.setAttribute('stroke', 'currentColor'); s.setAttribute('stroke-width', '2'); s.setAttribute('stroke-linecap', 'round'); s.setAttribute('stroke-linejoin', 'round');
    s.innerHTML = I[s.dataset.ic] || I.other || '';
  });
  var all = document.querySelector('.cm-chips .cm-sym-all'); if (all && I.layers) { all.innerHTML = '<svg class="cm-ic" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' + I.layers + '</svg>'; }
  // the symbol again, large and faint at the right of each banner (the app's DHero)
  document.querySelectorAll('.cm-chips .cm-chip').forEach(function (chip) {
    var f = chip.querySelector('.cm-sym svg'), g;
    if (f) { g = f.cloneNode(true); }
    else { var d = chip.classList.contains('cm-chip-none') ? I.focus : (chip.classList.contains('cm-chip-sys') ? I.radar : I.other); if (!d) return; g = document.createElementNS('http://www.w3.org/2000/svg', 'svg'); g.setAttribute('viewBox', '0 0 24 24'); g.setAttribute('fill', 'none'); g.setAttribute('stroke', 'currentColor'); g.setAttribute('stroke-linecap', 'round'); g.setAttribute('stroke-linejoin', 'round'); g.innerHTML = d; }
    g.setAttribute('stroke-width', '2'); g.setAttribute('class', 'cm-bg'); g.removeAttribute('width'); g.removeAttribute('height'); g.setAttribute('aria-hidden', 'true'); chip.appendChild(g);
  });
})();
</script>
JS;
}

/**
 * A committee's banner as a fade that comes in from the right end of a card (a profile's cover): its colours and its symbol, fading out
 * to the left. Decorative; the committee is named in the card itself. Needs committee_banner_script() on the page, and the card's `pd-fade` class.
 */
function committee_fade(string $ck, array $sdTypes, string $label): string
{
    return '<div class="cm-chips pd-fadewrap" aria-hidden="true"><a class="cm-chip cm-sd" tabindex="-1" style="' . e(cm_banner_style($ck, $sdTypes)) . '">' . cm_sym_tag($ck, $sdTypes, $label) . '</a></div>';
}
