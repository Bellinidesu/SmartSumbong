<?php
/**
 * The Notifications work board (Ace's pick, 15 Oct 2026): the engine's queue as columns, one per stage a case moves
 * through, each card coloured by urgency and wearing the face and rank of whoever handles it.
 *
 * Many people in the barangay hall use this at once, so it shows who has what and starts on the viewer's own work:
 * a Kagawad sees their committee's cases, the Chairman what reached them, the secretary's desk everything.
 * Dragging a card never changes anything by itself: dropping it opens the real action on the case (assign a tanod,
 * escalate...), and a column only a tanod can fill says so.
 */
declare(strict_types=1);

/** @return array{owners:array,committee:array,me:array} */
function board_data(Supabase $db, array $queue, array $admin): array
{
    $out = ['owners' => [], 'committee' => [], 'me' => ['official_role' => null, 'committee' => null]];
    if (!$queue) { return $out; }
    $ids = array_values(array_unique(array_column($queue, 'report_id')));
    try {
        $got = $db->selectMany([
            'own' => ['reports', ['select' => 'id,handler_id,tier,is_sensitive,category,handler:users!reports_handler_id_fkey(id,full_name,official_role,committee)',
                                  'id' => 'in.(' . implode(',', $ids) . ')'], true],
            'com' => ['committee_for_category', ['select' => 'category,committee'], true],
            'me'  => ['users', ['select' => 'official_role,committee', 'id' => 'eq.' . $admin['id'], 'limit' => '1'], true],
        ]);
        foreach ((array) ($got['own'] instanceof SupabaseError ? [] : $got['own']) as $r) { $out['owners'][$r['id']] = $r; }
        foreach ((array) ($got['com'] instanceof SupabaseError ? [] : $got['com']) as $r) { $out['committee'][$r['category']] = $r['committee']; }
        $me = $got['me'] instanceof SupabaseError ? [] : ($got['me'][0] ?? []);
        $out['me'] = ['official_role' => $me['official_role'] ?? null, 'committee' => $me['committee'] ?? null];
    } catch (SupabaseError) { /* the board shows the cases without owners */ }
    return $out;
}

/** What the ladder lets this person see, then the Mine / Unclaimed / Everyone choice. */
function board_visible(array $q, array $meta, array $admin, string $scope): bool
{
    $o    = $meta['owners'][$q['report_id']] ?? [];
    $mine = ($o['handler_id'] ?? null) === $admin['id'];
    $role = $meta['me']['official_role'];
    if ($role === 'kagawad' && !$mine && ($meta['committee'][$q['category']] ?? null) !== $meta['me']['committee']) { return false; }
    if ($role === 'chairman' && !$mine && (int) ($o['tier'] ?? 0) < 2) { return false; }
    if ($scope === 'mine') { return $mine; }
    if ($scope === 'free') { return empty($o['handler_id']); }
    return true;
}

function board_level(string $lv): array
{
    return match ($lv) {
        'urgent' => [t('Urgent', 'Madalian'), '#E5383B'],
        'high'   => [t('High', 'Mataas'), '#FF9800'],
        'normal' => [t('Normal', 'Katamtaman'), '#356CF9'],
        'low'    => [t('Low', 'Mababa'), '#8E9ABB'],
        default  => [t('Not scored', 'Walang marka'), '#8E9ABB'],
    };
}

function render_board(array $queue, array $meta, array $admin, string $scope, bool $err): void
{
    $cols = [
        'review'     => [t('Review', 'Suriin'), 1, t('Review the complaint', 'Suriin ang sumbong'), '', t('Open it and decide whether it is validated or rejected.', 'Buksan at pasyahan kung may bisa o tinanggihan.')],
        'dispatch'   => [t('Assign', 'Magtalaga'), 1, t('Assign a tanod', 'Magtalaga ng tanod'), '#assign-form', t('The assignment is on the case: choose the tanod, give instructions and a target date.', 'Nasa kaso ang pagtatalaga: pumili ng tanod, magbigay ng tagubilin at target na petsa.')],
        'accept'     => [t('Waiting for accept', 'Hinihintay ang pagtanggap'), 0, '', '', t('A tanod moves cards here by accepting the job. You cannot drop a case in this column.', 'Ang tanod ang naglilipat ng kaso rito kapag tinanggap ang trabaho. Hindi mo ito mailalagay rito.')],
        'reply'      => [t('Reply', 'Sagutin'), 1, t('Reply to the resident', 'Sagutin ang residente'), '', t('Open the case and answer in its messages.', 'Buksan ang kaso at sumagot sa mga mensahe nito.')],
        'approve'    => [t('Approve', 'Aprubahan'), 0, '', '', t('Cases arrive here when a tanod hands in a resolution. You cannot drop a case in this column.', 'Dumarating dito ang kaso kapag nagsumite ng resolusyon ang tanod. Hindi mo ito mailalagay rito.')],
        'escalation' => [t('Escalation', 'Eskalasyon'), 1, t('Escalate the case', 'I-escalate ang kaso'), '', t('Pass it up to a Kagawad or the Chairman, or out to another office.', 'Ipasa sa Kagawad o Punong Barangay, o sa ibang tanggapan.')],
        'follow_up'  => [t('Follow up', 'Sundan'), 1, t('Follow up the case', 'Sundan ang kaso'), '', t('Ask for news and nudge the people on it.', 'Humingi ng balita at paalalahanan ang mga may hawak.')],
    ];
    $rows = array_values(array_filter($queue, fn($q) => board_visible($q, $meta, $admin, $scope)));
    $by = array_fill_keys(array_keys($cols), []);
    foreach ($rows as $q) { if (isset($by[$q['stage']])) { $by[$q['stage']][] = $q; } }
    ?>
<div class="bd-wrap" id="board" data-sheet-ok="<?= e(t('Go to the case', 'Pumunta sa kaso')) ?>" data-sheet-cancel="<?= e(t('Cancel', 'Kanselahin')) ?>" data-sheet-close="<?= e(t('Got it', 'Sige')) ?>">
  <?php if ($err): ?>
    <p class="p-none-line"><?= e(t('SMART could not be reached just now. All notifications still shows everything.', 'Hindi maabot ang SMART ngayon. Ipinapakita pa rin ng Lahat ng abiso ang lahat.')) ?></p>
  <?php endif; ?>
  <div class="bd-cols">
    <?php foreach ($cols as $key => [$label, $ok, $verb, $hash, $hint]): ?>
      <section class="bd-col<?= $ok ? '' : ' is-locked' ?>" data-stage="<?= e($key) ?>" data-ok="<?= $ok ?>" data-verb="<?= e($verb) ?>" data-hash="<?= e($hash) ?>" data-hint="<?= e($hint) ?>" aria-label="<?= e($label) ?>">
        <header><h4><?= e($label) ?></h4><span><?= count($by[$key]) ?></span></header>
        <div class="bd-list">
          <?php if (!$by[$key]): ?><p class="bd-none"><?= e($ok ? t('Nothing here', 'Walang laman') : t('Filled by tanods', 'Pinupuno ng mga tanod')) ?></p><?php endif; ?>
          <?php foreach ($by[$key] as $q):
              [$lvName, $lvC] = board_level((string) $q['level']);
              $o = $meta['owners'][$q['report_id']] ?? [];
              $h = $o['handler'] ?? null;
              $href = 'case.php?id=' . rawurlencode((string) $q['report_id']);
              $short = $q['tracking_id'] ? preg_replace('/^[A-Z]+-\d{4}-/', '#', (string) $q['tracking_id']) : '';
          ?>
            <article class="bd-card" draggable="true" data-href="<?= e($href) ?>" data-title="<?= e((string) $q['tracking_id']) ?>" style="--c:<?= e($lvC) ?>">
              <div class="bd-top"><span class="bd-lv"><?= e($lvName) ?></span><span class="bd-age"><?= e(waiting_text($q['waiting_since'])) ?></span>
                <details class="bd-menu"><summary aria-label="<?= e(t('More actions', 'Iba pang aksyon')) ?>">&#8943;</summary>
                  <div><a href="<?= e($href) ?>"><?= e(t('Open the case', 'Buksan ang kaso')) ?></a>
                    <?php if ($ok && $verb !== ''): ?><a href="<?= e($href . $hash) ?>"><?= e($verb) ?></a><?php endif; ?>
                    <a href="<?= e($href) ?>"><?= e((string) $q['next_action']) ?></a></div></details></div>
              <a class="bd-title" href="<?= e($href) ?>"><span class="bd-id"><?= e($short) ?></span><b><?= e((string) $q['subject']) ?></b></a>
              <p class="bd-cat"><?= e(category_label((string) $q['category'])) ?></p>
              <div class="bd-own">
                <?php if ($h): ?>
                  <span class="bd-ring" data-r="<?= e(rank_of($h['official_role'] ?? null)) ?>"><?= admin_chip((string) $h['id'], (string) $h['full_name'], 22) ?></span>
                  <span class="bd-who"><b><?= e(($h['id'] ?? '') === $admin['id'] ? t('You', 'Ikaw') : explode(' ', display_name((string) $h['full_name']))[0]) ?></b>
                    <small><?= e(rank_of($h['official_role'] ?? null) === 'chair' ? t('Chairman', 'Punong Barangay') : (rank_of($h['official_role'] ?? null) === 'kagawad' ? t('Councilor', 'Kagawad') : t('Staff', 'Kawani'))) ?></small></span>
                <?php else: ?>
                  <span class="bd-ring bd-free" aria-hidden="true">?</span><span class="bd-who"><b><?= e(t('Nobody yet', 'Wala pa')) ?></b><small><?= e(!empty($o['is_sensitive']) ? t('Sensitive: elevate it', 'Sensitibo: i-elevate') : t('Open it to take it', 'Buksan para kunin')) ?></small></span>
                <?php endif; ?>
              </div>
            </article>
          <?php endforeach; ?>
        </div>
      </section>
    <?php endforeach; ?>
  </div>
</div>
<?php
}
