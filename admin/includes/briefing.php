<?php
/**
 * The Notifications page's top: the engine's briefing for the morning, the afternoon or the night, and three lanes
 * (Needs you now, Watching, Good to know). Ace's pick, 14 Oct 2026: the inbox, the briefing and the timeline together.
 *
 * Every call here is optional: a failure empties its own lane and never the page. The briefing reads the numbers as they
 * are now; the database also sends the same three briefings to the bell at 07:00, 14:00 and 20:00 (0131).
 */
declare(strict_types=1);

/** 'morning' until noon, 'afternoon' until 6 PM, then 'night' (Manila). */
function briefing_period(?DateTimeImmutable $now = null): string
{
    $h = (int) ($now ?? new DateTimeImmutable('now', new DateTimeZone('Asia/Manila')))->format('G');
    return $h < 12 ? 'morning' : ($h < 18 ? 'afternoon' : 'night');
}

/** Today / Yesterday / "Oct 12" for a timestamp, in Manila. */
function day_label(?string $iso): string
{
    if (!$iso) return '';
    try {
        $tz = new DateTimeZone('Asia/Manila');
        $d  = (new DateTimeImmutable($iso))->setTimezone($tz)->setTime(0, 0);
        $t  = (new DateTimeImmutable('now', $tz))->setTime(0, 0);
        $diff = (int) $t->diff($d)->format('%r%a');
        return $diff === 0 ? t('Today', 'Ngayon') : ($diff === -1 ? t('Yesterday', 'Kahapon') : $d->format('M j'));
    } catch (Exception) {
        return '';
    }
}

function render_briefing(Supabase $db, array $admin): void
{
    $tz    = new DateTimeZone('Asia/Manila');
    $now   = new DateTimeImmutable('now', $tz);
    $today = $now->setTime(0, 0);
    $iso   = fn(DateTimeImmutable $d): string => $d->format('Y-m-d\TH:i:sP');
    $open  = 'in.(pending_review,validated,assigned,in_progress,offline_investigation)';
    $here  = briefing_period($now);

    // ---- what the engine sees
    $got = [];
    try {
        $got = $db->selectMany([
            'summary' => ['rpc/smart_summary', [], true],
            'queue'   => ['rpc/smart_queue', ['p_stage' => null, 'p_limit' => 6], true],
            'risk'    => ['rpc/smart_deadline_risk', [], true],
            'spikes'  => ['rpc/smart_spikes', [], true],
            'recur'   => ['rpc/smart_patterns', ['p_days' => null], true],
            'stuck'   => ['rpc/smart_stuck_cases', [], true],
            'storm'   => ['smart_rules', ['select' => 'storm_mode,storm_until,storm_reason', 'id' => 'eq.1', 'limit' => '1'], true],
            'esc'     => ['escalation_requests', ['select' => 'id,reason,created_at,report:reports!escalation_requests_report_id_fkey(id,tracking_id),requester:users!escalation_requests_requested_by_fkey(full_name)',
                                                  'status' => 'eq.pending', 'order' => 'created_at.asc', 'limit' => '3'], true],
        ]);
    } catch (SupabaseError) { /* the lanes stay empty */ }
    $list = fn(string $k): array => (isset($got[$k]) && !($got[$k] instanceof SupabaseError) && is_array($got[$k])) ? $got[$k] : [];

    $counts = [];
    try {
        $c = $db->selectMany([
            'open'      => ['reports', ['deleted_at' => 'is.null', 'status' => $open], true],
            'overdue'   => ['reports', ['deleted_at' => 'is.null', 'status' => $open, 'due_at' => 'lt.' . $iso($now)], true],
            'due_today' => ['reports', ['deleted_at' => 'is.null', 'status' => $open, 'and' => '(due_at.gte.' . $iso($today) . ',due_at.lt.' . $iso($today->modify('+1 day')) . ')'], true],
            'due_tmrw'  => ['reports', ['deleted_at' => 'is.null', 'status' => $open, 'and' => '(due_at.gte.' . $iso($today->modify('+1 day')) . ',due_at.lt.' . $iso($today->modify('+2 day')) . ')'], true],
            'in_night'  => ['reports', ['deleted_at' => 'is.null', 'created_at' => 'gte.' . $iso($today->modify('-6 hours'))], true],
            'in_today'  => ['reports', ['deleted_at' => 'is.null', 'created_at' => 'gte.' . $iso($today)], true],
            'in_since'  => ['reports', ['deleted_at' => 'is.null', 'created_at' => 'gte.' . $iso($today->setTime(6, 0))], true],
            'out_today' => ['reports', ['deleted_at' => 'is.null', 'resolved_at' => 'gte.' . $iso($today)], true],
            'out_since' => ['reports', ['deleted_at' => 'is.null', 'resolved_at' => 'gte.' . $iso($today->setTime(6, 0))], true],
            'regs'      => ['users', ['role' => 'eq.resident', 'verification_status' => 'eq.pending'], true],
        ], true);
        foreach ($c as $k => $v) { $counts[$k] = is_int($v) ? $v : 0; }
    } catch (SupabaseError) { /* the numbers show as zero */ }
    $n = fn(string $k): int => (int) ($counts[$k] ?? 0);

    $sum      = is_array($got['summary'] ?? null) && !($got['summary'] instanceof SupabaseError) ? $got['summary'] : [];
    $waiting  = (int) ($sum['urgent_waiting'] ?? 0) + (int) ($sum['high_waiting'] ?? 0);
    $risk     = array_values(array_filter($list('risk'), fn($r) => ($r['risk'] ?? '') === 'high'));
    $spikes   = $list('spikes');
    $recur    = array_values(array_filter($list('recur'), fn($r) => (int) ($r['still_open'] ?? 0) > 0));
    $stuck    = $list('stuck');
    $esc      = $list('esc');
    $queue    = $list('queue');
    $stormRow = $list('storm')[0] ?? null;
    $storm    = $stormRow && !empty($stormRow['storm_mode']) ? $stormRow : null;

    // ---- the three briefings (the same numbers, read three ways)
    $m = fn(string $label, int $v, string $href = '', bool $hot = false): array => [$label, $v, $href, $hot];
    $periods = [
        'morning' => [
            'name' => t('Morning', 'Umaga'), 'greet' => t('The day ahead', 'Ang araw sa unahan'),
            'line' => sprintf(t('%d cases are open and %d wait for a tanod. %d are due today, and %d may miss their deadline.', '%d ang bukás na kaso at %d ang naghihintay ng tanod. %d ang takdang oras ngayon, at %d ang maaaring lumampas.'), $n('open'), $waiting, $n('due_today'), count($risk)),
            'tiles' => [
                $m(t('Open cases', 'Bukás na kaso'), $n('open'), 'cases.php'), $m(t('Waiting for a tanod', 'Naghihintay ng tanod'), $waiting, 'notifications.php?tab=next&stage=dispatch', $waiting > 0),
                $m(t('Due today', 'Takdang oras ngayon'), $n('due_today'), 'cases.php?status=overdue'), $m(t('Filed overnight', 'Naisampa kagabi'), $n('in_night'), 'cases.php'),
                $m(t('May miss the deadline', 'Maaaring lumampas'), count($risk), 'notifications.php?tab=next', count($risk) > 0),
            ],
        ],
        'afternoon' => [
            'name' => t('Afternoon', 'Hapon'), 'greet' => t('Midday check', 'Tingin sa kalagitnaan ng araw'),
            'line' => sprintf(t('Since 6 AM, %d cases came in and %d were resolved. %d urgent or high still wait for a tanod, and %d are overdue.', 'Mula 6 AM, %d ang pumasok at %d ang nalutas. %d na madalian o mataas ang naghihintay pa ng tanod, at %d ang lampas na sa oras.'), $n('in_since'), $n('out_since'), $waiting, $n('overdue')),
            'tiles' => [
                $m(t('Came in since 6 AM', 'Pumasok mula 6 AM'), $n('in_since'), 'cases.php'), $m(t('Resolved since 6 AM', 'Nalutas mula 6 AM'), $n('out_since'), 'cases.php?status=resolved'),
                $m(t('Still waiting for a tanod', 'Naghihintay pa ng tanod'), $waiting, 'notifications.php?tab=next&stage=dispatch', $waiting > 0), $m(t('Overdue now', 'Lampas na ngayon'), $n('overdue'), 'cases.php?status=overdue', $n('overdue') > 0),
                $m(t('May miss the deadline', 'Maaaring lumampas'), count($risk), 'notifications.php?tab=next', count($risk) > 0),
            ],
        ],
        'night' => [
            'name' => t('Night', 'Gabi'), 'greet' => t('The day in review', 'Balik-tanaw sa araw'),
            'line' => sprintf(t('Today %d cases were filed and %d resolved. %d stay open overnight, %d are due tomorrow, and %d are overdue.', 'Ngayon, %d ang naisampa at %d ang nalutas. %d ang mananatiling bukás ngayong gabi, %d ang takdang oras bukas, at %d ang lampas na.'), $n('in_today'), $n('out_today'), $n('open'), $n('due_tmrw'), $n('overdue')),
            'tiles' => [
                $m(t('Filed today', 'Naisampa ngayon'), $n('in_today'), 'cases.php'), $m(t('Resolved today', 'Nalutas ngayon'), $n('out_today'), 'cases.php?status=resolved'),
                $m(t('Carry over', 'Dadalhin bukas'), $n('open'), 'cases.php'), $m(t('Due tomorrow', 'Takdang oras bukas'), $n('due_tmrw'), 'cases.php'),
                $m(t('Overdue now', 'Lampas na ngayon'), $n('overdue'), 'cases.php?status=overdue', $n('overdue') > 0),
            ],
        ],
    ];
    ?>
<section class="ss-brief" id="ss-brief" data-now="<?= e($here) ?>" aria-label="<?= e(t('The engine\'s briefing', 'Ang briefing ng engine')) ?>">
  <div class="ss-brief-hero">
    <?= smart_logo(44) ?>
    <div class="ss-brief-txt">
      <?php foreach ($periods as $key => $p): ?>
        <div class="ss-brief-pane" data-pane="<?= e($key) ?>"<?= $key === $here ? '' : ' hidden' ?>>
          <b><?= e($p['greet']) ?></b>
          <p><?= e($p['line']) ?></p>
        </div>
      <?php endforeach; ?>
      <p class="ss-thinkline" aria-live="polite"><?= e(t('Reading the day…', 'Binabasa ang araw…')) ?></p>
    </div>
    <div class="p-seg-mini ss-brief-tabs" role="tablist" aria-label="<?= e(t('Briefing', 'Buod ng engine')) ?>">
      <?php foreach ($periods as $key => $p): ?>
        <button type="button" role="tab" data-period="<?= e($key) ?>" class="<?= $key === $here ? 'p-on' : '' ?>" aria-selected="<?= $key === $here ? 'true' : 'false' ?>"><?= e($p['name']) ?><?= $key === $here ? ' <i class="ss-now" title="' . e(t('Now', 'Ngayon')) . '"></i>' : '' ?></button>
      <?php endforeach; ?>
    </div>
  </div>
  <?php foreach ($periods as $key => $p): ?>
    <div class="ss-brief-tiles" data-pane="<?= e($key) ?>"<?= $key === $here ? '' : ' hidden' ?>>
      <?php foreach ($p['tiles'] as [$label, $v, $href, $hot]): ?>
        <a class="ss-btile<?= $hot ? ' hot' : '' ?>" href="<?= e($href ?: 'cases.php') ?>"><b><?= (int) $v ?></b><span><?= e($label) ?></span></a>
      <?php endforeach; ?>
    </div>
  <?php endforeach; ?>
</section>

<div class="ss-lanes">
  <section class="ss-lane" aria-labelledby="lane-now">
    <h3 id="lane-now"><?= e(t('Needs you now', 'Kailangan ka ngayon')) ?><span class="p-badge-n"><?= count($queue) + count($esc) ?></span></h3>
    <?php foreach ($esc as $x): ?>
      <article class="ss-nt" style="--c:#6A4FD3"><span class="ss-ic" aria-hidden="true">↑</span>
        <div><b><?= e(t('Escalation request', 'Hiling na i-escalate')) ?> · <?= e($x['report']['tracking_id'] ?? '') ?></b>
          <p><?= e(name_or($x['requester']['full_name'] ?? null, t('A tanod', 'Isang tanod'))) ?>: <?= e($x['reason']) ?></p></div>
        <?php if (!empty($x['report']['id'])): ?><a class="p-btn p-btn-sm p-btn-orange" href="case.php?id=<?= e($x['report']['id']) ?>"><?= e(t('Review', 'Suriin')) ?></a><?php endif; ?></article>
    <?php endforeach; ?>
    <?php foreach (array_slice($queue, 0, 4) as $q): $why = []; foreach (array_slice((array) ($q['reasons'] ?? []), 0, 3) as $rs) { $why[] = ($rs['detail'] ?? $rs['factor'] ?? '') . ' +' . (int) ($rs['points'] ?? 0); } ?>
      <article class="ss-nt" style="--c:<?= ($q['level'] ?? '') === 'urgent' ? '#E5383B' : (($q['level'] ?? '') === 'high' ? '#FF9800' : '#356CF9') ?>"><span class="ss-ic" aria-hidden="true">!</span>
        <div><b><?= e($q['tracking_id']) ?> · <?= e($q['subject']) ?></b>
          <p><?= e(waiting_text($q['waiting_since'])) ?> · <?= e(category_label((string) $q['category'])) ?></p>
          <?php if ($why): ?><div class="ss-whys"><?php foreach ($why as $w): ?><span><?= e($w) ?></span><?php endforeach; ?></div><?php endif; ?></div>
        <a class="p-btn p-btn-sm p-btn-orange" href="case.php?id=<?= e($q['report_id']) ?>"><?= e($q['next_action']) ?></a></article>
    <?php endforeach; ?>
    <?php if (!$queue && !$esc): ?><p class="p-none-line"><?= e(t('Nothing waits on you. Every open case has someone on it.', 'Walang naghihintay sa iyo. May nakatalaga sa bawat bukás na kaso.')) ?></p><?php endif; ?>
    <a class="ss-more" href="notifications.php?tab=next"><?= e(t('See the whole queue', 'Tingnan ang buong pila')) ?> ›</a>
  </section>

  <section class="ss-lane" aria-labelledby="lane-watch">
    <h3 id="lane-watch"><?= e(t('Watching', 'Binabantayan')) ?><span class="p-badge-n"><?= min(2, count($risk)) + min(2, count($spikes)) + min(2, count($recur)) + min(1, count($stuck)) ?></span></h3>
    <?php foreach (array_slice($risk, 0, 2) as $r): ?>
      <article class="ss-nt" style="--c:#FF9800"><span class="ss-ic" aria-hidden="true">⏱</span>
        <div><b><?= e($r['tracking_id']) ?> · <?= e(t('likely to miss its deadline', 'maaaring lumampas sa takdang oras')) ?></b>
          <p><?= e(sprintf(t('%s h left; such cases usually take %s h.', '%s oras na lang; karaniwang %s oras ang ganitong kaso.'), (string) round((float) $r['hours_left']), (string) round((float) $r['typical_hours']))) ?></p></div>
        <a class="p-btn p-btn-sm p-btn-ghost" href="case.php?id=<?= e($r['report_id']) ?>"><?= e(t('Open', 'Buksan')) ?></a></article>
    <?php endforeach; ?>
    <?php foreach (array_slice($spikes, 0, 2) as $s): ?>
      <article class="ss-nt" style="--c:#6A4FD3"><span class="ss-ic" aria-hidden="true">▲</span>
        <div><b><?= e(category_label((string) $s['category'])) ?>: <?= (int) $s['this_week'] ?> <?= e(t('this week', 'ngayong linggo')) ?></b>
          <p><?= e(t('usually', 'karaniwan')) ?> <?= e(rtrim(rtrim(number_format((float) $s['usual'], 1), '0'), '.')) ?><?= !empty($s['place']) ? ' · ' . e((string) $s['place']) : '' ?></p></div>
        <a class="p-btn p-btn-sm p-btn-ghost" href="spatial.php"><?= e(t('Map', 'Mapa')) ?></a></article>
    <?php endforeach; ?>
    <?php foreach (array_slice($recur, 0, 2) as $r): ?>
      <article class="ss-nt" style="--c:#6A4FD3"><span class="ss-ic" aria-hidden="true">⟲</span>
        <div><b><?= e(category_label((string) $r['category'])) ?> <?= e(t('keeps coming back', 'ay paulit-ulit')) ?></b>
          <p><?= (int) $r['reports'] ?> <?= e(t('reports from', 'ulat mula sa')) ?> <?= (int) $r['residents'] ?> <?= e(t('residents', 'residente')) ?> · <?= (int) $r['still_open'] ?> <?= e(t('still open', 'bukás pa')) ?></p></div>
        <a class="p-btn p-btn-sm p-btn-ghost" href="spatial.php"><?= e(t('Map', 'Mapa')) ?></a></article>
    <?php endforeach; ?>
    <?php foreach (array_slice($stuck, 0, 1) as $s): ?>
      <article class="ss-nt" style="--c:#8E9ABB"><span class="ss-ic" aria-hidden="true">z</span>
        <div><b><?= e($s['tracking_id']) ?> · <?= e(t('quiet for', 'tahimik nang')) ?> <?= (int) $s['days_quiet'] ?> <?= e(t('days', 'araw')) ?></b>
          <p><?= e(t('Count of quiet cases:', 'Bilang ng tahimik na kaso:')) ?> <?= count($stuck) ?></p></div>
        <a class="p-btn p-btn-sm p-btn-ghost" href="case.php?id=<?= e($s['report_id']) ?>"><?= e(t('Open', 'Buksan')) ?></a></article>
    <?php endforeach; ?>
    <?php if (!$risk && !$spikes && !$recur && !$stuck): ?><p class="p-none-line"><?= e(t('Nothing unusual right now.', 'Walang kakaiba sa ngayon.')) ?></p><?php endif; ?>
  </section>

  <section class="ss-lane" aria-labelledby="lane-know">
    <h3 id="lane-know"><?= e(t('Good to know', 'Mabuting malaman')) ?></h3>
    <?php if ($storm): ?>
      <article class="ss-nt" style="--c:#356CF9"><span class="ss-ic" aria-hidden="true">☂</span>
        <div><b><?= e(t('Storm mode is on', 'Naka-on ang storm mode')) ?></b>
          <p><?= e(t('until', 'hanggang')) ?> <?= e((new DateTimeImmutable((string) $storm['storm_until']))->setTimezone($tz)->format('M j, g:i A')) ?><?= !empty($storm['storm_reason']) ? ' · ' . e((string) $storm['storm_reason']) : '' ?></p></div>
        <a class="p-btn p-btn-sm p-btn-ghost" href="settings.php#smart"><?= e(t('Manage', 'Pamahalaan')) ?></a></article>
    <?php endif; ?>
    <?php if ($n('regs') > 0): ?>
      <article class="ss-nt" style="--c:#1F8A45"><span class="ss-ic" aria-hidden="true">+</span>
        <div><b><?= $n('regs') ?> <?= e(t('residents waiting for an ID check', 'residenteng naghihintay ng pagsusuri ng ID')) ?></b><p><?= e(t('The window to verify is two hours.', 'Dalawang oras ang palugit sa pagberipika.')) ?></p></div>
        <a class="p-btn p-btn-sm p-btn-ghost" href="residents.php?sort=pending"><?= e(t('Review', 'Suriin')) ?></a></article>
    <?php endif; ?>
    <article class="ss-nt" style="--c:#356CF9"><span class="ss-ic" aria-hidden="true">☀</span>
      <div><b><?= e(t('Briefings come three times a day', 'Tatlong beses sa isang araw ang briefing')) ?></b><p><?= e(t('Morning at 7, afternoon at 2, night at 8. They arrive in your notifications below.', 'Umaga ng 7, hapon ng 2, gabi ng 8. Darating sila sa iyong mga abiso sa ibaba.')) ?></p></div>
      <a class="p-btn p-btn-sm p-btn-ghost" href="settings.php#smart"><?= e(t('Settings', 'Mga Setting')) ?></a></article>
  </section>
</div>
<script src="assets/js/briefing.js?v=<?= e(asset_version('../js/briefing.js')) ?>"></script>
<?php
}
