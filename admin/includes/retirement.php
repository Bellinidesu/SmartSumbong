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
            $flash = 'That form expired. Please try again.';
            $level = 'error';
        } else {
            try {
                switch ($_POST['action'] ?? '') {
                    case 'approve':
                        $db->rpc('finalize_retirement', [
                            'p_request' => $target, 'p_decision' => 'approve',
                        ]);
                        $flash = 'Retirement approved. This account can no longer sign in, '
                               . 'and any dispatch it was holding has gone back to the queue.';
                        break;

                    case 'deny':
                        $db->rpc('finalize_retirement', [
                            'p_request'  => $target,
                            'p_decision' => 'deny',
                            'p_reason'   => trim((string) ($_POST['reason'] ?? '')),
                        ]);
                        $flash = 'Retirement request denied. The tanod has been told why.';
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
                            ? "Administrator access granted. You'll keep acting as administrator "
                              . 'for up to ' . $params['p_handover_days'] . ' day(s) while you train them.'
                            : 'Administrator access granted. You can now step down if you are leaving.';
                        $target = '';
                        break;

                    case 'cancel_handover':
                        $db->rpc('cancel_admin_handover');
                        $flash = 'Handover cancelled. Your successor keeps their administrator access; '
                               . 'you will remain administrator until you step down yourself.';
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
                        $flash = 'Unknown action.';
                        $level = 'error';
                }
            } catch (SupabaseError $ex) {
                $msg   = safe_error($ex);
                $flash = str_contains(strtolower($msg), 'credential')
                    ? 'That password is not right. Nothing was changed.'
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

    layout_head('Extra Administrative Services', $self);
    ?>

    <?php if ($flash): ?>
      <div class="flash flash--<?= e($flash['level']) ?>" role="status"><?= e($flash['text']) ?></div>
    <?php endif; ?>

    <?php if ($error): ?>
      <div class="alert-bar" role="alert"><?= e($error) ?></div>
    <?php endif; ?>

    <?php if ($handover): ?>
      <div class="flash flash--ok handover-banner" role="status">
        <strong>Handover in progress</strong> &mdash; training
        <?= e($handover['successor_name'] ?? 'your successor') ?>. You return to
        <?= e(ucfirst((string) $handover['admin_handover_role'])) ?> automatically on
        <?= e(long_datetime((string) $handover['admin_handover_until'])) ?> unless you cancel it first.
        <form method="post" style="display:inline">
          <input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>">
          <button class="btn-link-inline" type="submit" name="action" value="cancel_handover"
                  onclick="return confirm('Cancel the handover? Your successor keeps admin access either way.')">
            Cancel handover
          </button>
        </form>
      </div>
    <?php endif; ?>

    <section class="panel">
      <header class="panel-bar">
        <h2 class="panel-title">Grant Administrator Access</h2>
      </header>

      <div class="succession-body">
        <p class="control-note">
          Only verified accounts appear below. Verification is the step where the
          barangay confirmed the person lives in 183, so an outsider cannot be
          appointed. A real turnover &mdash; certification, oath-taking, the
          barangay's own bureaucracy &mdash; is not instant, so you can optionally
          keep acting as administrator for up to 90 days while you train them,
          instead of handing over everything at once.
        </p>

        <form method="get" class="panel-search succession-search">
          <?= nav_icon('search') ?>
          <input type="search" name="cand" placeholder="Type the successor's name"
                 value="<?= e($candSearch) ?>">
        </form>

        <form method="post">
          <input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>">

          <div class="cand-list">
            <?php if (!$candidates): ?>
              <p class="case-none">No verified account matches that name.</p>
            <?php endif; ?>
            <?php foreach ($candidates as $c): ?>
              <label class="roster-row">
                <input type="radio" name="successor" value="<?= e($c['id']) ?>" required>
                <span class="roster-name"><?= e($c['full_name']) ?>
                  <small class="roster-dist"><?= e($c['email']) ?></small></span>
                <span class="roster-state is-on"><?= e(strtoupper($c['role'])) ?></span>
                <span class="roster-pick">Appoint</span>
              </label>
            <?php endforeach; ?>
          </div>

          <div class="control-field">
            <label class="field-label" for="t-reason">Reason for the handover</label>
            <input type="text" id="t-reason" name="reason" maxlength="200"
                   placeholder="e.g. Turnover following the October 2026 barangay election">
          </div>

          <div class="control-field field-check">
            <label>
              <input type="checkbox" id="t-handover-toggle" name="use_handover" value="1">
              Keep my own admin access for a training/overlap period
            </label>
          </div>

          <div class="handover-fields" id="t-handover-fields" hidden>
            <div class="control-field">
              <label class="field-label" for="t-handover-days">Length, in days (max 90)</label>
              <input type="number" id="t-handover-days" name="handover_days" min="1" max="90" value="30">
            </div>
            <div class="control-field">
              <label class="field-label" for="t-revert-role">Your role once the handover ends</label>
              <select id="t-revert-role" name="revert_role">
                <option value="resident">Resident</option>
                <option value="tanod">Tanod</option>
              </select>
            </div>
          </div>

          <div class="control-field">
            <label class="field-label" for="t-pass">Your password</label>
            <input type="password" id="t-pass" name="password" required autocomplete="current-password">
            <p class="field-hint">Confirms it is you making this change.</p>
          </div>

          <div class="confirm-actions" style="justify-content:flex-start">
            <button class="btn-accept" type="submit" name="action" value="promote">Grant admin access</button>
          </div>
        </form>

        <form method="post" class="step-down">
          <input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>">
          <h3 class="case-sub">Stepping down</h3>
          <p class="control-note">
            Once your successor has admin access, hand over. You will be signed out
            and returned to a normal account. This is refused while you are the only
            administrator.
          </p>
          <div class="control-field">
            <label class="field-label" for="t-role">Return to</label>
            <select id="t-role" name="new_role">
              <option value="resident">Resident</option>
              <option value="tanod">Tanod</option>
            </select>
          </div>
          <div class="control-field">
            <label class="field-label" for="t-pass2">Your password</label>
            <input type="password" id="t-pass2" name="password" required autocomplete="current-password">
          </div>
          <button class="btn-deny-confirm" type="submit" name="action" value="step_down">
            Step down as administrator
          </button>
        </form>
      </div>
    </section>

    <section class="panel">
      <header class="panel-bar">
        <h2 class="panel-title">
          Retirement Requests (<span id="requests-count"><?= count($requests) ?></span>)
          <span class="live-badge" id="live-badge" title="Updates as they happen — no reload needed">
            <span class="live-dot" aria-hidden="true"></span><span id="live-badge-text">Live</span>
          </span>
          <span id="pending-wrap"<?= $pending > 0 ? '' : ' hidden' ?>>
            &middot; <span class="pending-count" id="pending-count"><?= $pending ?></span> awaiting a decision
          </span>
        </h2>
      </header>

      <div class="table-wrap">
        <table class="case-table">
          <thead>
            <tr>
              <th scope="col">Tanod Name</th>
              <th scope="col">Requested</th>
              <th scope="col">Status</th>
              <th scope="col">Decision</th>
              <th scope="col"><span class="visually-hidden">Action</span></th>
            </tr>
          </thead>
          <tbody id="requests-tbody">
            <?php if (!$requests): ?>
              <tr class="row-empty">
                <td colspan="5">No tanod has requested retirement yet.</td>
              </tr>
            <?php endif; ?>

            <?php foreach ($requests as $r): ?>
              <tr>
                <td><?= e($r['full_name']) ?></td>
                <td><?= e(long_datetime($r['requested_at'])) ?></td>
                <td><?= retirement_status_pill((string) $r['status']) ?></td>
                <td>
                  <?php if ($r['status'] === 'approved'): ?>
                    Approved by <?= e($r['decided_by_name'] ?? 'an administrator') ?>
                    on <?= e(long_datetime($r['decided_at'])) ?>
                  <?php elseif ($r['status'] === 'denied'): ?>
                    Denied by <?= e($r['decided_by_name'] ?? 'an administrator') ?>
                    on <?= e(long_datetime($r['decided_at'])) ?>.
                    Reason: <?= e($r['denial_reason'] ?? '') ?>
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
                              onclick="return confirm('Approve retirement for <?= e(addslashes($r['full_name'])) ?>? This account will no longer be able to sign in.')">
                        Approve
                      </button>
                    </form>
                    <button class="btn-deny" type="button" data-reveal="deny-<?= e($r['id']) ?>" aria-expanded="false">
                      Deny
                    </button>
                    <div class="deny-panel" id="deny-<?= e($r['id']) ?>" hidden>
                      <form method="post">
                        <input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>">
                        <input type="hidden" name="id" value="<?= e($r['id']) ?>">
                        <label class="field-label" for="reason-<?= e($r['id']) ?>">
                          Reason &mdash; the tanod sees this
                        </label>
                        <textarea id="reason-<?= e($r['id']) ?>" name="reason" rows="2" maxlength="200"
                                  placeholder="e.g. Please see the barangay captain before this request can be decided."></textarea>
                        <button class="btn-deny-confirm" type="submit" name="action" value="deny">Confirm denial</button>
                      </form>
                    </div>
                  <?php else: ?>
                    <span class="case-none">Decided</span>
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
        if (status === 'approved') return '<span class="pill pill--resolved">Approved</span>';
        if (status === 'denied')   return '<span class="pill pill--rejected">Denied</span>';
        return '<span class="pill pill--pending">Pending</span>';
      }

      function decisionCell(r) {
        if (r.status === 'approved') {
          return 'Approved by ' + escapeHtml(r.decided_by_name || 'an administrator') +
            ' on ' + escapeHtml(longDatetime(r.decided_at));
        }
        if (r.status === 'denied') {
          return 'Denied by ' + escapeHtml(r.decided_by_name || 'an administrator') +
            ' on ' + escapeHtml(longDatetime(r.decided_at)) + '. Reason: ' + escapeHtml(r.denial_reason || '');
        }
        return '<span class="case-none">&mdash;</span>';
      }

      function actionCell(r) {
        if (r.status !== 'pending') {
          return '<span class="case-none">Decided</span>';
        }
        var name = escapeHtml(r.full_name);
        return (
          '<form method="post" class="quick-verify-form" style="display:inline">' +
            '<input type="hidden" name="csrf" value="' + escapeHtml(CSRF) + '">' +
            '<input type="hidden" name="id" value="' + escapeHtml(r.id) + '">' +
            '<button class="btn-accept" type="submit" name="action" value="approve" ' +
              'onclick="return confirm(\'Approve retirement for ' + name.replace(/'/g, "\\'") +
              '? This account will no longer be able to sign in.\')">' +
              'Approve' +
            '</button>' +
          '</form>' +
          '<button class="btn-deny" type="button" data-reveal="deny-' + escapeHtml(r.id) + '" aria-expanded="false">' +
            'Deny' +
          '</button>' +
          '<div class="deny-panel" id="deny-' + escapeHtml(r.id) + '" hidden>' +
            '<form method="post">' +
              '<input type="hidden" name="csrf" value="' + escapeHtml(CSRF) + '">' +
              '<input type="hidden" name="id" value="' + escapeHtml(r.id) + '">' +
              '<label class="field-label" for="reason-' + escapeHtml(r.id) + '">Reason &mdash; the tanod sees this</label>' +
              '<textarea id="reason-' + escapeHtml(r.id) + '" name="reason" rows="2" maxlength="200" ' +
                'placeholder="e.g. Please see the barangay captain before this request can be decided."></textarea>' +
              '<button class="btn-deny-confirm" type="submit" name="action" value="deny">Confirm denial</button>' +
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
          tbody.innerHTML = '<tr class="row-empty"><td colspan="5">No tanod has requested retirement yet.</td></tr>';
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
            badge.classList.remove('is-down'); text.textContent = 'Live';
          } else if (status === 'CHANNEL_ERROR' || status === 'TIMED_OUT' || status === 'CLOSED') {
            badge.classList.add('is-down'); text.textContent = 'Reconnecting…';
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
        'approved' => '<span class="pill pill--resolved">Approved</span>',
        'denied'   => '<span class="pill pill--rejected">Denied</span>',
        default    => '<span class="pill pill--pending">Pending</span>',
    };
}
