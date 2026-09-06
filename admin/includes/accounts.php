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
function render_account_screen(string $role): void
{
    $admin = require_admin();
    $db    = db();

    $isTanod = $role === 'tanod';
    $title   = $isTanod ? 'Personnel' : 'Residents';
    $navFile = $isTanod ? 'personnel.php' : 'residents.php';
    $self    = $navFile;
    $noun    = $isTanod ? 'Tanod' : 'Resident';
    $idLabel = $isTanod
        ? 'Uploaded Barangay Appointment ID'
        : 'Uploaded Valid Identification';

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
                        $db->rpc('verify_user_account', [
                            'p_user' => $target, 'p_decision' => 'approve',
                        ]);
                        $flash = 'Account verified. They can file a complaint now.';
                        break;

                    case 'deny':
                        $db->rpc('verify_user_account', [
                            'p_user'     => $target,
                            'p_decision' => 'deny',
                            'p_reason'   => trim((string) ($_POST['reason'] ?? '')),
                        ]);
                        $flash = 'Registration denied. The applicant has been told why.';
                        break;

                    case 'suspend':
                        $db->rpc('set_account_suspension', [
                            'p_user'    => $target,
                            'p_suspend' => true,
                            'p_reason'  => trim((string) ($_POST['reason'] ?? '')),
                        ]);
                        $flash = 'Account suspended. Any incident they were holding went back to the queue.';
                        break;

                    case 'reinstate':
                        $db->rpc('set_account_suspension', [
                            'p_user' => $target, 'p_suspend' => false,
                        ]);
                        $flash = 'Account reinstated.';
                        break;

                    case 'request_ocr_rescan':
                        // 0050. OCR runs on-device only, once, at
                        // registration — this just flags the account so
                        // the resident's own app re-runs it against the
                        // already-uploaded photo next time it's open.
                        $db->rpc('request_ocr_rescan', [
                            'p_user' => $target,
                        ]);
                        $flash = 'Re-check requested. It will run automatically next time they open the app.';
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
                        $flash = 'Temporary password issued. Read it to them in person '
                               . 'and do not send it by message.';
                        break;

                    case 'promote':
                        // The database only knows the caller is an admin.
                        // Re-signing in is what proves it is still the
                        // person who owns the account at the keyboard.
                        Supabase::signIn($admin['email'], (string) ($_POST['password'] ?? ''));
                        $db->rpc('promote_to_admin', [
                            'p_user'   => (string) ($_POST['successor'] ?? ''),
                            'p_reason' => trim((string) ($_POST['reason'] ?? '')) ?: null,
                        ]);
                        $flash = 'Administrator access granted. You can now step down if you are leaving.';
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

    // ---------- data ----------
    $error    = null;
    $accounts = [];

    try {
        $accounts = $db->rpc('account_directory', ['p_role' => $role]);
    } catch (SupabaseError $ex) {
        $error = safe_error($ex);
    }

    $transfer   = isset($_GET['transfer']);
    $candSearch = trim((string) ($_GET['cand'] ?? ''));
    $candidates = [];
    if ($transfer && !$error) {
        try {
            $candidates = $db->rpc('admin_candidates', ['p_search' => $candSearch ?: null]);
        } catch (SupabaseError $ex) {
            $error = safe_error($ex);
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
        $error = 'That account is not in this list.';
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

        render_account_detail($person, $noun, $idLabel, $self, $navFile, $title, $flash,
                              $dupes[$person['id']] ?? [], $abuseHistory, $role);
        return;
    }

    // ---------- list ----------
    $search = trim((string) ($_GET['q'] ?? ''));
    if ($search !== '') {
        $needle   = mb_strtolower($search);
        $accounts = array_values(array_filter($accounts, function (array $a) use ($needle) {
            return str_contains(mb_strtolower($a['full_name'] . ' ' . $a['email'] . ' ' . $a['mobile_number']), $needle);
        }));
    }

    if (($_GET['sort'] ?? '') === 'newest') {
        usort($accounts, fn($x, $y) => strcmp((string) $y['created_at'], (string) $x['created_at']));
    }

    $pending = count(array_filter($accounts, fn($a) => $a['verification_status'] === 'pending'));
    $overdue = count(array_filter($accounts, fn($a) => !empty($a['is_overdue'])));

    layout_head($title, $navFile);
    ?>

    <?php if ($flash): ?>
      <div class="flash flash--<?= e($flash['level']) ?>" role="status"><?= e($flash['text']) ?></div>
    <?php endif; ?>

    <?php if ($error): ?>
      <div class="alert-bar" role="alert"><?= e($error) ?></div>
    <?php endif; ?>

    <!-- Always rendered so realtime polling below (added 6 Sep 2026) can
         toggle it as accounts age past the window, rather than only being
         able to show a banner that already existed at page load. -->
    <div class="flash flash--error" id="overdue-banner" role="alert"
         style="<?= $overdue > 0 ? '' : 'display:none' ?>">
      <span id="overdue-text"><?= $overdue ?> registration<?= $overdue === 1 ? '' : 's' ?>
        <?= $overdue === 1 ? 'has' : 'have' ?> passed the two-hour verification window.</span>
    </div>

    <section class="panel">
      <header class="panel-bar">
        <h2 class="panel-title">
          <?= e($noun) ?> Accounts (<span id="accounts-count"><?= count($accounts) ?></span>)<span id="pending-wrap"<?= $pending > 0 ? '' : ' hidden' ?>> &middot; <span class="pending-count" id="pending-count"><?= $pending ?></span> awaiting review</span>
          <span class="live-badge" id="live-badge" title="New registrations appear here on their own">
            <span class="live-dot" aria-hidden="true"></span><span id="live-badge-text">Live</span>
          </span>
        </h2>

        <form class="panel-search" method="get">
          <?= nav_icon('search') ?>
          <input type="search" name="q" placeholder="Search Here" value="<?= e($search) ?>">
        </form>

        <a class="btn-pdf" href="<?= e($self) ?>?transfer=1">Transfer Administration</a>

        <form class="panel-sort" method="get">
          <input type="hidden" name="q" value="<?= e($search) ?>">
          <label>Short by:
            <select name="sort" onchange="this.form.submit()">
              <option value="">Awaiting review first</option>
              <option value="newest" <?= ($_GET['sort'] ?? '') === 'newest' ? 'selected' : '' ?>>Newest</option>
            </select>
          </label>
        </form>
      </header>

      <div class="table-wrap">
        <table class="case-table">
          <thead>
            <tr>
              <th scope="col"><?= e($noun) ?> Name</th>
              <th scope="col">Phone Number</th>
              <th scope="col">Email</th>
              <th scope="col">Status</th>
              <th scope="col"><span class="visually-hidden">Action</span></th>
            </tr>
          </thead>
          <tbody id="accounts-tbody">
            <?php if (!$accounts): ?>
              <tr class="row-empty">
                <td colspan="5"><?= $search !== ''
                    ? 'No account matches that search.'
                    : 'No ' . e(strtolower($noun)) . ' accounts have registered yet.' ?></td>
              </tr>
            <?php endif; ?>

            <?php foreach ($accounts as $a): ?>
              <tr>
                <td><?= e($a['full_name']) ?></td>
                <td class="mono"><?= e($a['mobile_number']) ?></td>
                <td><?= e($a['email']) ?></td>
                <td><?= account_status_pills($a) ?><?php
                    if (!empty($dupes[$a['id']])): ?>
                      <span class="pill pill--escalated" title="<?= e(implode('; ', $dupes[$a['id']])) ?>">Possible duplicate</span>
                    <?php endif; ?><?php
                    if (!empty($a['ocr_flags'])): ?>
                      <span class="pill pill--escalated"
                            title="<?= e(implode('; ', array_map('ocr_flag_label', $a['ocr_flags']))) ?>">OCR flag</span>
                    <?php endif; ?><?php
                    if (!empty($a['ocr_rescan_requested_at'])
                        && (empty($a['ocr_processed_at'])
                            || (string) $a['ocr_processed_at'] < (string) $a['ocr_rescan_requested_at'])): ?>
                      <span class="pill" title="Waiting for them to open the app">Re-check pending</span>
                    <?php endif; ?></td>
                <td class="cell-action">
                  <a class="btn-review" href="<?= e($self) ?>?id=<?= e($a['id']) ?>">
                    <?= $a['verification_status'] === 'pending' ? 'Review' : 'View' ?>
                  </a>
                </td>
              </tr>
            <?php endforeach; ?>
          </tbody>
        </table>
      </div>
    </section>

    <?php if ($transfer): ?>
      <dialog class="succession" id="transfer" open>
        <h2 class="doc-h">Transfer Administration</h2>
        <p class="control-note">
          Only verified accounts appear below. Verification is the step where the
          barangay confirmed the person lives in 183, so an outsider cannot be
          appointed. Appoint your successor first &mdash; you cannot step down
          while you are the only administrator.
        </p>

        <form method="get" class="panel-search succession-search">
          <?= nav_icon('search') ?>
          <input type="hidden" name="transfer" value="1">
          <input type="search" name="cand" placeholder="Type the successor's name"
                 value="<?= e($candSearch) ?>" autofocus>
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

          <div class="control-field">
            <label class="field-label" for="t-pass">Your password</label>
            <input type="password" id="t-pass" name="password" required autocomplete="current-password">
            <p class="field-hint">Confirms it is you making this change.</p>
          </div>

          <div class="confirm-actions" style="justify-content:flex-start">
            <button class="btn-accept" type="submit" name="action" value="promote">Grant admin access</button>
            <a class="btn-deny" href="<?= e($self) ?>">Cancel</a>
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
      </dialog>
    <?php endif; ?>

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
      const SORT_NEWEST = <?= json_encode(($_GET['sort'] ?? '') === 'newest') ?>;
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
      const titleCase = s => String(s || '').replace(/_/g, ' ')
        .replace(/\b\w/g, c => c.toUpperCase());

      function ocrFlagLabel(f) {
        switch (f) {
          case 'type_mismatch': return 'ID type does not match';
          case 'unreadable': return 'ID could not be read';
          case 'name_mismatch': return 'Name does not match';
          case 'no_id_number': return 'No ID number found';
          default: return titleCase(f);
        }
      }

      function statusPillsHtml(a) {
        var out = [];
        if (a.verification_status === 'verified') out.push('<span class="pill pill--resolved">Verified</span>');
        else if (a.verification_status === 'rejected') out.push('<span class="pill pill--rejected">Rejected</span>');
        else out.push('<span class="pill pill--pending">Pending</span>');

        if (a.is_suspended) out.push('<span class="pill pill--rejected">Suspended</span>');

        if (a.verification_status === 'pending') {
          if (a.is_overdue) out.push('<span class="pill pill--escalated">Overdue</span>');
          else if (a.minutes_left !== null && a.minutes_left !== undefined) {
            out.push('<span class="pill pill--validated">' + Math.trunc(a.minutes_left) + ' min left</span>');
          }
        }
        if (a.holding_incident) out.push('<span class="pill pill--assigned">On an incident</span>');
        if (a.duty_status) out.push('<span class="pill pill--closed">' + escapeHtml(titleCase(a.duty_status)) + '</span>');
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
            (out[a.id] = out[a.id] || []).push('Same mobile number as '
              + others.map(function (b) { return b.full_name; }).join(', '));
          });
        });
        Object.keys(byName).forEach(function (k) {
          var group = byName[k];
          if (group.length < 2) return;
          group.forEach(function (a) {
            (out[a.id] = out[a.id] || []).push('Same name as another account (' + group.length + ' total)');
          });
        });
        return out;
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
        if (SORT_NEWEST) {
          filtered = filtered.slice().sort(function (x, y) {
            return String(y.created_at).localeCompare(String(x.created_at));
          });
        }
        var dupes = duplicateFlags(accounts);

        document.getElementById('accounts-count').textContent = filtered.length;
        var pending = accounts.filter(function (a) { return a.verification_status === 'pending'; }).length;
        var overdue = accounts.filter(function (a) { return a.is_overdue; }).length;

        var pendingWrap = document.getElementById('pending-wrap');
        pendingWrap.hidden = pending === 0;
        document.getElementById('pending-count').textContent = pending;

        var overdueBanner = document.getElementById('overdue-banner');
        overdueBanner.style.display = overdue > 0 ? '' : 'none';
        document.getElementById('overdue-text').textContent =
          overdue + ' registration' + (overdue === 1 ? '' : 's') + ' '
          + (overdue === 1 ? 'has' : 'have') + ' passed the two-hour verification window.';

        var tbody = document.getElementById('accounts-tbody');
        if (!filtered.length) {
          tbody.innerHTML = '<tr class="row-empty"><td colspan="5">' +
            (SEARCH ? 'No account matches that search.'
                    : 'No ' + escapeHtml(<?= json_encode(strtolower($noun)) ?>) + ' accounts have registered yet.') +
            '</td></tr>';
          return;
        }
        tbody.innerHTML = filtered.map(function (a) {
          var extra = '';
          if (dupes[a.id] && dupes[a.id].length) {
            extra += '<span class="pill pill--escalated" title="' + escapeHtml(dupes[a.id].join('; ')) + '">Possible duplicate</span>';
          }
          if (a.ocr_flags && a.ocr_flags.length) {
            extra += '<span class="pill pill--escalated" title="' +
              escapeHtml(a.ocr_flags.map(ocrFlagLabel).join('; ')) + '">OCR flag</span>';
          }
          if (a.ocr_rescan_requested_at &&
              (!a.ocr_processed_at || String(a.ocr_processed_at) < String(a.ocr_rescan_requested_at))) {
            extra += '<span class="pill" title="Waiting for them to open the app">Re-check pending</span>';
          }
          return '<tr>' +
            '<td>' + escapeHtml(a.full_name) + '</td>' +
            '<td class="mono">' + escapeHtml(a.mobile_number) + '</td>' +
            '<td>' + escapeHtml(a.email) + '</td>' +
            '<td>' + statusPillsHtml(a) + extra + '</td>' +
            '<td class="cell-action"><a class="btn-review" href="' + SELF + '?id=' + encodeURIComponent(a.id) + '">' +
              (a.verification_status === 'pending' ? 'Review' : 'View') + '</a></td>' +
            '</tr>';
        }).join('');
      }

      let timer = null;
      function scheduleRefresh() {
        clearTimeout(timer);
        timer = setTimeout(function () {
          sb.rpc('account_directory', { p_role: ROLE }).then(function (res) {
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
      text.textContent = 'Live (updates every 20s)';
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
            $out[$a['id']][] = 'Same mobile number as '
                . implode(', ', array_map(fn($b) => $b['full_name'], $others));
        }
    }
    foreach ($byName as $group) {
        if (count($group) < 2) continue;
        foreach ($group as $a) {
            $out[$a['id']][] = 'Same name as another account (' . count($group) . ' total)';
        }
    }
    return $out;
}

/**
 * Human label for what the applicant's on-device OCR pass (0039) read the
 * ID photo as. Independent of id_type (what the applicant selected at
 * signup) — account_directory() does not currently return id_type, so
 * this screen can show what OCR detected but not a side-by-side compare
 * against what was picked in the dropdown.
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
        default                => 'Unrecognized document',
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
        'type_mismatch' => 'ID type does not match',
        'unreadable'    => 'ID could not be read',
        'name_mismatch' => 'Name does not match',
        'no_id_number'  => 'No ID number found',
        default         => ucfirst(str_replace('_', ' ', $flag)),
    };
}

/** Status, suspension and the two-hour clock, as pills. */
function account_status_pills(array $a): string
{
    $out = [];

    $out[] = match ($a['verification_status']) {
        'verified' => '<span class="pill pill--resolved">Verified</span>',
        'rejected' => '<span class="pill pill--rejected">Rejected</span>',
        default    => '<span class="pill pill--pending">Pending</span>',
    };

    if (!empty($a['is_suspended'])) {
        $out[] = '<span class="pill pill--rejected">Suspended</span>';
    }

    if ($a['verification_status'] === 'pending') {
        $mins = $a['minutes_left'];
        if (!empty($a['is_overdue'])) {
            $out[] = '<span class="pill pill--escalated">Overdue</span>';
        } elseif ($mins !== null) {
            $out[] = '<span class="pill pill--validated">' . (int) $mins . ' min left</span>';
        }
    }

    if (!empty($a['holding_incident'])) {
        $out[] = '<span class="pill pill--assigned">On an incident</span>';
    }

    if (!empty($a['duty_status'])) {
        $out[] = '<span class="pill pill--closed">' . e(status_label((string) $a['duty_status'])) . '</span>';
    }

    return implode(' ', $out);
}

function render_account_detail(
    array $p, string $noun, string $idLabel,
    string $self, string $navFile, string $title, ?array $flash, array $dupes = [],
    array $abuseHistory = [], string $role = 'resident'
): void {
    $pending = $p['verification_status'] === 'pending';

    layout_head($title, $navFile);
    ?>

    <?php if ($flash): ?>
      <div class="flash flash--<?= e($flash['level']) ?>" role="status"><?= e($flash['text']) ?></div>
      <?php
        // Shown once and cleared. Kept out of the flash text itself so a
        // reload, a screenshot of the toast, or a shoulder at the desk
        // does not carry it any further than it has to go.
        $issuedPassword = $_SESSION['issued_password'] ?? null;
        unset($_SESSION['issued_password']);
      ?>
      <?php if ($issuedPassword !== null): ?>
        <div class="issued-password" role="status">
          <span class="issued-password__label">Temporary password</span>
          <code class="issued-password__value"><?= e($issuedPassword) ?></code>
          <span class="issued-password__note">
            Shown once. It is not stored anywhere and cannot be looked up
            again &mdash; if it is lost, issue another.
          </span>
        </div>
      <?php endif; ?>
    <?php endif; ?>

    <!-- Same reasoning as case.php: this page has a deny-reason textarea
         and password fields live on screen, so a background change is
         announced rather than silently swapped in. -->
    <div class="update-banner" id="update-banner" role="status">
      <span>This account has changed since you opened it.</span>
      <a href="<?= e($self) ?>?id=<?= e($p['id']) ?>">Refresh to see it</a>
    </div>

    <div class="case-top">
      <a class="back-link" href="<?= e($self) ?>" aria-label="Back to the list">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"
             stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
          <line x1="20" y1="12" x2="5" y2="12"/><polyline points="11 18 5 12 11 6"/>
        </svg>
      </a>
      <span class="chip-tab"><?= e($noun) ?> Account</span>
      <span class="live-badge" id="live-badge" title="Watching this account for changes">
        <span class="live-dot" aria-hidden="true"></span><span id="live-badge-text">Live (checks every 20s)</span>
      </span>
    </div>

    <div class="case-grid">
      <section class="card card--complaint">
        <h1 class="case-heading"><?= e($p['full_name']) ?></h1>
        <div class="case-flags"><?= account_status_pills($p) ?></div>

        <?php if ($pending && !empty($p['due_at'])): ?>
          <p class="clock-line verif-clock<?= !empty($p['is_overdue']) ? ' is-late' : '' ?>"
             data-due="<?= e($p['due_at']) ?>">
            <span class="verif-text">calculating&hellip;</span>
            Submitted <?= e(long_datetime($p['submitted_at'])) ?>.
          </p>
        <?php elseif ($pending && $p['minutes_left'] !== null): ?>
          <p class="clock-line<?= !empty($p['is_overdue']) ? ' is-late' : '' ?>">
            <?php if (!empty($p['is_overdue'])): ?>
              Past the two-hour window by <?= abs((int) $p['minutes_left']) ?> minutes.
            <?php else: ?>
              <?= (int) $p['minutes_left'] ?> minutes left of the two-hour verification window.
            <?php endif; ?>
            Submitted <?= e(long_datetime($p['submitted_at'])) ?>.
          </p>
        <?php endif; ?>

        <?php if (!empty($p['rejection_reason'])): ?>
          <p class="clock-line is-late">Reason on file: <?= e($p['rejection_reason']) ?></p>
        <?php endif; ?>

        <div class="case-block">
          <h3 class="case-sub">Account Details</h3>
          <dl class="detail-list">
            <dt>Full name</dt><dd><?= e($p['full_name']) ?></dd>
            <dt>Email address</dt><dd><?= e($p['email']) ?></dd>
            <dt>Mobile number</dt><dd class="mono"><?= e($p['mobile_number']) ?></dd>
            <dt>Registered</dt><dd><?= e(long_datetime($p['created_at'])) ?></dd>
          </dl>
        </div>

        <div class="case-block">
          <h3 class="case-sub"><?= e($idLabel) ?></h3>
          <?php if (empty($p['id_image_url'])): ?>
            <p class="case-none">No identification was uploaded. This account cannot be verified until one is.</p>
          <?php else: ?>
            <a class="id-shot" href="<?= e($p['id_image_url']) ?>" target="_blank" rel="noopener">
              <img src="<?= e($p['id_image_url']) ?>" alt="Identification submitted by <?= e($p['full_name']) ?>" loading="lazy">
            </a>
          <?php endif; ?>
        </div>

        <?php if (!empty($p['id_image_url'])): ?>
        <!-- OCR triage (0039): the applicant's own device reads the ID
             photo and flags anything worth a second look before the admin
             opens it. Advisory only — never gates verification, just
             orders the queue and points at what to check first. The data
             has been flowing through account_directory() since 0039; this
             box is the first place any of it actually reaches a screen. -->
        <div class="case-block">
          <h3 class="case-sub">OCR Triage</h3>
          <?php
            $ocrRescanPending = !empty($p['ocr_rescan_requested_at'])
                && (empty($p['ocr_processed_at'])
                    || (string) $p['ocr_processed_at'] < (string) $p['ocr_rescan_requested_at']);
          ?>
          <?php if (empty($p['ocr_detected_type']) && empty($p['ocr_flags'])
                    && empty($p['ocr_extracted_name']) && empty($p['ocr_extracted_number'])): ?>
            <?php if (empty($p['ocr_processed_at'])): ?>
              <p class="case-none">
                OCR has never run on this account &mdash; it registered before this
                feature existed, or on an older app build.
              </p>
            <?php else: ?>
              <p class="case-none">OCR ran and found nothing to flag on this ID.</p>
            <?php endif; ?>
          <?php else: ?>
            <?php if (!empty($p['ocr_flags'])): ?>
              <div class="case-flags">
                <?php foreach ($p['ocr_flags'] as $flag): ?>
                  <span class="pill pill--escalated"><?= e(ocr_flag_label((string) $flag)) ?></span>
                <?php endforeach; ?>
              </div>
            <?php endif; ?>
            <dl class="detail-list">
              <?php if (!empty($p['ocr_detected_type'])): ?>
                <dt>OCR read this as</dt><dd><?= e(id_document_type_label($p['ocr_detected_type'])) ?></dd>
              <?php endif; ?>
              <?php if (!empty($p['ocr_extracted_name'])): ?>
                <dt>Name on the ID</dt><dd><?= e($p['ocr_extracted_name']) ?></dd>
              <?php endif; ?>
              <?php if (!empty($p['ocr_extracted_number'])): ?>
                <dt>ID number</dt><dd class="mono"><?= e($p['ocr_extracted_number']) ?></dd>
              <?php endif; ?>
            </dl>
            <p class="case-none" style="margin-top:8px">
              Advisory only, read off the photo by the applicant's own device &mdash;
              cross-check it against the ID photo above before deciding.
            </p>
          <?php endif; ?>
          <?php if ($ocrRescanPending): ?>
            <p class="control-note" style="margin-top:8px">
              Re-check requested <?= e(relative_time($p['ocr_rescan_requested_at'])) ?> &mdash;
              waiting for them to open the app.
            </p>
          <?php endif; ?>
        </div>
        <?php endif; ?>

        <div class="case-block">
          <h3 class="case-sub">Uploaded Selfie</h3>
          <?php if (empty($p['selfie_url'])): ?>
            <p class="case-none">
              Not submitted. Registration does not currently ask for one &mdash;
              see the note in migration 0013.
            </p>
          <?php else: ?>
            <a class="id-shot id-shot--square" href="<?= e($p['selfie_url']) ?>" target="_blank" rel="noopener">
              <img src="<?= e($p['selfie_url']) ?>" alt="Selfie submitted by <?= e($p['full_name']) ?>" loading="lazy">
            </a>
          <?php endif; ?>
        </div>

        <?php if ($noun === 'Resident'): ?>
          <div class="case-block">
            <h3 class="case-sub">Abuse History</h3>
            <?php if (!$abuseHistory): ?>
              <p class="case-none">No complaints from this resident have been flagged as abusive or fabricated.</p>
            <?php else: ?>
              <p class="clock-line<?= count($abuseHistory) >= 3 ? ' is-late' : '' ?>">
                <strong><?= count($abuseHistory) ?></strong> report<?= count($abuseHistory) === 1 ? '' : 's' ?>
                flagged as abusive or fabricated<?php if (count($abuseHistory) >= 3): ?>
                  &mdash; this account was automatically restricted after the third flag.
                <?php elseif (count($abuseHistory) === 2): ?>
                  &mdash; one more flag will automatically restrict this account.
                <?php else: ?>.<?php endif; ?>
              </p>
              <dl class="detail-list">
                <?php foreach ($abuseHistory as $ab): ?>
                  <dt class="mono"><?= e($ab['tracking_id']) ?></dt>
                  <dd>
                    <?= e($ab['subject']) ?><br>
                    <span class="clock-line" style="margin:0">
                      Denied <?= e(long_datetime($ab['flagged_at'])) ?><?php if (!empty($ab['remark'])): ?>
                        &mdash; <?= e($ab['remark']) ?>
                      <?php endif; ?>
                    </span>
                  </dd>
                <?php endforeach; ?>
              </dl>
            <?php endif; ?>
          </div>
        <?php endif; ?>
      </section>

      <aside class="card card--controls">
        <h3 class="case-sub">Admin Controls</h3>

        <form method="post" class="control-stack">
          <input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>">
          <input type="hidden" name="id" value="<?= e($p['id']) ?>">

          <?php if (!empty($p['id_image_url'])): ?>
            <?php if ($ocrRescanPending): ?>
              <p class="control-note">
                ID re-check requested <?= e(relative_time($p['ocr_rescan_requested_at'])) ?>.
              </p>
            <?php else: ?>
              <button class="btn-secondary" type="submit" name="action" value="request_ocr_rescan">
                Request ID Re-check
              </button>
            <?php endif; ?>
          <?php endif; ?>

          <?php if ($pending): ?>
            <p class="control-note">
              Check the name and address on the document against barangay records
              before approving.
            </p>

            <button class="btn-accept" type="submit" name="action" value="approve"
                    <?= empty($p['id_image_url']) ? 'disabled' : '' ?>>
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2"
                   stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
                <polyline points="20 6 9 17 4 12"/>
              </svg>
              Verify Account
            </button>

            <button class="btn-deny" type="button" data-reveal="deny-panel" aria-expanded="false">
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2"
                   stroke-linecap="round" aria-hidden="true"><line x1="5" y1="12" x2="19" y2="12"/></svg>
              Deny Account
            </button>

            <div class="deny-panel" id="deny-panel" hidden>
              <label class="field-label" for="deny-reason">
                Reason &mdash; the applicant sees this
              </label>
              <textarea id="deny-reason" name="reason" rows="3" maxlength="200"
                        placeholder="e.g. The ID photo is unreadable. Please re-upload a clearer image."></textarea>
              <button class="btn-deny-confirm" type="submit" name="action" value="deny">Confirm denial</button>
            </div>

          <?php elseif (!empty($p['is_suspended'])): ?>
            <p class="control-note">
              This account is suspended and cannot sign in.
              <?php if (!empty($p['rejection_reason'])): ?>
                Reason on file: <?= e($p['rejection_reason']) ?>
              <?php endif; ?>
            </p>
            <button class="btn-accept" type="submit" name="action" value="reinstate">Reinstate Account</button>

          <?php elseif ($p['verification_status'] === 'verified'): ?>
            <p class="control-note">
              Verified<?= !empty($p['holding_incident'])
                  ? '. This tanod is holding a live incident — suspending them sends it back to the queue.'
                  : '.' ?>
            </p>

            <button class="btn-deny" type="button" data-reveal="suspend-panel" aria-expanded="false">
              Suspend Account
            </button>

            <div class="deny-panel" id="suspend-panel" hidden>
              <label class="field-label" for="suspend-reason">Reason for suspension</label>
              <textarea id="suspend-reason" name="reason" rows="3" maxlength="200"
                        placeholder="e.g. Repeatedly filed fraudulent complaints."></textarea>
              <button class="btn-deny-confirm" type="submit" name="action" value="suspend">Confirm suspension</button>
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
            <button class="btn-secondary" type="button" data-reveal="reset-panel"
                    aria-expanded="false">
              Reset Password
            </button>

            <div class="deny-panel" id="reset-panel" hidden>
              <p class="control-note">
                Only do this with the person in front of you and their ID in
                hand. They will be shown a temporary password once &mdash; read
                it to them, do not send it. They must change it when they
                next sign in.
              </p>
              <label class="field-label" for="reset-password">
                Your password &mdash; confirms it is you at the keyboard
              </label>
              <input id="reset-password" type="password" name="password"
                     autocomplete="current-password">
              <button class="btn-deny-confirm" type="submit" name="action"
                      value="reset_password">Issue temporary password</button>
            </div>

          <?php else: ?>
            <p class="control-note">
              This registration was denied. The applicant must register again.
            </p>
          <?php endif; ?>
        </form>
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
          ? 'Past the two-hour verification window by ' + span + '.'
          : span + ' left of the two-hour verification window.';
        el.classList.toggle('is-late', late);
        setTimeout(tick, 20000);
      })();
    })();

    document.querySelectorAll('[data-reveal]').forEach(function (btn) {
      btn.addEventListener('click', function () {
        var panel = document.getElementById(btn.getAttribute('data-reveal'));
        var open  = panel.hasAttribute('hidden');
        if (open) { panel.removeAttribute('hidden'); } else { panel.setAttribute('hidden', ''); }
        btn.setAttribute('aria-expanded', String(open));
        if (open) { panel.querySelector('textarea').focus(); }
      });
    });
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
        { global: { headers: { Authorization: 'Bearer ' + TOKEN } },
          auth: { persistSession: false, autoRefreshToken: false } }
      );
      sb.realtime.setAuth(TOKEN);

      // Excludes minutes_left/is_overdue on purpose — those already tick
      // on their own via the countdown script above and would otherwise
      // raise the banner every 20 seconds for no real change.
      function fingerprint(a) {
        return JSON.stringify([
          a.verification_status, !!a.is_suspended, a.rejection_reason || '',
          !!a.holding_incident, a.duty_status || '',
          a.ocr_detected_type || '', (a.ocr_flags || []).slice().sort(),
          a.ocr_extracted_name || '', a.ocr_extracted_number || '',
          a.ocr_processed_at || '', a.ocr_rescan_requested_at || ''
        ]);
      }
      const INITIAL_FINGERPRINT = <?= json_encode(json_encode([
          $p['verification_status'] ?? null, (bool) ($p['is_suspended'] ?? false),
          $p['rejection_reason'] ?? '', (bool) ($p['holding_incident'] ?? false),
          $p['duty_status'] ?? '', $p['ocr_detected_type'] ?? '',
          array_values($p['ocr_flags'] ?? []), $p['ocr_extracted_name'] ?? '',
          $p['ocr_extracted_number'] ?? '',
          $p['ocr_processed_at'] ?? '', $p['ocr_rescan_requested_at'] ?? '',
      ])) ?>;

      function poll() {
        sb.rpc('account_directory', { p_role: ROLE }).then(function (res) {
          if (res.error || !res.data) return;
          var found = res.data.find(function (a) { return a.id === ACCOUNT_ID; });
          if (!found) { return; } // account left this role's queue entirely (rare) — nothing safe to compare
          if (fingerprint(found) !== INITIAL_FINGERPRINT) {
            document.getElementById('update-banner').classList.add('is-shown');
          }
        });
      }
      setInterval(poll, 20000);
    })();
    </script>

    <?php
    layout_foot();
}
