<?php
/**
 * Retirement Requests — new dedicated queue, not folded into Personnel's
 * own account-actions menu.
 *
 * The barangay's own instruction was explicit that a tanod's retirement
 * needs an admin to "finalize" it, and the four design decisions made
 * for this feature settled the portal side of that: retirement gets its
 * own page and its own audit trail here, separate from Personnel's
 * suspend/reinstate history, because approving someone's end of service
 * is not the same action as suspending them mid-service and should not
 * share a review queue with it.
 *
 * finalize_retirement() (migration 0052) does the actual work — row
 * lock, decision validation, a reason required on denial, the tanod
 * notified, and (on approval) any live dispatch released back to the
 * queue exactly the way set_account_suspension() already does. This
 * file is the same thin wrapper around an RPC that accounts.php already
 * is for verify_user_account()/set_account_suspension() — no business
 * rule lives here that isn't also enforced, redundantly, inside the
 * function itself.
 *
 * Live since 8 Sep 2026 (migration 0053): public.retirement_requests
 * joined the supabase_realtime publication, so this page gets a true
 * push subscription — cases.php's idiom, not accounts.php's 20-second
 * poll. A postgres_changes event here is only ever a signal to re-run
 * retirement_requests_queue() through PostgREST, never a payload
 * rendered directly, same reasoning as everywhere else this pattern is
 * used. The table this pass adds to the queue was the one gap left when
 * the audit doc for the full tanod tree called out that resident and
 * tanod weren't yet "as live as the portal."
 */
declare(strict_types=1);

require_once __DIR__ . '/auth.php';
require_once __DIR__ . '/layout.php';

function render_retirement_queue(): void
{
    require_admin();
    $db  = db();
    $self = 'retirement-requests.php';

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

                    default:
                        $flash = 'Unknown action.';
                        $level = 'error';
                }
            } catch (SupabaseError $ex) {
                $flash = safe_error($ex);
                $level = 'error';
            }
        }

        $_SESSION['flash'] = ['text' => $flash, 'level' => $level];
        header('Location: ' . $self);
        exit;
    }

    $flash = $_SESSION['flash'] ?? null;
    unset($_SESSION['flash']);

    // ---------- data ----------
    $error    = null;
    $requests = [];
    try {
        $requests = $db->rpc('retirement_requests_queue');
    } catch (SupabaseError $ex) {
        $error = safe_error($ex);
    }

    $pending = count(array_filter($requests, fn($r) => $r['status'] === 'pending'));

    layout_head('Retirement Requests', $self);
    ?>

    <?php if ($flash): ?>
      <div class="flash flash--<?= e($flash['level']) ?>" role="status"><?= e($flash['text']) ?></div>
    <?php endif; ?>

    <?php if ($error): ?>
      <div class="alert-bar" role="alert"><?= e($error) ?></div>
    <?php endif; ?>

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

    <script src="assets/vendor/supabase/supabase.js"></script>
    <script>
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

    // Realtime for the retirement queue — explicit ask, 6 Sep 2026: "the
    // entire system needs to work realtime," and this page was the one
    // named gap left once resident and tanod caught up to the rest of
    // the portal. retirement_requests joined the supabase_realtime
    // publication in migration 0053; a postgres_changes event here is a
    // signal to re-run retirement_requests_queue() through PostgREST,
    // never a payload rendered directly — same idiom cases.php and
    // dashboard.php already use for reports/dispatches.
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
