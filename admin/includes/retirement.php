<?php
/**
 * Extra Administrative Services — formerly "Retirement Requests" (renamed
 * 15 Sep 2026 to match the tanod app's own password-gated "Extra
 * Administrative Services" screen, and to give Transfer Administration a
 * permanent home now that it has moved off Residents/Personnel).
 *
 * Two unrelated pieces of business share this page because both are rare,
 * high-consequence account actions an admin reaches for only occasionally
 * — not day-to-day account management, which is what Residents/Personnel
 * is for:
 *
 *   - Grant Administrator Access: promote a verified account (optionally
 *     with a bounded handover/training window, 0055) or step down.
 *     Filename kept as retirement-requests.php throughout — only the
 *     visible title and nav label changed — so no link anywhere breaks.
 *
 *   - Retirement Requests: the existing tanod-retirement queue, unchanged
 *     from its original design (finalize_retirement(), migration 0052).
 *
 * The barangay's own instruction was explicit that a tanod's retirement
 * needs an admin to "finalize" it, and the four design decisions made
 * for that feature settled the portal side of it: retirement gets its
 * own review queue and its own audit trail, separate from Personnel's
 * suspend/reinstate history, because approving someone's end of service
 * is not the same action as suspending them mid-service.
 *
 * finalize_retirement() (migration 0052) does the actual work — row
 * lock, decision validation, a reason required on denial, the tanod
 * notified, and (on approval) any live dispatch released back to the
 * queue exactly the way set_account_suspension() already does. Likewise
 * promote_to_admin()/step_down_as_admin()/cancel_admin_handover() (0014,
 * extended 0055) do the actual work for the succession half of this page
 * — no business rule lives here that isn't also enforced, redundantly,
 * inside those functions themselves.
 *
 * Live since 8 Sep 2026 (migration 0053): public.retirement_requests
 * joined the supabase_realtime publication, so the retirement queue
 * below gets a true push subscription — cases.php's idiom, not
 * accounts.php's 20-second poll. Succession has no equivalent push
 * signal (public.users still deliberately carries none, per 0046), so
 * that half of the page is a plain page load, same as accounts.php's own
 * Transfer Administration always was.
 */
declare(strict_types=1);

require_once __DIR__ . '/auth.php';
require_once __DIR__ . '/layout.php';

/**
 * Admin succession (Grant Administrator Access, handover, step down) is
 * off for now (Rose, 30 Sep 2026) and planned for the next update. Its
 * code stays as it is; true brings the whole section back.
 */
const ADMIN_SUCCESSION_ENABLED = false;

function render_retirement_queue(): void
{
    $admin = require_admin();
    $db    = db();
    $self  = 'retirement-requests.php';

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
                if (!ADMIN_SUCCESSION_ENABLED
                    && in_array($action, ['promote', 'cancel_handover', 'step_down'], true)) {
                    $action = '';   // falls through to "Unknown action."
                }
                switch ($action) {
                    case 'approve':
                        $db->rpc('finalize_retirement', [
                            'p_request' => $target, 'p_decision' => 'approve',
                        ]);
                        $flash = t('Retirement approved. This account can no longer sign in, and any dispatch it was holding has gone back to the queue.',
                                   'Inaprubahan ang pagreretiro. Hindi na makakapag-sign in ang account na ito, at ibinalik sa pila ang anumang dispatch na hawak nito.');
                        break;

                    case 'deny':
                        $db->rpc('finalize_retirement', [
                            'p_request'  => $target,
                            'p_decision' => 'deny',
                            'p_reason'   => trim((string) ($_POST['reason'] ?? '')),
                        ]);
                        $flash = t('Retirement request denied. The tanod has been told why.', 'Tinanggihan ang kahilingang magretiro. Nasabihan na ang tanod kung bakit.');
                        break;

                    case 'promote':
                        // The database only knows the caller is an admin.
                        // Re-signing in is what proves it is still the
                        // person who owns the account at the keyboard.
                        Supabase::signIn($admin['email'], (string) ($_POST['password'] ?? ''));

                        $params = [
                            'p_user'   => (string) ($_POST['successor'] ?? ''),
                            'p_reason' => trim((string) ($_POST['reason'] ?? '')) ?: null,
                        ];

                        $useHandover = !empty($_POST['use_handover']);
                        if ($useHandover) {
                            $days = (int) ($_POST['handover_days'] ?? 30);
                            $params['p_handover_days'] = max(1, min(90, $days));
                            $params['p_revert_role']   = ($_POST['revert_role'] ?? 'resident') === 'tanod'
                                ? 'tanod' : 'resident';
                        }

                        $db->rpc('promote_to_admin', $params);

                        $flash = $useHandover
                            ? t("Administrator access granted. You'll keep acting as administrator for up to " . $params['p_handover_days'] . ' day(s) while you train them.',
                                'Naibigay ang administrator access. Mananatili kang administrator nang hanggang ' . $params['p_handover_days'] . ' araw habang sinasanay mo sila.')
                            : t('Administrator access granted. You can now step down if you are leaving.', 'Naibigay ang administrator access. Maaari ka nang bumaba sa puwesto kung aalis ka.');
                        $target = '';
                        break;

                    case 'cancel_handover':
                        $db->rpc('cancel_admin_handover');
                        $flash = t('Handover cancelled. Your successor keeps their administrator access; you will remain administrator until you step down yourself.',
                                   'Kinansela ang handover. Mananatili ang administrator access ng iyong kahalili; mananatili ka ring administrator hanggang ikaw mismo ang bumaba.');
                        $target = '';
                        break;

                    case 'step_down':
                        Supabase::signIn($admin['email'], (string) ($_POST['password'] ?? ''));
                        $db->rpc('step_down_as_admin', [
                            'p_new_role' => ($_POST['new_role'] ?? 'resident') === 'tanod' ? 'tanod' : 'resident',
                        ]);
                        logout();
                        header('Location: login.php?steppeddown=1');
                        exit;

                    default:
                        $flash = t('Unknown action.', 'Hindi kilalang aksyon.');
                        $level = 'error';
                }
            } catch (SupabaseError $ex) {
                // Narrowed to GoTrue's actual "Invalid login credentials"
                // phrase (same fix as login.php and accounts.php) so a
                // differently-caused failure in this action isn't
                // relabeled as a wrong admin password.
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

    // ---------- data: retirement queue ----------
    $error    = null;
    $requests = [];
    try {
        $requests = $db->rpc('retirement_requests_queue');
    } catch (SupabaseError $ex) {
        $error = safe_error($ex);
    }

    $pending = count(array_filter($requests, fn($r) => $r['status'] === 'pending'));

    // ---------- data: succession ----------
    $candSearch = trim((string) ($_GET['cand'] ?? ''));
    $candidates = [];
    $candidates = [];
    $handover = null;
    if (ADMIN_SUCCESSION_ENABLED) {
        try {
            $candidates = $db->rpc('admin_candidates', ['p_search' => $candSearch ?: null]);
        } catch (SupabaseError $ex) {
            $error = $error ?? safe_error($ex);
        }

        // My own in-progress handover, if any — my_admin_handover_status()
        // always returns exactly one row for the calling admin, with null
        // fields when no handover is active.
        try {
            $rows = $db->rpc('my_admin_handover_status');
            $row  = $rows[0] ?? null;
            if ($row && !empty($row['admin_handover_until'])) {
                $handover = $row;
            }
        } catch (SupabaseError) {
            // Not fatal — the succession form still works without this banner.
        }
    }

    layout_head(t('Extra Administrative Services', 'Iba pang Serbisyong Pang-admin'), $self);
    ?>

    <div class="p-topbar"><h1><?= e(t('Extra Administrative Services', 'Iba pang Serbisyong Pang-admin')) ?></h1>
      <span class="p-live" id="live-badge" title="<?= e(t('Updates as they happen — no reload needed', 'Nag-a-update habang nangyayari — hindi na kailangang i-reload')) ?>"><i></i><span id="live-badge-text"><?= e(t('Live', 'Live')) ?></span></span></div>

    <?php if ($flash): ?>
      <div class="p-flash p-flash--<?= e($flash['level']) ?>" role="status"><?= e($flash['text']) ?></div>
    <?php endif; ?>

    <?php if ($error): ?>
      <div class="p-flash p-flash--error" role="alert"><?= e($error) ?></div>
    <?php endif; ?>

    <?php if (ADMIN_SUCCESSION_ENABLED): ?>
    <?php if ($handover): ?>
      <div class="p-flash p-flash--ok" role="status">
        <strong><?= e(t('Handover in progress', 'Kasalukuyang handover')) ?></strong> &mdash; <?= e(t('training', 'sinasanay si')) ?>
        <?= e($handover['successor_name'] ?? t('your successor', 'ang iyong kahalili')) ?>. <?= e(t('You return to', 'Babalik ka bilang')) ?>
        <?= e(status_label((string) $handover['admin_handover_role'])) ?> <?= e(t('automatically on', 'nang awtomatiko sa')) ?>
        <?= e(long_datetime((string) $handover['admin_handover_until'])) ?> <?= e(t('unless you cancel it first.', 'maliban kung kanselahin mo ito.')) ?>
        <form method="post" style="display:inline">
          <input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>">
          <button class="p-btn p-btn-ghost p-btn-sm" type="submit" name="action" value="cancel_handover"
                  data-native-confirm="<?= e(t('Cancel the handover? Your successor keeps admin access either way.', 'Kanselahin ang handover? Mananatili ang admin access ng iyong kahalili alinman dito.')) ?>">
            <?= e(t('Cancel handover', 'Kanselahin ang handover')) ?>
          </button>
        </form>
      </div>
    <?php endif; ?>

    <div class="p-band"><h2><?= e(t('Grant Administrator Access', 'Magbigay ng Administrator Access')) ?></h2></div>
    <section class="p-card p-card-pad" style="margin-bottom:28px">
      <div class="p-ctl-stack">
        <p class="p-ctl-note">
          <?= e(t("Only verified accounts appear below. Verification is the step where the barangay confirmed the person lives in 183, so an outsider cannot be appointed. A real turnover — certification, oath-taking, the barangay's own bureaucracy — is not instant, so you can optionally keep acting as administrator for up to 90 days while you train them, instead of handing over everything at once.",
                  'Mga beripikadong account lamang ang lumalabas sa ibaba. Sa beripikasyon kinumpirma ng barangay na nakatira sa 183 ang tao, kaya hindi maitatalaga ang taga-labas. Hindi agad-agad ang tunay na turnover — sertipikasyon, panunumpa, at proseso ng barangay — kaya maaari kang manatiling administrator nang hanggang 90 araw habang sinasanay mo sila, sa halip na ibigay agad ang lahat.')) ?>
        </p>

        <form method="get" class="p-input" style="margin:8px 0">
          <?= nav_icon('search') ?>
          <input type="search" name="cand" style="border:0;outline:0;background:transparent;width:100%" placeholder="<?= e(t("Type the successor's name", 'I-type ang pangalan ng kahalili')) ?>"
                 value="<?= e($candSearch) ?>">
        </form>

        <form method="post">
          <input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>">

          <div class="p-roster" style="margin-bottom:12px">
            <?php if (!$candidates): ?>
              <p class="p-none-line"><?= e(t('No verified account matches that name.', 'Walang beripikadong account na tugma sa pangalang iyan.')) ?></p>
            <?php endif; ?>
            <?php foreach ($candidates as $c): ?>
              <label class="p-tanod-opt">
                <input type="radio" name="successor" value="<?= e($c['id']) ?>" required>
                <span class="p-who"><?= e(formal_name($c['full_name'])) ?>
                  <small><?= e($c['email']) ?></small></span>
                <span class="p-status-dot p-on-c"><?= e(mb_strtoupper(status_label((string) $c['role']))) ?></span>
                <span class="p-pick"><?= e(t('Appoint', 'Italaga')) ?></span>
              </label>
            <?php endforeach; ?>
          </div>

          <div class="p-cfield">
            <label class="p-flabel" for="t-reason"><?= e(t('Reason for the handover', 'Dahilan ng handover')) ?></label>
            <input class="p-input-plain" type="text" id="t-reason" name="reason" maxlength="200" autocomplete="off"
                   placeholder="<?= e(t('e.g. Turnover following the October 2026 barangay election', 'hal. Turnover kasunod ng halalang pambarangay ng Oktubre 2026')) ?>">
          </div>

          <div class="p-cfield">
            <label>
              <input type="checkbox" id="t-handover-toggle" name="use_handover" value="1">
              <?= e(t('Keep my own admin access for a training/overlap period', 'Panatilihin ang aking admin access habang nagsasanay')) ?>
            </label>
          </div>

          <div class="p-reveal" id="t-handover-fields" hidden>
            <div class="p-cfield">
              <label class="p-flabel" for="t-handover-days"><?= e(t('Length, in days (max 90)', 'Haba, sa araw (hanggang 90)')) ?></label>
              <input class="p-input-plain" type="number" id="t-handover-days" name="handover_days" min="1" max="90" value="30">
            </div>
            <div class="p-cfield">
              <label class="p-flabel" for="t-revert-role"><?= e(t('Your role once the handover ends', 'Ang iyong papel pagkatapos ng handover')) ?></label>
              <select class="p-input-plain" id="t-revert-role" name="revert_role">
                <option value="resident"><?= e(t('Resident', 'Residente')) ?></option>
                <option value="tanod">Tanod</option>
              </select>
            </div>
          </div>

          <!-- new-password, not current-password: to the browser a text box
               followed by a password box is a sign-in form, and it filled
               the admin's saved email into the reason and their password
               below, one click away from granting access. -->
          <div class="p-cfield">
            <label class="p-flabel" for="t-pass"><?= e(t('Your password', 'Ang iyong password')) ?></label>
            <input class="p-input-plain" type="password" id="t-pass" name="password" required autocomplete="new-password">
            <p class="p-hint" style="margin:4px 0 0"><?= e(t('Confirms it is you making this change.', 'Patunay na ikaw ang gumagawa ng pagbabagong ito.')) ?></p>
          </div>

          <div>
            <button class="p-btn p-btn-primary" type="submit" name="action" value="promote"><?= e(t('Grant admin access', 'Ibigay ang admin access')) ?></button>
          </div>
        </form>

        <form method="post" class="p-ctl-stack" style="margin-top:20px;border-top:1px solid var(--p-line);padding-top:16px">
          <input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>">
          <p class="p-eyebrow"><?= e(t('Stepping down', 'Pagbaba sa puwesto')) ?></p>
          <p class="p-ctl-note">
            <?= e(t('Once your successor has admin access, hand over. You will be signed out and returned to a normal account. This is refused while you are the only administrator.',
                    'Kapag may admin access na ang iyong kahalili, ipasa na. Masa-sign out ka at ibabalik sa karaniwang account. Hindi ito papayagan habang ikaw lamang ang administrator.')) ?>
          </p>
          <div class="p-cfield">
            <label class="p-flabel" for="t-role"><?= e(t('Return to', 'Bumalik bilang')) ?></label>
            <select class="p-input-plain" id="t-role" name="new_role">
              <option value="resident"><?= e(t('Resident', 'Residente')) ?></option>
              <option value="tanod">Tanod</option>
            </select>
          </div>
          <div class="p-cfield">
            <label class="p-flabel" for="t-pass2"><?= e(t('Your password', 'Ang iyong password')) ?></label>
            <input class="p-input-plain" type="password" id="t-pass2" name="password" required autocomplete="new-password">
          </div>
          <button class="p-btn p-btn-danger-solid" type="submit" name="action" value="step_down">
            <?= e(t('Step down as administrator', 'Bumaba bilang administrator')) ?>
          </button>
        </form>
      </div>
    </section>

    <?php endif; ?>

    <div class="p-band">
      <h2><?= e(t('Retirement requests', 'Mga kahilingang magretiro')) ?><span class="p-badge-n" id="pending-wrap"<?= $pending > 0 ? '' : ' hidden' ?>><span id="pending-count"><?= $pending ?></span> <?= e(t('waiting', 'naghihintay')) ?></span></h2>
      <span class="p-spacer"></span>
      <label class="p-pill-select"><span class="p-lbl"><?= e(t('Show', 'Ipakita')) ?></span>
        <select id="ret-filter"><option value="pending"><?= e(t('Waiting', 'Naghihintay')) ?></option><option value="" id="ret-all" data-label="<?= e(t('All', 'Lahat')) ?>"><?= e(t('All', 'Lahat')) ?> (<?= count($requests) ?>)</option></select></label>
    </div>

    <div class="p-card p-table-card"><div class="p-tscroll">
      <table class="p-t">
        <thead><tr>
          <th scope="col"><?= e(t('Tanod', 'Tanod')) ?></th>
          <th scope="col"><?= e(t('Requested', 'Hiniling')) ?></th>
          <th scope="col"><?= e(t('Status', 'Katayuan')) ?></th>
          <th scope="col"><?= e(t('Decision', 'Desisyon')) ?></th>
          <th scope="col" class="p-right"><span class="p-sr"><?= e(t('Action', 'Aksyon')) ?></span></th>
        </tr></thead>
        <tbody id="requests-tbody"></tbody>
      </table>
    </div></div>
    <p class="p-hint" style="margin-top:12px"><?= e(t('A tanod files this from the app when they stop serving. Approving it retires the account, so they no longer appear when you dispatch.',
                                                  'Inihahain ito ng tanod mula sa app kapag titigil na sila. Kapag inaprubahan, nireretiro ang account kaya hindi na sila lalabas sa pag-dispatch.')) ?></p>

    <script>
    // Show/hide the handover-length fields as the checkbox toggles.
    (function () {
      var box    = document.getElementById('t-handover-toggle');
      var fields = document.getElementById('t-handover-fields');
      if (!box || !fields) return;
      box.addEventListener('change', function () {
        fields.hidden = !box.checked;
      });
    })();

    // Delegated rather than bound to the rows PHP rendered on this load —
    // renderRequests() below rewrites #requests-tbody wholesale on every
    // live update, the same reason accounts.php's Quick Verify listener
    // is delegated instead of bound per-row.
    document.getElementById('requests-tbody').addEventListener('click', function (e) {
      var btn = e.target.closest('[data-reveal]');
      if (!btn) return;
      var panel = document.getElementById(btn.getAttribute('data-reveal'));
      var open  = panel.hasAttribute('hidden');
      if (open) { panel.removeAttribute('hidden'); } else { panel.setAttribute('hidden', ''); }
      btn.setAttribute('aria-expanded', String(open));
      if (open) { panel.querySelector('textarea').focus(); }
    });
    </script>

    <script src="assets/vendor/supabase/supabase.js"></script>
    <script>
    // Realtime for the retirement queue — explicit ask, 6 Sep 2026: "the
    // entire system needs to work realtime," and this page was the one
    // named gap left once resident and tanod caught up to the rest of
    // the portal. retirement_requests joined the supabase_realtime
    // publication in migration 0053; a postgres_changes event here is a
    // signal to re-run retirement_requests_queue() through PostgREST,
    // never a payload rendered directly — same idiom cases.php and
    // dashboard.php already use for reports/dispatches. This does not
    // cover the succession panel above — public.users still carries no
    // realtime push (0046) — so that half of the page is a plain load.
    (function () {
      const TOKEN = <?= json_encode(access_token()) ?>;
      // Same session token every page load (csrf_token() memoizes it) --
      // safe to bake into the JS-rendered Approve/Deny forms below the
      // same way the PHP-rendered ones already carry it as a hidden
      // input.
      const CSRF = <?= json_encode(csrf_token()) ?>;
      const sb = window.supabase ? window.supabase.createClient(
        <?= json_encode(supabase_url()) ?>,
        <?= json_encode(supabase_key()) ?>,
        { accessToken: window.ssAccessToken(TOKEN) }
      ) : null;

      function escapeHtml(s) {
        return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) {
          return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
        });
      }

      // Mirrors long_datetime() in layout.php exactly: "Sep 08, 2026 •
      // 3:45 PM", Asia/Manila.
      function longDatetime(iso) {
        if (!iso) return '';
        var d = new Date(iso);
        var parts = new Intl.DateTimeFormat('en-US', {
          timeZone: 'Asia/Manila', month: 'short', day: '2-digit', year: 'numeric',
        }).formatToParts(d);
        var get = function (t) { return (parts.find(function (p) { return p.type === t; }) || {}).value || ''; };
        var date = get('month') + ' ' + get('day') + ', ' + get('year');
        var time = new Intl.DateTimeFormat('en-US', {
          timeZone: 'Asia/Manila', hour: 'numeric', minute: '2-digit', hour12: true,
        }).format(d);
        return date + ' • ' + time;
      }

      // Mirrors retirement_status_pill() in this same file exactly.
      function statusPill(status) {
        if (status === 'approved') return '<span class="p-badge p-b-done">' + T('Approved', 'Inaprubahan') + '</span>';
        if (status === 'denied')   return '<span class="p-badge p-b-denied">' + T('Denied', 'Tinanggihan') + '</span>';
        return '<span class="p-badge p-b-pending">' + T('Waiting', 'Naghihintay') + '</span>';
      }

      function decisionCell(r) {
        if (r.status === 'approved') {
          return T('Approved by ', 'Inaprubahan ni ') + escapeHtml(r.decided_by_name || T('an administrator', 'isang administrator')) +
            T(' on ', ' noong ') + escapeHtml(longDatetime(r.decided_at));
        }
        if (r.status === 'denied') {
          return T('Denied by ', 'Tinanggihan ni ') + escapeHtml(r.decided_by_name || T('an administrator', 'isang administrator')) +
            T(' on ', ' noong ') + escapeHtml(longDatetime(r.decided_at)) + T('. Reason: ', '. Dahilan: ') + escapeHtml(r.denial_reason || '');
        }
        return '<span class="p-sub">&mdash;</span>';
      }

      function actionCell(r) {
        if (r.status !== 'pending') {
          return '<span class="p-sub">' + T('Decided', 'Napagpasyahan na') + '</span>';
        }
        // Escaped for the JS string first, then for the HTML attribute —
        // the other order let the browser decode &#39; back into a bare
        // quote inside confirm('...'), so a name like D'Souza broke the
        // handler and the request was approved with no confirmation.
        var name = escapeHtml(String(r.full_name == null ? '' : r.full_name)
          .replace(/\\/g, '\\\\').replace(/'/g, "\\'"));
        var nm = escapeHtml(String(r.full_name == null ? '' : r.full_name).replace(/\|/g, '/'));
        return (
          '<button class="p-btn p-btn-ghost p-btn-sm" type="button" data-reveal="deny-' + escapeHtml(r.id) + '" aria-expanded="false">' +
            T('Decline', 'Tanggihan') +
          '</button> ' +
          '<form method="post" style="display:inline">' +
            '<input type="hidden" name="csrf" value="' + escapeHtml(CSRF) + '">' +
            '<input type="hidden" name="id" value="' + escapeHtml(r.id) + '">' +
            '<button class="p-btn p-btn-primary p-btn-sm" type="submit" name="action" value="approve" data-confirm="' +
              T('Approve ', 'Aprubahan ang pagreretiro ni ') + nm + T('’s retirement?', '?') + '|' +
              T('Their account is retired and they no longer appear when you dispatch. They will not be able to sign in.', 'Nireretiro ang kanilang account at hindi na sila lalabas sa pag-dispatch. Hindi na sila makakapag-sign in.') + '|' +
              T('Approve', 'Aprubahan') + '|blue">' +
              T('Approve', 'Aprubahan') +
            '</button>' +
          '</form>' +
          '<div class="p-reveal p-deny-row" id="deny-' + escapeHtml(r.id) + '" hidden>' +
            '<form method="post">' +
              '<input type="hidden" name="csrf" value="' + escapeHtml(CSRF) + '">' +
              '<input type="hidden" name="id" value="' + escapeHtml(r.id) + '">' +
              '<label class="p-field" style="margin:0"><span>' + T('Reason — the tanod sees this', 'Dahilan — makikita ito ng tanod') + '</span>' +
              '<textarea class="p-note" id="reason-' + escapeHtml(r.id) + '" name="reason" rows="2" maxlength="200" ' +
                'placeholder="' + T('e.g. Please see the barangay captain before this request can be decided.', 'hal. Mangyaring kausapin muna ang kapitan bago mapagpasyahan ang kahilingang ito.') + '"></textarea></label>' +
              '<button class="p-btn p-btn-danger-solid p-btn-sm" type="submit" name="action" value="deny">' + T('Confirm decline', 'Kumpirmahin ang pagtanggi') + '</button>' +
            '</form>' +
          '</div>'
        );
      }

      function renderRequests(rows) {
        window.__retRows = rows;
        var all = document.getElementById('ret-all'); all.textContent = all.dataset.label + ' (' + rows.length + ')';
        var pending = rows.filter(function (r) { return r.status === 'pending'; }).length;
        var pendingWrap = document.getElementById('pending-wrap');
        pendingWrap.hidden = pending === 0;
        document.getElementById('pending-count').textContent = pending;

        var tbody = document.getElementById('requests-tbody');
        var want = document.getElementById('ret-filter').value;
        var shown = want ? rows.filter(function (r) { return r.status === want; }) : rows;
        if (!shown.length) {
          tbody.innerHTML = '<tr><td colspan="5" class="p-empty">' + (rows.length
            ? T('No requests waiting.', 'Walang naghihintay na kahilingan.')
            : T('No tanod has requested retirement yet.', 'Wala pang tanod na humiling na magretiro.')) + '</td></tr>';
          return;
        }
        tbody.innerHTML = shown.map(function (r) {
          return '<tr>' +
            '<td><b>' + escapeHtml(String(r.full_name || '').trim()) + '</b></td>' +
            '<td class="p-num">' + escapeHtml(longDatetime(r.requested_at)) + '</td>' +
            '<td>' + statusPill(r.status) + '</td>' +
            '<td>' + decisionCell(r) + '</td>' +
            '<td class="p-right">' + actionCell(r) + '</td>' +
            '</tr>';
        }).join('');
      }
      document.getElementById('ret-filter').addEventListener('change', function () { renderRequests(window.__retRows || []); });
      renderRequests(<?= json_encode(array_values($requests), JSON_UNESCAPED_UNICODE) ?>);

      // Bursts (approve + deny landing close together from two admins)
      // collapse into one refetch instead of one per row.
      let timer = null;
      function kick() {
        clearTimeout(timer);
        timer = setTimeout(function () {
          sb.rpc('retirement_requests_queue').then(function (res) {
            if (res.error || !res.data) return;
            renderRequests(res.data);
          });
        }, 250);
      }

      if (sb) sb.channel('retirement-requests-list')
        .on('postgres_changes', { event: '*', schema: 'public', table: 'retirement_requests' }, kick)
        .subscribe(function (status) {
          var badge = document.getElementById('live-badge'),
              text  = document.getElementById('live-badge-text');
          if (status === 'SUBSCRIBED') {
            badge.classList.remove('p-down'); text.textContent = T('Live', 'Live');
          } else if (status === 'CHANNEL_ERROR' || status === 'TIMED_OUT' || status === 'CLOSED') {
            badge.classList.add('p-down'); text.textContent = T('Reconnecting…', 'Kumokonekta muli…');
          }
        });
    })();
    </script>

    <?php
    layout_foot();
}

/** Status, as a pill — same visual language as account_status_pills() in accounts.php. */
function retirement_status_pill(string $status): string
{
    return match ($status) {
        'approved' => '<span class="p-badge p-b-done">' . e(t('Approved', 'Inaprubahan')) . '</span>',
        'denied'   => '<span class="p-badge p-b-denied">' . e(t('Denied', 'Tinanggihan')) . '</span>',
        default    => '<span class="p-badge p-b-pending">' . e(t('Waiting', 'Naghihintay')) . '</span>',
    };
}
