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
        render_account_detail($person, $noun, $idLabel, $self, $navFile, $title, $flash,
                              $dupes[$person['id']] ?? []);
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

    <?php if ($overdue > 0): ?>
      <div class="flash flash--error" role="alert">
        <?= $overdue ?> registration<?= $overdue === 1 ? '' : 's' ?>
        <?= $overdue === 1 ? 'has' : 'have' ?> passed the two-hour verification window.
      </div>
    <?php endif; ?>

    <section class="panel">
      <header class="panel-bar">
        <h2 class="panel-title">
          <?= e($noun) ?> Accounts (<?= count($accounts) ?>)<?php
            if ($pending > 0): ?> &middot; <span class="pending-count"><?= $pending ?> awaiting review</span><?php endif; ?>
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
          <tbody>
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
    string $self, string $navFile, string $title, ?array $flash, array $dupes = []
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

    <div class="case-top">
      <a class="back-link" href="<?= e($self) ?>" aria-label="Back to the list">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"
             stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
          <line x1="20" y1="12" x2="5" y2="12"/><polyline points="11 18 5 12 11 6"/>
        </svg>
      </a>
      <span class="chip-tab"><?= e($noun) ?> Account</span>
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
      </section>

      <aside class="card card--controls">
        <h3 class="case-sub">Admin Controls</h3>

        <form method="post" class="control-stack">
          <input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>">
          <input type="hidden" name="id" value="<?= e($p['id']) ?>">

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

    <?php
    layout_foot();
}
