<?php
/**
 * Residents and Personnel — Figma "Resident Lists" (2:3703),
 * "TanodLists" (12:5382), "Resident Verification" (2:3969),
 * "Responder Verification" (12:5531) and their accept/deny/suspend
 * variants.
 *
 * Four frames, one implementation. The two list screens differ only by
 * which role they filter on, and the two detail screens differ only by
 * which identity document they expect — a government ID for a resident,
 * a barangay appointment ID for a tanod. Everything else is the same
 * queue with the same two-hour clock.
 *
 * residents.php and personnel.php are thin wrappers around this.
 */
declare(strict_types=1);

require_once __DIR__ . '/auth.php';
require_once __DIR__ . '/layout.php';

/**
 * @param 'resident'|'tanod' $role
 */
/**
 * OCR ID triage (0039/0050): flags, "read as", re-check, Quick Verify. Off from Rose's call of
 * 27–30 Sep 2026 until 22 Oct 2026, when the reading came back on the phone with open-source
 * PaddleOCR (tools/ocr_lab). A reading only points to what to check: a person verifies. The app has
 * the same switch (kIdOcrEnabled in mobile/core/lib/src/id_ocr.dart).
 */
const ID_OCR_ENABLED = true;

function render_account_screen(string $role): void
{
    $admin = require_admin();
    $db    = db();

    $isTanod = $role === 'tanod';
    $title   = $isTanod ? t('Personnel', 'Mga Tanod') : t('Residents', 'Mga Residente');
    $navFile = $isTanod ? 'personnel.php' : 'residents.php';
    $self    = $navFile;
    $noun    = $isTanod ? 'Tanod' : 'Resident';   // logic below keys off this; see $nounLabel
    $nounLabel = $isTanod ? 'Tanod' : t('Resident', 'Residente');
    $idLabel = $isTanod
        ? t('Uploaded Barangay Appointment ID', 'Na-upload na Barangay Appointment ID')
        : t('Uploaded Valid Identification', 'Na-upload na Valid na ID');

    session_start_once();

    // ---------- actions ---------- (in includes/account_actions.php)
    require __DIR__ . '/account_actions.php';

    // 0153: the Committee staff tab (punch cards) of Personnel
    if ($isTanod) {
        require_once __DIR__ . '/personnel_committees.php';
        if (($_GET['view'] ?? '') === 'staff' && (is_super() || is_captain() || is_committee())) {
            render_punch_page($db);
            return;
        }
        if (($_GET['view'] ?? '') === 'retire' && is_committee()) {
            require_once __DIR__ . '/retirement.php';
            render_retire_page($db);
            return;
        }
    }

    $flash = $_SESSION['flash'] ?? null;
    unset($_SESSION['flash']);

    // ---------- data ----------
    $error    = null;
    $accounts = [];

    // One round trip for the list, the tanods' latest cases and the waiting
    // profile requests (speed, 7 Oct 2026); they used to follow one another.
    $batch = [
        'accounts' => ['rpc/account_directory', ['p_role' => $role]],
        // 0086 (Martin): name changes and new ID photos waiting for a decision.
        'requests' => ['profile_requests', [
            'select' => 'id,kind,new_full_name,id_type,id_image_url,reason,created_at,'
                      . 'who:users!profile_requests_user_id_fkey(full_name,mobile_number,role)',
            'status' => 'eq.pending',
            'order'  => 'created_at.asc',
        ], true],
    ];
    if ($isTanod) {
        // Figma TanodLists (branch B): "Latest Complaint Handled" — the
        // complaint of each tanod's most recent dispatch. Newest first, so
        // the first row seen per tanod is theirs.
        $batch['latest'] = ['dispatches', [
            'select' => 'tanod_id,report:reports!dispatches_report_id_fkey(tracking_id)',
            'order'  => 'assigned_at.desc',
            'limit'  => '1000',
        ], true];
        // 0153: each tanod's committees, and the committee of the case they are on
        $batch['tc'] = ['rpc/personnel_committees', [], true];
    }
    $got = [];
    try {
        $got = $db->selectMany($batch);
        $accounts = (array) $got['accounts'];
    } catch (SupabaseError $ex) {
        $error = safe_error($ex);
    }

    $tc = $isTanod ? tc_by_tanod($got['tc'] ?? []) : [];

    $latestCase = [];
    // The column reads "None" rather than failing the list.
    if (isset($got['latest']) && is_array($got['latest'])) {
        foreach ($got['latest'] as $d) {
            $latestCase[$d['tanod_id']] ??= $d['report']['tracking_id'] ?? null;
        }
    }

    // A complaint system is worth gaming: one person, several accounts,
    // several "independent" complaints about a neighbour. Nothing here
    // blocks anything — it puts the collision in front of the admin who
    // is about to verify, which is the only place the judgement belongs.
    $dupes = duplicate_flags($accounts);

    $viewId = (string) ($_GET['id'] ?? '');
    $person = null;
    foreach ($accounts as $a) {
        if ($a['id'] === $viewId) { $person = $a; break; }
    }

    if ($viewId !== '' && !$person && !$error) {
        $error = t('That account is not in this list.', 'Wala sa listahang ito ang account na iyan.');
    }

    if ($person) {
        // Only a resident can have reports of their own to be flagged
        // abusive — tanod accounts never file complaints, so the RPC
        // is skipped for them rather than called just to get back [].
        $abuseHistory = [];
        if (!$isTanod) {
            try {
                $abuseHistory = $db->rpc('resident_abuse_reports', ['p_user' => $person['id']]);
            } catch (SupabaseError) {
                // The profile still renders; the panel just shows no
                // history note instead of failing the whole page.
            }
        }

        $duty = $isTanod ? tanod_duty($db, $person['id']) : null;
        render_account_detail($person, $noun, $idLabel, $self, $navFile, $title, $flash,
                              $dupes[$person['id']] ?? [], $abuseHistory, $role, $duty, $isTanod ? ($tc[$person['id']] ?? []) : null);
        return;
    }

    // ---------- list ----------
    $allAccounts = $accounts;
    $search = trim((string) ($_GET['q'] ?? ''));
    if ($search !== '') {
        $needle   = mb_strtolower($search);
        $accounts = array_values(array_filter($accounts, function (array $a) use ($needle) {
            return str_contains(mb_strtolower($a['full_name'] . ' ' . $a['email'] . ' ' . $a['mobile_number']), $needle);
        }));
    }

    // Filter, not a sort — Rose's feedback (15 Sep 2026): the two options
    // people actually reach for are "show me who still needs review" and
    // "show me who's already in," not a re-ordering of the same list.
    $statusFilter = (string) ($_GET['sort'] ?? '');
    if ($statusFilter === 'pending') {
        $accounts = array_values(array_filter($accounts, fn($a) => $a['verification_status'] === 'pending'));
    } elseif ($statusFilter === 'verified') {
        $accounts = array_values(array_filter($accounts, fn($a) => $a['verification_status'] === 'verified'));
    } elseif ($statusFilter === 'overdue') {
        $accounts = array_values(array_filter($accounts, fn($a) => !empty($a['is_overdue'])));
    } elseif ($statusFilter === 'duplicate') {
        $accounts = array_values(array_filter($accounts, fn($a) => !empty($dupes[$a['id']])));
    } elseif ($statusFilter === 'suspended') {
        $accounts = array_values(array_filter($accounts, fn($a) => !empty($a['is_suspended'])));
    }
    // 0153: a committee picked from the chips (super admins and captains): its tanods, or the ones in none
    $comF = $isTanod && sees_everything() ? (string) ($_GET['com'] ?? '') : '';
    $inCom = function (array $a, string $k) use ($tc): bool {
        foreach ($tc[$a['id']]['committees'] ?? [] as $c) { if (($c['status'] ?? '') === 'approved' && ($k === '' || $c['key'] === $k)) return true; }
        return false;
    };
    if ($comF === 'none') {
        $accounts = array_values(array_filter($accounts, fn ($a) => !$inCom($a, '')));
    } elseif ($comF !== '' && isset(committees_all()[$comF])) {
        $accounts = array_values(array_filter($accounts, fn ($a) => $inCom($a, $comF)));
    } else {
        $comF = '';
    }
    // The duty tiles above the list filter too: the active tanods in that state (no state yet counts as offline).
    $dutyF = $isTanod && isset(TANOD_DUTY_STATES[(string) ($_GET['duty'] ?? '')]) ? (string) $_GET['duty'] : '';
    if ($dutyF !== '') {
        $accounts = array_values(array_filter($accounts, fn ($a) => account_is_active($a) && account_duty($a) === $dutyF));
    }
    // Chip counts (over every account of this kind, whatever the search).
    $chipN = [
        ''          => count($allAccounts),
        'pending'   => count(array_filter($allAccounts, fn($a) => $a['verification_status'] === 'pending')),
        'verified'  => count(array_filter($allAccounts, fn($a) => $a['verification_status'] === 'verified')),
        'overdue'   => count(array_filter($allAccounts, fn($a) => !empty($a['is_overdue']))),
        'duplicate' => count(array_filter($allAccounts, fn($a) => !empty($dupes[$a['id']]))),
        'suspended' => count(array_filter($allAccounts, fn($a) => !empty($a['is_suspended']))),
    ];
    $chipLabel = [
        ''          => t('All', 'Lahat'),
        'pending'   => t('Pending', 'Nakabinbin'),
        'verified'  => t('Verified', 'Beripikado'),
        'overdue'   => t('Overdue', 'Lampas-oras'),
        'duplicate' => t('Possible duplicate', 'Posibleng doble'),
        'suspended' => t('Suspended', 'Suspendido'),
    ];

    $pending = count(array_filter($accounts, fn($a) => $a['verification_status'] === 'pending'));
    $overdue = count(array_filter($accounts, fn($a) => !empty($a['is_overdue'])));
    // The panel's "no scroll scroll" (7 Sep): fifteen to a page, the counts above stay over the whole filtered list.
    $perPage  = 15;
    $accTotal = count($accounts);
    $accPage  = max(1, min((int) ($_GET['page'] ?? 1), max(1, (int) ceil($accTotal / $perPage))));
    $accounts = array_slice($accounts, ($accPage - 1) * $perPage, $perPage);
    $attendance = $isTanod ? tanod_attendance_counts($allAccounts) : [];

    layout_head($title, $navFile);
    ?>

    <div class="p-topbar"><h1><?= e($title) ?></h1>
      <span class="p-live" id="live-badge" title="<?= e(t('New registrations appear here on their own', 'Kusang lumalabas dito ang mga bagong rehistro')) ?>"><i></i><span id="live-badge-text"><?= e(t('Live', 'Live')) ?></span></span></div>
    <?= $isTanod ? personnel_tabs('') : '' ?>

    <?php if ($flash): ?>
      <div class="p-flash p-flash--<?= e($flash['level']) ?>" role="status"><?= e($flash['text']) ?></div>
    <?php endif; ?>
    <?php if ($error): ?>
      <div class="p-flash p-flash--error" role="alert"><?= e($error) ?></div>
    <?php endif; ?>

    <?php
    // 0086 (Martin): fetched with the list above.
    $requests = isset($got['requests']) && is_array($got['requests'])
        ? array_values(array_filter($got['requests'], fn($r) => ($r['who']['role'] ?? '') === ($isTanod ? 'tanod' : 'resident')))
        : [];
    ?>
    <?php if ($requests): ?>
      <div class="p-card p-card-pad ss-requests">
        <p class="p-eyebrow"><?= e(t('Requests waiting', 'Mga naghihintay na kahilingan')) ?> · <?= count($requests) ?></p>
        <div style="display:grid;gap:12px">
        <?php foreach ($requests as $r): ?>
          <div class="ss-req">
            <?php if ($r['kind'] === 'id_document'): ?>
              <a href="<?= e(cld_private_url((string) $r['id_image_url'])) ?>" target="_blank" rel="noopener"><img src="<?= e(cld_thumb($r['id_image_url'], 480)) ?>" alt="<?= e(t('New ID photo', 'Bagong litrato ng ID')) ?>" class="ss-req-img"></a>
            <?php else: ?>
              <span class="p-chip"><?= e(t('Name', 'Pangalan')) ?></span>
            <?php endif; ?>
            <div style="min-width:0">
              <b><?= e(formal_name($r['who']['full_name'] ?? '')) ?></b>
              <span class="p-hint"> · <?= e((string) ($r['who']['mobile_number'] ?? '')) ?> · <?= e(long_datetime($r['created_at'])) ?></span>
              <p style="margin:4px 0 0"><?= $r['kind'] === 'full_name'
                  ? e(t('Change name to', 'Palitan ang pangalan sa')) . ' <b>' . e(formal_name($r['new_full_name'])) . '</b>'
                  : e(t('New ID photo', 'Bagong litrato ng ID')) . ' (' . e(str_replace('_', ' ', (string) $r['id_type'])) . ')' ?></p>
              <?php if (!empty($r['reason'])): ?><p class="p-quote" style="margin:4px 0 0"><?= e($r['reason']) ?></p><?php endif; ?>
              <form method="post" class="ss-req-actions">
                <input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>">
                <input type="hidden" name="action" value="profile_request">
                <input type="hidden" name="request" value="<?= e($r['id']) ?>">
                <input class="p-input-plain" name="note" maxlength="300" placeholder="<?= e(t('Reason (needed to decline)', 'Dahilan (kailangan kung tatanggihan)')) ?>">
                <button class="p-btn p-btn-success p-btn-sm" type="submit" name="decision" value="approve"><?= e(t('Approve', 'Aprubahan')) ?></button>
                <button class="p-btn p-btn-danger-soft p-btn-sm" type="submit" name="decision" value="decline"><?= e(t('Decline', 'Tanggihan')) ?></button>
              </form>
            </div>
          </div>
        <?php endforeach; ?>
        </div>
      </div>
    <?php endif; ?>

    <!-- Always rendered so the polling below can show it as accounts age past the window. -->
    <div class="p-flash p-flash--error" id="overdue-banner" role="alert"<?= $overdue > 0 ? '' : ' hidden' ?>>
      <span id="overdue-text"><?= $overdue ?> <?= e(t(($overdue === 1 ? 'registration has' : 'registrations have') . ' passed the two-hour verification window.',
                                                 'rehistro ang lumampas na sa dalawang oras na palugit ng beripikasyon.')) ?></span>
    </div>

    <?php if ($isTanod) { render_tc_strip($db, $tc, $allAccounts); } ?>

    <?php if ($isTanod):
        $dutyHref = fn (string $d) => 'personnel.php?' . http_build_query(array_filter(['q' => $search, 'sort' => $statusFilter, 'com' => $comF, 'duty' => $d], fn ($v) => $v !== '')); ?>
      <!-- Today's shift: every active tanod (verified, not suspended or retired), whatever the search. A tile filters the list; the lit one again clears it. -->
      <nav class="p-kpis p-attendance" id="attendance-grid" aria-label="<?= e(t("Today's shift attendance summary", 'Buod ng pagdalo sa shift ngayong araw')) ?>">
        <?php foreach (TANOD_DUTY_STATES as $state => $label): $on = $dutyF === $state; ?>
          <a class="p-card p-kpi p-att-<?= e($state) ?><?= $on ? ' p-on' : '' ?>" href="<?= e($dutyHref($on ? '' : $state)) ?>"<?= $on ? ' aria-current="true"' : '' ?> title="<?= e($on ? t('Show everyone again', 'Ipakita muli ang lahat') : sprintf(t('Show only %s', 'Ipakita lamang ang %s'), status_label($state))) ?>"><div class="p-label"><span class="p-att-dot" aria-hidden="true"></span><?= e(status_label($state)) ?></div>
            <div class="p-value p-num" data-state="<?= e($state) ?>"><?= (int) ($attendance[$state] ?? 0) ?></div>
            <div class="p-delta"><?= e(t('Today’s shift', 'Shift ngayong araw')) ?></div></a>
        <?php endforeach; ?>
      </nav>
    <?php endif; ?>

    <?php if ($isTanod && sees_everything()):
        $comHref = fn (string $c) => 'personnel.php?' . http_build_query(array_filter(['q' => $search, 'sort' => $statusFilter, 'duty' => $dutyF, 'com' => $c], fn ($v) => $v !== ''));
        $comN = fn (string $k) => count(array_filter($allAccounts, fn ($a) => $k === 'none' ? !$inCom($a, '') : $inCom($a, $k))); ?>
    <nav class="cm-chips" aria-label="<?= e(t('Committees', 'Mga komite')) ?>">
      <a class="cm-chip<?= $comF === '' ? ' p-on' : '' ?>" href="<?= e($comHref('')) ?>"<?= $comF === '' ? ' aria-current="true"' : '' ?>><?= e(t('All', 'Lahat')) ?><b><?= count($allAccounts) ?></b></a>
      <?php foreach (committees_active() as $ck => $cl): ?>
        <a class="cm-chip<?= $comF === $ck ? ' p-on' : '' ?>" style="--cc:<?= e(committee_colour($ck)) ?>" href="<?= e($comHref($ck)) ?>"<?= $comF === $ck ? ' aria-current="true"' : '' ?>><i></i><?= e($cl) ?><b><?= $comN($ck) ?></b></a>
      <?php endforeach; ?>
      <a class="cm-chip cm-chip-none<?= $comF === 'none' ? ' p-on' : '' ?>" href="<?= e($comHref('none')) ?>"<?= $comF === 'none' ? ' aria-current="true"' : '' ?>><i></i><?= e(t('No committee yet', 'Wala pang komite')) ?><b><?= $comN('none') ?></b></a>
    </nav>
    <?php endif; ?>

    <div class="p-band ss-pband">
      <h2><?= e(t($noun . ' accounts', 'Mga account ng ' . $nounLabel)) ?><span class="p-badge-n p-badge-n--quiet" id="accounts-count"><?= $accTotal ?></span><span class="p-badge-n" id="pending-wrap"<?= $pending > 0 ? '' : ' hidden' ?>><span id="pending-count"><?= $pending ?></span> <?= e(t('to review', 'susuriin')) ?></span></h2>
      <form class="p-search" method="get" role="search">
        <?= p_icon('i-search', 16) ?><label class="p-sr" for="acc-q"><?= e(t('Search', 'Maghanap')) ?></label>
        <input id="acc-q" type="search" name="q" placeholder="<?= e(t('Search name, phone or email', 'Hanapin ang pangalan, telepono o email')) ?>" value="<?= e($search) ?>" autocomplete="off">
        <?php if ($statusFilter !== ''): ?><input type="hidden" name="sort" value="<?= e($statusFilter) ?>"><?php endif; ?>
      </form>
      <span class="p-spacer"></span>
      <form method="get">
        <input type="hidden" name="q" value="<?= e($search) ?>">
        <label class="p-pill-select"><span class="p-lbl"><?= e(t('Status', 'Katayuan')) ?></span>
          <select id="acc-st" name="sort" data-autosubmit aria-label="<?= e(t('Status', 'Katayuan')) ?>">
            <?php foreach ($chipLabel as $ck => $cl): ?>
              <option value="<?= e($ck) ?>" data-chip="<?= e($ck === '' ? 'all' : $ck) ?>" data-l="<?= e($cl) ?>"<?= $statusFilter === $ck ? ' selected' : '' ?>><?= e($cl) ?> (<?= (int) $chipN[$ck] ?>)</option>
            <?php endforeach; ?>
          </select></label>
      </form>
      <div class="ss-viewsw" role="group" aria-label="<?= e(t('Layout', 'Ayos')) ?>">
        <button type="button" data-view="list" aria-pressed="true" title="<?= e(t('List', 'Listahan')) ?>"><?= p_icon('i-doc', 15) ?><span><?= e(t('List', 'Listahan')) ?></span></button>
        <button type="button" data-view="sq" aria-pressed="false" title="<?= e(t('Squares', 'Mga parisukat')) ?>"><?= p_icon('i-users', 15) ?><span><?= e(t('Squares', 'Mga parisukat')) ?></span></button>
      </div>
    </div>

    <div class="ss-bulk" id="ss-bulk" hidden>
      <b><span id="ss-bulk-n">0</span> <?= e(t('selected', 'napili')) ?></b>
      <?php if ($isTanod && is_super()): ?>
        <form method="post" class="ss-bulk-tc" id="ss-bulk-tc">
          <input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>"><input type="hidden" name="action" value="tc_bulk"><input type="hidden" name="to_list" value="1">
          <label class="p-sr" for="ss-bulk-com"><?= e(t('Committee', 'Komite')) ?></label>
          <select class="p-input-plain" id="ss-bulk-com" name="committee" required><option value="" disabled selected><?= e(t('Add to a committee…', 'Idagdag sa komite…')) ?></option>
            <?php foreach (committees_active() as $ck => $cl): ?><option value="<?= e($ck) ?>"><?= e($cl) ?></option><?php endforeach; ?></select>
          <button type="submit" class="ss-bulk-go"><?= e(t('Add to committee', 'Idagdag sa komite')) ?></button>
        </form>
      <?php endif; ?>
      <button type="button" class="ss-bulk-go" id="ss-bulk-go"><?= e(t('Review one after another', 'Suriin nang sunud-sunod')) ?></button>
      <button type="button" class="ss-bulk-clear" id="ss-bulk-clear"><?= e(t('Clear', 'I-clear')) ?></button>
    </div>
    <div class="ss-rqstrip" id="ss-rqstrip" hidden data-self="<?= e($self) ?>">
      <span><?= e(t('Your review queue', 'Ang iyong pila sa pagsusuri')) ?>: <b id="ss-rq-n">0</b> <?= e(t('left', 'natitira')) ?></span>
      <a class="ss-bulk-go" id="ss-rq-go" href="#"><?= e(t('Continue', 'Ituloy')) ?></a>
      <button type="button" class="ss-bulk-clear" id="ss-rq-drop"><?= e(t('Drop the queue', 'Alisin ang pila')) ?></button>
    </div>

    <div class="p-card p-table-card jp-scope ss-people<?= $isTanod ? ' ss-tanods pe-roster' : ' pe-roster pe-res' ?>" id="ss-people"><div class="p-tscroll">
      <table class="p-t ss-ohead">
        <?php if ($isTanod): ?><colgroup><col class="pe-c-cb"><col class="pe-c-who"><col class="pe-c-duty"><col class="pe-c-com"><col class="pe-c-last"><col class="pe-c-contact"><col class="pe-c-acct"><col class="pe-c-act"></colgroup>
        <?php else: ?><colgroup><col class="pe-c-cb"><col class="pe-c-who"><col class="pe-c-contact"><col class="pe-c-acct"><col class="pe-c-act"></colgroup><?php endif; ?>
        <thead><tr>
          <th scope="col" class="ss-cbh"><input type="checkbox" id="ss-all" aria-label="<?= e(t('Select everyone on this page', 'Piliin ang lahat sa pahinang ito')) ?>"></th>
          <th scope="col"><?= e(t($noun, $nounLabel)) ?></th>
          <?php if ($isTanod): ?>
            <th scope="col"><?= e(t('Duty', 'Tungkulin')) ?></th><th scope="col"><?= e(t('Committees', 'Mga komite')) ?></th><th scope="col"><?= e(t('Latest complaint handled', 'Huling hinawakang sumbong')) ?></th>
            <th scope="col"><?= e(t('Contact', 'Kontak')) ?></th><th scope="col"><?= e(t('Account', 'Account')) ?></th>
          <?php else: ?>
            <th scope="col"><?= e(t('Contact', 'Kontak')) ?></th><th scope="col"><?= e(t('Status', 'Katayuan')) ?></th>
          <?php endif; ?>
          <th scope="col" class="p-right"><span class="p-sr"><?= e(t('Action', 'Aksyon')) ?></span></th>
        </tr></thead>
        <tbody id="accounts-tbody">
          <?php if (!$accounts): ?>
            <tr><td colspan="<?= $isTanod ? 8 : 5 ?>" class="p-empty"><?= $search !== ''
                ? e(t('No account matches that search.', 'Walang account na tugma sa hinanap.'))
                : e(t('No ' . strtolower($noun) . ' accounts have registered yet.', 'Wala pang nagparehistrong ' . strtolower($nounLabel) . '.')) ?></td></tr>
          <?php endif; ?>
          <?php foreach ($accounts as $a): ?>
            <tr data-id="<?= e($a['id']) ?>" data-pending="<?= $a['verification_status'] === 'pending' ? '1' : '0' ?>">
              <td class="ss-cbc"><input type="checkbox" class="ss-cb" value="<?= e($a['id']) ?>" aria-label="<?= e(t('Select', 'Piliin')) ?> <?= e(formal_name($a['full_name'])) ?>"></td>
              <td><div class="p-person"><?= account_avatar_html($a['avatar_url'] ?? null, $a['full_name'], 'sm') ?><span title="<?= e(formal_name($a['full_name'])) ?>"><?= e(formal_name($a['full_name'])) ?></span></div></td>
              <?php if ($isTanod): ?>
                <td class="pe-duty-c"><?= tanod_duty_cell($a, $tc[$a['id']] ?? null) ?></td>
                <td class="tc-cell"><?= tc_list_pills($tc[$a['id']] ?? null) ?></td>
                <td class="ss-latest"><?= !empty($latestCase[$a['id']]) ? '<span class="p-mono-id">' . e($latestCase[$a['id']]) . '</span>' : '<span class="p-sub">—</span>' ?></td>
                <td class="pe-contact"><span class="p-num"><?= e($a['mobile_number']) ?></span><span class="pe-mail"<?= $a['email'] ? ' title="' . e($a['email']) . '"' : '' ?>><?= $a['email'] ? e($a['email']) : '—' ?></span></td>
              <?php else: ?>
                <td class="pe-contact"><span class="p-num"><?= e($a['mobile_number']) ?></span><span class="pe-mail"<?= $a['email'] ? ' title="' . e($a['email']) . '"' : '' ?>><?= $a['email'] ? e($a['email']) : '—' ?></span></td>
              <?php endif; ?>
              <td><div class="p-badges"><?= account_status_pills($a, !$isTanod) ?><?php
                  if (!empty($dupes[$a['id']])): ?><span class="p-badge p-b-violet" title="<?= e(implode('; ', $dupes[$a['id']])) ?>"><?= e(t('Possible duplicate', 'Posibleng doble')) ?></span><?php endif; ?><?php
                  if (ID_OCR_ENABLED && !empty($a['ocr_flags'])): ?><span class="p-badge p-b-violet" title="<?= e(implode('; ', array_map('ocr_flag_label', $a['ocr_flags']))) ?>"><?= e(t('OCR flag', 'OCR flag')) ?></span><?php endif; ?><?php
                  if (ID_OCR_ENABLED && !empty($a['ocr_rescan_requested_at'])
                      && (empty($a['ocr_processed_at'])
                          || (string) $a['ocr_processed_at'] < (string) $a['ocr_rescan_requested_at'])): ?><span class="p-badge p-b-grey" title="<?= e(t('Waiting for them to open the app', 'Hinihintay na buksan nila ang app')) ?>"><?= e(t('Re-check pending', 'Nakabinbing muling pagsuri')) ?></span><?php endif; ?></div></td>
              <td class="p-right">
                <a class="p-btn p-btn-sm <?= $a['verification_status'] === 'pending' ? 'p-btn-primary' : 'p-btn-ghost' ?>" href="<?= e($self) ?>?id=<?= e($a['id']) ?>">
                  <?= $a['verification_status'] === 'pending' ? e(t('Review', 'Suriin')) : e(t('View', 'Tingnan')) ?>
                </a>
                <?php if ($a['verification_status'] === 'pending'
                          && ID_OCR_ENABLED && account_ocr_is_clean($a)
                          && empty($dupes[$a['id']])): ?>
                  <form method="post" class="quick-verify-form" style="display:inline" data-name="<?= e(display_name($a['full_name'])) ?>">
                    <input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>">
                    <input type="hidden" name="id" value="<?= e($a['id']) ?>">
                    <button class="p-btn p-btn-ghost p-btn-sm" type="submit" name="action" value="approve"
                            title="<?= e(t('OCR read a clean, matching ID with no flags — verify without opening the full review', 'Malinaw at tugma ang ID ayon sa OCR, walang flag — i-verify nang hindi binubuksan ang buong pagsusuri')) ?>">
                      <?= p_icon('i-check', 14) ?><?= e(t('Quick Verify', 'Mabilisang I-verify')) ?></button>
                  </form>
                <?php endif; ?>
              </td>
            </tr>
          <?php endforeach; ?>
        </tbody>
      </table>
    </div></div>
    <div id="accounts-pager"><?= pager($accTotal, $accPage, 'page', $perPage) ?></div>
    <script src="assets/js/people-list.js?v=2"></script>

    <script src="assets/vendor/supabase/supabase.js?v=2.117.3"></script>
    <script>
    // Realtime for the verification queue — explicit ask, 6 Sep 2026: "the
    // entire system needs to work realtime," and this is exactly the
    // "new additions" case: a fresh registration should appear here on
    // its own. public.users is deliberately NOT in the supabase_realtime
    // publication (migration 0046's own reasoning: identity images and
    // mobile numbers in the row), so there is no push signal to
    // subscribe to here the way cases.php/dashboard.php could. A short
    // poll of the same account_directory() RPC the page already calls is
    // the honest way to still keep this current without asking the team
    // to reopen that privacy decision.
    (function () {
      if (!window.supabase) { return; }
      const { createClient } = supabase;

      const TOKEN = <?= json_encode(access_token()) ?>;
      const ROLE  = <?= json_encode($role) ?>;
      const SELF  = <?= json_encode($self) ?>;
      const SEARCH = <?= json_encode($search) ?>;
      const STATUS_FILTER = <?= json_encode($statusFilter) ?>;
      const PER = <?= (int) $perPage ?>;
      let PAGE = <?= (int) $accPage ?>;
      // Same session token every page load (csrf_token() memoizes it) --
      // safe to bake into the JS-rendered Quick Verify forms below the
      // same way the PHP-rendered ones already carry it as a hidden
      // input.
      const CSRF = <?= json_encode(csrf_token()) ?>;
      const OCR_ON = <?= json_encode(ID_OCR_ENABLED) ?>;
      const STATUS_LABEL = <?= json_encode(status_labels(), JSON_UNESCAPED_UNICODE) ?>;
      const NOUN_LABEL = <?= json_encode(strtolower($nounLabel), JSON_UNESCAPED_UNICODE) ?>;
      const IS_TANOD = <?= json_encode($isTanod) ?>;
      // tanod id -> tracking id of their latest dispatch; refreshed with
      // the list on every poll.
      let LATEST = <?= json_encode((object) array_filter($latestCase)) ?>;
      // 0153: each tanod's committees (id -> {committees, busy}), refreshed with the list; the committees' names and colours; the filters picked
      let TC = <?= json_encode((object) ($isTanod ? $tc : [])) ?>;
      const COM = <?= json_encode((object) array_combine(array_keys(committees_all()), array_map(fn ($k) => [(string) committees_all()[$k]['short_en'], committee_colour($k)], array_keys(committees_all())))) ?>;
      const COM_F = <?= json_encode($isTanod ? $comF : '') ?>;
      const DUTY_F = <?= json_encode($dutyF ?? '') ?>;
      const NO_COM = <?= json_encode(is_scoped() ? '—' : t('No committee', 'Walang komite')) ?>;
      const sb = createClient(
        <?= json_encode(supabase_url()) ?>,
        <?= json_encode(supabase_key()) ?>,
        { accessToken: window.ssAccessToken(TOKEN) }
      );

      function escapeHtml(s) {
        return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) {
          return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
        });
      }
      const titleCase = s => String(s || '').replace(/_/g, ' ')
        .replace(/\b\w/g, c => c.toUpperCase());

      // Mirrors account_avatar_html()/account_initials() in this same
      // file exactly, so a live refresh shows the same picture (or the
      // same initials fallback) a reload would.
      function initials(name) {
        var parts = window.ssName(name || '').trim().split(/\s+/).filter(Boolean);
        if (!parts.length) return '?';
        var first = parts[0].charAt(0);
        var last = parts.length > 1 ? parts[parts.length - 1].charAt(0) : '';
        return (first + last).toUpperCase();
      }
      function avatarHtml(url, name, size) {
        var cls = 'p-avatar p-av-' + size;
        if (url) {
          return '<img class="' + cls + '" src="' + escapeHtml(window.ssThumb(url, 160, true)) + '" alt="" loading="lazy">';
        }
        return '<span class="' + cls + '" aria-hidden="true">' + escapeHtml(initials(name)) + '</span>';
      }

      // Mirrors account_ocr_is_clean() in this same file exactly.
      function ocrIsClean(a) {
        if (!a.id_image_url || !a.ocr_processed_at) return false;
        if (a.ocr_flags && a.ocr_flags.length) return false;
        var rescanPending = a.ocr_rescan_requested_at &&
          String(a.ocr_processed_at) < String(a.ocr_rescan_requested_at);
        return !rescanPending;
      }

      function ocrFlagLabel(f) {
        switch (f) {
          case 'type_mismatch': return T('ID type does not match', 'Hindi tugma ang uri ng ID');
          case 'unreadable': return T('ID could not be read', 'Hindi mabasa ang ID');
          case 'name_mismatch': return T('Name does not match', 'Hindi tugma ang pangalan');
          case 'no_id_number': return T('No ID number found', 'Walang nakitang numero ng ID');
          default: return titleCase(f);
        }
      }

      // Mirrors is_self_deleted_account() in this same file exactly — the
      // fixed sentence request_account_deletion() (0045) writes into
      // suspended_reason is the only thing that tells a self-deleted
      // account apart from an ordinary admin suspension.
      function isSelfDeletedAccount(a) {
        return String(a.suspended_reason || '').indexOf('Account deleted by the resident') === 0;
      }

      function statusPillsHtml(a) {
        var out = [];
        if (a.verification_status === 'verified') out.push('<span class="p-badge p-b-done">' + T('Verified', 'Beripikado') + '</span>');
        else if (a.verification_status === 'rejected') out.push('<span class="p-badge p-b-denied">' + T('Rejected', 'Tinanggihan') + '</span>');
        else out.push('<span class="p-badge p-b-pending">' + T('Pending', 'Nakabinbin') + '</span>');

        if (a.is_suspended) {
          out.push(isSelfDeletedAccount(a)
            ? '<span class="p-badge p-b-denied">' + T('Deleted by Resident', 'Binura ng Residente') + '</span>'
            : '<span class="p-badge p-b-denied">' + T('Suspended', 'Suspendido') + '</span>');
        }

        if (a.verification_status === 'pending') {
          if (a.is_overdue) out.push('<span class="p-badge p-b-denied">' + T('Overdue', 'Lampas-oras') + '</span>');
          else if (a.minutes_left !== null && a.minutes_left !== undefined) {
            out.push('<span class="p-badge p-b-progress">' + Math.trunc(a.minutes_left) + T(' min left', ' minuto pa') + '</span>');
          }
        }
        if (!IS_TANOD && a.holding_incident) out.push('<span class="p-badge p-b-progress">' + T('On an incident', 'May hawak na insidente') + '</span>');
        if (!IS_TANOD && a.duty_status) out.push('<span class="p-badge p-b-grey">' + escapeHtml(STATUS_LABEL[a.duty_status] || titleCase(a.duty_status)) + '</span>');
        return out.join(' ');
      }

      // Mirrors duplicate_flags() in this same file exactly, so a live
      // refresh flags the same collisions a reload would.
      function normalizeName(name) {
        var stripped = String(name || '').toLowerCase().replace(/[^\p{L}\s]/gu, ' ');
        return stripped.split(/\s+/).filter(Boolean).sort().join(' ');
      }
      function duplicateFlags(accounts) {
        var byMobile = {}, byName = {}, out = {};
        accounts.forEach(function (a) {
          var m = String(a.mobile_number || '').replace(/\D+/g, '');
          var n = normalizeName(a.full_name);
          if (m) { (byMobile[m] = byMobile[m] || []).push(a); }
          if (n) { (byName[n] = byName[n] || []).push(a); }
        });
        Object.keys(byMobile).forEach(function (k) {
          var group = byMobile[k];
          if (group.length < 2) return;
          group.forEach(function (a) {
            var others = group.filter(function (b) { return b.id !== a.id; });
            (out[a.id] = out[a.id] || []).push(T('Same mobile number as ', 'Kaparehong mobile number ni ')
              + others.map(function (b) { return b.full_name; }).join(', '));
          });
        });
        Object.keys(byName).forEach(function (k) {
          var group = byName[k];
          if (group.length < 2) return;
          group.forEach(function (a) {
            (out[a.id] = out[a.id] || []).push(T('Same name as another account (' + group.length + ' total)', 'Kaparehong pangalan ng ibang account (' + group.length + ' lahat)'));
          });
        });
        return out;
      }

      // Mirrors account_is_active(), account_duty(), tanod_duty_cell(), tc_pill() and tc_list_pills() in PHP exactly.
      function isActive(a) { return a.verification_status === 'verified' && !a.is_suspended && !a.is_retired; }
      function dutyOf(a) { return ['on_duty', 'lunch', 'break', 'offline'].indexOf(a.duty_status) > -1 ? a.duty_status : 'offline'; }
      function comPill(k) {
        return COM[k] ? '<span class="cm-pill" title="' + escapeHtml(COM[k][0]) + '" style="--cc:' + escapeHtml(COM[k][1]) + '"><i></i>' + escapeHtml(COM[k][0]) + '</span>'
                      : '<span class="cm-pill cm-none" title="' + T('No committee', 'Walang komite') + '"><i></i>' + T('No committee', 'Walang komite') + '</span>';
      }
      function tcPill(c) {
        var cm = COM[c.key] || [c.key, '#888'], role = String(c.role || '').trim(), prop = c.status === 'proposed';
        return '<span class="cm-pill' + (prop ? ' cm-prop' : '') + '" style="--cc:' + escapeHtml(cm[1]) + '" title="' + escapeHtml(cm[0] + (role ? ' · ' + role : '')) + '"><i></i>' +
          escapeHtml(cm[0]) + (role ? '<small>' + escapeHtml(role) + '</small>' : '') + (prop ? '<small>' + T('proposed', 'iminungkahi') + '</small>' : '') + '</span>';
      }
      function tcListPills(row) {
        var cs = (row && row.committees) || [];
        if (!cs.length) return '<div class="tc-pills"><span class="p-sub">' + escapeHtml(NO_COM) + '</span></div>';
        var show = cs.length > 2 ? 1 : cs.length, o = cs.slice(0, show).map(tcPill).join('');
        if (cs.length > show) {
          var rest = cs.slice(show).map(function (c) { return COM[c.key] ? COM[c.key][0] : c.key; });
          o += '<span class="cm-more" title="' + escapeHtml(rest.join(', ')) + '">+' + rest.length + ' ' + T('more', 'pa') + '</span>';
        }
        return '<div class="tc-pills">' + o + '</div>';
      }
      function dutyCellHtml(a) {
        if (!isActive(a)) return '<span class="p-sub">—</span>';
        var d = dutyOf(a), row = TC[a.id], o = '<span class="pe-duty pe-d-' + d + '"><i></i>' + escapeHtml(STATUS_LABEL[d] || titleCase(d)) + '</span>';
        if (row && row.busy) o += '<span class="tc-busy"><small>' + T('On a case', 'May kaso') + '</small>' + comPill(row.busy) + '</span>';
        else if (a.holding_incident) o += '<span class="tc-busy"><small>' + T('On an incident', 'May hawak na insidente') + '</small></span>';
        return '<div class="pe-dutybox">' + o + '</div>';
      }
      function inCom(a, k) {
        var cs = (TC[a.id] && TC[a.id].committees) || [];
        return cs.some(function (c) { return c.status === 'approved' && (k === '' || c.key === k); });
      }

      // Mirrors tanod_attendance_counts() in this same file exactly.
      function renderAttendance(accounts) {
        var grid = document.getElementById('attendance-grid');
        if (!grid) return;
        var counts = { on_duty: 0, lunch: 0, break: 0, offline: 0 };
        accounts.forEach(function (a) {
          if (a.verification_status !== 'verified' || a.is_suspended || a.is_retired) return;
          counts[counts.hasOwnProperty(a.duty_status) ? a.duty_status : 'offline']++;
        });
        grid.querySelectorAll('[data-state]').forEach(function (el) {
          el.textContent = counts[el.dataset.state] || 0;
        });
      }

      function pagerHtml(total, page) {
        var pages = Math.max(1, Math.ceil(total / PER));
        if (pages <= 1) { return ''; }
        var href = function (n) { var u = new URLSearchParams(location.search); u.set('page', n); return '?' + u.toString(); };
        var from = Math.max(1, Math.min(page - 2, pages - 4)), to = Math.min(pages, from + 4);
        var o = '<nav class="ss-pager" aria-label="' + T('Pages', 'Mga pahina') + '">';
        o += page > 1 ? '<a href="' + href(page - 1) + '" rel="prev">&lsaquo; ' + T('Previous', 'Nakaraan') + '</a>' : '<span class="off">&lsaquo; ' + T('Previous', 'Nakaraan') + '</span>';
        if (from > 1) { o += '<a href="' + href(1) + '">1</a>' + (from > 2 ? '<span class="gap">&hellip;</span>' : ''); }
        for (var i = from; i <= to; i++) { o += i === page ? '<span class="on" aria-current="page">' + i + '</span>' : '<a href="' + href(i) + '">' + i + '</a>'; }
        if (to < pages) { o += (to < pages - 1 ? '<span class="gap">&hellip;</span>' : '') + '<a href="' + href(pages) + '">' + pages + '</a>'; }
        o += page < pages ? '<a href="' + href(page + 1) + '" rel="next">' + T('Next', 'Susunod') + ' &rsaquo;</a>' : '<span class="off">' + T('Next', 'Susunod') + ' &rsaquo;</span>';
        return o + '<span class="of">' + ((page - 1) * PER + 1) + '&ndash;' + Math.min(total, page * PER) + ' ' + T('of', 'sa') + ' ' + total + '</span></nav>';
      }
      function renderAccounts(accounts) {
        var filtered = accounts;
        if (SEARCH) {
          var needle = SEARCH.toLowerCase();
          filtered = filtered.filter(function (a) {
            return ((a.full_name || '') + ' ' + (a.email || '') + ' ' + (a.mobile_number || ''))
              .toLowerCase().indexOf(needle) !== -1;
          });
        }
        var dupes = duplicateFlags(accounts);
        if (COM_F === 'none') filtered = filtered.filter(function (a) { return !inCom(a, ''); });
        else if (COM_F) filtered = filtered.filter(function (a) { return inCom(a, COM_F); });
        if (DUTY_F) filtered = filtered.filter(function (a) { return isActive(a) && dutyOf(a) === DUTY_F; });
        if (STATUS_FILTER === 'pending' || STATUS_FILTER === 'verified') {
          filtered = filtered.filter(function (a) { return a.verification_status === STATUS_FILTER; });
        } else if (STATUS_FILTER === 'overdue') {
          filtered = filtered.filter(function (a) { return a.is_overdue; });
        } else if (STATUS_FILTER === 'duplicate') {
          filtered = filtered.filter(function (a) { return dupes[a.id] && dupes[a.id].length; });
        } else if (STATUS_FILTER === 'suspended') {
          filtered = filtered.filter(function (a) { return a.is_suspended; });
        }
        // The filter chips' counts, over every account of this kind (the PHP render counts the same).
        var chipCounts = { all: accounts.length,
          pending: accounts.filter(function (a) { return a.verification_status === 'pending'; }).length,
          verified: accounts.filter(function (a) { return a.verification_status === 'verified'; }).length,
          overdue: accounts.filter(function (a) { return a.is_overdue; }).length,
          duplicate: accounts.filter(function (a) { return dupes[a.id] && dupes[a.id].length; }).length,
          suspended: accounts.filter(function (a) { return a.is_suspended; }).length };
        Object.keys(chipCounts).forEach(function (k) { var o = document.querySelector('#acc-st option[data-chip="' + k + '"]'); if (o) o.textContent = o.dataset.l + ' (' + chipCounts[k] + ')'; });
        var total = filtered.length;

        // Counted over the filtered list, the same as the PHP render above
        // does — counting all accounts made the "awaiting review" note and
        // the overdue banner appear 20 seconds after loading a Verified-only
        // or searched view, with nothing having changed.
        document.getElementById('accounts-count').textContent = filtered.length;
        var pending = filtered.filter(function (a) { return a.verification_status === 'pending'; }).length;
        var overdue = filtered.filter(function (a) { return a.is_overdue; }).length;

        var pendingWrap = document.getElementById('pending-wrap');
        pendingWrap.hidden = pending === 0;
        document.getElementById('pending-count').textContent = pending;

        var overdueBanner = document.getElementById('overdue-banner');
        overdueBanner.hidden = !(overdue > 0);
        document.getElementById('overdue-text').textContent =
          overdue + ' ' + T((overdue === 1 ? 'registration has' : 'registrations have') + ' passed the two-hour verification window.',
                            'rehistro ang lumampas na sa dalawang oras na palugit ng beripikasyon.');

        renderAttendance(accounts);

        PAGE = Math.max(1, Math.min(PAGE, Math.ceil(total / PER) || 1));
        filtered = filtered.slice((PAGE - 1) * PER, PAGE * PER);
        document.getElementById('accounts-pager').innerHTML = pagerHtml(total, PAGE);

        var tbody = document.getElementById('accounts-tbody');
        if (!filtered.length) {
          tbody.innerHTML = '<tr><td class="p-empty" colspan="' + (IS_TANOD ? 8 : 5) + '">' +
            (SEARCH ? T('No account matches that search.', 'Walang account na tugma sa hinanap.')
                    : T('No ' + <?= json_encode(strtolower($noun)) ?> + ' accounts have registered yet.', 'Wala pang nagparehistrong ' + escapeHtml(NOUN_LABEL) + '.')) +
            '</td></tr>';
          return;
        }
        tbody.innerHTML = filtered.map(function (a) {
          var extra = '';
          if (dupes[a.id] && dupes[a.id].length) {
            extra += '<span class="p-badge p-b-violet" title="' + escapeHtml(dupes[a.id].join('; ')) + '">' + T('Possible duplicate', 'Posibleng doble') + '</span>';
          }
          if (OCR_ON && a.ocr_flags && a.ocr_flags.length) {
            extra += '<span class="p-badge p-b-violet" title="' +
              escapeHtml(a.ocr_flags.map(ocrFlagLabel).join('; ')) + '">' + T('OCR flag', 'OCR flag') + '</span>';
          }
          if (OCR_ON && a.ocr_rescan_requested_at &&
              (!a.ocr_processed_at || String(a.ocr_processed_at) < String(a.ocr_rescan_requested_at))) {
            extra += '<span class="p-badge p-b-grey" title="' + T('Waiting for them to open the app', 'Hinihintay na buksan nila ang app') + '">' + T('Re-check pending', 'Nakabinbing muling pagsuri') + '</span>';
          }
          var quickVerify = '';
          if (OCR_ON && a.verification_status === 'pending' && ocrIsClean(a) &&
              !(dupes[a.id] && dupes[a.id].length)) {
            quickVerify =
              '<form method="post" class="quick-verify-form" style="display:inline" data-name="' + escapeHtml(window.ssName(a.full_name)) + '">' +
                '<input type="hidden" name="csrf" value="' + escapeHtml(CSRF) + '">' +
                '<input type="hidden" name="id" value="' + escapeHtml(a.id) + '">' +
                '<button class="p-btn p-btn-ghost p-btn-sm" type="submit" name="action" value="approve" ' +
                  'title="' + T('OCR read a clean, matching ID with no flags — verify without opening the full review', 'Malinaw at tugma ang ID ayon sa OCR, walang flag — i-verify nang hindi binubuksan ang buong pagsusuri') + '">' +
                  '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" ' +
                    'stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' +
                    '<polyline points="20 6 9 17 4 12"/></svg>' +
                  T('Quick Verify', 'Mabilisang I-verify') +
                '</button>' +
              '</form>';
          }
          return '<tr data-id="' + escapeHtml(a.id) + '" data-pending="' + (a.verification_status === 'pending' ? '1' : '0') + '">' +
            '<td class="ss-cbc"><input type="checkbox" class="ss-cb" value="' + escapeHtml(a.id) + '" aria-label="' + T('Select', 'Piliin') + ' ' + escapeHtml(String(a.full_name || '').trim()) + '"></td>' +
            '<td><div class="p-person">' + avatarHtml(a.avatar_url, a.full_name, 'sm') + '<span title="' + escapeHtml(String(a.full_name || '').trim()) + '">' + escapeHtml(String(a.full_name || '').trim()) + '</span></div></td>' +
            (IS_TANOD
              ? '<td class="pe-duty-c">' + dutyCellHtml(a) + '</td><td class="tc-cell">' + tcListPills(TC[a.id]) + '</td><td class="ss-latest">' +
                (LATEST[a.id] ? '<span class="p-mono-id">' + escapeHtml(LATEST[a.id]) + '</span>' : '<span class="p-sub">—</span>') + '</td>' +
                '<td class="pe-contact"><span class="p-num">' + escapeHtml(a.mobile_number) + '</span><span class="pe-mail"' + (a.email ? ' title="' + escapeHtml(a.email) + '"' : '') + '>' + (a.email ? escapeHtml(a.email) : '—') + '</span></td>'
              : '<td class="pe-contact"><span class="p-num">' + escapeHtml(a.mobile_number) + '</span><span class="pe-mail"' + (a.email ? ' title="' + escapeHtml(a.email) + '"' : '') + '>' + (a.email ? escapeHtml(a.email) : '—') + '</span></td>') +
            '<td><div class="p-badges">' + statusPillsHtml(a) + extra + '</div></td>' +
            '<td class="p-right"><a class="p-btn p-btn-sm ' + (a.verification_status === 'pending' ? 'p-btn-primary' : 'p-btn-ghost') + '" href="' + SELF + '?id=' + encodeURIComponent(a.id) + '">' +
              (a.verification_status === 'pending' ? T('Review', 'Suriin') : T('View', 'Tingnan')) + '</a>' + quickVerify + '</td>' +
            '</tr>';
        }).join('');
      }

      // Delegated so it also covers rows renderAccounts() replaces on
      // every 20s poll -- a listener bound to the original elements
      // would go stale the moment the tbody's innerHTML is rewritten.
      document.getElementById('accounts-tbody').addEventListener('submit', function (e) {
        var form = e.target.closest('.quick-verify-form');
        if (!form) return;
        var name = form.dataset.name || T('this account', 'ang account na ito');
        if (!confirm(T('Verify ' + name + ' now? OCR read a clean, matching ID with no flags.',
                       'I-verify si ' + name + ' ngayon? Malinaw at tugma ang ID ayon sa OCR, walang flag.'))) {
          e.preventDefault();
        }
      });

      let timer = null;
      function scheduleRefresh() {
        clearTimeout(timer);
        timer = setTimeout(function () {
          var latest = IS_TANOD
            ? sb.from('dispatches')
                .select('tanod_id,report:reports!dispatches_report_id_fkey(tracking_id)')
                .order('assigned_at', { ascending: false }).limit(1000)
                .then(function (r) {
                  if (r.error || !r.data) return;
                  var m = {};
                  r.data.forEach(function (d) {
                    if (!(d.tanod_id in m) && d.report) m[d.tanod_id] = d.report.tracking_id;
                  });
                  LATEST = m;
                })
            : Promise.resolve();
          var coms = IS_TANOD
            ? sb.rpc('personnel_committees').then(function (r) {
                if (r.error || !Array.isArray(r.data)) return;
                var m = {};
                r.data.forEach(function (x) { m[x.tanod_id] = { committees: x.committees || [], busy: x.busy_committee || null }; });
                TC = m;
              })
            : Promise.resolve();
          Promise.all([sb.rpc('account_directory', { p_role: ROLE }), latest, coms]).then(function (out) {
            var res = out[0];
            if (res.error || !res.data) return;
            renderAccounts(res.data);
          });
        }, 300);
      }

      // No push signal exists for this table (see comment above), so
      // "live" here means "polls quietly" rather than "pushed instantly."
      // Said plainly rather than dressed up as the same thing cases.php
      // and dashboard.php do.
      setInterval(scheduleRefresh, 20000);

      var badge = document.getElementById('live-badge'),
          text  = document.getElementById('live-badge-text');
      text.textContent = T('Live (updates every 20s)', 'Live (nag-a-update kada 20s)');
    })();
    </script>

    <?php
    layout_foot();
}

/**
 * Accounts that collide with another on mobile number or on a normalised
 * name. Returns [id => [reasons]]. Deliberately loose: a false flag costs
 * the admin ten seconds, a missed one costs the register its integrity.
 */
function duplicate_flags(array $accounts): array
{
    $byMobile = $byName = $out = [];

    foreach ($accounts as $a) {
        $m = preg_replace('/\D+/', '', (string) $a['mobile_number']);
        // Strip punctuation, order and case so "Dela Cruz, Ana" and
        // "ana dela cruz" collide.
        $parts = preg_split('/\s+/', mb_strtolower(preg_replace('/[^\p{L}\s]/u', ' ', (string) $a['full_name'])));
        sort($parts);
        $n = trim(implode(' ', array_filter($parts)));

        if ($m !== '') { $byMobile[$m][] = $a; }
        if ($n !== '') { $byName[$n][] = $a; }
    }

    foreach ($byMobile as $group) {
        if (count($group) < 2) continue;
        foreach ($group as $a) {
            $others = array_filter($group, fn($b) => $b['id'] !== $a['id']);
            $out[$a['id']][] = t('Same mobile number as ', 'Kaparehong mobile number ni ')
                . implode(', ', array_map(fn($b) => $b['full_name'], $others));
        }
    }
    foreach ($byName as $group) {
        if (count($group) < 2) continue;
        foreach ($group as $a) {
            $out[$a['id']][] = t('Same name as another account (' . count($group) . ' total)', 'Kaparehong pangalan ng ibang account (' . count($group) . ' lahat)');
        }
    }
    return $out;
}

/**
 * Human label for what the applicant's on-device OCR pass (0039) read the
 * ID photo as, or (since migration 0051) what the applicant themselves
 * selected at signup — id_type and ocr_detected_type share this same enum
 * and label set, so a true side-by-side compare is possible: see the
 * "Applicant selected" line in the OCR Triage card below.
 */
function id_document_type_label(?string $t): string
{
    return match ($t) {
        'barangay_id'          => 'Barangay ID',
        'drivers_license'      => "Driver's License",
        'passport'             => 'Passport',
        'philsys'              => 'PhilSys ID',
        'postal_id'            => 'Postal ID',
        'barangay_appointment' => 'Barangay Appointment',
        default                => t('Unrecognized document', 'Hindi makilalang dokumento'),
    };
}

/**
 * Human label for one of 0039's machine-generated ocr_flags entries.
 * Unknown flags (a future client build adding a new one) still render
 * readably rather than as a raw snake_case string or a blank pill.
 */
function ocr_flag_label(string $flag): string
{
    return match ($flag) {
        'type_mismatch' => t('ID type does not match', 'Hindi tugma ang uri ng ID'),
        'unreadable'    => t('ID could not be read', 'Hindi mabasa ang ID'),
        'name_mismatch' => t('Name does not match', 'Hindi tugma ang pangalan'),
        'no_id_number'  => t('No ID number found', 'Walang nakitang numero ng ID'),
        default         => ucfirst(str_replace('_', ' ', $flag)),
    };
}

/**
 * True only when OCR has actually run on this account's ID photo AND
 * came back with nothing to flag -- an account where OCR never ran
 * (registered before the feature existed, or a re-check is still
 * mid-flight) is deliberately NOT "clean": there is no positive evidence
 * either way, so it stays in ordinary manual review rather than skipping
 * it. This is what gates the Quick Verify shortcut (6 Sep 2026) -- an
 * admin still has to click it, but only ever sees it offered on an
 * account OCR has actually looked at and found nothing wrong with.
 */
function account_ocr_is_clean(array $a): bool
{
    if (empty($a['id_image_url']) || empty($a['ocr_processed_at'])) {
        return false;
    }
    if (!empty($a['ocr_flags'])) {
        return false;
    }
    $rescanPending = !empty($a['ocr_rescan_requested_at'])
        && (string) $a['ocr_processed_at'] < (string) $a['ocr_rescan_requested_at'];
    return !$rescanPending;
}

/**
 * True only for a resident who used self-service account deletion (0045)
 * on an account that had reports on file, not an ordinary admin
 * suspension. request_account_deletion() always writes this exact prefix
 * into suspended_reason, so it doubles as a reliable marker without a
 * dedicated boolean column — an admin-typed suspension reason could
 * theoretically coincide, but not with this specific, deliberately-worded
 * sentence.
 */
function is_self_deleted_account(array $a): bool
{
    return str_starts_with((string) ($a['suspended_reason'] ?? ''), 'Account deleted by the resident');
}

/**
 * The picture a resident or tanod chose for themselves in Edit Profile
 * (migration 0038's avatar_url) — falls back to a two-letter initials
 * badge when they never set one, rather than reusing the verification
 * selfie: that photo is identity evidence taken once at registration for
 * an admin to check against an ID, not the everyday picture someone
 * picked for their own account.
 */
function account_avatar_html(?string $url, string $name, string $size = 'sm'): string
{
    $cls = 'p-avatar p-av-' . $size;
    if (!empty($url)) {
        return '<img class="' . $cls . '" src="' . e(cld_thumb($url, 160, true)) . '" alt="" loading="lazy">';
    }
    return '<span class="' . $cls . '" aria-hidden="true">' . e(account_initials($name)) . '</span>';
}

function account_initials(string $name): string
{
    $parts = array_values(array_filter(preg_split('/\s+/', trim(display_name($name))) ?: []));
    if (!$parts) return '?';
    $first = mb_substr($parts[0], 0, 1);
    $last  = count($parts) > 1 ? mb_substr($parts[count($parts) - 1], 0, 1) : '';
    return mb_strtoupper($first . $last);
}

/**
 * The tanod page's two extra cards (preview, 2 Oct 2026): this month's
 * dispatches and today's shift. Reads dispatches and attendance only —
 * nothing new is stored. Any failure leaves the cards out.
 *
 * @return array{stats: array<string,mixed>, recent: array, shift: array<string,float>}|null
 */
function tanod_duty(Supabase $db, string $tanodId): ?array
{
    $tz    = new DateTimeZone('Asia/Manila');
    $now   = new DateTimeImmutable('now', $tz);
    $month = $now->modify('first day of this month')->setTime(0, 0);
    $today = $now->setTime(0, 0);
    try {
        $got = $db->selectMany([
            'disp' => ['dispatches', [
                'select'   => 'id,state,assigned_at,accepted_at,resolved_at,report:reports!dispatches_report_id_fkey(id,tracking_id)',
                'tanod_id' => 'eq.' . $tanodId,
                'order'    => 'assigned_at.desc',
                'limit'    => '200',
            ]],
            'att' => ['attendance', [
                'select'   => 'duty_status,logged_at',
                'tanod_id' => 'eq.' . $tanodId,
                'logged_at' => 'gte.' . $today->modify('-1 day')->format(DateTimeInterface::ATOM),
                'order'    => 'logged_at.asc',
            ]],
        ]);
    } catch (Throwable) {
        return null;
    }

    $monthStart = $month->getTimestamp();
    $mine = array_values(array_filter($got['disp'] ?? [], fn($d) => strtotime($d['assigned_at']) >= $monthStart));
    $accepted = array_values(array_filter($mine, fn($d) => !empty($d['accepted_at'])));
    $resolved = array_values(array_filter($mine, fn($d) => ($d['state'] ?? '') === 'resolved'));
    $mins = array_map(fn($d) => (strtotime($d['accepted_at']) - strtotime($d['assigned_at'])) / 60, $accepted);
    $avg  = $mins ? array_sum($mins) / count($mins) : null;

    // Today's shift: each log is a change of duty status; it lasts until
    // the next one (or now). The status carried in from before midnight
    // counts from midnight.
    $shift = array_fill_keys(array_keys(TANOD_DUTY_STATES), 0.0);
    $t0 = $today->getTimestamp(); $tEnd = $now->getTimestamp();
    $logs = $got['att'] ?? [];
    $cur = null; $from = $t0;
    foreach ($logs as $l) {
        $at = strtotime($l['logged_at']);
        if ($at <= $t0) { $cur = $l['duty_status']; continue; }
        if ($cur !== null && isset($shift[$cur])) $shift[$cur] += ($at - $from) / 3600;
        $cur = $l['duty_status']; $from = $at;
    }
    if ($cur !== null && isset($shift[$cur])) $shift[$cur] += ($tEnd - $from) / 3600;

    return [
        'stats'  => ['dispatched' => count($mine), 'accepted' => count($accepted), 'resolved' => count($resolved),
                     'avg_min' => $avg, 'month' => month_year($month)],
        'recent' => array_slice($got['disp'] ?? [], 0, 8),
        'shift'  => $shift,
    ];
}

/** Status, suspension and the two-hour clock, as pills. */
/** duty_state (0001), in the Figma summary's order. */
const TANOD_DUTY_STATES = [
    'on_duty' => 'On Duty',
    'lunch'   => 'Lunch',
    'break'   => 'Break',
    'offline' => 'Offline',
];

/**
 * Personnel's shift attendance summary: active tanods (verified, not
 * suspended, not retired) by duty status; no status yet counts as
 * offline. renderAttendance() in the list's script mirrors this.
 *
 * @return array<string,int>
 */
function tanod_attendance_counts(array $accounts): array
{
    $out = array_fill_keys(array_keys(TANOD_DUTY_STATES), 0);
    foreach ($accounts as $a) {
        if (($a['verification_status'] ?? '') !== 'verified'
            || !empty($a['is_suspended']) || !empty($a['is_retired'])) {
            continue;
        }
        $s = (string) ($a['duty_status'] ?? '');
        $out[isset($out[$s]) ? $s : 'offline']++;
    }
    return $out;
}

/** Verified, not suspended, not retired: the tanods the duty tiles count. */
function account_is_active(array $a): bool
{
    return ($a['verification_status'] ?? '') === 'verified' && empty($a['is_suspended']) && empty($a['is_retired']);
}

/** A tanod's duty state; none yet counts as offline. */
function account_duty(array $a): string
{
    $s = (string) ($a['duty_status'] ?? '');
    return isset(TANOD_DUTY_STATES[$s]) ? $s : 'offline';
}

/**
 * Personnel's Duty column: the state as one pill, and under it the committee of the case they are on (other committees see
 * the pill, never the case) or "On an incident". Someone who is not active has no duty. The list's script mirrors this.
 */
function tanod_duty_cell(array $a, ?array $tcRow): string
{
    if (!account_is_active($a)) return '<span class="p-sub">—</span>';
    $d = account_duty($a);
    $o = '<span class="pe-duty pe-d-' . e($d) . '"><i></i>' . e(status_label($d)) . '</span>';
    if (!empty($tcRow['busy'])) {
        $o .= '<span class="tc-busy"><small>' . e(t('On a case', 'May kaso')) . '</small>' . committee_pill((string) $tcRow['busy']) . '</span>';
    } elseif (!empty($a['holding_incident'])) {
        $o .= '<span class="tc-busy"><small>' . e(t('On an incident', 'May hawak na insidente')) . '</small></span>';
    }
    return '<div class="pe-dutybox">' . $o . '</div>';
}

/** Status, suspension and the two-hour clock as pills; $withDuty: the duty state and incident too (Residents never have one; Personnel has its own column). */
function account_status_pills(array $a, bool $withDuty = true): string
{
    $out = [];

    $out[] = match ($a['verification_status']) {
        'verified' => '<span class="p-badge p-b-done">' . e(t('Verified', 'Beripikado')) . '</span>',
        'rejected' => '<span class="p-badge p-b-denied">' . e(t('Rejected', 'Tinanggihan')) . '</span>',
        default    => '<span class="p-badge p-b-pending">' . e(t('Pending', 'Nakabinbin')) . '</span>',
    };

    if (!empty($a['is_suspended'])) {
        $out[] = is_self_deleted_account($a)
            ? '<span class="p-badge p-b-denied">' . e(t('Deleted by Resident', 'Binura ng Residente')) . '</span>'
            : '<span class="p-badge p-b-denied">' . e(t('Suspended', 'Suspendido')) . '</span>';
    }

    if ($a['verification_status'] === 'pending') {
        $mins = $a['minutes_left'];
        if (!empty($a['is_overdue'])) {
            $out[] = '<span class="p-badge p-b-denied">' . e(t('Overdue', 'Lampas-oras')) . '</span>';
        } elseif ($mins !== null) {
            $out[] = '<span class="p-badge p-b-progress">' . (int) $mins . e(t(' min left', ' minuto pa')) . '</span>';
        }
    }

    if ($withDuty && !empty($a['holding_incident'])) {
        $out[] = '<span class="p-badge p-b-progress">' . e(t('On an incident', 'May hawak na insidente')) . '</span>';
    }

    if ($withDuty && !empty($a['duty_status'])) {
        $out[] = '<span class="p-badge p-b-grey">' . e(status_label((string) $a['duty_status'])) . '</span>';
    }

    return implode(' ', $out);
}

function render_account_detail(
    array $p, string $noun, string $idLabel,
    string $self, string $navFile, string $title, ?array $flash, array $dupes = [],
    array $abuseHistory = [], string $role = 'resident', ?array $duty = null, ?array $tcRow = null
): void {
    $pending = $p['verification_status'] === 'pending';
    $nounLabel = $noun === 'Tanod' ? 'Tanod' : t('Resident', 'Residente');

    layout_head($title, $navFile);
    ?>

    <?php if ($flash): ?>
      <div class="p-flash p-flash--<?= e($flash['level']) ?>" role="status"><?= e($flash['text']) ?></div>
      <?php
        // Shown once and cleared. Kept out of the flash text itself so a
        // reload, a screenshot of the toast, or a shoulder at the desk
        // does not carry it any further than it has to go.
        $issuedPassword = $_SESSION['issued_password'] ?? null;
        unset($_SESSION['issued_password']);
      ?>
      <?php if ($issuedPassword !== null): ?>
        <div class="p-temp-pass" role="status" style="margin-bottom:16px">
          <span class="p-eyebrow" style="margin:0"><?= e(t('Temporary password', 'Pansamantalang password')) ?></span>
          <code><?= e($issuedPassword) ?></code>
          <small>
            <?= e(t('Shown once. It is not stored anywhere and cannot be looked up again — if it is lost, issue another.',
                    'Isang beses lang ipinapakita. Hindi ito naka-save kahit saan at hindi na makikita muli — kung mawala, magbigay ng bago.')) ?>
          </small>
        </div>
      <?php endif; ?>
    <?php endif; ?>

    <!-- Same reasoning as case.php: this page has a deny-reason textarea
         and password fields live on screen, so a background change is
         announced rather than silently swapped in. -->
    <div class="p-upd" id="update-banner" role="status">
      <span><?= e(t('This account has changed since you opened it.', 'May nagbago sa account na ito mula nang buksan mo.')) ?></span>
      <a class="p-btn p-btn-ghost p-btn-sm" href="<?= e($self) ?>?id=<?= e($p['id']) ?>"><?= e(t('Refresh to see it', 'I-refresh para makita')) ?></a>
    </div>

    <div class="ss-rqbar" id="ss-rqbar" hidden data-self="<?= e($self) ?>" data-id="<?= e($p['id']) ?>">
      <span><?= e(t('Review queue', 'Pila sa pagsusuri')) ?>: <b id="ss-rqbar-n">0</b> <?= e(t('more after this one', 'pa pagkatapos nito')) ?></span>
      <a class="ss-bulk-go" id="ss-rqbar-next" href="#"><?= e(t('Next in the queue', 'Susunod sa pila')) ?> &rarr;</a>
      <button type="button" class="ss-bulk-clear" id="ss-rqbar-drop"><?= e(t('Drop the queue', 'Alisin ang pila')) ?></button>
    </div>
    <script src="assets/js/people-list.js?v=2"></script>

    <div class="p-acc-top">
      <a class="p-back" href="<?= e($self) ?>" aria-label="<?= e(t('Back to the list', 'Bumalik sa listahan')) ?>"><?= p_icon('i-back', 18) ?><?= e($navFile === 'personnel.php' ? t('Personnel', 'Mga Tanod') : t('Residents', 'Mga Residente')) ?></a>
      <span class="p-acc-chip"><?= e(t($noun . ' Account', 'Account ng ' . $nounLabel)) ?></span>
      <span class="p-live" id="live-badge" title="<?= e(t('Watching this account for changes', 'Binabantayan ang mga pagbabago sa account na ito')) ?>"><i></i><span id="live-badge-text"><?= e(t('Live (checks every 20s)', 'Live (sinusuri kada 20s)')) ?></span></span>
    </div>

    <div class="p-profile-grid">
      <div class="p-grid">
        <div class="p-card p-card-pad">
        <div class="p-acc-head"><?= account_avatar_html($p['avatar_url'] ?? null, $p['full_name'], 'lg') ?><div><h2><?= e(formal_name($p['full_name'])) ?></h2><div class="p-acc-flags"><?= account_status_pills($p) ?></div></div></div>

        <?php if ($pending && !empty($p['due_at'])): ?>
          <p class="p-clock verif-clock<?= !empty($p['is_overdue']) ? ' p-late' : '' ?>"
             data-due="<?= e($p['due_at']) ?>">
            <span class="verif-text"><?= e(t('calculating…', 'kinakalkula…')) ?></span>
            <?= e(t('Submitted', 'Isinumite')) ?> <?= e(long_datetime($p['submitted_at'])) ?>.
          </p>
        <?php elseif ($pending && $p['minutes_left'] !== null): ?>
          <p class="p-clock<?= !empty($p['is_overdue']) ? ' p-late' : '' ?>">
            <?php if (!empty($p['is_overdue'])): ?>
              <?= e(t('Past the two-hour window by ', 'Lampas na sa dalawang oras na palugit nang ')) ?><?= abs((int) $p['minutes_left']) ?><?= e(t(' minutes.', ' minuto.')) ?>
            <?php else: ?>
              <?= (int) $p['minutes_left'] ?><?= e(t(' minutes left of the two-hour verification window.', ' minuto pa ang natitira sa dalawang oras na palugit ng beripikasyon.')) ?>
            <?php endif; ?>
            <?= e(t('Submitted', 'Isinumite')) ?> <?= e(long_datetime($p['submitted_at'])) ?>.
          </p>
        <?php endif; ?>

        <?php if (!empty($p['rejection_reason'])): ?>
          <p class="p-clock p-late"><?= e(t('Reason on file:', 'Nakatalang dahilan:')) ?> <?= e($p['rejection_reason']) ?></p>
        <?php endif; ?>

        </div>
        <div class="p-card p-card-pad">
          <p class="p-eyebrow"><?= e(t('Account Details', 'Detalye ng Account')) ?></p>
          <dl class="p-dl">
            <dt><?= e(t('Full name', 'Buong pangalan')) ?></dt><dd><?= e(formal_name($p['full_name'])) ?></dd>
            <dt><?= e(t('Email address', 'Email address')) ?></dt><dd><?= e($p['email']) ?></dd>
            <dt><?= e(t('Mobile number', 'Mobile number')) ?></dt><dd class="p-mono"><?= e($p['mobile_number']) ?></dd>
            <dt><?= e(t('Registered', 'Nagparehistro')) ?></dt><dd><?= e(long_datetime($p['created_at'])) ?></dd>
          </dl>
        </div>

        <?php if ($tcRow !== null) { render_tc_card($p, $tcRow); } ?>

        <?php if ($duty): $st = $duty['stats']; ?>
        <div class="p-card p-card-pad">
          <p class="p-eyebrow"><?= e(t('Duty', 'Tungkulin')) ?> &middot; <?= e($st['month']) ?></p>
          <div class="p-duty-grid">
            <div><small><?= e(t('Dispatched', 'Na-dispatch')) ?></small><b><?= (int) $st['dispatched'] ?></b></div>
            <div><small><?= e(t('Accepted', 'Tinanggap')) ?></small><b><?= (int) $st['accepted'] ?></b></div>
            <div><small><?= e(t('Resolved', 'Nalutas')) ?></small><b><?= (int) $st['resolved'] ?></b></div>
            <div><small><?= e(t('Avg. response', 'Karaniwang tugon')) ?></small><b><?= $st['avg_min'] === null ? '—' : ($st['avg_min'] < 60 ? (int) round($st['avg_min']) . ' min' : round($st['avg_min'] / 60, 1) . ' h') ?></b></div>
          </div>
          <?php $sh = $duty['shift']; $tot = array_sum($sh); ?>
          <small class="p-hint"><?= e(t("Today's shift", 'Shift ngayong araw')) ?></small>
          <?php if ($tot > 0): ?>
            <div class="p-shift">
              <?php foreach (['on_duty' => '#A6C442', 'lunch' => '#C49742', 'break' => '#FF9800', 'offline' => '#BDBDBD'] as $k => $c): ?>
                <?php if ($sh[$k] > 0): ?><i style="flex:<?= round($sh[$k] / $tot * 100, 2) ?>;background:<?= $c ?>"></i><?php endif; ?>
              <?php endforeach; ?>
            </div>
            <div class="p-shift-legend">
              <?php foreach (['on_duty' => '#A6C442', 'lunch' => '#C49742', 'break' => '#FF9800', 'offline' => '#BDBDBD'] as $k => $c): ?>
                <span style="--c:<?= $c ?>"><?= e(status_label($k)) ?> <?= $sh[$k] >= 1 ? round($sh[$k], 1) . ' h' : (int) round($sh[$k] * 60) . ' min' ?></span>
              <?php endforeach; ?>
            </div>
          <?php else: ?>
            <p class="p-none-line" style="margin-top:6px"><?= !empty($p['duty_status'])
                ? e(t('Now: ', 'Ngayon: ') . status_label((string) $p['duty_status']) . t('. No shift history is recorded yet.', '. Wala pang naitatalang kasaysayan ng shift.'))
                : e(t('No shift history is recorded yet.', 'Wala pang naitatalang kasaysayan ng shift.')) ?></p>
          <?php endif; ?>
        </div>

        <div class="p-card p-table-card">
          <div class="p-card-head" style="padding-bottom:14px"><h2><?= e(t('Recent dispatches', 'Mga huling dispatch')) ?></h2></div>
          <div class="p-tscroll"><table class="p-t">
            <thead><tr><th><?= e(t('Complaint', 'Sumbong')) ?></th><th><?= e(t('Assigned', 'Na-assign')) ?></th><th><?= e(t('Accepted', 'Tinanggap')) ?></th><th><?= e(t('Outcome', 'Kinalabasan')) ?></th></tr></thead>
            <tbody>
              <?php if (!$duty['recent']): ?>
                <tr><td colspan="4" class="p-empty"><?= e(t('No dispatches yet.', 'Wala pang dispatch.')) ?></td></tr>
              <?php endif; ?>
              <?php foreach ($duty['recent'] as $d): ?>
                <?php $state = (string) ($d['state'] ?? ''); ?>
                <tr<?= !empty($d['report']['id']) ? ' class="p-click" data-href="case.php?id=' . e($d['report']['id']) . '"' : '' ?>>
                  <td><span class="p-mono-id"><?= e($d['report']['tracking_id'] ?? '—') ?></span></td>
                  <td class="p-num"><?= e(long_datetime($d['assigned_at'])) ?></td>
                  <td class="p-num"><?= !empty($d['accepted_at']) ? e(long_datetime($d['accepted_at'])) : '<span class="p-over">' . e(t('Not accepted', 'Hindi tinanggap')) . '</span>' ?></td>
                  <td><span class="p-badge <?= match ($state) { 'resolved' => 'p-b-done', 'accepted' => 'p-b-progress', 'assigned' => 'p-b-pending', default => 'p-b-grey' } ?>"><?= e(status_label($state)) ?></span></td>
                </tr>
              <?php endforeach; ?>
            </tbody>
          </table></div>
        </div>
        <?php endif; ?>

        <div class="p-card p-card-pad">
          <p class="p-eyebrow"><?= e($idLabel) ?></p>
          <?php if (empty($p['id_image_url'])): ?>
            <p class="p-none-line"><?= e(t('No identification was uploaded. This account cannot be verified until one is.', 'Walang na-upload na ID. Hindi maveberipika ang account na ito hangga\'t walang ID.')) ?></p>
          <?php else: ?>
            <a class="p-id-shot" href="<?= e(cld_private_url((string) $p['id_image_url'])) ?>" target="_blank" rel="noopener">
              <img src="<?= e(cld_thumb($p['id_image_url'], 1000)) ?>" alt="<?= e(t('Identification submitted by ', 'ID na isinumite ni ') . $p['full_name']) ?>" loading="lazy">
            </a>
          <?php endif; ?>
        <?php
          $ocrRescanPending = !empty($p['ocr_rescan_requested_at'])
              && (empty($p['ocr_processed_at'])
                  || (string) $p['ocr_processed_at'] < (string) $p['ocr_rescan_requested_at']);
        ?>
        <?php if (!ID_OCR_ENABLED && !empty($p['id_type'])): ?>
          <p class="p-meta-line">
            <?= e(t('Applicant selected:', 'Pinili ng aplikante:')) ?> <?= e(id_document_type_label($p['id_type'])) ?>
          </p>
        <?php endif; ?>
        </div>

        <?php if (ID_OCR_ENABLED && !empty($p['id_image_url'])): ?>
        <!-- OCR triage (0039): the applicant's own device reads the ID
             photo and flags anything worth a second look before the admin
             opens it. Advisory only — never gates verification, just
             orders the queue and points at what to check first. The data
             has been flowing through account_directory() since 0039; this
             box is the first place any of it actually reaches a screen. -->
        <div class="p-card p-card-pad">
          <p class="p-eyebrow"><?= e(t('OCR Triage', 'Pagsusuri ng OCR')) ?></p>
          <?php if (!empty($p['id_type'])): ?>
            <p class="p-meta-line">
              <?= e(t('Applicant selected:', 'Pinili ng aplikante:')) ?> <?= e(id_document_type_label($p['id_type'])) ?>
            </p>
          <?php endif; ?>

          <?php if (empty($p['ocr_detected_type']) && empty($p['ocr_flags'])
                    && empty($p['ocr_extracted_name']) && empty($p['ocr_extracted_number'])): ?>
            <?php if (empty($p['ocr_processed_at'])): ?>
              <p class="p-none-line">
                <?= e(t('OCR has never run on this account — it registered before this feature existed, or on an older app build.',
                        'Hindi pa natakbo ang OCR sa account na ito — nagparehistro ito bago ang feature na ito, o sa lumang bersyon ng app.')) ?>
              </p>
            <?php else: ?>
              <p class="p-none-line"><?= e(t('OCR ran and found nothing to flag on this ID.', 'Natakbo ang OCR at walang nakitang dapat i-flag sa ID na ito.')) ?></p>
            <?php endif; ?>
          <?php else: ?>
            <?php if (!empty($p['ocr_flags'])): ?>
              <div class="p-acc-flags">
                <?php foreach ($p['ocr_flags'] as $flag): ?>
                  <span class="p-badge p-b-violet"><?= e(ocr_flag_label((string) $flag)) ?></span>
                <?php endforeach; ?>
              </div>
            <?php endif; ?>
            <dl class="p-dl">
              <?php if (!empty($p['ocr_detected_type'])): ?>
                <dt><?= e(t('OCR read this as', 'Binasa ito ng OCR bilang')) ?></dt><dd><?= e(id_document_type_label($p['ocr_detected_type'])) ?></dd>
              <?php endif; ?>
              <?php if (!empty($p['ocr_extracted_name'])): ?>
                <dt><?= e(t('Name on the ID', 'Pangalan sa ID')) ?></dt><dd><?= e($p['ocr_extracted_name']) ?></dd>
              <?php endif; ?>
              <?php if (!empty($p['ocr_extracted_number'])): ?>
                <dt><?= e(t('ID number', 'Numero ng ID')) ?></dt><dd class="p-mono"><?= e($p['ocr_extracted_number']) ?></dd>
              <?php endif; ?>
            </dl>
            <p class="p-none-line" style="margin-top:8px">
              <?= e(t("Advisory only, read off the photo by the applicant's own device — cross-check it against the ID photo above before deciding.",
                      'Payo lamang, binasa mula sa larawan ng sariling device ng aplikante — ihambing ito sa larawan ng ID sa itaas bago magpasya.')) ?>
            </p>
          <?php endif; ?>
          <?php if ($ocrRescanPending): ?>
            <p class="p-ctl-note" style="margin-top:8px">
              <?= e(t('Re-check requested', 'Humiling ng muling pagsuri')) ?> <?= e(relative_time($p['ocr_rescan_requested_at'])) ?> &mdash;
              <?= e(t('waiting for them to open the app.', 'hinihintay na buksan nila ang app.')) ?>
            </p>
          <?php endif; ?>
        </div>
        <?php endif; ?>

        <div class="p-card p-card-pad">
          <p class="p-eyebrow"><?= e(t('Uploaded Selfie', 'Na-upload na Selfie')) ?></p>
          <?php if (empty($p['selfie_url'])): ?>
            <p class="p-none-line">
              <?= e(t('Not submitted. Registration does not currently ask for one.', 'Hindi isinumite. Hindi ito kasalukuyang hinihingi sa rehistro.')) ?>
            </p>
          <?php else: ?>
            <a class="p-id-shot p-id-shot--square" href="<?= e(cld_private_url((string) $p['selfie_url'])) ?>" target="_blank" rel="noopener">
              <img src="<?= e(cld_thumb($p['selfie_url'], 600)) ?>" alt="<?= e(t('Selfie submitted by ', 'Selfie na isinumite ni ') . $p['full_name']) ?>" loading="lazy">
            </a>
          <?php endif; ?>
        </div>

        <?php if ($noun === 'Resident'): ?>
          <div class="p-card p-card-pad">
            <p class="p-eyebrow"><?= e(t('Abuse History', 'Kasaysayan ng Pang-aabuso')) ?></p>
            <?php if (!$abuseHistory): ?>
              <p class="p-none-line"><?= e(t('No complaints from this resident have been flagged as abusive or fabricated.', 'Walang sumbong ng residenteng ito na namarkahang mapang-abuso o gawa-gawa.')) ?></p>
            <?php else: ?>
              <p class="p-clock<?= count($abuseHistory) >= 3 ? ' p-late' : '' ?>" style="margin:0">
                <strong><?= count($abuseHistory) ?></strong> <?= e(t((count($abuseHistory) === 1 ? 'report' : 'reports') . ' flagged as abusive or fabricated',
                                                                  'ulat na namarkahang mapang-abuso o gawa-gawa')) ?><?php if (count($abuseHistory) >= 3): ?>
                  &mdash; <?= e(t('this account was automatically restricted after the third flag.', 'awtomatikong pinigilan ang account na ito pagkatapos ng ikatlong flag.')) ?>
                <?php elseif (count($abuseHistory) === 2): ?>
                  &mdash; <?= e(t('one more flag will automatically restrict this account.', 'isa pang flag at awtomatikong pipigilan ang account na ito.')) ?>
                <?php else: ?>.<?php endif; ?>
              </p>
              <dl class="p-dl">
                <?php foreach ($abuseHistory as $ab): ?>
                  <dt class="p-mono"><?= e($ab['tracking_id']) ?></dt>
                  <dd>
                    <?= e($ab['subject']) ?><br>
                    <span class="p-sub">
                      <?= e(t('Denied', 'Tinanggihan')) ?> <?= e(long_datetime($ab['flagged_at'])) ?><?php if (!empty($ab['remark'])): ?>
                        &mdash; <?= e($ab['remark']) ?>
                      <?php endif; ?>
                    </span>
                  </dd>
                <?php endforeach; ?>
              </dl>
            <?php endif; ?>
          </div>
        <?php endif; ?>
      </div>

      <aside class="p-card p-controls">
        <p class="p-eyebrow" style="margin:0"><?= e(t('Admin Controls', 'Kontrol ng Admin')) ?></p>
        <?php if (!is_super()): ?>
        <p class="p-ctl-note"><?= e(t('Only a super admin verifies, suspends or changes an account. You can see it, and its committees above.', 'Ang super admin lang ang nagbe-verify, nagsususpinde o nagbabago ng account. Nakikita mo ito, at ang mga komite nito sa itaas.')) ?></p>
        <?php else: ?>

        <form method="post" class="p-ctl-stack">
          <input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>">
          <input type="hidden" name="id" value="<?= e($p['id']) ?>">

          <?php if (ID_OCR_ENABLED && !empty($p['id_image_url'])): ?>
            <?php if ($ocrRescanPending): ?>
              <p class="p-ctl-note">
                <?= e(t('ID re-check requested', 'Humiling ng muling pagsuri ng ID')) ?> <?= e(relative_time($p['ocr_rescan_requested_at'])) ?>.
              </p>
            <?php else: ?>
              <button class="p-btn p-btn-ghost p-btn-block" type="submit" name="action" value="request_ocr_rescan">
                <?= e(t('Request ID Re-check', 'Humiling ng Muling Pagsuri ng ID')) ?>
              </button>
            <?php endif; ?>
          <?php endif; ?>

          <?php if ($pending): ?>
            <p class="p-ctl-note">
              <?= e(t('Check the name and address on the document against barangay records before approving.',
                      'Ihambing ang pangalan at address sa dokumento sa talaan ng barangay bago aprubahan.')) ?>
            </p>

            <button class="p-btn p-btn-success p-btn-block" type="submit" name="action" value="approve"
                    <?= empty($p['id_image_url']) ? 'disabled' : '' ?>>
              <?= p_icon('i-check', 18) ?>
              <?= e(t('Approve Registration', 'Aprubahan ang Rehistro')) ?>
            </button>

            <button class="p-btn p-btn-danger-soft p-btn-block" type="button" data-reveal="deny-panel" aria-expanded="false">
              <?= p_icon('i-x', 18) ?>
              <?= e(t('Deny Account', 'Tanggihan ang Account')) ?>
            </button>

            <div class="p-reveal" id="deny-panel" hidden>
              <label class="p-flabel" for="deny-reason"><?= e(t('Reason — the applicant sees this', 'Dahilan — makikita ito ng aplikante')) ?></label>
              <textarea class="p-note" id="deny-reason" name="reason" rows="3" maxlength="200"
                        placeholder="<?= e(t('e.g. The ID photo is unreadable. Please re-upload a clearer image.', 'hal. Hindi mabasa ang larawan ng ID. Mag-upload muli ng mas malinaw.')) ?>"></textarea>
              <button class="p-btn p-btn-danger-solid p-btn-sm" type="submit" name="action" value="deny"><?= e(t('Confirm denial', 'Kumpirmahin ang pagtanggi')) ?></button>
            </div>

          <?php elseif (!empty($p['is_suspended'])): ?>
            <?php $selfDeleted = is_self_deleted_account($p); ?>
            <p class="p-ctl-note">
              <?= $selfDeleted
                  ? e(t('This resident deleted their own account. Their filed reports remain on record — the name, email, and phone number you see here have been intentionally scrubbed, not just hidden.',
                        'Binura ng residenteng ito ang sarili niyang account. Nananatili sa talaan ang kanyang mga isinampang ulat — sinadyang burahin ang pangalan, email, at numerong nakikita mo rito, hindi lang itinago.'))
                  : e(t('This account is suspended and cannot sign in.', 'Suspendido ang account na ito at hindi makakapag-sign in.')) ?>
              <?php if (!empty($p['suspended_reason'])): ?>
                <?= e(t('Reason on file:', 'Nakatalang dahilan:')) ?> <?= e($p['suspended_reason']) ?>
              <?php endif; ?>
            </p>
            <?php if ($selfDeleted): ?>
              <p class="p-none-line">
                <?= e(t('Reinstating would not restore their original name, email, or phone number — those are gone, not just concealed. There is nothing meaningful to reinstate this account to.',
                        'Hindi maibabalik ng pag-reinstate ang orihinal na pangalan, email, o numero — wala na ang mga iyon, hindi lang itinago. Walang makabuluhang maibabalik sa account na ito.')) ?>
              </p>
            <?php else: ?>
              <button class="p-btn p-btn-success p-btn-block" type="submit" name="action" value="reinstate"
                      data-confirm="<?= e(t('Reinstate ' . display_name($p['full_name']) . '?', 'Ibalik si ' . display_name($p['full_name']) . '?') . '|' . t('They will be able to sign in again.', 'Makakapag-sign in na silang muli.') . '|' . t('Reinstate', 'Ibalik') . '|blue') ?>"><?= e(t('Reinstate Account', 'Ibalik ang Account')) ?></button>
            <?php endif; ?>

          <?php elseif ($p['verification_status'] === 'verified'): ?>
            <p class="p-ctl-note">
              <?= e(t('Verified', 'Beripikado')) ?><?= !empty($p['holding_incident'])
                  ? e(t('. This tanod is holding a live incident — suspending them sends it back to the queue.', '. May hawak na insidente ang tanod na ito — kapag sinuspinde, babalik ito sa pila.'))
                  : '.' ?>
            </p>

            <button class="p-btn p-btn-danger-soft p-btn-block" type="button" data-reveal="suspend-panel" aria-expanded="false">
              <?= e(t('Suspend Account', 'Suspindihin ang Account')) ?>
            </button>

            <div class="p-reveal" id="suspend-panel" hidden>
              <label class="p-flabel" for="suspend-reason"><?= e(t('Reason for suspension', 'Dahilan ng suspensyon')) ?></label>
              <textarea class="p-note" id="suspend-reason" name="reason" rows="3" maxlength="200"
                        placeholder="<?= e(t('e.g. Repeatedly filed fraudulent complaints.', 'hal. Paulit-ulit na nagsampa ng mapanlinlang na sumbong.')) ?>"></textarea>
              <button class="p-btn p-btn-danger-solid p-btn-sm" type="submit" name="action" value="suspend"><?= e(t('Confirm suspension', 'Kumpirmahin ang suspensyon')) ?></button>
            </div>

            <!--
              Password reset. There is no self-service route: the sign-in
              address is derived from the phone number and its domain
              receives no mail, so the barangay is the only way back in
              for someone who has forgotten their password.

              Check their ID first, the same way it was checked when the
              account was approved. That inspection is the whole security
              of this control.
            -->
            <button class="p-btn p-btn-ghost p-btn-block" type="button" data-reveal="reset-panel"
                    aria-expanded="false">
              <?= e(t('Reset Password', 'I-reset ang Password')) ?>
            </button>

            <div class="p-reveal" id="reset-panel" hidden>
              <p class="p-ctl-note">
                <?= e(t('Only do this with the person in front of you and their ID in hand. They will be shown a temporary password once — read it to them, do not send it. They must change it when they next sign in.',
                        'Gawin lamang ito kung kaharap mo ang tao at hawak mo ang kanilang ID. Isang beses lang ipapakita ang pansamantalang password — basahin ito sa kanila, huwag ipadala. Kailangan nila itong palitan sa susunod na pag-sign in.')) ?>
              </p>
              <label class="p-flabel" for="reset-password"><?= e(t('Your password — confirms it is you at the keyboard', 'Ang iyong password — patunay na ikaw ang gumagamit')) ?></label>
              <input class="p-input-plain" id="reset-password" type="password" name="password"
                     autocomplete="new-password">
              <button class="p-btn p-btn-danger-solid p-btn-sm" type="submit" name="action"
                      value="reset_password"><?= e(t('Issue temporary password', 'Magbigay ng pansamantalang password')) ?></button>
            </div>

          <?php else: ?>
            <p class="p-ctl-note">
              <?= e(t('This registration was denied. The applicant must register again.', 'Tinanggihan ang rehistrong ito. Kailangang magparehistro muli ng aplikante.')) ?>
            </p>
          <?php endif; ?>
        </form>

        <?php // 0073 — Manage User Account 3.2: fix a typo'd name or email. ?>
        <details class="p-fix">
          <summary><?= e(t('Correct profile details', 'Itama ang detalye ng profile')) ?></summary>
          <form method="post" class="p-ctl-stack p-reveal">
            <input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>">
            <input type="hidden" name="id" value="<?= e($p['id']) ?>">
            <input type="hidden" name="action" value="correct_profile">
            <div class="p-cfield">
              <label class="p-flabel" for="fix-name"><?= e(t('Full name', 'Buong pangalan')) ?></label>
              <input class="p-input-plain" type="text" id="fix-name" name="full_name" maxlength="120" required value="<?= e($p['full_name']) ?>">
            </div>
            <div class="p-cfield">
              <label class="p-flabel" for="fix-email"><?= e(t('Email address', 'Email address')) ?></label>
              <input class="p-input-plain" type="email" id="fix-email" name="email" maxlength="160" value="<?= e($p['email'] ?? '') ?>" autocomplete="off">
            </div>
            <p class="p-ctl-note"><?= e(t('The mobile number is their sign-in and cannot be changed here.', 'Ang mobile number ang kanilang pang-sign in at hindi mababago rito.')) ?></p>
            <button class="p-btn p-btn-primary p-btn-sm" type="submit"><?= e(t('Save corrections', 'I-save ang pagtatama')) ?></button>
          </form>
        </details>
        <?php endif; ?>
      </aside>
    </div>

    <script>
    // The two-hour window is the point of this screen, so it ticks rather
    // than reporting what was true when the page happened to load.
    (function () {
      var el = document.querySelector('.verif-clock');
      if (!el) return;
      var due = new Date(el.dataset.due), out = el.querySelector('.verif-text');
      (function tick() {
        var ms = due - new Date(), late = ms < 0, a = Math.abs(ms);
        var h = Math.floor(a / 3600000), m = Math.floor(a % 3600000 / 60000);
        var span = (h ? h + 'h ' : '') + m + 'm';
        out.textContent = late
          ? T('Past the two-hour verification window by ', 'Lampas na sa dalawang oras na palugit nang ') + span + '.'
          : span + T(' left of the two-hour verification window.', ' pa ang natitira sa dalawang oras na palugit.');
        el.classList.toggle('p-late', late);
        setTimeout(tick, 20000);
      })();
    })();

    document.querySelectorAll('[data-reveal]').forEach(function (btn) {
      btn.addEventListener('click', function () {
        var panel = document.getElementById(btn.getAttribute('data-reveal'));
        var open  = panel.hasAttribute('hidden');
        if (open) { panel.removeAttribute('hidden'); } else { panel.setAttribute('hidden', ''); }
        btn.setAttribute('aria-expanded', String(open));
        if (open) {
          var field = panel.querySelector('textarea, input');
          if (field) { field.focus(); }
        }
      });
    });

    // Enter in the reset panel's password field would otherwise submit
    // this whole form through its first submit button — Request ID
    // Re-check or Suspend, not Issue temporary password.
    (function () {
      var pw = document.getElementById('reset-password');
      if (!pw) return;
      pw.addEventListener('keydown', function (ev) {
        if (ev.key !== 'Enter') return;
        ev.preventDefault();
        var btn = pw.form.querySelector('button[value="reset_password"]');
        if (pw.form.requestSubmit) { pw.form.requestSubmit(btn); } else { btn.click(); }
      });
    })();
    </script>

    <script src="assets/vendor/supabase/supabase.js?v=2.117.3"></script>
    <script>
    // Same polling idiom as the list view above, and the same reason:
    // public.users carries no realtime push (0046's privacy decision).
    // This page has a deny/suspend textarea and password fields on
    // screen, so a detected change raises the banner above rather than
    // rewriting the account details out from under whatever the admin
    // is mid-typing.
    (function () {
      if (!window.supabase) { return; }
      const { createClient } = supabase;

      const TOKEN = <?= json_encode(access_token()) ?>;
      const ROLE  = <?= json_encode($role) ?>;
      const ACCOUNT_ID = <?= json_encode($p['id']) ?>;
      const sb = createClient(
        <?= json_encode(supabase_url()) ?>,
        <?= json_encode(supabase_key()) ?>,
        { accessToken: window.ssAccessToken(TOKEN) }
      );

      // Excludes minutes_left/is_overdue on purpose — those already tick
      // on their own via the countdown script above and would otherwise
      // raise the banner every 20 seconds for no real change.
      function fingerprint(a) {
        return JSON.stringify([
          a.verification_status, !!a.is_suspended, a.rejection_reason || '',
          !!a.holding_incident, a.duty_status || '',
          a.ocr_detected_type || '', (a.ocr_flags || []).slice().sort(),
          a.ocr_extracted_name || '', a.ocr_extracted_number || '',
          a.ocr_processed_at || '', a.ocr_rescan_requested_at || '',
          a.suspended_reason || '', a.id_type || ''
        ]);
      }
      // Must serialise byte-for-byte like fingerprint() above: flags
      // sorted the same way, and no \/ or \uXXXX escaping, which
      // JSON.stringify never produces. Otherwise any reason containing a
      // slash or an accented letter, or two OCR flags out of order, raised
      // the "has changed" banner 20 seconds after every page load.
      <?php $fpFlags = array_values($p['ocr_flags'] ?? []); sort($fpFlags, SORT_STRING); ?>
      const INITIAL_FINGERPRINT = <?= json_encode(json_encode([
          $p['verification_status'] ?? null, (bool) ($p['is_suspended'] ?? false),
          $p['rejection_reason'] ?? '', (bool) ($p['holding_incident'] ?? false),
          $p['duty_status'] ?? '', $p['ocr_detected_type'] ?? '',
          $fpFlags, $p['ocr_extracted_name'] ?? '',
          $p['ocr_extracted_number'] ?? '',
          $p['ocr_processed_at'] ?? '', $p['ocr_rescan_requested_at'] ?? '',
          $p['suspended_reason'] ?? '', $p['id_type'] ?? '',
      ], JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE)) ?>;

      function poll() {
        sb.rpc('account_directory', { p_role: ROLE }).then(function (res) {
          if (res.error || !res.data) return;
          var found = res.data.find(function (a) { return a.id === ACCOUNT_ID; });
          if (!found) { return; } // account left this role's queue entirely (rare) — nothing safe to compare
          if (fingerprint(found) !== INITIAL_FINGERPRINT) {
            document.getElementById('update-banner').classList.add('p-on');
          }
        });
      }
      setInterval(poll, 20000);
    })();
    </script>

    <?php
    layout_foot();
}
