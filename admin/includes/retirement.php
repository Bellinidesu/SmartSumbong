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
                switch ($_POST['action'] ?? '') {
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
    try {
        $candidates = $db->rpc('admin_candidates', ['p_search' => $candSearch ?: null]);
    } catch (SupabaseError $ex) {
        $error = $error ?? safe_error($ex);
    }

    // My own in-progress handover, if any — my_admin_handover_status()
    // always returns exactly one row for the calling admin, with null
    // fields when no handover is active.
    $handover = null;
    try {
        $rows = $db->rpc('my_admin_handover_status');
        $row  = $rows[0] ?? null;
        if ($row && !empty($row['admin_handover_until'])) {
            $handover = $row;
        }
    } catch (SupabaseError) {
        // Not fatal — the succession form still works without this banner.
    }

    layout_head(t('Extra Administrative Services', 'Iba pang Serbisyong Pang-admin'), $self);
    ?>

    <?php if ($flash): ?>
      <div class="flash flash--<?= e($flash['level']) ?>" role="status"><?= e($flash['text']) ?></div>
    <?php endif; ?>

    <?php if ($error): ?>
      <div class="alert-bar" role="alert"><?= e($error) ?></div>
    <?php endif; ?>

    <?php if ($handover): ?>
      <div class="flash flash--ok handover-banner" role="status">
        <strong><?= e(t('Handover in progress', 'Kasalukuyang handover')) ?></strong> &mdash; <?= e(t('training', 'sinasanay si')) ?>
        <?= e($handover['successor_name'] ?? t('your successor', 'ang iyong kahalili')) ?>. <?= e(t('You return to', 'Babalik ka bilang')) ?>
        <?= e(status_label((string) $handover['admin_handover_role'])) ?> <?= e(t('automatically on', 'nang awtomatiko sa')) ?>
        <?= e(long_datetime((string) $handover['admin_handover_until'])) ?> <?= e(t('unless you cancel it first.', 'maliban kung kanselahin mo ito.')) ?>
        <form method="post" style="display:inline">
          <input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>">
          <button class="btn-link-inline" type="submit" name="action" value="cancel_handover"
                  onclick="return confirm(<?= e(json_encode(t('Cancel the handover? Your successor keeps admin access either way.', 'Kanselahin ang handover? Mananatili ang admin access ng iyong kahalili alinman dito.'), JSON_UNESCAPED_UNICODE)) ?>)">
            <?= e(t('Cancel handover', 'Kanselahin ang handover')) ?>
          </button>
        </form>
      </div>
    <?php endif; ?>

    <section class="panel">
      <header class="panel-bar">
        <h2 class="panel-title"><?= e(t('Grant Administrator Access', 'Magbigay ng Administrator Access')) ?></h2>
      </header>

      <div class="succession-body">
        <p class="control-note">
          <?= e(t("Only verified accounts appear below. Verification is the step where the barangay confirmed the person lives in 183, so an outsider cannot be appointed. A real turnover — certification, oath-taking, the barangay's own bureaucracy — is not instant, so you can optionally keep acting as administrator for up to 90 days while you train them, instead of handing over everything at once.",
                  'Mga beripikadong account lamang ang lumalabas sa ibaba. Sa beripikasyon kinumpirma ng barangay na nakatira sa 183 ang tao, kaya hindi maitatalaga ang taga-labas. Hindi agad-agad ang tunay na turnover — sertipikasyon, panunumpa, at proseso ng barangay — kaya maaari kang manatiling administrator nang hanggang 90 araw habang sinasanay mo sila, sa halip na ibigay agad ang lahat.')) ?>
        </p>

        <form method="get" class="panel-search succession-search">
          <?= nav_icon('search') ?>
          <input type="search" name="cand" placeholder="<?= e(t("Type the successor's name", 'I-type ang pangalan ng kahalili')) ?>"
                 value="<?= e($candSearch) ?>">
        </form>

        <form method="post">
          <input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>">

          <div class="cand-list">
            <?php if (!$candidates): ?>
              <p class="case-none"><?= e(t('No verified account matches that name.', 'Walang beripikadong account na tugma sa pangalang iyan.')) ?></p>
            <?php endif; ?>
            <?php foreach ($candidates as $c): ?>
              <label class="roster-row">
                <input type="radio" name="successor" value="<?= e($c['id']) ?>" required>
                <span class="roster-name"><?= e($c['full_name']) ?>
                  <small class="roster-dist"><?= e($c['email']) ?></small></span>
                <span class="roster-state is-on"><?= e(mb_strtoupper(status_label((string) $c['role']))) ?></span>
                <span class="roster-pick"><?= e(t('Appoint', 'Italaga')) ?></span>
              </label>
            <?php endforeach; ?>
          </div>

          <div class="control-field">
            <label class="field-label" for="t-reason"><?= e(t('Reason for the handover', 'Dahilan ng handover')) ?></label>
            <input type="text" id="t-reason" name="reason" maxlength="200" autocomplete="off"
                   placeholder="<?= e(t('e.g. Turnover following the October 2026 barangay election', 'hal. Turnover kasunod ng halalang pambarangay ng Oktubre 2026')) ?>">
          </div>

          <div class="control-field field-check">
            <label>
              <input type="checkbox" id="t-handover-toggle" name="use_handover" value="1">
              <?= e(t('Keep my own admin access for a training/overlap period', 'Panatilihin ang aking admin access habang nagsasanay')) ?>
            </label>
          </div>

          <div class="handover-fields" id="t-handover-fields" hidden>
            <div class="control-field">
              <label class="field-label" for="t-handover-days"><?= e(t('Length, in days (max 90)', 'Haba, sa araw (hanggang 90)')) ?></label>
              <input type="number" id="t-handover-days" name="handover_days" min="1" max="90" value="30">
            </div>
            <div class="control-field">
              <label class="field-label" for="t-revert-role"><?= e(t('Your role once the handover ends', 'Ang iyong papel pagkatapos ng handover')) ?></label>
              <select id="t-revert-role" name="revert_role">
                <option value="resident"><?= e(t('Resident', 'Residente')) ?></option>
                <option value="tanod">Tanod</option>
              </select>
            </div>
          </div>

          <!-- new-password, not current-password: to the browser a text box
               followed by a password box is a sign-in form, and it filled
               the admin's saved email into the reason and their password
               below, one click away from granting access. -->
          <div class="control-field">
            <label class="field-label" for="t-pass"><?= e(t('Your password', 'Ang iyong password')) ?></label>
            <input type="password" id="t-pass" name="password" required autocomplete="new-password">
            <p class="field-hint"><?= e(t('Confirms it is you making this change.', 'Patunay na ikaw ang gumagawa ng pagbabagong ito.')) ?></p>
          </div>

          <div class="confirm-actions" style="justify-content:flex-start">
            <button class="btn-accept" type="submit" name="action" value="promote"><?= e(t('Grant admin access', 'Ibigay ang admin access')) ?></button>
          </div>
        </form>

        <form method="post" class="step-down">
          <input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>">
          <h3 class="case-sub"><?= e(t('Stepping down', 'Pagbaba sa puwesto')) ?></h3>
          <p class="control-note">
            <?= e(t('Once your successor has admin access, hand over. You will be signed out and returned to a normal account. This is refused while you are the only administrator.',
                    'Kapag may admin access na ang iyong kahalili, ipasa na. Masa-sign out ka at ibabalik sa karaniwang account. Hindi ito papayagan habang ikaw lamang ang administrator.')) ?>
          </p>
          <div class="control-field">
            <label class="field-label" for="t-role"><?= e(t('Return to', 'Bumalik bilang')) ?></label>
            <select id="t-role" name="new_role">
              <option value="resident"><?= e(t('Resident', 'Residente')) ?></option>
              <option value="tanod">Tanod</option>
            </select>
          </div>
          <div class="control-field">
            <label class="field-label" for="t-pass2"><?= e(t('Your password', 'Ang iyong password')) ?></label>
            <input type="password" id="t-pass2" name="password" required autocomplete="new-password">
          </div>
          <button class="btn-deny-confirm" type="submit" name="action" value="step_down">
            <?= e(t('Step down as administrator', 'Bumaba bilang administrator')) ?>
          </button>
        </form>
      </div>
    </section>

    <section class="panel">
      <header class="panel-bar">
        <h2 class="panel-title">
          <?= e(t('Retirement Requests', 'Mga Kahilingang Magretiro')) ?> (<span id="requests-count"><?= count($requests) ?></span>)
          <span class="live-badge" id="live-badge" title="<?= e(t('Updates as they happen — no reload needed', 'Nag-a-update habang nangyayari — hindi na kailangang i-reload')) ?>">
            <span class="live-dot" aria-hidden="true"></span><span id="live-badge-text"><?= e(t('Live', 'Live')) ?></span>
          </span>
          <span id="pending-wrap"<?= $pending > 0 ? '' : ' hidden' ?>>
            &middot; <span class="pending-count" id="pending-count"><?= $pending ?></span> <?= e(t('awaiting a decision', 'naghihintay ng desisyon')) ?>
          </span>
        </h2>
      </header>

      <div class="table-wrap">
        <table class="case-table">
          <thead>
            <tr>
              <th scope="col"><?= e(t('Tanod Name', 'Pangalan ng Tanod')) ?></th>
              <th scope="col"><?= e(t('Requested', 'Hiniling')) ?></th>
              <th scope="col"><?= e(t('Status', 'Katayuan')) ?></th>
              <th scope="col"><?= e(t('Decision', 'Desisyon')) ?></th>
              <th scope="col"><span class="visually-hidden"><?= e(t('Action', 'Aksyon')) ?></span></th>
            </tr>
          </thead>
          <tbody id="requests-tbody">
            <?php if (!$requests): ?>
              <tr class="row-empty">
                <td colspan="5"><?= e(t('No tanod has requested retirement yet.', 'Wala pang tanod na humiling na magretiro.')) ?></td>
              </tr>
            <?php endif; ?>

            <?php foreach ($requests as $r): ?>
              <tr>
                <td><?= e($r['full_name']) ?></td>
                <td><?= e(long_datetime($r['requested_at'])) ?></td>
                <td><?= retirement_status_pill((string) $r['status']) ?></td>
                <td>
                  <?php if ($r['status'] === 'approved'): ?>
                    <?= e(t('Approved by', 'Inaprubahan ni')) ?> <?= e($r['decided_by_name'] ?? t('an administrator', 'isang administrator')) ?>
                    <?= e(t('on', 'noong')) ?> <?= e(long_datetime($r['decided_at'])) ?>
                  <?php elseif ($r['status'] === 'denied'): ?>
                    <?= e(t('Denied by', 'Tinanggihan ni')) ?> <?= e($r['decided_by_name'] ?? t('an administrator', 'isang administrator')) ?>
                    <?= e(t('on', 'noong')) ?> <?= e(long_datetime($r['decided_at'])) ?>.
                    <?= e(t('Reason:', 'Dahilan:')) ?> <?= e($r['denial_reason'] ?? '') ?>
                  <?php else: ?>
                    <span class="case-none">&mdash;</span>
                  <?php endif; ?>
                </td>
                <td class="cell-action">
                  <?php if ($r['status'] === 'pending'): ?>
                    <form method="post" class="quick-verify-form" style="display:inline">
                      <input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>">
                      <input type="hidden" name="id" value="<?= e($r['id']) ?>">
                      <button class="btn-accept" type="submit" name="action" value="approve"
                              onclick="return confirm(<?= e(json_encode(t('Approve retirement for ' . $r['full_name'] . '? This account will no longer be able to sign in.', 'Aprubahan ang pagreretiro ni ' . $r['full_name'] . '? Hindi na makakapag-sign in ang account na ito.'), JSON_UNESCAPED_UNICODE)) ?>)">
                        <?= e(t('Approve', 'Aprubahan')) ?>
                      </button>
                    </form>
                    <button class="btn-deny" type="button" data-reveal="deny-<?= e($r['id']) ?>" aria-expanded="false">
                      <?= e(t('Deny', 'Tanggihan')) ?>
                    </button>
                    <div class="deny-panel" id="deny-<?= e($r['id']) ?>" hidden>
                      <form method="post">
                        <input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>">
                        <input type="hidden" name="id" value="<?= e($r['id']) ?>">
                        <label class="field-label" for="reason-<?= e($r['id']) ?>">
                          <?= e(t('Reason — the tanod sees this', 'Dahilan — makikita ito ng tanod')) ?>
                        </label>
                        <textarea id="reason-<?= e($r['id']) ?>" name="reason" rows="2" maxlength="200"
                                  placeholder="<?= e(t('e.g. Please see the barangay captain before this request can be decided.', 'hal. Mangyaring kausapin muna ang kapitan bago mapagpasyahan ang kahilingang ito.')) ?>"></textarea>
                        <button class="btn-deny-confirm" type="submit" name="action" value="deny"><?= e(t('Confirm denial', 'Kumpirmahin ang pagtanggi')) ?></button>
                      </form>
                    </div>
                  <?php else: ?>
                    <span class="case-none"><?= e(t('Decided', 'Napagpasyahan na')) ?></span>
                  <?php endif; ?>
                </td>
              </tr>
            <?php endforeach; ?>
          </tbody>
        </table>
      </div>
    </section>

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
      if (!window.supabase) { return; }
      const { createClient } = supabase;

      const TOKEN = <?= json_encode(access_token()) ?>;
      // Same session token every page load (csrf_token() memoizes it) --
      // safe to bake into the JS-rendered Approve/Deny forms below the
      // same way the PHP-rendered ones already carry it as a hidden
      // input.
      const CSRF = <?= json_encode(csrf_token()) ?>;
      const sb = createClient(
        <?= json_encode(supabase_url()) ?>,
        <?= json_encode(supabase_key()) ?>,
        { global: { headers: { Authorization: 'Bearer ' + TOKEN } },
          auth: { persistSession: false, autoRefreshToken: false } }
      );
      sb.realtime.setAuth(TOKEN);

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
        if (status === 'approved') return '<span class="pill pill--resolved">' + T('Approved', 'Inaprubahan') + '</span>';
        if (status === 'denied')   return '<span class="pill pill--rejected">' + T('Denied', 'Tinanggihan') + '</span>';
        return '<span class="pill pill--pending">' + T('Pending', 'Nakabinbin') + '</span>';
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
        return '<span class="case-none">&mdash;</span>';
      }

      function actionCell(r) {
        if (r.status !== 'pending') {
          return '<span class="case-none">' + T('Decided', 'Napagpasyahan na') + '</span>';
        }
        // Escaped for the JS string first, then for the HTML attribute —
        // the other order let the browser decode &#39; back into a bare
        // quote inside confirm('...'), so a name like D'Souza broke the
        // handler and the request was approved with no confirmation.
        var name = escapeHtml(String(r.full_name == null ? '' : r.full_name)
          .replace(/\\/g, '\\\\').replace(/'/g, "\\'"));
        return (
          '<form method="post" class="quick-verify-form" style="display:inline">' +
            '<input type="hidden" name="csrf" value="' + escapeHtml(CSRF) + '">' +
            '<input type="hidden" name="id" value="' + escapeHtml(r.id) + '">' +
            '<button class="btn-accept" type="submit" name="action" value="approve" ' +
              'onclick="return confirm(\'' + T('Approve retirement for ', 'Aprubahan ang pagreretiro ni ') + name +
              T('? This account will no longer be able to sign in.', '? Hindi na makakapag-sign in ang account na ito.') + '\')">' +
              T('Approve', 'Aprubahan') +
            '</button>' +
          '</form>' +
          '<button class="btn-deny" type="button" data-reveal="deny-' + escapeHtml(r.id) + '" aria-expanded="false">' +
            T('Deny', 'Tanggihan') +
          '</button>' +
          '<div class="deny-panel" id="deny-' + escapeHtml(r.id) + '" hidden>' +
            '<form method="post">' +
              '<input type="hidden" name="csrf" value="' + escapeHtml(CSRF) + '">' +
              '<input type="hidden" name="id" value="' + escapeHtml(r.id) + '">' +
              '<label class="field-label" for="reason-' + escapeHtml(r.id) + '">' + T('Reason — the tanod sees this', 'Dahilan — makikita ito ng tanod') + '</label>' +
              '<textarea id="reason-' + escapeHtml(r.id) + '" name="reason" rows="2" maxlength="200" ' +
                'placeholder="' + T('e.g. Please see the barangay captain before this request can be decided.', 'hal. Mangyaring kausapin muna ang kapitan bago mapagpasyahan ang kahilingang ito.') + '"></textarea>' +
              '<button class="btn-deny-confirm" type="submit" name="action" value="deny">' + T('Confirm denial', 'Kumpirmahin ang pagtanggi') + '</button>' +
            '</form>' +
          '</div>'
        );
      }

      function renderRequests(rows) {
        document.getElementById('requests-count').textContent = rows.length;
        var pending = rows.filter(function (r) { return r.status === 'pending'; }).length;
        var pendingWrap = document.getElementById('pending-wrap');
        pendingWrap.hidden = pending === 0;
        document.getElementById('pending-count').textContent = pending;

        var tbody = document.getElementById('requests-tbody');
        if (!rows.length) {
          tbody.innerHTML = '<tr class="row-empty"><td colspan="5">' + T('No tanod has requested retirement yet.', 'Wala pang tanod na humiling na magretiro.') + '</td></tr>';
          return;
        }
        tbody.innerHTML = rows.map(function (r) {
          return '<tr>' +
            '<td>' + escapeHtml(r.full_name) + '</td>' +
            '<td>' + escapeHtml(longDatetime(r.requested_at)) + '</td>' +
            '<td>' + statusPill(r.status) + '</td>' +
            '<td>' + decisionCell(r) + '</td>' +
            '<td class="cell-action">' + actionCell(r) + '</td>' +
            '</tr>';
        }).join('');
      }

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

      sb.channel('retirement-requests-list')
        .on('postgres_changes', { event: '*', schema: 'public', table: 'retirement_requests' }, kick)
        .subscribe(function (status) {
          var badge = document.getElementById('live-badge'),
              text  = document.getElementById('live-badge-text');
          if (status === 'SUBSCRIBED') {
            badge.classList.remove('is-down'); text.textContent = T('Live', 'Live');
          } else if (status === 'CHANNEL_ERROR' || status === 'TIMED_OUT' || status === 'CLOSED') {
            badge.classList.add('is-down'); text.textContent = T('Reconnecting…', 'Kumokonekta muli…');
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
        'approved' => '<span class="pill pill--resolved">' . e(t('Approved', 'Inaprubahan')) . '</span>',
        'denied'   => '<span class="pill pill--rejected">' . e(t('Denied', 'Tinanggihan')) . '</span>',
        default    => '<span class="pill pill--pending">' . e(t('Pending', 'Nakabinbin')) . '</span>',
    };
}
