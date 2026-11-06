<?php
/**
 * The brain button on every page that has one answers from the person's own module of the SMART engine (Ace, 4 Nov 2026,
 * Priority 2 part 4; smart_module(), 0165): the barangay's for a super admin, their committee's for a Kagawad, a staff
 * member's for staff. One read per request, shared by the button, its window and Report Summary's window.
 *
 *   module_brain($db)            the button and its window (Case Reports, Notifications, Home)
 *   module_brain_section($db)    the module alone, for a page whose window says more (Report Summary)
 */
declare(strict_types=1);

/** The person's module, read once per request; null when the engine cannot be read. */
function smart_module_read(Supabase $db): ?array
{
    static $memo = false;
    if ($memo !== false) return $memo;
    try { $m = $db->rpc('smart_module'); } catch (SupabaseError) { $m = null; }
    return $memo = is_array($m) ? $m : null;
}

/** What the badge on the button counts: the decisions waiting on the person, or for staff the urgent and overdue cases. */
function module_brain_count(?array $m): int
{
    if ($m === null) return 0;
    if (is_array($m['decisions'] ?? null)) return (int) array_sum(array_map('intval', array_filter($m['decisions'], fn ($v) => $v !== null)));
    return (int) ($m['counts']['urgent_waiting'] ?? 0) + (int) ($m['counts']['overdue'] ?? 0);
}

/** The module's name as the person reads it. */
function module_brain_name(?array $m): string
{
    return match ((string) ($m['module'] ?? '')) {
        'committee' => t('Your committee module', 'Ang module ng komite mo'),
        'staff'     => t('Your staff module', 'Ang module mo bilang kawani'),
        default     => t('The barangay module', 'Ang module ng barangay'),
    };
}

/** The module's readings: what waits on the person, right now, and the engine's lists. */
function module_brain_section(Supabase $db): string
{
    $m = smart_module_read($db);
    if ($m === null) {
        return '<section class="p-card p-card-pad mb-sec"><p class="p-eyebrow">' . e(module_brain_name(null)) . '</p><p class="p-hint" style="margin:0">'
             . e(t('The engine could not be read just now. Try again in a moment.', 'Hindi mabasa ang engine ngayon. Subukan muli mamaya.')) . '</p></section>';
    }
    $cn = (array) ($m['counts'] ?? []); $dc = is_array($m['decisions'] ?? null) ? $m['decisions'] : null; $tn = (array) ($m['tanods'] ?? []);
    $me = (string) (current_admin()['id'] ?? '');
    $tile = fn (string $href, string $label, $n, bool $hot = false): string => '<a class="p-card ss-tile' . ($hot && (int) $n > 0 ? ' hot' : '') . '" href="' . e($href) . '"><span>' . e($label) . '</span><b>' . (int) $n . '</b></a>';
    ob_start(); ?>
    <section class="p-card p-card-pad mb-sec">
      <p class="p-eyebrow"><?= e(module_brain_name($m)) ?><?php if (!empty($m['committee'])): ?> &middot; <?= e((string) (committees_all()[(string) $m['committee']]['short_en'] ?? '')) ?><?php endif; ?></p>
      <?php if ($dc !== null): ?>
        <p class="mb-h"><?= e(t('Waiting for you', 'Naghihintay sa iyo')) ?></p>
        <div class="ss-tiles">
          <?= $tile('notifications.php', t('Escalations to decide', 'Eskalasyong pagpapasyahan'), $dc['escalations'] ?? 0, true) ?>
          <?= $tile('inbox.php', t('Tanods to pick', 'Tanod na pipiliin'), $dc['reroute'] ?? 0, true) ?>
          <?php if (($m['module'] ?? '') === 'barangay'): ?>
            <?= $tile('notifications.php', t('Cases to place', 'Kasong ilalagay'), $dc['to_place'] ?? 0, true) ?>
            <?= $tile('personnel.php', t('Tanods proposed', 'Tanod na iminungkahi'), $dc['tanods_proposed'] ?? 0) ?>
          <?php else: ?>
            <?= $tile('cases.php?com=fwd', t('Forwarded to you', 'Ipinasa sa iyo'), $dc['forwarded'] ?? 0) ?>
            <?= $tile('cases.php?com=flagged', t('Staff flags', 'Mga flag ng kawani'), $dc['flags'] ?? 0) ?>
          <?php endif; ?>
        </div>
      <?php endif; ?>
      <p class="mb-h"><?= e(t('Right now', 'Ngayon')) ?></p>
      <div class="ss-tiles">
        <?= $tile('cases.php?tanod=needs', t('Urgent, no tanod yet', 'Urgent, wala pang tanod'), $cn['urgent_waiting'] ?? 0, true) ?>
        <?= $tile('cases.php?view=attention', t('Overdue', 'Lampas-oras'), $cn['overdue'] ?? 0, true) ?>
        <?= $tile('cases.php?who=unclaimed', t('Nobody has taken', 'Walang humahawak'), $cn['untaken'] ?? 0) ?>
        <?= $tile('cases.php?who=' . rawurlencode($me), t('Yours', 'Hawak mo'), $cn['mine'] ?? 0) ?>
      </div>
    </section>
    <?php $risk = (array) ($m['deadline_risk'] ?? []); $quiet = (array) ($m['quiet'] ?? []); $spk = (array) ($m['spikes'] ?? []); ?>
    <section class="p-card p-card-pad mb-sec">
      <p class="p-eyebrow"><?= e(t('Likely to miss the deadline', 'Maaaring lumampas sa deadline')) ?> &middot; <?= count($risk) ?></p>
      <?php if (!$risk): ?><p class="p-hint" style="margin:0"><?= e(t('Nothing at risk.', 'Walang nanganganib.')) ?></p><?php else: ?>
      <ul class="mb-list"><?php foreach (array_slice($risk, 0, 5) as $r): ?>
        <li><a class="p-mono-id" href="case.php?id=<?= e((string) $r['report_id']) ?>"><?= e((string) $r['tracking_id']) ?></a><span><?= e(sprintf(t('%s h left', '%s oras na lang'), rtrim(rtrim(number_format((float) ($r['hours_left'] ?? 0), 1), '0'), '.'))) ?></span><em class="mb-r mb-r-<?= e((string) ($r['risk'] ?? 'medium')) ?>"><?= e(($r['risk'] ?? '') === 'high' ? t('High', 'Mataas') : t('Medium', 'Katamtaman')) ?></em></li>
      <?php endforeach; ?></ul><?php endif; ?>
    </section>
    <section class="p-card p-card-pad mb-sec">
      <p class="p-eyebrow"><?= e(t('Quiet cases', 'Mga tahimik na kaso')) ?> &middot; <?= count($quiet) ?></p>
      <?php if (!$quiet): ?><p class="p-hint" style="margin:0"><?= e(t('No open case has gone quiet.', 'Walang bukas na kasong natahimik.')) ?></p><?php else: ?>
      <ul class="mb-list"><?php foreach (array_slice($quiet, 0, 5) as $q): ?>
        <li><a class="p-mono-id" href="case.php?id=<?= e((string) $q['report_id']) ?>"><?= e((string) $q['tracking_id']) ?></a><span><?= e((string) ($q['last_activity'] ?? '')) ?></span><em><?= e(sprintf((int) $q['days_quiet'] === 1 ? t('%d day', '%d araw') : t('%d days', '%d araw'), (int) $q['days_quiet'])) ?></em></li>
      <?php endforeach; ?></ul><?php endif; ?>
    </section>
    <section class="p-card p-card-pad mb-sec">
      <p class="p-eyebrow"><?= e(t('Tanods and the week', 'Mga tanod at ang linggo')) ?></p>
      <p class="mb-line"><?= e(sprintf(t('%1$d free, %2$d on a case, %3$d on a break or at lunch, %4$d off.', '%1$d bakante, %2$d may kaso, %3$d nagpapahinga o nanananghalian, %4$d wala.'),
            (int) ($tn['on_duty'] ?? 0), (int) ($tn['busy'] ?? 0), (int) ($tn['break'] ?? 0) + (int) ($tn['lunch'] ?? 0), (int) ($tn['offline'] ?? 0))) ?></p>
      <?php foreach (array_slice($spk, 0, 3) as $sp): ?>
        <p class="mb-line"><?= e(sprintf(t('%1$s: %2$d this week, usually %3$s%4$s.', '%1$s: %2$d ngayong linggo, karaniwan %3$s%4$s.'), category_label((string) $sp['category']), (int) $sp['this_week'],
              rtrim(rtrim(number_format((float) $sp['usual'], 1), '0'), '.'), !empty($sp['place']) ? ' · ' . (string) $sp['place'] : '')) ?></p>
      <?php endforeach; ?>
      <?php if (!$spk): ?><p class="mb-line"><?= e(t('Nothing is coming in more than usual this week.', 'Walang dumarating nang higit sa karaniwan ngayong linggo.')) ?></p><?php endif; ?>
      <?php $nPat = count((array) ($m['patterns'] ?? [])); if ($nPat > 0): ?><p class="mb-line"><a href="spatial.php"><?= e(sprintf($nPat === 1 ? t('%d recurring problem on the map', '%d paulit-ulit na problema sa mapa') : t('%d recurring problems on the map', '%d paulit-ulit na problema sa mapa'), $nPat)) ?></a></p><?php endif; ?>
    </section>
    <?php return (string) ob_get_clean();
}

/** The brain button and its window, for a page with no window of its own ($homeLink false on Home itself). */
function module_brain(Supabase $db, bool $homeLink = true): string
{
    $m = smart_module_read($db);
    $n = module_brain_count($m);
    $home = !$homeLink ? null : (is_scoped() ? ['home.php', t('Open Home', 'Buksan ang Home')] : (page_allowed('dashboard.php') ? ['dashboard.php', t('Open the Dashboard', 'Buksan ang Dashboard')] : null));
    ob_start(); ?>
<button type="button" class="ss-brain-btn" id="ss-win-open" aria-haspopup="dialog" aria-controls="ss-panel" title="<?= e(t('Ask the SMART engine', 'Tanungin ang SMART engine')) ?>"><?= smart_brain(26) ?><span class="p-sr"><?= e(t('Ask the SMART engine', 'Tanungin ang SMART engine')) ?></span><?php if ($n > 0): ?><b class="ss-brain-n"><?= $n > 99 ? '99+' : $n ?></b><?php endif; ?></button>
<div class="ss-win-scrim" id="ss-win-scrim"></div>
<div class="ss-win" id="ss-panel" role="dialog" aria-modal="true" aria-labelledby="ss-win-title" aria-hidden="true">
  <header class="ss-win-head">
    <?= smart_logo(40) ?>
    <div class="ss-win-ttl"><b id="ss-win-title"><?= e(t('What the engine sees', 'Ang nakikita ng engine')) ?></b><small><?= e(module_brain_name($m)) ?></small></div>
    <button type="button" class="ss-win-x" id="ss-win-close" aria-label="<?= e(t('Close', 'Isara')) ?>"><svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" aria-hidden="true"><path d="M6 6l12 12M18 6 6 18"/></svg></button>
  </header>
  <div class="ss-win-body"><div class="ss-panel-in">
    <?= module_brain_section($db) ?>
    <?php if ($home): ?><a class="p-btn p-btn-ghost p-btn-sm mb-home" href="<?= e($home[0]) ?>"><?= e($home[1]) ?> &rarr;</a><?php endif; ?>
  </div></div>
</div>
<script src="assets/js/smart-panel.js?v=<?= e(asset_version('../js/smart-panel.js')) ?>"></script>
<?php return (string) ob_get_clean();
}

/**
 * Residents' engine button and window (Ace, 6 Nov 2026): the alerts of the Residents page live here, one row each with a button that filters the
 * list for the super admin, so they never have to set the filter by hand; the red banner on the page can be sent here and comes back as a count.
 *   $n: the chip counts ('pending', 'overdue', 'duplicate', 'suspended'), $requests: the requests waiting (ID photo changes)
 */
function residents_brain(array $n, int $requests = 0): string
{
    $rows = [
        ['overdue',   t('Past the two-hour window', 'Lampas sa dalawang oras'),   t('Registrations that waited longer than two hours for a review.', 'Mga rehistrong higit dalawang oras nang naghihintay ng pagsusuri.'), 'high', 'residents.php?sort=overdue'],
        ['pending',   t('Waiting for review', 'Naghihintay ng pagsusuri'),        t('New registrations nobody has verified yet.', 'Mga bagong rehistrong wala pang nagbeberipika.'), 'warn', 'residents.php?sort=pending'],
        ['duplicate', t('Possible duplicates', 'Posibleng doble'),                t('Accounts that look like another account.', 'Mga account na kahawig ng ibang account.'), 'info', 'residents.php?sort=duplicate'],
        ['suspended', t('Suspended', 'Suspendido'),                              t('Accounts that are switched off right now.', 'Mga account na naka-off ngayon.'), 'info', 'residents.php?sort=suspended'],
    ];
    $badge = (int) ($n['pending'] ?? 0) + (int) ($n['duplicate'] ?? 0) + $requests;
    ob_start(); ?>
<button type="button" class="ss-brain-btn" id="ss-win-open" aria-haspopup="dialog" aria-controls="ss-panel" title="<?= e(t('Ask the SMART engine', 'Tanungin ang SMART engine')) ?>"><?= smart_brain(26) ?><span class="p-sr"><?= e(t('Ask the SMART engine', 'Tanungin ang SMART engine')) ?></span><b class="ss-brain-n" id="rs-brain-n"<?= $badge > 0 ? '' : ' hidden' ?>><?= $badge > 99 ? '99+' : $badge ?></b></button>
<div class="ss-win-scrim" id="ss-win-scrim"></div>
<div class="ss-win" id="ss-panel" role="dialog" aria-modal="true" aria-labelledby="ss-win-title" aria-hidden="true">
  <header class="ss-win-head">
    <?= smart_logo(40) ?>
    <div class="ss-win-ttl"><b id="ss-win-title"><?= e(t('What the engine sees', 'Ang nakikita ng engine')) ?></b><small><?= e(t('Residents', 'Mga Residente')) ?></small></div>
    <button type="button" class="ss-win-x" id="ss-win-close" aria-label="<?= e(t('Close', 'Isara')) ?>"><svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" aria-hidden="true"><path d="M6 6l12 12M18 6 6 18"/></svg></button>
  </header>
  <div class="ss-win-body"><div class="ss-panel-in">
    <section class="p-card p-card-pad mb-sec">
      <p class="p-eyebrow"><?= e(t('Needs a super admin', 'Kailangan ng super admin')) ?></p>
      <p class="p-hint" style="margin:0"><?= e(t('Press a button and the list is filtered for you.', 'Pindutin ang isang button at masasala ang listahan para sa iyo.')) ?></p>
      <div class="rs-als">
      <?php foreach ($rows as [$k, $label, $sentence, $tone, $href]): $c = (int) ($n[$k] ?? 0); ?>
        <div class="rs-al rs-al-<?= e($tone) ?><?= $c > 0 ? '' : ' is-zero' ?>" data-rs="<?= e($k) ?>">
          <b class="rs-al-n" data-rs-n><?= $c ?></b>
          <div class="rs-al-t"><strong><?= e($label) ?></strong><span><?= e($sentence) ?></span></div>
          <a class="p-btn p-btn-sm p-btn-orange" href="<?= e($href) ?>"><?= e(t('Show them', 'Ipakita')) ?></a>
        </div>
      <?php endforeach; ?>
      <?php if ($requests > 0): ?>
        <div class="rs-al rs-al-warn" data-rs="requests">
          <b class="rs-al-n"><?= $requests ?></b>
          <div class="rs-al-t"><strong><?= e(t('Requests waiting', 'Mga naghihintay na kahilingan')) ?></strong><span><?= e(t('New ID photos and other changes residents asked for.', 'Mga bagong litrato ng ID at iba pang hiniling ng mga residente.')) ?></span></div>
          <a class="p-btn p-btn-sm p-btn-orange" href="#ss-requests" data-close-win><?= e(t('Show them', 'Ipakita')) ?></a>
        </div>
      <?php endif; ?>
      </div>
    </section>
    <a class="p-btn p-btn-ghost p-btn-sm mb-home" href="residents.php"><?= e(t('Show every resident', 'Ipakita ang lahat ng residente')) ?> &rarr;</a>
  </div></div>
</div>
<script src="assets/js/smart-panel.js?v=<?= e(asset_version('../js/smart-panel.js')) ?>"></script>
<?php return (string) ob_get_clean();
}
