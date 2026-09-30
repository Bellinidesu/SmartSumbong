<?php
/**
 * Case detail — Figma nodes 2:2526 (Case review) and 36:1202 (Case Assign).
 *
 * One page, not two. The two frames are the same screen at two points in
 * a complaint's life: while it is pending_review the Admin Controls panel
 * offers Accept and Deny, and once it is validated the same panel becomes
 * the tanod roster with a note, a target date and Dispatch. Splitting them
 * into separate files would mean duplicating the complaint card, the
 * timeline and the map three times over.
 *
 * Every state change goes through a database function, never a bare
 * UPDATE, so the status, the audit trail and the resident's notification
 * move together or not at all.
 */
declare(strict_types=1);

require_once __DIR__ . '/includes/auth.php';
require_once __DIR__ . '/includes/layout.php';

$admin = require_admin();
$db    = db();

$id = (string) ($_GET['id'] ?? '');
if (!preg_match('/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i', $id)) {
    header('Location: cases.php');
    exit;
}

session_start_once();

// ---------- actions ----------
// Post-redirect-get: a refresh after accepting must not accept again.
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $flash = null;
    $level = 'ok';

    if (!csrf_check($_POST['csrf'] ?? null)) {
        $flash = t('That form expired. Please try again.', 'Nag-expire ang form. Subukan muli.');
        $level = 'error';
    } else {
        try {
            switch ($_POST['action'] ?? '') {
                case 'accept':
                    $db->rpc('review_report', [
                        'p_report'   => $id,
                        'p_decision' => 'validate',
                    ]);
                    $flash = t('Complaint accepted. Assign a tanod when you are ready.', 'Tinanggap ang sumbong. Mag-assign ng tanod kapag handa ka na.');
                    break;

                case 'deny':
                    $db->rpc('review_report', [
                        'p_report'   => $id,
                        'p_decision' => 'reject',
                        'p_remark'   => trim((string) ($_POST['reason'] ?? '')),
                        // Checkbox, so its mere presence in $_POST means
                        // checked — absent means unchecked, never sent
                        // by the browser at all, so an ordinary honest-
                        // mistake denial never touches the resident's
                        // strike count.
                        'p_abusive'  => isset($_POST['abusive']),
                    ]);
                    $flash = t('Complaint denied. The resident has been told why.', 'Tinanggihan ang sumbong. Nasabihan na ang residente kung bakit.');
                    break;

                case 'dispatch':
                    $tanod = trim((string) ($_POST['tanod'] ?? ''));
                    if ($tanod === '') {
                        throw new SupabaseError(t('Choose a tanod before dispatching.', 'Pumili muna ng tanod bago mag-dispatch.'));
                    }

                    // The target date is required (0071): set before the
                    // dispatch, told to the resident, and on the tanod's
                    // ticket. Instructions are checked here and by the RPC.
                    $target = trim((string) ($_POST['target'] ?? ''));
                    if ($target === '') {
                        throw new SupabaseError(t('Set a target resolution date before dispatching.', 'Magtakda muna ng target na petsa bago mag-dispatch.'));
                    }
                    if (trim((string) ($_POST['note'] ?? '')) === '') {
                        throw new SupabaseError(t('Write instructions for the tanod before dispatching.', 'Sumulat muna ng tagubilin para sa tanod bago mag-dispatch.'));
                    }
                    $iso = (new DateTimeImmutable($target, new DateTimeZone('Asia/Manila')))
                        ->format(DateTimeInterface::ATOM);
                    $db->rpc('set_resolution_target', [
                        'p_report' => $id,
                        'p_due'    => $iso,
                    ]);

                    $db->rpc('admin_dispatch', [
                        'p_report'       => $id,
                        'p_tanod'        => $tanod,
                        'p_instructions' => trim((string) ($_POST['note'] ?? '')) ?: null,
                    ]);
                    $flash = t('Dispatched. The tanod has been notified.', 'Na-dispatch. Naabisuhan na ang tanod.');
                    break;

                // 0057 — the resident's appeal of a denial. Grants it
                // straight to 'validated' with a fresh SLA window; there
                // is no separate "deny the appeal" action because
                // declining is simply not acting on it, the same way an
                // unactioned reopen request just stays finished.
                case 'appeal_grant':
                    $db->rpc('appeal_report', [
                        'p_report' => $id,
                        'p_remark' => trim((string) ($_POST['remark'] ?? '')) ?: null,
                    ]);
                    $flash = t('Appeal granted. The complaint is back with the barangay.', 'Pinagbigyan ang apela. Nasa barangay na muli ang sumbong.');
                    break;

                // 0070 — the admin moves a live dispatch: to a named
                // tanod, or back to the system's nearest-tanod routing.
                case 'reroute':
                    $to = trim((string) ($_POST['to'] ?? ''));
                    $db->rpc('admin_reroute_dispatch', [
                        'p_dispatch' => (string) ($_POST['dispatch'] ?? ''),
                        'p_reason'   => trim((string) ($_POST['reason'] ?? '')),
                        'p_to'       => $to !== '' ? $to : null,
                    ]);
                    $flash = $to !== ''
                        ? t('Rerouted. The new tanod has been notified.', 'Nailipat. Naabisuhan na ang bagong tanod.')
                        : t('Rerouted. The system is finding the nearest available tanod.', 'Nailipat. Hinahanap ng sistema ang pinakamalapit na available na tanod.');
                    break;

                // 0072 — escalation is the admin's referral to an outside
                // office. The complaint closes here; the resident is told
                // where it went.
                // 0073 — Approve Complaint Resolution.
                case 'approve_resolution':
                    $db->rpc('approve_resolution', ['p_report' => $id]);
                    $flash = t('Resolution approved. The resident has been told the complaint is resolved.', 'Naaprubahan ang resolusyon. Nasabihan na ang residente na nalutas na ang sumbong.');
                    break;

                case 'reject_resolution':
                    $db->rpc('reject_resolution', [
                        'p_report' => $id,
                        'p_reason' => trim((string) ($_POST['reason'] ?? '')),
                    ]);
                    $flash = t('Returned to the tanod with your reason.', 'Ibinalik sa tanod kasama ang iyong dahilan.');
                    break;

                // 0073 — Update Resolution Status.
                case 'set_status':
                    $db->rpc('admin_set_status', [
                        'p_report' => $id,
                        'p_status' => (string) ($_POST['status'] ?? ''),
                        'p_remark' => trim((string) ($_POST['remark'] ?? '')) ?: null,
                    ]);
                    $flash = t('Status updated. The resident has been told.', 'Na-update ang katayuan. Nasabihan na ang residente.');
                    break;

                // 0073 — Manage Escalation Request.
                case 'approve_escalation':
                    $agency = trim((string) ($_POST['agency'] ?? ''));
                    if ($agency === 'other') {
                        $agency = trim((string) ($_POST['agency_other'] ?? ''));
                    }
                    $db->rpc('approve_escalation', [
                        'p_request' => (string) ($_POST['request'] ?? ''),
                        'p_office'  => $agency,
                        'p_note'    => trim((string) ($_POST['note'] ?? '')) ?: null,
                    ]);
                    $flash = t('Escalation approved. The resident and the tanod have been told.', 'Naaprubahan ang pag-escalate. Nasabihan na ang residente at ang tanod.');
                    break;

                case 'deny_escalation':
                    $db->rpc('deny_escalation', [
                        'p_request' => (string) ($_POST['request'] ?? ''),
                        'p_reason'  => trim((string) ($_POST['reason'] ?? '')),
                    ]);
                    $flash = t('Escalation request denied. The tanod has been told why.', 'Tinanggihan ang hiling na i-escalate. Nasabihan na ang tanod kung bakit.');
                    break;

                // 0073 — Monitor Real-Time Map (resident): published incidents.
                case 'set_public':
                    $db->rpc('set_report_public', [
                        'p_report' => $id,
                        'p_public' => !empty($_POST['public']),
                    ]);
                    $flash = !empty($_POST['public'])
                        ? t("Shown on residents' map (category and status only).", 'Ipinapakita na sa mapa ng mga residente (kategorya at katayuan lamang).')
                        : t("Removed from residents' map.", 'Inalis sa mapa ng mga residente.');
                    break;

                case 'refer':
                    $agency = trim((string) ($_POST['agency'] ?? ''));
                    if ($agency === 'other') {
                        $agency = trim((string) ($_POST['agency_other'] ?? ''));
                    }
                    $db->rpc('refer_report', [
                        'p_report' => $id,
                        'p_agency' => $agency,
                        'p_note'   => trim((string) ($_POST['note'] ?? '')) ?: null,
                    ]);
                    $flash = t('Escalated. The resident has been told where their complaint went.', 'Na-escalate na. Nasabihan na ang residente kung saan napunta ang sumbong.');
                    break;

                // 0072 — the barangay's answer in the resident's question thread.
                case 'resident_reply':
                    $db->rpc('post_report_message', [
                        'p_report' => $id,
                        'p_body'   => trim((string) ($_POST['body'] ?? '')),
                    ]);
                    $flash = t('Reply sent to the resident.', 'Naipadala ang sagot sa residente.');
                    break;

                // 0069 — a reply into the tanod's dispatch window. The
                // tanod is notified; the resident never sees it.
                case 'dispatch_reply':
                    $db->rpc('post_dispatch_update', [
                        'p_dispatch' => (string) ($_POST['dispatch'] ?? ''),
                        'p_body'     => trim((string) ($_POST['body'] ?? '')),
                    ]);
                    $flash = t('Sent to the tanod.', 'Naipadala sa tanod.');
                    break;

                default:
                    $flash = t('Unknown action.', 'Hindi kilalang aksyon.');
                    $level = 'error';
            }
        } catch (SupabaseError $ex) {
            $flash = safe_error($ex);
            $level = 'error';
        } catch (Exception $ex) {
            $flash = t('That date could not be read. Use the date picker.', 'Hindi mabasa ang petsang iyon. Gamitin ang date picker.');
            $level = 'error';
        }
    }

    $_SESSION['flash'] = ['text' => $flash, 'level' => $level];
    header('Location: case.php?id=' . urlencode($id));
    exit;
}

$flash = $_SESSION['flash'] ?? null;
unset($_SESSION['flash']);

// ---------- data ----------
$error = null;
$report = null;
$media = $logs = $dispatches = $roster = [];
$policy = null;
$feedback = null;
$proof = [];
$proofCount = 0;
$thread = [];      // dispatch id => dispatch_updates rows (0069)
$messages = [];    // the resident's question thread (0072)
$escRequest = null; // a tanod's pending escalation request (0073)
$threadMedia = []; // update id => its photos

// Two parallel rounds (branch B) in place of about nine requests one
// after another: everything keyed on the complaint id at once, then what
// needs the first round's answers (its category, its dispatches, whether
// it is still to be judged or assigned). With the database in Mumbai
// every sequential round trip was a visible part of opening a case.
$trail = [];
$abuseHistory = [];
try {
    $first = $db->selectMany([
        'report' => ['reports', [
            'select' => 'id,tracking_id,subject,description,category,status,is_anonymous,'
                      . 'latitude,longitude,location_label,due_at,reopened_count,'
                      . 'referred_to,referral_note,referred_at,followed_up_at,follow_up_count,'
                      . 'resolution_submitted_at,resolution_returned_reason,is_public,'
                      . 'appealed_at,awaiting_unit_since,dispatch_attempts,resolved_at,closed_at,created_at,'
                      . 'resident:users!reports_resident_id_fkey(id,full_name,mobile_number)',
            'id'         => 'eq.' . $id,
            'deleted_at' => 'is.null',
            'limit'      => '1',
        ]],
        'media' => ['report_media', [
            'select'    => 'id,media_url,mime_type,bytes,uploaded_at',
            'report_id' => 'eq.' . $id,
            'order'     => 'uploaded_at.asc',
        ]],
        'logs' => ['status_logs', [
            'select'    => 'id,old_status,new_status,remark,is_system,created_at,'
                         . 'by:users!status_logs_changed_by_fkey(full_name,role)',
            'report_id' => 'eq.' . $id,
            'order'     => 'created_at.asc',
        ]],
        'dispatches' => ['dispatches', [
            'select'    => 'id,state,assigned_at,accept_due_at,accepted_at,admin_instructions,'
                         . 'rerouted_at,reroute_reason,field_report_text,resolved_at,'
                         . 'tanod:users!dispatches_tanod_id_fkey(id,full_name,mobile_number)',
            'report_id' => 'eq.' . $id,
            'order'     => 'assigned_at.desc',
        ]],
        // Resident's post-resolution rating, if any. feedback_read (0003)
        // already lets an admin see any resident's row, so this is a
        // plain select, not a new RPC — same pattern as media and logs.
        'feedback' => ['feedback', [
            'select'    => 'rating,comment,submitted_at',
            'report_id' => 'eq.' . $id,
            'limit'     => '1',
        ]],
        // Tamper check on this complaint's trail. Cheap (a handful of
        // hashes) and it makes the guarantee visible rather than a claim
        // in a document nobody reads. Optional: a failure shows no badge.
        'trail' => ['rpc/verify_report_trail', ['p_report' => $id], true],
    ]);
    $report = $first['report'][0] ?? null;

    if ($report) {
        $media      = $first['media'];
        $logs       = $first['logs'];
        $dispatches = $first['dispatches'];
        $feedback   = $first['feedback'][0] ?? null;
        $trail      = $first['trail'] instanceof SupabaseError ? [] : (array) $first['trail'];
    }
} catch (SupabaseError $ex) {
    $error = safe_error($ex);
}

if (!$report && !$error) {
    $error = t('That complaint could not be found. It may have been archived.', 'Hindi mahanap ang sumbong na iyon. Maaaring naka-archive na ito.');
}

/** The dispatch that is currently live, if any. */
$active = null;
foreach ($dispatches as $d) {
    if (in_array($d['state'], ['assigned', 'accepted'], true)) {
        $active = $d;
        break;
    }
}

$status   = $report['status'] ?? '';
$canJudge = $status === 'pending_review';

// 0057 — is there a live appeal request sitting on this rejected
// complaint? $logs is oldest-first, so the newest entry decides: an
// appeal that has already been granted moved the status off 'rejected'
// (this branch never runs then), and an appeal that was granted and the
// case rejected again would leave a newer, different-remarked entry on
// top — so reading only the last row is enough to tell "pending" from
// "already asked about, nothing since".
$appealReason = null;
if ($status === 'rejected' && $logs) {
    $last = $logs[count($logs) - 1];
    if (($last['new_status'] ?? '') === 'rejected'
        && str_starts_with((string) ($last['remark'] ?? ''), 'Resident appealed the rejection:')) {
        $appealReason = trim(substr((string) $last['remark'], strlen('Resident appealed the rejection:')));
    }
}

$canAssign = in_array($status, ['validated', 'in_progress', 'offline_investigation'], true)
             && $active === null;

if ($report && !$error) {
    $second = [
        'sla' => ['sla_policies', [
            'select'   => 'resolution_hours,accept_minutes,auto_dispatch_on_file',
            'category' => 'eq.' . $report['category'],
            'limit'    => '1',
        ]],
    ];

    // Field proof. dispatch_media is keyed to the dispatch rather
    // than the report, so it needs the ids from above — and it is
    // fetched at all because until now the admin had no way to see
    // it. 0024 gave the filing resident a look at these photos
    // months before the barangay could. (Pulled in from the
    // Codespaces copy, 5 Sep 2026 — see the tracking doc.)
    $liveIds = array_values(array_filter(array_map(
        fn($d) => $d['id'] ?? null,
        $dispatches
    )));
    if ($liveIds) {
        $second['proof'] = ['dispatch_media', [
            'select'      => 'dispatch_id,update_id,media_url,mime_type,bytes,uploaded_at',
            'dispatch_id' => 'in.(' . implode(',', $liveIds) . ')',
            'order'       => 'uploaded_at.asc',
        ]];
    }

    // The dispatch window's thread (0069): the tanod's updates and
    // steps, and admin replies. Optional — the page stands without it.
    if ($liveIds) {
        $second['escalation'] = ['escalation_requests', [
            'select'    => 'id,reason,suggested_office,created_at,requester:users!escalation_requests_requested_by_fkey(full_name)',
            'report_id' => 'eq.' . $id,
            'status'    => 'eq.pending',
            'limit'     => '1',
        ], true];
        $second['messages'] = ['report_messages', [
            'select'    => 'id,from_barangay,body,created_at',
            'report_id' => 'eq.' . $id,
            'order'     => 'created_at.asc',
        ], true];
        $second['thread'] = ['dispatch_updates', [
            'select'      => 'id,dispatch_id,author_id,kind,step,body,created_at',
            'dispatch_id' => 'in.(' . implode(',', $liveIds) . ')',
            'order'       => 'created_at.asc',
        ], true];
    }

    // Context for the Deny panel: has this resident been flagged abusive
    // before, and how many times. Fetched only while it can actually matter
    // — once a decision is already made the count cannot change what
    // happened here. resident_abuse_reports() returns full rows because
    // accounts.php's profile panel needs them too; this screen only needs
    // count($abuseHistory). Optional: not worth blocking the review over.
    if ($canJudge && !empty($report['resident']['id'])) {
        $second['abuse'] = ['rpc/resident_abuse_reports', ['p_user' => $report['resident']['id']], true];
    }

    // Only when nobody is on the case already. One round trip saved on
    // every screen that will not show it.
    if ($canAssign || $active) {
        $second['roster'] = ['rpc/tanod_roster', ['p_report' => $id], true];
    }

    try {
        $got = $db->selectMany($second);
        $policy = $got['sla'][0] ?? null;
        foreach ($got['proof'] ?? [] as $r) {
            $proofCount++;
            // An update's photos belong to the thread; untagged rows are
            // the final field report's proof.
            if (!empty($r['update_id'])) {
                $threadMedia[$r['update_id']][] = $r;
                continue;
            }
            $proof[$r['dispatch_id']][] = $r;
        }
        if (isset($got['escalation']) && !$got['escalation'] instanceof SupabaseError) {
            $escRequest = $got['escalation'][0] ?? null;
        }
        if (isset($got['messages']) && !$got['messages'] instanceof SupabaseError) {
            $messages = (array) $got['messages'];
        }
        if (isset($got['thread']) && !$got['thread'] instanceof SupabaseError) {
            foreach ((array) $got['thread'] as $u) {
                $thread[$u['dispatch_id']][] = $u;
            }
        }
        if (isset($got['abuse']) && !$got['abuse'] instanceof SupabaseError) {
            $abuseHistory = (array) $got['abuse'];
        }
        if (isset($got['roster'])) {
            if ($got['roster'] instanceof SupabaseError) {
                // The reroute list is a convenience; only the assign
                // screen cannot stand without it.
                if ($canAssign) {
                    $error = safe_error($got['roster']);
                }
            } else {
                $roster = (array) $got['roster'];
            }
        }
    } catch (SupabaseError $ex) {
        $error = safe_error($ex);
    }
}

layout_head(t('Case Review', 'Pagsusuri ng Kaso'), 'cases.php');
?>

<?php if ($flash): ?>
  <div class="flash flash--<?= e($flash['level']) ?>" role="status"><?= e($flash['text']) ?></div>
<?php endif; ?>

<?php if ($error): ?>
  <div class="alert-bar" role="alert"><?= e($error) ?></div>
  <p><a class="back-link" href="cases.php">&larr; <?= e(t('Back to case reports', 'Bumalik sa mga sumbong')) ?></a></p>
  <?php layout_foot(); exit; ?>
<?php endif; ?>

<!-- This page has live inputs on it (a deny reason, a dispatch note, a
     target date) that a silent data swap would risk wiping out mid-type.
     So unlike cases.php/dashboard.php, realtime here announces rather
     than rewrites — the admin chooses when to reload. -->
<div class="update-banner" id="update-banner" role="status">
  <span><?= e(t('This case has new activity since you opened it.', 'May bagong aktibidad sa kasong ito mula nang buksan mo.')) ?></span>
  <a href="case.php?id=<?= e($id) ?>"><?= e(t('Refresh to see it', 'I-refresh para makita')) ?></a>
</div>

<div class="case-top">
  <a class="back-link" href="cases.php" aria-label="<?= e(t('Back to case reports', 'Bumalik sa mga sumbong')) ?>">
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"
         stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
      <line x1="20" y1="12" x2="5" y2="12"/><polyline points="11 18 5 12 11 6"/>
    </svg>
  </a>
  <span class="chip-tab"><?= e(t('Original Report', 'Orihinal na Ulat')) ?></span>
  <span class="live-badge" id="live-badge" title="<?= e(t('Watching this case for new activity', 'Binabantayan ang bagong aktibidad sa kasong ito')) ?>">
    <span class="live-dot" aria-hidden="true"></span><span id="live-badge-text"><?= e(t('Live', 'Live')) ?></span>
  </span>
</div>

<div class="case-grid<?= $canAssign ? ' case-grid--assign' : '' ?>">

  <!-- ---------- the complaint itself ---------- -->
  <section class="card card--complaint">
    <h1 class="case-heading">
      <?= e($report['tracking_id']) ?>: <?= e(category_label($report['category'])) ?>
      <!-- Admins read this number out over the phone and paste it into
           texts to residents. One click beats selecting it by hand. -->
      <button class="copy-id" type="button" data-copy="<?= e($report['tracking_id']) ?>"
              title="<?= e(t('Copy complaint ID', 'Kopyahin ang ID ng sumbong')) ?>" aria-label="<?= e(t('Copy complaint ID', 'Kopyahin ang ID ng sumbong')) ?>">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9"
             stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
          <rect x="9" y="9" width="11" height="11" rx="2"/>
          <path d="M5 15V5a2 2 0 0 1 2-2h10"/>
        </svg>
      </button>
    </h1>

    <p class="case-filed">
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"
           stroke-linecap="round" aria-hidden="true">
        <circle cx="12" cy="12" r="9"/><polyline points="12 7 12 12 15 14"/>
      </svg>
      <?= e(t('Filed on', 'Isinampa noong')) ?> <?= e(long_datetime($report['created_at'])) ?>
    </p>
    <?php if (!empty($report['location_label'])): ?>
      <!-- The street saved with the complaint (0068): a label read off the
           map, not something the resident typed — the coordinates on the
           map below stay the record. -->
      <p class="case-filed case-place" title="<?= e(t('Nearest street, from OpenStreetMap', 'Pinakamalapit na kalye, mula sa OpenStreetMap')) ?>">
        <svg class="loc-pin" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12 21s-7-6.2-7-11.5A7 7 0 0 1 19 9.5C19 14.8 12 21 12 21z"/><circle cx="12" cy="9.5" r="2.5"/></svg>
        <?= e(t('Near', 'Malapit sa')) ?> <?= e($report['location_label']) ?>
      </p>
    <?php endif; ?>
    <!-- Filled in by the map script: the Project NOAH hazard levels at
         this spot, only when there is one. -->
    <p class="case-filed case-hazard" id="case-hazard" hidden></p>
    <p class="case-filed case-zone" id="case-zone" hidden></p>

    <?php if (!empty($report['due_at'])
              && !in_array($status, ['resolved','closed','archived','rejected'], true)): ?>
      <!-- A date makes you do the arithmetic; a countdown does not. -->
      <p class="sla-countdown" data-due="<?= e($report['due_at']) ?>">
        <span class="sla-text"><?= e(t('calculating…', 'kinakalkula…')) ?></span>
      </p>
    <?php endif; ?>

    <div class="case-flags">
      <span class="pill pill--<?= e(status_class($status)) ?>"><?= e(status_label($status)) ?></span>
      <?php if (!empty($report['referred_to'])): ?>
        <span class="pill pill--escalated"><?= e(t('Escalated to ', 'In-escalate sa ')) . e($report['referred_to']) ?></span>
      <?php endif; ?>
      <?php if (!empty($report['resolution_submitted_at'])): ?>
        <span class="pill pill--pending"><?= e(t('Resolution awaiting approval', 'Naghihintay ng pag-apruba ang resolusyon')) ?></span>
      <?php endif; ?>
      <?php if ($escRequest): ?>
        <span class="pill pill--pending"><?= e(t('Escalation requested', 'Hiniling na i-escalate')) ?></span>
      <?php endif; ?>
      <?php if (!empty($report['is_public'])): ?>
        <span class="pill"><?= e(t("On residents' map", 'Nasa mapa ng mga residente')) ?></span>
      <?php endif; ?>
      <?php if (!empty($report['followed_up_at'])): ?>
        <span class="pill pill--pending" title="<?= e(t('Last follow-up ', 'Huling follow-up ') . relative_time($report['followed_up_at'])) ?>">
          <?= e(t('Resident followed up', 'Nag-follow up ang residente')) ?><?= (int) ($report['follow_up_count'] ?? 0) > 1 ? ' ' . (int) $report['follow_up_count'] . '&times;' : '' ?>
        </span>
      <?php endif; ?>
      <?php if (!empty($report['awaiting_unit_since']) && !$active): ?>
        <span class="pill pill--rejected"><?= e(t('Awaiting a unit since', 'Naghihintay ng tanod mula')) ?> <?= e(relative_time($report['awaiting_unit_since'])) ?></span>
      <?php endif; ?>
      <?php if (($report['reopened_count'] ?? 0) > 0): ?>
        <span class="pill pill--pending"><?= e(t('Reopened', 'Binuksang muli')) ?> <?= (int) $report['reopened_count'] ?>&times;</span>
      <?php endif; ?>
      <?php if (!empty($report['appealed_at'])): ?>
        <span class="pill pill--pending" title="<?= e(t('Reinstated on appeal', 'Ibinalik dahil sa apela')) ?>"><?= e(t('Appealed', 'Inapela')) ?></span>
      <?php endif; ?>
    </div>

    <div class="case-block">
      <h3 class="case-sub"><?= e(t('Subject', 'Paksa')) ?></h3>
      <p class="case-body"><?= e($report['subject']) ?></p>
    </div>

    <div class="case-block">
      <h3 class="case-sub"><?= e(t('Problem Description', 'Paglalarawan ng Problema')) ?></h3>
      <p class="case-body"><?= nl2br(e($report['description'])) ?></p>
    </div>

    <div class="case-block">
      <h3 class="case-sub"><?= e(t('Attached Evidence', 'Kalakip na Ebidensya')) ?></h3>
      <?php if (!$media): ?>
        <p class="case-none"><?= e(t('No photo or video was attached to this complaint.', 'Walang larawan o video na kalakip sa sumbong na ito.')) ?></p>
      <?php else: ?>
        <div class="media-strip">
          <?php foreach ($media as $m): ?>
            <?php $mime = (string) ($m['mime_type'] ?? ''); ?>
            <?php if (str_starts_with($mime, 'video/')): ?>
              <!-- Video support has existed since 0033, but this viewer used to
                   render every attachment as an <img> regardless of mime_type —
                   a video just showed as a broken image with no way to watch
                   it. Not wrapped in the usual <a>: a click on the native
                   controls would otherwise also fire the anchor's navigation. -->
              <div class="media-thumb media-thumb--video">
                <video controls preload="metadata" playsinline>
                  <source src="<?= e($m['media_url']) ?>" type="<?= e($mime) ?>">
                  <?= e(t('Your browser cannot play this video.', 'Hindi ma-play ng browser ang video na ito.')) ?>
                  <a href="<?= e($m['media_url']) ?>" target="_blank" rel="noopener"><?= e(t('Open it directly', 'Buksan ito nang direkta')) ?></a>.
                </video>
                <span class="media-size"><?= e(byte_size((int) $m['bytes'])) ?></span>
              </div>
            <?php else: ?>
              <a class="media-thumb" href="<?= e($m['media_url']) ?>" target="_blank" rel="noopener">
                <img src="<?= e($m['media_url']) ?>" alt="<?= e(t('Evidence submitted with ', 'Ebidensyang isinumite kasama ng ') . $report['tracking_id']) ?>" loading="lazy">
                <span class="media-size"><?= e(byte_size((int) $m['bytes'])) ?></span>
              </a>
            <?php endif; ?>
          <?php endforeach; ?>
        </div>
      <?php endif; ?>
    </div>

    <?php
    // Only dispatches that were actually resolved carry a field
    // report. A rerouted or expired one has a reason, not an outcome,
    // and that belongs in the timeline rather than here. (Pulled in
    // from the Codespaces copy, 5 Sep 2026 — see the tracking doc.)
    $resolved = array_values(array_filter(
        $dispatches,
        fn($d) => ($d['state'] ?? '') === 'resolved'
    ));
    ?>
    <?php if ($resolved): ?>
      <div class="case-block">
        <h3 class="case-sub"><?= e(t('Field Report', 'Ulat mula sa Lugar')) ?></h3>
        <?php foreach ($resolved as $d): ?>
          <?php $shots = $proof[$d['id']] ?? []; ?>
          <p class="case-meta">
            <?= e($d['tanod']['full_name'] ?? t('Barangay tanod', 'Tanod ng barangay')) ?>
            <?php if (!empty($d['resolved_at'])): ?>
              &middot; <?= e(long_datetime($d['resolved_at'])) ?>
            <?php endif; ?>
          </p>
          <?php if (!empty($d['field_report_text'])): ?>
            <p class="case-body"><?= nl2br(e($d['field_report_text'])) ?></p>
          <?php else: ?>
            <p class="case-none"><?= e(t('No narrative was submitted.', 'Walang isinumiteng salaysay.')) ?></p>
          <?php endif; ?>

          <?php if ($shots): ?>
            <div class="media-strip">
              <?php foreach ($shots as $m): ?>
                <a class="media-thumb" href="<?= e($m['media_url']) ?>"
                   target="_blank" rel="noopener">
                  <img src="<?= e($m['media_url']) ?>"
                       alt="<?= e(t('Proof photo for ', 'Larawang patunay para sa ') . $report['tracking_id']) ?>"
                       loading="lazy">
                  <span class="media-size"><?= e(byte_size((int) $m['bytes'])) ?></span>
                </a>
              <?php endforeach; ?>
            </div>
          <?php else: ?>
            <p class="case-none"><?= e(t('No photo proof was attached.', 'Walang kalakip na larawang patunay.')) ?></p>
          <?php endif; ?>
        <?php endforeach; ?>
      </div>
    <?php endif; ?>

    <?php
    // The dispatch window (0069): what the tanod sent from the field, the
    // steps, and the barangay's replies — newest dispatch first, only
    // those with a thread or still open for one.
    $threaded = array_values(array_filter(
        $dispatches,
        fn($d) => !empty($thread[$d['id']]) || ($d['state'] ?? '') === 'accepted'
    ));
    ?>
    <?php if ($threaded): ?>
      <div class="case-block">
        <h3 class="case-sub"><?= e(t('Dispatch Updates', 'Mga Update sa Dispatch')) ?></h3>
        <?php foreach ($threaded as $d): ?>
          <?php $tanodName = $d['tanod']['full_name'] ?? t('Tanod', 'Tanod'); ?>
          <p class="case-meta"><?= e($tanodName) ?></p>
          <?php if (empty($thread[$d['id']])): ?>
            <p class="case-none"><?= e(t('No updates yet.', 'Wala pang update.')) ?></p>
          <?php else: ?>
            <ol class="thread">
              <?php foreach ($thread[$d['id']] as $u): ?>
                <?php if ($u['kind'] === 'step'): ?>
                  <li class="thread-step">
                    <?= e($u['step'] === 'arrived'
                        ? t('Tanod arrived', 'Nakarating ang tanod')
                        : t('Tanod on the way', 'Papunta na ang tanod')) ?>
                    &middot; <?= e(long_datetime($u['created_at'])) ?>
                  </li>
                <?php else: ?>
                  <?php $fromTanod = $u['author_id'] === ($d['tanod']['id'] ?? null); ?>
                  <li class="thread-msg <?= $fromTanod ? 'is-tanod' : 'is-admin' ?>">
                    <span class="thread-who"><?= e($fromTanod ? $tanodName : t('Barangay', 'Barangay')) ?></span>
                    <?php if (!empty($u['body'])): ?>
                      <p><?= nl2br(e($u['body'])) ?></p>
                    <?php endif; ?>
                    <?php if (!empty($threadMedia[$u['id']])): ?>
                      <div class="thread-media">
                        <?php foreach ($threadMedia[$u['id']] as $m): ?>
                          <a href="<?= e($m['media_url']) ?>" target="_blank" rel="noopener">
                            <img src="<?= e($m['media_url']) ?>" alt="<?= e(t('Update photo', 'Larawan ng update')) ?>" loading="lazy">
                          </a>
                        <?php endforeach; ?>
                      </div>
                    <?php endif; ?>
                    <time><?= e(long_datetime($u['created_at'])) ?></time>
                  </li>
                <?php endif; ?>
              <?php endforeach; ?>
            </ol>
          <?php endif; ?>
          <?php if (($d['state'] ?? '') === 'accepted'): ?>
            <form method="post" class="thread-reply">
              <input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>">
              <input type="hidden" name="action" value="dispatch_reply">
              <input type="hidden" name="dispatch" value="<?= e($d['id']) ?>">
              <textarea name="body" rows="2" maxlength="2000" required
                        placeholder="<?= e(t('Reply to the tanod…', 'Sumagot sa tanod…')) ?>"></textarea>
              <button type="submit" class="thread-send"><?= e(t('Send', 'Ipadala')) ?></button>
            </form>
          <?php endif; ?>
        <?php endforeach; ?>
      </div>
    <?php endif; ?>

    <?php
    // 0072: the resident's own questions about this complaint, and the
    // barangay's answers — the resident sees all of it in their app.
    $canMessage = !in_array($status, ['archived', 'cancelled'], true);
    ?>
    <?php if ($messages || $canMessage): ?>
      <div class="case-block" id="resident-messages">
        <h3 class="case-sub"><?= e(t('Questions from the Resident', 'Mga Tanong ng Residente')) ?></h3>
        <?php if (!$messages): ?>
          <p class="case-none"><?= e(t('No questions yet. The resident can ask from their app, and you can write to them first.', 'Wala pang tanong. Maaaring magtanong ang residente mula sa app, at maaari mo rin silang sulatan muna.')) ?></p>
        <?php else: ?>
          <ol class="thread">
            <?php foreach ($messages as $m): ?>
              <li class="thread-msg <?= !empty($m['from_barangay']) ? 'is-admin' : 'is-tanod' ?>">
                <span class="thread-who"><?= e(!empty($m['from_barangay']) ? t('Barangay', 'Barangay') : t('Resident', 'Residente')) ?></span>
                <p><?= nl2br(e($m['body'])) ?></p>
                <time><?= e(long_datetime($m['created_at'])) ?></time>
              </li>
            <?php endforeach; ?>
          </ol>
        <?php endif; ?>
        <?php if ($canMessage): ?>
          <form method="post" class="thread-reply">
            <input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>">
            <input type="hidden" name="action" value="resident_reply">
            <textarea name="body" rows="2" maxlength="1000" required
                      placeholder="<?= e(t('Answer the resident…', 'Sagutin ang residente…')) ?>"></textarea>
            <button type="submit" class="thread-send"><?= e(t('Send', 'Ipadala')) ?></button>
          </form>
        <?php endif; ?>
      </div>
    <?php endif; ?>
  </section>

  <!-- ---------- admin controls ---------- -->
  <aside class="card card--controls">
    <h3 class="case-sub"><?= e(t('Admin Controls', 'Kontrol ng Admin')) ?></h3>

    <?php if ($canJudge): ?>
      <form method="post" class="control-stack" id="review-form">
        <input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>">

        <p class="kbd-hint"><?= e(t('Press', 'Pindutin ang')) ?> <kbd>A</kbd> <?= e(t('to accept,', 'para tanggapin,')) ?> <kbd>D</kbd> <?= e(t('to deny.', 'para tanggihan.')) ?></p>

        <!-- formnovalidate: the hidden denial reason must never stop an
             Accept (Rose, 27 Sep 2026 — Accept did nothing). -->
        <button class="btn-accept" type="submit" name="action" value="accept" formnovalidate>
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2"
               stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
            <polyline points="20 6 9 17 4 12"/>
          </svg>
          <?= e(t('Validate Report', 'I-validate ang Ulat')) ?>
        </button>

        <button class="btn-deny" type="button" id="deny-toggle" aria-expanded="false"
                aria-controls="deny-panel">
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2"
               stroke-linecap="round" aria-hidden="true"><line x1="5" y1="12" x2="19" y2="12"/></svg>
          <?= e(t('Reject Report', 'Tanggihan ang Ulat')) ?>
        </button>

        <div class="deny-panel" id="deny-panel" hidden>
          <label for="reason" class="field-label">
            <?= e(t('Reason for denial — the resident sees this', 'Dahilan ng pagtanggi — makikita ito ng residente')) ?>
          </label>
          <textarea id="reason" name="reason" rows="3" maxlength="200"
                    placeholder="<?= e(t('e.g. Outside barangay jurisdiction — refer to the city ENRO.', 'hal. Labas sa sakop ng barangay — i-refer sa ENRO ng lungsod.')) ?>"></textarea>

          <label class="field-check">
            <input type="checkbox" name="abusive" value="1">
            <?= e(t('Flag as abusive or fabricated', 'Markahang mapang-abuso o gawa-gawa')) ?>
          </label>
          <p class="control-note">
            <?= e(t('Only for a fake, malicious, or bad-faith report — not an honest mistake like the wrong barangay or a duplicate. Three flagged reports from the same resident automatically restrict their account from filing new ones, the same way Suspend does today.',
                    'Para lamang sa pekeng ulat, may masamang layunin, o hindi tapat — hindi sa tapat na pagkakamali gaya ng maling barangay o doble. Kapag tatlong ulat ng iisang residente ang namarkahan, awtomatikong hindi na siya makakapagsampa ng bago, gaya ng Suspend.')) ?>
            <?php if (count($abuseHistory) > 0): ?>
              <?= e(t('This resident already has', 'Mayroon nang')) ?>
              <strong><?= (int) count($abuseHistory) ?></strong>
              <?= e(t('on file', 'na naitala sa residenteng ito')) ?><?= count($abuseHistory) >= 2
                  ? e(t(' — one more will restrict them.', ' — isa pa at mapipigilan na siya.')) : '.' ?>
            <?php endif; ?>
          </p>

          <button class="btn-deny-confirm" type="submit" name="action" value="deny">
            <?= e(t('Confirm denial', 'Kumpirmahin ang pagtanggi')) ?>
          </button>
        </div>
      </form>

    <?php elseif ($canAssign): ?>
      <form method="post" class="control-stack" id="assign-form">
        <input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>">

        <p class="roster-head"><?= e(t('Assign Tanod', 'Mag-assign ng Tanod')) ?></p>

        <?php if (!$roster): ?>
          <p class="case-none"><?= e(t('No tanod accounts exist yet. Add them under Personnel.', 'Wala pang account ng tanod. Idagdag sila sa Mga Tanod.')) ?></p>
        <?php endif; ?>

        <div class="roster">
          <?php foreach ($roster as $i => $t): ?>
            <?php $ok = !empty($t['assignable']); ?>
            <label class="roster-row<?= $ok ? '' : ' is-out' ?>">
              <input type="radio" name="tanod" value="<?= e($t['tanod_id']) ?>"
                     <?= $ok ? '' : 'disabled' ?>>
              <span class="roster-name">
                <?= e($t['full_name']) ?>
                <?php if ($ok && $t['metres'] !== null): ?>
                  <small class="roster-dist<?= empty($t['location_fresh']) ? ' is-stale' : '' ?>">
                    <?= e(distance_label((float) $t['metres'])) ?><?= e(t(' away', ' ang layo')) ?><?php
                      if (empty($t['location_fresh'])) echo e(t(', last seen a while ago', ', matagal nang huling nakita')); ?>
                  </small>
                <?php endif; ?>
              </span>
              <span class="roster-state <?= $ok ? 'is-on' : 'is-off' ?>">
                <?= $ok ? 'ONLINE' : e(strtoupper((string) ($t['unavailable_why'] ?? 'OFFLINE'))) ?>
              </span>
              <span class="roster-pick"><?= $ok ? e(t('Assign', 'I-assign')) : '&mdash;' ?></span>
            </label>
          <?php endforeach; ?>
        </div>

        <div class="control-field">
          <!-- 0071 (Rose, 27 Sep 2026): the admin, not the system, gives the
               tanod their instructions and the complaint its deadline. -->
          <label class="field-label" for="note"><?= e(t('Instructions for the tanod', 'Mga tagubilin para sa tanod')) ?></label>
          <textarea id="note" name="note" rows="2" maxlength="500" required
                    placeholder="<?= e(t('What to check, who to talk to, what to bring back.', 'Ano ang titingnan, sino ang kakausapin, ano ang iuulat.')) ?>"></textarea>
        </div>

        <div class="control-field">
          <label class="field-label" for="target"><?= e(t('Target date resolution', 'Target na petsa ng paglutas')) ?></label>
          <input type="datetime-local" id="target" name="target" required
                 min="<?= e((new DateTimeImmutable('now', new DateTimeZone('Asia/Manila')))->format('Y-m-d\TH:i')) ?>"
                 value="<?= e(local_input_value($report['due_at'])) ?>">
          <p class="field-hint">
            <?= e(t('The resident is told this date, so choose one the barangay can keep.', 'Sasabihin sa residente ang petsang ito, kaya pumili ng kayang tuparin ng barangay.')) ?>
            <?php if ($policy): ?>
              <?= e(t('Guide for', 'Gabay para sa')) ?> <?= e(category_label($report['category'])) ?>:
              <?= (int) $policy['resolution_hours'] ?> <?= e(t('hours.', 'oras.')) ?>
            <?php endif; ?>
            <?php if (!empty($report['due_at'])): ?>
              <?= e(t('Currently due', 'Kasalukuyang takdang oras:')) ?> <?= e(long_datetime($report['due_at'])) ?>.
            <?php endif; ?>
          </p>
        </div>

        <button class="btn-dispatch" type="submit" name="action" value="dispatch"><?= e(t('Dispatch', 'I-dispatch')) ?></button>
      </form>

    <?php elseif ($status === 'rejected' && $appealReason !== null): ?>
      <!-- 0057 — the resident disputed this denial. Granting hands the
           case straight back to the roster (canAssign becomes true on
           reload, same as any freshly validated complaint) rather than
           adding a second review step the design never asked for. -->
      <form method="post" class="control-stack" id="appeal-form">
        <input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>">

        <p class="kbd-hint"><?= e(t('The resident is appealing this denial.', 'Inaapela ng residente ang pagtangging ito.')) ?></p>

        <div class="control-field">
          <label class="field-label"><?= e(t("Resident's reason", 'Dahilan ng residente')) ?></label>
          <p class="case-body"><?= e($appealReason) ?></p>
        </div>

        <div class="control-field">
          <label for="remark" class="field-label">
            <?= e(t('Note for the trail (optional)', 'Tala para sa talaan (opsyonal)')) ?>
          </label>
          <textarea id="remark" name="remark" rows="2" maxlength="300"
                    placeholder="<?= e(t('e.g. New photos confirm the report — reinstating.', 'hal. Kinukumpirma ng bagong larawan ang ulat — ibinabalik.')) ?>"></textarea>
        </div>

        <button class="btn-accept" type="submit" name="action" value="appeal_grant">
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2"
               stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
            <polyline points="20 6 9 17 4 12"/>
          </svg>
          <?= e(t('Grant Appeal', 'Pagbigyan ang Apela')) ?>
        </button>
        <p class="control-note">
          <?= e(t('Moves this complaint back to Validated with a fresh resolution window. To decline, simply leave this as is — the complaint stays denied.',
                  'Ibabalik ang sumbong sa Tinanggap na may bagong palugit sa paglutas. Para tanggihan, hayaan lamang ito — mananatiling tinanggihan ang sumbong.')) ?>
        </p>
      </form>

    <?php else: ?>
      <?php if ($active): ?>
        <div class="assigned-card">
          <p class="assigned-label"><?= e(t('Currently with', 'Kasalukuyang hawak ni')) ?></p>
          <p class="assigned-name"><?= e($active['tanod']['full_name'] ?? t('Unknown tanod', 'Hindi kilalang tanod')) ?></p>
          <p class="assigned-meta">
            <?= e(status_label($active['state'])) ?>
            &middot; <?= e(t('assigned', 'na-assign')) ?> <?= e(relative_time($active['assigned_at'])) ?>
          </p>
          <?php if ($active['state'] === 'assigned' && !empty($active['accept_due_at'])): ?>
            <p class="assigned-meta">
              <?= e(t('Must accept by', 'Dapat tanggapin bago')) ?> <?= e(long_datetime($active['accept_due_at'])) ?>
            </p>
          <?php endif; ?>
          <?php if (!empty($active['admin_instructions'])): ?>
            <p class="assigned-note"><?= e($active['admin_instructions']) ?></p>
          <?php endif; ?>
          <?php if (!empty($report['due_at'])): ?>
            <p class="assigned-meta"><?= e(t('Resolution target:', 'Target na paglutas:')) ?> <strong><?= e(long_datetime($report['due_at'])) ?></strong></p>
          <?php endif; ?>
        </div>

        <?php // 0070: the admin's reroute. The system's own (a tanod's
              // hand-back, a lapsed acceptance window) needs nothing here. ?>
        <details class="reroute">
          <summary><?= e(t('Reroute this dispatch', 'Ilipat ang dispatch na ito')) ?></summary>
          <form method="post" class="control-stack">
            <input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>">
            <input type="hidden" name="action" value="reroute">
            <input type="hidden" name="dispatch" value="<?= e($active['id']) ?>">
            <div class="roster">
              <label class="roster-row">
                <input type="radio" name="to" value="" checked>
                <span class="roster-name"><?= e(t('Let the system find the nearest tanod', 'Hayaang hanapin ng sistema ang pinakamalapit na tanod')) ?></span>
                <span class="roster-pick"><?= e(t('Auto', 'Auto')) ?></span>
              </label>
              <?php foreach ($roster as $t): ?>
                <?php if (($t['tanod_id'] ?? null) === ($active['tanod']['id'] ?? null)) continue; ?>
                <?php $ok = !empty($t['assignable']); ?>
                <label class="roster-row<?= $ok ? '' : ' is-out' ?>">
                  <input type="radio" name="to" value="<?= e($t['tanod_id']) ?>" <?= $ok ? '' : 'disabled' ?>>
                  <span class="roster-name">
                    <?= e($t['full_name']) ?>
                    <?php if ($ok && $t['metres'] !== null): ?>
                      <small class="roster-dist<?= empty($t['location_fresh']) ? ' is-stale' : '' ?>">
                        <?= e(distance_label((float) $t['metres'])) ?><?= e(t(' away', ' ang layo')) ?>
                      </small>
                    <?php endif; ?>
                  </span>
                  <span class="roster-state <?= $ok ? 'is-on' : 'is-off' ?>">
                    <?= $ok ? 'ONLINE' : e(strtoupper((string) ($t['unavailable_why'] ?? 'OFFLINE'))) ?>
                  </span>
                  <span class="roster-pick"><?= $ok ? e(t('Move', 'Ilipat')) : '&mdash;' ?></span>
                </label>
              <?php endforeach; ?>
            </div>
            <div class="control-field">
              <label class="field-label" for="reroute-reason"><?= e(t('Reason', 'Dahilan')) ?></label>
              <textarea id="reroute-reason" name="reason" rows="2" maxlength="300" required
                        placeholder="<?= e(t('e.g. Tanod is needed at another emergency.', 'hal. Kailangan ang tanod sa ibang emergency.')) ?>"></textarea>
            </div>
            <button class="btn-dispatch" type="submit"><?= e(t('Reroute', 'Ilipat')) ?></button>
          </form>
        </details>
      <?php else: ?>
        <p class="case-none">
          <?= $status === 'rejected'
              ? e(t('This complaint was denied. Nothing further is required.', 'Tinanggihan ang sumbong na ito. Wala nang kailangang gawin.'))
              : e(t('No action is available at this stage.', 'Walang aksyong magagawa sa yugtong ito.')) ?>
        </p>
      <?php endif; ?>

      <?php if (!empty($report['due_at']) && !$active): ?>
        <p class="due-line"><?= e(t('Resolution target:', 'Target na paglutas:')) ?> <strong><?= e(long_datetime($report['due_at'])) ?></strong></p>
      <?php endif; ?>
    <?php endif; ?>

    <?php if (!empty($report['resolution_submitted_at'])): ?>
      <?php // 0073 — Approve Complaint Resolution: the tanod's report is in the Field Report block. ?>
      <div class="review-box">
        <p class="assigned-label"><?= e(t('Resolution waiting for approval', 'Resolusyong naghihintay ng pag-apruba')) ?></p>
        <p class="control-note"><?= e(t("Check the tanod's report and proof under Field Report, then approve it or send it back.", 'Suriin ang ulat at patunay ng tanod sa Field Report, saka aprubahan o ibalik.')) ?></p>
        <form method="post" class="control-stack">
          <input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>">
          <button class="btn-accept" type="submit" name="action" value="approve_resolution"><?= e(t('Approve Resolution', 'Aprubahan ang Resolusyon')) ?></button>
        </form>
        <details class="reroute">
          <summary><?= e(t('Return to the tanod', 'Ibalik sa tanod')) ?></summary>
          <form method="post" class="control-stack">
            <input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>">
            <input type="hidden" name="action" value="reject_resolution">
            <div class="control-field">
              <label class="field-label" for="return-reason"><?= e(t('What still needs doing — the tanod sees this', 'Ano pa ang kailangang gawin — makikita ito ng tanod')) ?></label>
              <textarea id="return-reason" name="reason" rows="2" maxlength="300" required></textarea>
            </div>
            <button class="btn-deny-confirm" type="submit"><?= e(t('Return to Tanod', 'Ibalik sa Tanod')) ?></button>
          </form>
        </details>
      </div>
    <?php endif; ?>

    <?php if ($escRequest && empty($report['referred_to'])): ?>
      <?php // 0073 — Manage Escalation Request. ?>
      <div class="review-box">
        <p class="assigned-label"><?= e(t('Escalation request', 'Hiling na i-escalate')) ?></p>
        <p class="assigned-meta">
          <?= e($escRequest['requester']['full_name'] ?? t('Tanod', 'Tanod')) ?> &middot; <?= e(relative_time($escRequest['created_at'])) ?>
        </p>
        <p class="assigned-note"><?= nl2br(e($escRequest['reason'])) ?></p>
        <details class="reroute" open>
          <summary><?= e(t('Approve: escalate', 'Aprubahan: i-escalate')) ?></summary>
          <form method="post" class="control-stack">
            <input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>">
            <input type="hidden" name="action" value="approve_escalation">
            <input type="hidden" name="request" value="<?= e($escRequest['id']) ?>">
            <?php office_picker('esc-agency', $escRequest['suggested_office'] ?? null); ?>
            <div class="control-field">
              <label class="field-label" for="esc-note"><?= e(t('Note — the resident sees this', 'Tala — makikita ito ng residente')) ?></label>
              <textarea id="esc-note" name="note" rows="2" maxlength="300"></textarea>
            </div>
            <button class="btn-deny-confirm" type="submit"><?= e(t('Approve and escalate', 'Aprubahan at i-escalate')) ?></button>
          </form>
        </details>
        <details class="reroute">
          <summary><?= e(t('Deny the request', 'Tanggihan ang hiling')) ?></summary>
          <form method="post" class="control-stack">
            <input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>">
            <input type="hidden" name="action" value="deny_escalation">
            <input type="hidden" name="request" value="<?= e($escRequest['id']) ?>">
            <div class="control-field">
              <label class="field-label" for="esc-deny"><?= e(t('Reason — the tanod sees this', 'Dahilan — makikita ito ng tanod')) ?></label>
              <textarea id="esc-deny" name="reason" rows="2" maxlength="300" required></textarea>
            </div>
            <button class="btn-dispatch" type="submit"><?= e(t('Deny', 'Tanggihan')) ?></button>
          </form>
        </details>
      </div>
    <?php endif; ?>

    <?php if (in_array($status, ['validated', 'assigned', 'in_progress', 'offline_investigation'], true)
              && empty($report['resolution_submitted_at'])): ?>
      <?php // 0073 — Update Resolution Status. ?>
      <details class="reroute status-control">
        <summary><?= e(t('Update status', 'I-update ang katayuan')) ?></summary>
        <form method="post" class="control-stack">
          <input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>">
          <input type="hidden" name="action" value="set_status">
          <div class="control-field">
            <label class="field-label" for="set-status"><?= e(t('New status', 'Bagong katayuan')) ?></label>
            <select id="set-status" name="status" required>
              <?php foreach (['in_progress', 'offline_investigation', 'resolved'] as $opt): ?>
                <?php if ($opt === $status) continue; ?>
                <option value="<?= e($opt) ?>"><?= e($opt === 'resolved' ? t('Resolved/Completed', 'Nalutas/Nakumpleto') : status_label($opt)) ?></option>
              <?php endforeach; ?>
            </select>
          </div>
          <div class="control-field">
            <label class="field-label" for="set-remark"><?= e(t('Remark — the resident sees this', 'Tala — makikita ito ng residente')) ?></label>
            <textarea id="set-remark" name="remark" rows="2" maxlength="300"></textarea>
          </div>
          <button class="btn-dispatch" type="submit"><?= e(t('Update status', 'I-update ang katayuan')) ?></button>
        </form>
      </details>
    <?php endif; ?>

    <?php if (!in_array($status, ['rejected', 'cancelled'], true)): ?>
      <?php // 0073 — the resident map shows published incidents: category and status only. ?>
      <form method="post" class="publish-toggle">
        <input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>">
        <input type="hidden" name="action" value="set_public">
        <label class="field-check">
          <input type="checkbox" name="public" value="1" <?= !empty($report['is_public']) ? 'checked' : '' ?> onchange="this.form.submit()">
          <?= e(t("Show on residents' map (category and status only)", 'Ipakita sa mapa ng mga residente (kategorya at katayuan lamang)')) ?>
        </label>
      </form>
    <?php endif; ?>

    <?php if (!empty($report['referred_to'])): ?>
      <div class="assigned-card referral-card">
        <p class="assigned-label"><?= e(t('Escalated to', 'In-escalate sa')) ?></p>
        <p class="assigned-name"><?= e($report['referred_to']) ?></p>
        <p class="assigned-meta"><?= e(long_datetime($report['referred_at'])) ?></p>
        <?php if (!empty($report['referral_note'])): ?>
          <p class="assigned-note"><?= e($report['referral_note']) ?></p>
        <?php endif; ?>
        <a class="btn-dispatch cert-link" target="_blank" rel="noopener" href="certificate.php?id=<?= e($id) ?>">
          <?= e(t('Certification of Lack of Jurisdiction', 'Sertipikasyon ng Kawalan ng Hurisdiksyon')) ?>
        </a>
      </div>
    <?php elseif (!in_array($status, ['resolved', 'closed', 'archived', 'rejected', 'cancelled'], true)): ?>
      <?php // 0072: escalation = referral to an office outside the barangay. ?>
      <details class="reroute referral">
        <summary><?= e(t('Escalate to an outside office', 'I-escalate sa ibang tanggapan')) ?></summary>
        <form method="post" class="control-stack">
          <input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>">
          <input type="hidden" name="action" value="refer">
          <?php office_picker('refer-agency'); ?>
          <div class="control-field">
            <label class="field-label" for="refer-note"><?= e(t('Note — the resident sees this', 'Tala — makikita ito ng residente')) ?></label>
            <textarea id="refer-note" name="note" rows="2" maxlength="300"
                      placeholder="<?= e(t('e.g. Please visit the VAWC desk at the barangay hall with a valid ID.', 'hal. Pumunta sa VAWC desk sa barangay hall na may dalang valid ID.')) ?>"></textarea>
          </div>
          <p class="control-note"><?= e(t('This closes the complaint here and stands down any tanod on it. Afterwards you can print the Certification of Lack of Jurisdiction for the resident.', 'Isasara nito ang sumbong dito at ititigil ang sinumang tanod na nakatalaga. Pagkatapos, maaari mong i-print ang Sertipikasyon ng Kawalan ng Hurisdiksyon para sa residente.')) ?></p>
          <button class="btn-deny-confirm" type="submit"><?= e(t('Escalate', 'I-escalate')) ?></button>
        </form>
      </details>
    <?php endif; ?>

    <!-- ---------- map preview ---------- -->
    <!-- Martin's note / Rose's feedback: the preview had no way to get
         bigger — it is deliberately a non-interactive thumbnail (see the
         JS below), so "expanding" here means the Fullscreen API, same
         mechanism spatial.php's own expand button already uses, not
         panning or zooming this small a widget. -->
    <div class="map-preview" id="case-map-preview">
      <div id="case-map"></div>
      <button class="map-btn map-btn--preview" id="case-map-expand" type="button"
              title="<?= e(t('Expand map to full screen', 'I-full screen ang mapa')) ?>">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"
             stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
          <path d="M15 3h6v6M9 21H3v-6M21 3l-7 7M3 21l7-7"/>
        </svg>
      </button>
      <span class="map-label"><?php if (!empty($report['location_label'])): ?><span class="map-label-place"><?= e($report['location_label']) ?></span><?php endif; ?><?= e(coord_label((float) $report['latitude'], (float) $report['longitude'])) ?></span>
    </div>
  </aside>

  <!-- ---------- the register row, as designed ---------- -->
  <div class="case-strip">
    <span><?= !empty($report['is_anonymous'])
              ? '<em class="anon">' . e(t('Anonymous', 'Hindi nagpakilala')) . '</em>'
              : e($report['resident']['full_name'] ?? t('Unknown', 'Hindi kilala')) ?></span>
    <span class="mono"><?= e($report['tracking_id']) ?></span>
    <span><?= e(category_label($report['category'])) ?></span>
    <span><?= e(short_date($report['created_at'])) ?></span>
  </div>

  <!-- ---------- timeline ---------- -->
  <section class="card card--timeline">
    <h3 class="case-sub"><?= e(t('Activity Timeline', 'Takbo ng Aktibidad')) ?></h3>

    <?php
    $trail  = $trail ?? [];
    $broken = array_values(array_filter($trail, fn($t) => empty($t['intact'])));
    ?>
    <?php if ($trail && !$broken): ?>
      <p class="trail-ok">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2"
             stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
          <path d="M12 3l7 3v6c0 4.5-3 7.5-7 9-4-1.5-7-4.5-7-9V6z"/><polyline points="9 12 11 14 15 10"/>
        </svg>
        <?= e(t('Trail verified — ', 'Beripikado ang talaan — ')) ?><?= count($trail) ?><?= e(t(' entries, none altered since they were written.', ' tala, walang binago mula nang isulat.')) ?>
      </p>
    <?php elseif ($broken): ?>
      <p class="trail-bad" role="alert">
        <strong><?= e(t('This trail has been tampered with.', 'May nagbago sa talaang ito.')) ?></strong>
        <?php foreach ($broken as $b): ?>
          <?= e(t('Entry', 'Tala')) ?> <?= (int) $b['entry_no'] ?>: <?= e($b['problem']) ?>.
        <?php endforeach; ?>
        <?= e(t('Report this to the barangay administrator before acting on this case.', 'Iulat ito sa administrator ng barangay bago kumilos sa kasong ito.')) ?>
      </p>
    <?php endif; ?>

    <?php
    // The same entry repeated back to back (the SLA-breach retries 0063
    // capped, still on older complaints) is shown once with its count and
    // when it last happened, as Report Summary and the resident app's
    // timeline do. The trail itself is untouched; only its display folds.
    $timeline = [];
    foreach ($logs as $l) {
        $sig = implode('|', [$l['old_status'] ?? '', $l['new_status'] ?? '', $l['remark'] ?? '',
                             !empty($l['is_system']) ? 'sys' : ($l['by']['full_name'] ?? '')]);
        $prev = array_key_last($timeline);
        if ($prev !== null && $timeline[$prev]['sig'] === $sig) {
            $timeline[$prev]['repeat']++;
            $timeline[$prev]['last_at'] = $l['created_at'];
            continue;
        }
        $timeline[] = $l + ['sig' => $sig, 'repeat' => 1, 'last_at' => null];
    }
    ?>
    <ol class="timeline">
      <?php foreach ($timeline as $l): ?>
        <li class="tl-item">
          <span class="tl-dot" aria-hidden="true"></span>
          <p class="tl-title"><?= e(timeline_title($l)) ?><?php if ($l['repeat'] > 1): ?> <span class="tl-repeat">&times; <?= (int) $l['repeat'] ?></span><?php endif; ?></p>
          <p class="tl-when"><?= e(long_datetime($l['created_at'])) ?><?php if ($l['repeat'] > 1): ?> &ndash; <?= e(t('last', 'huli')) ?> <?= e(long_datetime($l['last_at'])) ?><?php endif; ?></p>
          <?php if (!empty($l['remark'])): ?>
            <p class="tl-remark"><?= e($l['remark']) ?></p>
          <?php endif; ?>
          <p class="tl-who">
            <?= !empty($l['is_system'])
                ? e(t('System', 'System'))
                : e($l['by']['full_name'] ?? t('Barangay staff', 'Kawani ng barangay')) ?>
          </p>
        </li>
      <?php endforeach; ?>

      <li class="tl-item tl-now">
        <span class="tl-dot tl-dot--now" aria-hidden="true"></span>
        <p class="tl-when"><?= e(t('Today', 'Ngayon')) ?> &middot; <?= e((new DateTimeImmutable('now', new DateTimeZone('Asia/Manila')))->format('g:i A')) ?></p>
      </li>
    </ol>
  </section>

  <!-- ---------- resident feedback ---------- -->
  <!-- Only ever possible on a finished report — feedback_insert (0003)
       requires status in (resolved, closed), same gate the resident
       app's own feedback card uses. Shown either way once finished, so
       "no rating yet" reads as a fact, not a missing feature. -->
  <?php if (in_array($status, ['resolved', 'closed'], true)): ?>
  <section class="card card--feedback">
    <h3 class="case-sub"><?= e(t('Resident Feedback', 'Puna ng Residente')) ?></h3>
    <?php if ($feedback): ?>
      <div class="fb-stars" role="img"
           aria-label="<?= e(t('Rated ', 'Rating na ')) ?><?= (int) $feedback['rating'] ?><?= e(t(' out of 5 stars', ' sa 5 bituin')) ?>">
        <?php for ($i = 1; $i <= 5; $i++): ?>
          <svg class="fb-star<?= $i <= (int) $feedback['rating'] ? ' is-filled' : '' ?>"
               viewBox="0 0 24 24" aria-hidden="true">
            <path d="M12 2l3.09 6.26L22 9.27l-5 4.87L18.18 21 12 17.77 5.82 21 7 14.14 2 9.27l6.91-1.01L12 2z"/>
          </svg>
        <?php endfor; ?>
      </div>
      <?php if (!empty($feedback['comment'])): ?>
        <p class="fb-comment">&ldquo;<?= nl2br(e($feedback['comment'])) ?>&rdquo;</p>
      <?php endif; ?>
      <p class="tl-when"><?= e(t('Submitted', 'Isinumite')) ?> <?= e(long_datetime($feedback['submitted_at'])) ?></p>
    <?php else: ?>
      <p class="case-none"><?= e(t('The resident has not left feedback on this complaint yet.', 'Hindi pa nag-iiwan ng puna ang residente sa sumbong na ito.')) ?></p>
    <?php endif; ?>
  </section>
  <?php endif; ?>
</div>

<link rel="stylesheet" href="assets/vendor/maplibre/maplibre-gl.css">
<script src="assets/vendor/maplibre/maplibre-gl.js"></script>
<script src="assets/js/map-theme.js"></script>
<script>
(function () {
  // ---- copy the tracking id ----
  document.querySelectorAll('[data-copy]').forEach(function (btn) {
    btn.addEventListener('click', function () {
      navigator.clipboard.writeText(btn.dataset.copy).then(function () {
        btn.classList.add('is-done');
        setTimeout(function () { btn.classList.remove('is-done'); }, 1400);
      });
    });
  });

  // ---- live SLA countdown ----
  var sla = document.querySelector('.sla-countdown');
  if (sla) {
    var due = new Date(sla.dataset.due);
    var out = sla.querySelector('.sla-text');
    (function tick() {
      var ms = due - new Date(), late = ms < 0, a = Math.abs(ms);
      var d = Math.floor(a / 86400000),
          h = Math.floor(a % 86400000 / 3600000),
          m = Math.floor(a % 3600000 / 60000);
      var span = (d ? d + 'd ' : '') + (d || h ? h + 'h ' : '') + m + 'm';
      out.textContent = late ? T('Overdue by ', 'Lampas na nang ') + span : span + T(' left to resolve', ' na lang para malutas');
      sla.classList.toggle('is-late', late);
      sla.classList.toggle('is-close', !late && a < 21600000);   // under six hours
      setTimeout(tick, 30000);
    })();
  }

  // ---- keyboard: A accepts, D opens the denial, Esc closes it ----
  // An admin clearing twenty complaints should not have to find the
  // mouse for each one. Ignored while typing, so a reason containing
  // the letter A does not submit the form.
  document.addEventListener('keydown', function (ev) {
    var t = ev.target.tagName;
    if (t === 'INPUT' || t === 'TEXTAREA' || t === 'SELECT' || ev.metaKey || ev.ctrlKey) return;

    var accept = document.querySelector('[value="accept"]'),
        denyBtn = document.getElementById('deny-toggle'),
        panel   = document.getElementById('deny-panel');

    if (ev.key === 'Escape' && panel && !panel.hasAttribute('hidden')) { denyBtn.click(); return; }
    if (!accept) return;
    if (ev.key === 'a' || ev.key === 'A') { ev.preventDefault(); accept.click(); }
    if (ev.key === 'd' || ev.key === 'D') { ev.preventDefault(); denyBtn.click(); }
  });

  // Escalation: "Another office…" asks for the office's name.
  document.querySelectorAll('select[data-office]').forEach(function (sel) {
    var wrap = sel.closest('.control-field').nextElementSibling;
    sel.addEventListener('change', function () {
      var other = sel.value === 'other';
      wrap.hidden = !other;
      wrap.querySelector('input').required = other;
    });
  });

  // Deny is destructive and irreversible, so it asks for a reason before
  // it will submit. The button only reveals the field; the second one commits.
  var toggle = document.getElementById('deny-toggle');
  if (toggle) {
    var panel = document.getElementById('deny-panel');
    toggle.addEventListener('click', function () {
      var open = panel.hasAttribute('hidden');
      if (open) { panel.removeAttribute('hidden'); } else { panel.setAttribute('hidden', ''); }
      // Required only while the denial is open: a hidden required field
      // silently blocked the Accept button in the same form.
      document.getElementById('reason').required = open;
      toggle.setAttribute('aria-expanded', String(open));
      if (open) { document.getElementById('reason').focus(); }
    });
  }

  // A preview, not a tool: no dragging, no zoom, no scroll hijack while
  // small. The full interactive map is Spatial Distribution; expanding
  // this one to full screen (below) briefly turns those back on, since a
  // fixed, uninteractive view stops making sense once it fills the screen.
  var el = document.getElementById('case-map');
  if (el && window.maplibregl) {
    var lat = <?= json_encode((float) $report['latitude']) ?>,
        lng = <?= json_encode((float) $report['longitude']) ?>;
    // Branch B: the same MapLibre + OpenFreeMap style as Spatial
    // Distribution and the apps (see spatial.php). Zoom 16 here is
    // Leaflet's 17 — MapLibre's scale sits one lower.
    var map = new maplibregl.Map({
      container: el,
      style: window.mapStyleUrl(),
      center: [lng, lat], zoom: 16, maxZoom: 18,
      interactive: true, dragRotate: false, pitchWithRotate: false,
      attributionControl: { compact: true }
    });
    map.touchZoomRotate.disableRotation();
    map.keyboard.disableRotation();
    mapFollowTheme(map);
    mapLandmarks(map);
    mapZones(map);
    zoneAt(lng, lat).then(function (z) {
      if (!z) return;
      var el = document.getElementById('case-zone');
      el.textContent = T('Zone: ', 'Purok: ') + z;
      el.hidden = false;
    });
    hazardAt(lng, lat).then(function (h) {
      var names = [T('none', 'wala'), T('low', 'mababa'), T('medium', 'katamtaman'), T('high', 'mataas')];
      var bits = [];
      if (h.flood) bits.push(T('Flood hazard (100-year): ', 'Panganib ng baha (100-taon): ') + names[h.flood]);
      if (h.surge) bits.push(T('Storm surge: ', 'Daluyong: ') + names[h.surge]);
      if (!bits.length) return;
      var el = document.getElementById('case-hazard');
      el.textContent = bits.join(' · ') + ' — Project NOAH';
      el.classList.toggle('is-high', Math.max(h.flood, h.surge) >= 3);
      el.hidden = false;
    }).catch(function () {});
    // Navy on the light map, pale blue on the dark one.
    new maplibregl.Marker({ color: document.documentElement.getAttribute('data-theme') === 'dark' ? '#a9c1ff' : '#00308f' })
      .setLngLat([lng, lat]).addTo(map);
    // Folded to its (i) button: opened, it covers the coordinates label.
    map.on('load', function () {
      var attrib = el.querySelector('.maplibregl-ctrl-attrib');
      if (attrib) { attrib.classList.remove('maplibregl-compact-show'); attrib.removeAttribute('open'); }
    });
    var interactive = ['dragPan', 'scrollZoom', 'doubleClickZoom',
                       'keyboard', 'touchZoomRotate', 'boxZoom'];
    interactive.forEach(function (h) { map[h].disable(); });

    // ---- expand to full screen ----
    // Same Fullscreen API pattern as spatial.php's own expand button: the
    // target has to be the wrapping .map-preview, not #map itself, or the
    // expand button and coordinate label would be left behind outside the
    // fullscreen element.
    var expandBtn = document.getElementById('case-map-expand');
    var preview    = document.getElementById('case-map-preview');
    if (expandBtn && preview) {
      // zoomControl was left off entirely at creation (zoomControl: false
      // above) since the small preview has no use for it — a single
      // instance is made the first time it is actually needed, then
      // just shown/hidden with the rest of the interactive controls.
      var zoomCtl = null;

      // iPhone Safari has no element fullscreen; hide the button there
      // rather than leave one that does nothing when tapped.
      if (!document.fullscreenEnabled && !document.webkitFullscreenEnabled) {
        expandBtn.hidden = true;
      }

      expandBtn.addEventListener('click', function () {
        if (!document.fullscreenElement) {
          // The prefixed call returns nothing rather than a promise.
          var p = (preview.requestFullscreen || preview.webkitRequestFullscreen || function () {}).call(preview);
          if (p && p.catch) { p.catch(function () {}); }
        } else {
          (document.exitFullscreen || document.webkitExitFullscreen || function () {}).call(document);
        }
      });
      document.addEventListener('fullscreenchange', function () {
        var active = document.fullscreenElement === preview;
        preview.classList.toggle('is-fullscreen', active);
        expandBtn.title = active ? T('Exit full screen', 'Lumabas sa full screen') : T('Expand map to full screen', 'I-full screen ang mapa');
        // Only worth interacting with once it actually fills the screen —
        // small again, it goes right back to a fixed thumbnail.
        interactive.forEach(function (opt) {
          active ? map[opt].enable() : map[opt].disable();
        });
        // enable() turns rotation back on with the zoom; the map stays north-up.
        map.touchZoomRotate.disableRotation();
        map.keyboard.disableRotation();
        if (active) {
          if (!zoomCtl) { zoomCtl = new maplibregl.NavigationControl({ showCompass: false }); }
          map.addControl(zoomCtl, 'bottom-right');
        } else if (zoomCtl) {
          map.removeControl(zoomCtl);
        }
        setTimeout(function () { map.resize(); }, 120);
      });
    }
  }
})();
</script>

<script src="assets/vendor/supabase/supabase.js"></script>
<script>
// Realtime, added 6 Sep 2026 — explicit ask: "the entire system needs to
// work realtime." This is the one page in the portal with live form
// inputs on screen at the same time as the data that could change under
// it (a deny reason mid-type, a dispatch note, a target date), so unlike
// cases.php/dashboard.php it never rewrites the DOM itself — it only
// raises the .update-banner above and leaves reloading to the admin.
(function () {
  if (!window.supabase) { return; }
  const { createClient } = supabase;

  const TOKEN = <?= json_encode(access_token()) ?>;
  const REPORT_ID = <?= json_encode($id) ?>;
  const sb = createClient(
    <?= json_encode(supabase_url()) ?>,
    <?= json_encode(supabase_key()) ?>,
    { accessToken: window.ssAccessToken(TOKEN) }
  );

  function showBanner() {
    document.getElementById('update-banner').classList.add('is-shown');
  }

  sb.channel('case-' + REPORT_ID)
    .on('postgres_changes', { event: '*', schema: 'public', table: 'reports',
                               filter: 'id=eq.' + REPORT_ID }, showBanner)
    .on('postgres_changes', { event: '*', schema: 'public', table: 'status_logs',
                               filter: 'report_id=eq.' + REPORT_ID }, showBanner)
    .on('postgres_changes', { event: '*', schema: 'public', table: 'dispatches',
                               filter: 'report_id=eq.' + REPORT_ID }, showBanner)
    .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'report_messages',
                               filter: 'report_id=eq.' + REPORT_ID }, showBanner)
    .on('postgres_changes', { event: '*', schema: 'public', table: 'escalation_requests',
                               filter: 'report_id=eq.' + REPORT_ID }, showBanner)
<?php if (!empty($liveIds)): ?>
    .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'dispatch_updates',
                               filter: <?= json_encode('dispatch_id=in.(' . implode(',', $liveIds) . ')') ?> }, showBanner)
<?php endif; ?>
    .subscribe(function (status) {
      var badge = document.getElementById('live-badge'),
          text  = document.getElementById('live-badge-text');
      if (status === 'SUBSCRIBED') {
        badge.classList.remove('is-down'); text.textContent = T('Live', 'Live');
      } else if (status === 'CHANNEL_ERROR' || status === 'TIMED_OUT' || status === 'CLOSED') {
        badge.classList.add('is-down'); text.textContent = T('Reconnecting…', 'Kumokonekta muli…');
      }
    });

  // feedback and dispatch_media are not in the supabase_realtime
  // publication (only reports/dispatches/status_logs/notifications are —
  // see migrations 0004/0046), so a change to either has no push signal.
  // A light poll is the honest way to still surface them as "current"
  // without asking the team to publish two more tables just for this.
  const INITIAL_FEEDBACK_AT = <?= json_encode($feedback['submitted_at'] ?? null) ?>;
  const LIVE_DISPATCH_IDS   = <?= json_encode(array_values($liveIds ?? [])) ?>;
  const INITIAL_PROOF_COUNT = <?= json_encode($proofCount) ?>;

  async function pollUnpublished() {
    if (INITIAL_FEEDBACK_AT === null) {
      const { data } = await sb.from('feedback').select('submitted_at')
        .eq('report_id', REPORT_ID).limit(1);
      if (data && data.length) { showBanner(); return; }
    }
    if (LIVE_DISPATCH_IDS.length) {
      const { count } = await sb.from('dispatch_media')
        .select('id', { count: 'exact', head: true })
        .in('dispatch_id', LIVE_DISPATCH_IDS);
      if (typeof count === 'number' && count > INITIAL_PROOF_COUNT) { showBanner(); return; }
    }
  }
  setInterval(pollUnpublished, 25000);
})();
</script>

<?php layout_foot(); ?>
