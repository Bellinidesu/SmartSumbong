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
 * OCR ID triage (0039/0050) is off for now (Rose, 27–30 Sep 2026): no
 * flags, no "read as", no re-check, no Quick Verify. The code stays for a
 * future update; true brings it all back. The app has the same switch
 * (kIdOcrEnabled in mobile/core/lib/src/id_ocr.dart).
 */
const ID_OCR_ENABLED = false;

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

    // ---------- actions ----------
    if ($_SERVER['REQUEST_METHOD'] === 'POST') {
        $target = (string) ($_POST['id'] ?? '');
        $flash  = null;
        $level  = 'ok';

        if (!csrf_check($_POST['csrf'] ?? null)) {
            $flash = t('That form expired. Please try again.', 'Nag-expire ang form. Subukan muli.');
            $level = 'error';
        } else {
            try {
                $action = (string) ($_POST['action'] ?? '');
                if (!ID_OCR_ENABLED && $action === 'request_ocr_rescan') {
                    $action = '';   // falls through to "Unknown action."
                }
                switch ($action) {
                    // 0086 (Martin): a name change or a new ID photo.
                    case 'profile_request':
                        $approve = ($_POST['decision'] ?? '') === 'approve';
                        $db->rpc('decide_profile_request', [
                            'p_request' => (string) ($_POST['request'] ?? ''),
                            'p_approve' => $approve,
                            'p_note'    => trim((string) ($_POST['note'] ?? '')) ?: null,
                        ]);
                        $flash = $approve
                            ? t('Approved. They have been told.', 'Naaprubahan. Nasabihan na sila.')
                            : t('Declined. They have been told why.', 'Tinanggihan. Nasabihan na sila kung bakit.');
                        break;

                    case 'approve':
                        $db->rpc('verify_user_account', [
                            'p_user' => $target, 'p_decision' => 'approve',
                        ]);
                        $flash = t('Account verified. They can file a complaint now.', 'Beripikado na ang account. Makakapagsampa na sila ng sumbong.');
                        break;

                    case 'deny':
                        $db->rpc('verify_user_account', [
                            'p_user'     => $target,
                            'p_decision' => 'deny',
                            'p_reason'   => trim((string) ($_POST['reason'] ?? '')),
                        ]);
                        $flash = t('Registration denied. The applicant has been told why.', 'Tinanggihan ang rehistro. Nasabihan na ang aplikante kung bakit.');
                        break;

                    case 'suspend':
                        $db->rpc('set_account_suspension', [
                            'p_user'    => $target,
                            'p_suspend' => true,
                            'p_reason'  => trim((string) ($_POST['reason'] ?? '')),
                        ]);
                        $flash = t('Account suspended. Any incident they were holding went back to the queue.', 'Na-suspend ang account. Ibinalik sa pila ang anumang insidenteng hawak nila.');
                        break;

                    case 'reinstate':
                        $db->rpc('set_account_suspension', [
                            'p_user' => $target, 'p_suspend' => false,
                        ]);
                        $flash = t('Account reinstated.', 'Naibalik ang account.');
                        break;

                    case 'request_ocr_rescan':
                        // 0050. OCR runs on-device only, once, at
                        // registration — this just flags the account so
                        // the resident's own app re-runs it against the
                        // already-uploaded photo next time it's open.
                        $db->rpc('request_ocr_rescan', [
                            'p_user' => $target,
                        ]);
                        $flash = t('Re-check requested. It will run automatically next time they open the app.', 'Humiling ng muling pagsuri. Awtomatiko itong tatakbo sa susunod nilang pagbukas ng app.');
                        break;

                    // 0073 — Manage User Account (3.2): correct a
                    // resident's or tanod's name and email.
                    case 'correct_profile':
                        $db->rpc('admin_update_user', [
                            'p_user'      => $target,
                            'p_full_name' => trim((string) ($_POST['full_name'] ?? '')),
                            'p_email'     => trim((string) ($_POST['email'] ?? '')) ?: null,
                        ]);
                        $flash = t('Profile corrected. The account holder has been told.', 'Naitama ang profile. Nasabihan na ang may-ari ng account.');
                        break;

                    case 'reset_password':
                        // Re-authenticated for the same reason promote
                        // and step_down are: this hands working
                        // credentials for someone else's account to
                        // whoever is at the keyboard, and the database
                        // only knows that an admin is calling.
                        Supabase::signIn($admin['email'], (string) ($_POST['password'] ?? ''));
                        $issued = $db->rpc('admin_reset_password', [
                            'p_user' => $target,
                        ]);
                        // The RPC returns the password once and never
                        // stores it. If it is lost between here and the
                        // counter, the only remedy is another reset.
                        $_SESSION['issued_password'] = is_array($issued)
                            ? (string) reset($issued)
                            : (string) $issued;
                        $flash = t('Temporary password issued. Read it to them in person and do not send it by message.',
                                   'Naibigay ang pansamantalang password. Basahin ito sa kanila nang personal at huwag ipadala sa mensahe.');
                        break;

                    default:
                        $flash = t('Unknown action.', 'Hindi kilalang aksyon.');
                        $level = 'error';
                }
            } catch (SupabaseError $ex) {
                // Same fix as login.php: GoTrue's own wrong-password error
                // says "Invalid login credentials", but admin_reset_password()
                // has its own, unrelated exception for an account with no
                // auth.users row at all -- "has no credential to reset" --
                // and the old broad `str_contains(..., 'credential')` check
                // caught that one too, so a reset against a seeded test
                // account (no real login) always came back "That password
                // is not right," even typed correctly. Narrowed to the
                // actual GoTrue phrase so the real reason surfaces instead.
                $msg   = safe_error($ex);
                $flash = str_contains(strtolower($msg), 'invalid login')
                    ? t('That password is not right. Nothing was changed.', 'Mali ang password na iyan. Walang binago.')
                    : $msg;
                $level = 'error';
            }
        }

        $_SESSION['flash'] = ['text' => $flash, 'level' => $level];
        header('Location: ' . $self . ($target !== '' ? '?id=' . urlencode($target) : ''));
        exit;
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
    }
    $got = [];
    try {
        $got = $db->selectMany($batch);
        $accounts = (array) $got['accounts'];
    } catch (SupabaseError $ex) {
        $error = safe_error($ex);
    }

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
                              $dupes[$person['id']] ?? [], $abuseHistory, $role, $duty);
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
    }

    $pending = count(array_filter($accounts, fn($a) => $a['verification_status'] === 'pending'));
    $overdue = count(array_filter($accounts, fn($a) => !empty($a['is_overdue'])));
    $attendance = $isTanod ? tanod_attendance_counts($allAccounts) : [];

    layout_head($title, $navFile);
    ?>

    <div class="p-topbar"><h1><?= e($title) ?></h1>
      <span class="p-live" id="live-badge" title="<?= e(t('New registrations appear here on their own', 'Kusang lumalabas dito ang mga bagong rehistro')) ?>"><i></i><span id="live-badge-text"><?= e(t('Live', 'Live')) ?></span></span></div>

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
              <a href="<?= e($r['id_image_url']) ?>" target="_blank" rel="noopener"><img src="<?= e(cld_thumb($r['id_image_url'], 480)) ?>" alt="<?= e(t('New ID photo', 'Bagong litrato ng ID')) ?>" class="ss-req-img"></a>
            <?php else: ?>
              <span class="p-chip"><?= e(t('Name', 'Pangalan')) ?></span>
            <?php endif; ?>
            <div style="min-width:0">
              <b><?= e(display_name($r['who']['full_name'] ?? '')) ?></b>
              <span class="p-hint"> · <?= e((string) ($r['who']['mobile_number'] ?? '')) ?> · <?= e(long_datetime($r['created_at'])) ?></span>
              <p style="margin:4px 0 0"><?= $r['kind'] === 'full_name'
                  ? e(t('Change name to', 'Palitan ang pangalan sa')) . ' <b>' . e(display_name($r['new_full_name'])) . '</b>'
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

    <?php if ($isTanod): ?>
      <!-- Today's shift: every active tanod (verified, not suspended or retired), whatever the search. -->
      <div class="p-kpis p-attendance" id="attendance-grid" aria-label="<?= e(t("Today's shift attendance summary", 'Buod ng pagdalo sa shift ngayong araw')) ?>" style="margin-bottom:20px">
        <?php foreach (TANOD_DUTY_STATES as $state => $label): ?>
          <div class="p-card p-kpi p-att-<?= e($state) ?>"><div class="p-label"><span class="p-att-dot" aria-hidden="true"></span><?= e(status_label($state)) ?></div>
            <div class="p-value p-num" data-state="<?= e($state) ?>"><?= (int) ($attendance[$state] ?? 0) ?></div>
            <div class="p-delta"><?= e(t('Today’s shift', 'Shift ngayong araw')) ?></div></div>
        <?php endforeach; ?>
      </div>
    <?php endif; ?>

    <div class="p-band">
      <h2><?= e(t($noun . ' accounts', 'Mga account ng ' . $nounLabel)) ?><span class="p-badge-n p-badge-n--quiet" id="accounts-count"><?= count($accounts) ?></span><span class="p-badge-n" id="pending-wrap"<?= $pending > 0 ? '' : ' hidden' ?>><span id="pending-count"><?= $pending ?></span> <?= e(t('to review', 'susuriin')) ?></span></h2>
      <form class="p-search" method="get" role="search">
        <?= p_icon('i-search', 16) ?><label class="p-sr" for="acc-q"><?= e(t('Search', 'Maghanap')) ?></label>
        <input id="acc-q" type="search" name="q" placeholder="<?= e(t('Search name, phone or email', 'Hanapin ang pangalan, telepono o email')) ?>" value="<?= e($search) ?>">
        <?php if ($statusFilter !== ''): ?><input type="hidden" name="sort" value="<?= e($statusFilter) ?>"><?php endif; ?>
      </form>
      <span class="p-spacer"></span>
      <form method="get">
        <input type="hidden" name="q" value="<?= e($search) ?>">
        <label class="p-pill-select"><span class="p-lbl"><?= e(t('Status', 'Katayuan')) ?></span>
          <select name="sort" onchange="this.form.submit()">
            <option value=""><?= e(t('All', 'Lahat')) ?></option>
            <option value="pending" <?= $statusFilter === 'pending' ? 'selected' : '' ?>><?= e(t('Pending', 'Nakabinbin')) ?></option>
            <option value="verified" <?= $statusFilter === 'verified' ? 'selected' : '' ?>><?= e(t('Verified', 'Beripikado')) ?></option>
          </select></label>
      </form>
    </div>

    <div class="p-card p-table-card"><div class="p-tscroll">
      <table class="p-t">
        <thead><tr>
          <th scope="col"><?= e(t($noun, $nounLabel)) ?></th>
          <th scope="col"><?= e(t('Phone number', 'Numero ng telepono')) ?></th>
          <?php if ($isTanod): ?><th scope="col"><?= e(t('Latest complaint handled', 'Huling hinawakang sumbong')) ?></th><?php endif; ?>
          <th scope="col"><?= e(t('Email', 'Email')) ?></th>
          <th scope="col"><?= e(t('Status', 'Katayuan')) ?></th>
          <th scope="col" class="p-right"><span class="p-sr"><?= e(t('Action', 'Aksyon')) ?></span></th>
        </tr></thead>
        <tbody id="accounts-tbody">
          <?php if (!$accounts): ?>
            <tr><td colspan="<?= $isTanod ? 6 : 5 ?>" class="p-empty"><?= $search !== ''
                ? e(t('No account matches that search.', 'Walang account na tugma sa hinanap.'))
                : e(t('No ' . strtolower($noun) . ' accounts have registered yet.', 'Wala pang nagparehistrong ' . strtolower($nounLabel) . '.')) ?></td></tr>
          <?php endif; ?>
          <?php foreach ($accounts as $a): ?>
            <tr>
              <td><div class="p-person"><?= account_avatar_html($a['avatar_url'] ?? null, $a['full_name'], 'sm') ?><span><?= e(display_name($a['full_name'])) ?></span></div></td>
              <td class="p-num"><?= e($a['mobile_number']) ?></td>
              <?php if ($isTanod): ?>
                <td><?= !empty($latestCase[$a['id']]) ? '<span class="p-mono-id">' . e($latestCase[$a['id']]) . '</span>' : '<span class="p-sub">' . e(t('None', 'Wala')) . '</span>' ?></td>
              <?php endif; ?>
              <td><?= $a['email'] ? e($a['email']) : '<span class="p-sub">—</span>' ?></td>
              <td><div class="p-badges"><?= account_status_pills($a) ?><?php
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

    <script src="assets/vendor/supabase/supabase.js"></script>
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
        if (a.holding_incident) out.push('<span class="p-badge p-b-progress">' + T('On an incident', 'May hawak na insidente') + '</span>');
        if (a.duty_status) out.push('<span class="p-badge p-b-grey">' + escapeHtml(STATUS_LABEL[a.duty_status] || titleCase(a.duty_status)) + '</span>');
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

      function renderAccounts(accounts) {
        var filtered = accounts;
        if (SEARCH) {
          var needle = SEARCH.toLowerCase();
          filtered = filtered.filter(function (a) {
            return ((a.full_name || '') + ' ' + (a.email || '') + ' ' + (a.mobile_number || ''))
              .toLowerCase().indexOf(needle) !== -1;
          });
        }
        if (STATUS_FILTER === 'pending' || STATUS_FILTER === 'verified') {
          filtered = filtered.filter(function (a) { return a.verification_status === STATUS_FILTER; });
        }
        var dupes = duplicateFlags(accounts);

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

        var tbody = document.getElementById('accounts-tbody');
        if (!filtered.length) {
          tbody.innerHTML = '<tr><td class="p-empty" colspan="' + (IS_TANOD ? 6 : 5) + '">' +
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
          return '<tr>' +
            '<td><div class="p-person">' + avatarHtml(a.avatar_url, a.full_name, 'sm') + '<span>' + escapeHtml(window.ssName(a.full_name)) + '</span></div></td>' +
            '<td class="p-num">' + escapeHtml(a.mobile_number) + '</td>' +
            (IS_TANOD ? '<td>' + (LATEST[a.id] ? '<span class="p-mono-id">' + escapeHtml(LATEST[a.id]) + '</span>'
                                               : '<span class="p-sub">' + T('None', 'Wala') + '</span>') + '</td>' : '') +
            '<td>' + (a.email ? escapeHtml(a.email) : '<span class="p-sub">—</span>') + '</td>' +
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
          Promise.all([sb.rpc('account_directory', { p_role: ROLE }), latest]).then(function (out) {
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

function account_status_pills(array $a): string
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

    if (!empty($a['holding_incident'])) {
        $out[] = '<span class="p-badge p-b-progress">' . e(t('On an incident', 'May hawak na insidente')) . '</span>';
    }

    if (!empty($a['duty_status'])) {
        $out[] = '<span class="p-badge p-b-grey">' . e(status_label((string) $a['duty_status'])) . '</span>';
    }

    return implode(' ', $out);
}

function render_account_detail(
    array $p, string $noun, string $idLabel,
    string $self, string $navFile, string $title, ?array $flash, array $dupes = [],
    array $abuseHistory = [], string $role = 'resident', ?array $duty = null
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

    <div class="p-acc-top">
      <a class="p-back" href="<?= e($self) ?>" aria-label="<?= e(t('Back to the list', 'Bumalik sa listahan')) ?>"><?= p_icon('i-back', 18) ?><?= e($navFile === 'personnel.php' ? t('Personnel', 'Mga Tanod') : t('Residents', 'Mga Residente')) ?></a>
      <span class="p-acc-chip"><?= e(t($noun . ' Account', 'Account ng ' . $nounLabel)) ?></span>
      <span class="p-live" id="live-badge" title="<?= e(t('Watching this account for changes', 'Binabantayan ang mga pagbabago sa account na ito')) ?>"><i></i><span id="live-badge-text"><?= e(t('Live (checks every 20s)', 'Live (sinusuri kada 20s)')) ?></span></span>
    </div>

    <div class="p-profile-grid">
      <div class="p-grid">
        <div class="p-card p-card-pad">
        <div class="p-acc-head"><?= account_avatar_html($p['avatar_url'] ?? null, $p['full_name'], 'lg') ?><div><h2><?= e(display_name($p['full_name'])) ?></h2><div class="p-acc-flags"><?= account_status_pills($p) ?></div></div></div>

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
            <dt><?= e(t('Full name', 'Buong pangalan')) ?></dt><dd><?= e(display_name($p['full_name'])) ?></dd>
            <dt><?= e(t('Email address', 'Email address')) ?></dt><dd><?= e($p['email']) ?></dd>
            <dt><?= e(t('Mobile number', 'Mobile number')) ?></dt><dd class="p-mono"><?= e($p['mobile_number']) ?></dd>
            <dt><?= e(t('Registered', 'Nagparehistro')) ?></dt><dd><?= e(long_datetime($p['created_at'])) ?></dd>
          </dl>
        </div>

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
            <a class="p-id-shot" href="<?= e($p['id_image_url']) ?>" target="_blank" rel="noopener">
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
            <a class="p-id-shot p-id-shot--square" href="<?= e($p['selfie_url']) ?>" target="_blank" rel="noopener">
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

    <script src="assets/vendor/supabase/supabase.js"></script>
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
