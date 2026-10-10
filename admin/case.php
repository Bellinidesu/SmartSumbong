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

/**
 * Highest Project NOAH flood and storm-surge level (0-3) at a point, from
 * assets/map/hazards.geojson — the same test map-theme.js's hazardAt() does.
 */
function case_hazard_at(float $lng, float $lat): array
{
    $out = ['flood' => 0, 'surge' => 0];
    $fc = json_decode((string) @file_get_contents(__DIR__ . '/assets/map/hazards.geojson'), true);
    $inRing = function (array $ring) use ($lng, $lat): bool {
        $c = false;
        for ($i = 0, $j = count($ring) - 1; $i < count($ring); $j = $i++) {
            [$xi, $yi] = $ring[$i]; [$xj, $yj] = $ring[$j];
            if ((($yi > $lat) !== ($yj > $lat)) && $lng < ($xj - $xi) * ($lat - $yi) / ($yj - $yi) + $xi) $c = !$c;
        }
        return $c;
    };
    foreach ((array) ($fc['features'] ?? []) as $f) {
        $g = $f['geometry'] ?? [];
        $polys = ($g['type'] ?? '') === 'Polygon' ? [$g['coordinates']] : (array) ($g['coordinates'] ?? []);
        foreach ($polys as $poly) {
            if (!$inRing($poly[0])) continue;
            $hole = false;
            for ($k = 1; $k < count($poly); $k++) { if ($inRing($poly[$k])) { $hole = true; break; } }
            if ($hole) continue;
            $h = $f['properties']['hazard'] ?? '';
            if (isset($out[$h])) $out[$h] = max($out[$h], (int) ($f['properties']['level'] ?? 0));
            break;
        }
    }
    return $out;
}
$db    = db();

$id = (string) ($_GET['id'] ?? '');
if (!preg_match('/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i', $id)) {
    header('Location: cases.php');
    exit;
}

session_start_once();

// ---------- actions ---------- (in includes/case_actions.php)
require __DIR__ . '/includes/case_actions.php';

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
$evidence = [];    // the barangay's own photos (0079)
$handlerLog = [];  // takes, releases and take-overs (0087)
$extUsed = 0;      // target-date extensions since the last hand-up (0079)
$extCap = 2;
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
                      . 'higher_official,higher_official_note,handed_up_at,'
                      . 'handler_id,handled_since,version,handler:users!reports_handler_id_fkey(id,full_name),'
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

    // The resident's questions and the barangay's answers (0072), for
    // every case: Rose (7 Oct 2026) found them missing on cases with no
    // tanod on them, where they were never loaded.
    $second['messages'] = ['report_messages', [
        'select'    => 'id,from_barangay,body,created_at',
        'report_id' => 'eq.' . $id,
        'order'     => 'created_at.asc',
    ], true];

    // The dispatch window's thread (0069): the tanod's updates and
    // steps, and admin replies. Optional — the page stands without it.
    if ($liveIds) {
        $second['escalation'] = ['escalation_requests', [
            'select'    => 'id,reason,suggested_office,created_at,requester:users!escalation_requests_requested_by_fkey(full_name)',
            'report_id' => 'eq.' . $id,
            'status'    => 'eq.pending',
            'limit'     => '1',
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

    // 0079: the barangay's photos, and how many extensions are left.
    $second['evidence'] = ['report_evidence', [
        'select'    => 'id,kind,media_url,bytes,created_at',
        'report_id' => 'eq.' . $id,
        'order'     => 'created_at.asc',
    ], true];
    $second['ext'] = ['rpc/extensions_used', ['p_report' => $id], true];
    $second['handlers'] = ['case_handler_log', [
        'select'    => 'action,reason,created_at,admin:users!case_handler_log_admin_id_fkey(id,full_name),prev:users!case_handler_log_previous_id_fkey(full_name)',
        'report_id' => 'eq.' . $id, 'order' => 'created_at.desc', 'limit' => '4',
    ], true];
    $second['ops'] = ['operational_settings', ['select' => 'max_deadline_extensions', 'limit' => '1'], true];

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
        if (isset($got['handlers']) && !$got['handlers'] instanceof SupabaseError) {
            $handlerLog = (array) $got['handlers'];
        }
        if (isset($got['evidence']) && !$got['evidence'] instanceof SupabaseError) {
            $evidence = (array) $got['evidence'];
        }
        if (isset($got['ext']) && !$got['ext'] instanceof SupabaseError) {
            $extUsed = (int) (is_array($got['ext']) ? ($got['ext'][0] ?? 0) : $got['ext']);
        }
        if (isset($got['ops']) && !$got['ops'] instanceof SupabaseError && isset($got['ops'][0]['max_deadline_extensions'])) {
            $extCap = (int) $got['ops'][0]['max_deadline_extensions'];
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
  <div class="p-flash p-flash--<?= e($flash['level']) ?>" role="status"><?= e($flash['text']) ?></div>
<?php endif; ?>

<?php if ($error): ?>
  <div class="p-flash p-flash--error" role="alert"><?= e($error) ?></div>
  <p><a class="p-back" href="cases.php"><?= p_icon('i-back', 18) ?><?= e(t('Case Reports', 'Mga Sumbong')) ?></a></p>
  <?php layout_foot(); exit; ?>
<?php endif; ?>

<!-- Live inputs on this page (a deny reason, a dispatch note, a target date)
     mean realtime announces rather than rewrites; the admin chooses when to reload. -->
<div class="p-upd" id="update-banner" role="status">
  <span><?= e(t('This case has new activity since you opened it.', 'May bagong aktibidad sa kasong ito mula nang buksan mo.')) ?></span>
  <a class="p-btn p-btn-ghost p-btn-sm" href="case.php?id=<?= e($id) ?>"><?= e(t('Refresh to see it', 'I-refresh para makita')) ?></a>
</div>

<div class="p-topbar">
  <a class="p-back" href="cases.php" aria-label="<?= e(t('Back to case reports', 'Bumalik sa mga sumbong')) ?>"><?= p_icon('i-back', 18) ?><?= e(t('Case Reports', 'Mga Sumbong')) ?></a>
  <span class="p-crumb">/ <?= e($report['tracking_id']) ?></span>
  <span class="p-live" id="live-badge" title="<?= e(t('Watching this case for new activity', 'Binabantayan ang bagong aktibidad sa kasong ito')) ?>"><i></i><span id="live-badge-text"><?= e(t('Live', 'Live')) ?></span></span>  <span class="p-spacer"></span>
  <?php // Rose (7 Oct 2026): this case on the barangay's letterhead, to print or save as PDF. ?>
  <a class="p-btn p-btn-ghost" href="complaint-print.php?id=<?= e($id) ?>" target="_blank" rel="noopener"><?= p_icon('i-dl', 16) ?><?= e(t('Print complaint', 'I-print ang sumbong')) ?></a>
</div>

<div class="p-case-grid">
  <div class="p-grid p-case-left">
  <!-- ---------- the complaint itself ---------- -->
  <div>
    <div class="p-case-tabs"><button type="button" class="p-on"><?= e(t('Original Report', 'Orihinal na Ulat')) ?></button></div>
    <article class="p-report">
    <h1 class="p-case-title">
      <?= e($report['tracking_id']) ?>: <?= e(category_label($report['category'])) ?>
      <!-- Admins read this number out over the phone and paste it into
           texts to residents. One click beats selecting it by hand. -->
      <button class="p-copy-id" type="button" data-copy="<?= e($report['tracking_id']) ?>"
              title="<?= e(t('Copy complaint ID', 'Kopyahin ang ID ng sumbong')) ?>" aria-label="<?= e(t('Copy complaint ID', 'Kopyahin ang ID ng sumbong')) ?>">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9"
             stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
          <rect x="9" y="9" width="11" height="11" rx="2"/>
          <path d="M5 15V5a2 2 0 0 1 2-2h10"/>
        </svg>
      </button>
    </h1>

    <p class="p-filed">
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
      <p class="p-filed p-place" title="<?= e(t('Nearest street, from OpenStreetMap', 'Pinakamalapit na kalye, mula sa OpenStreetMap')) ?>">
        <svg class="loc-pin" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12 21s-7-6.2-7-11.5A7 7 0 0 1 19 9.5C19 14.8 12 21 12 21z"/><circle cx="12" cy="9.5" r="2.5"/></svg>
        <?= e(t('Near', 'Malapit sa')) ?> <?= e($report['location_label']) ?>
      </p>
    <?php endif; ?>
    <?php
      // Project NOAH hazard levels at this spot, worked out here so the
      // browser no longer downloads the 640 KB hazard file (speed, 7 Oct).
      $hz = case_hazard_at((float) $report['longitude'], (float) $report['latitude']);
      $hzNames = [t('none', 'wala'), t('low', 'mababa'), t('medium', 'katamtaman'), t('high', 'mataas')];
      $hzBits = [];
      if ($hz['flood']) $hzBits[] = t('Flood hazard (100-year): ', 'Panganib ng baha (100-taon): ') . $hzNames[$hz['flood']];
      if ($hz['surge']) $hzBits[] = t('Storm surge: ', 'Daluyong: ') . $hzNames[$hz['surge']];
    ?>
    <?php if ($hzBits): ?>
      <p class="p-filed p-hazard<?= max($hz['flood'], $hz['surge']) >= 3 ? ' p-high' : '' ?>" id="case-hazard"><?= e(implode(' · ', $hzBits)) ?> — Project NOAH</p>
    <?php endif; ?>
    <p class="p-filed p-zone" id="case-zone" hidden></p>

    <?php if (!empty($report['due_at'])
              && !in_array($status, ['resolved','closed','archived','rejected'], true)): ?>
      <!-- A date makes you do the arithmetic; a countdown does not. -->
      <p class="p-clock sla-countdown" data-due="<?= e($report['due_at']) ?>">
        <span class="sla-text"><?= e(t('calculating…', 'kinakalkula…')) ?></span>
      </p>
    <?php endif; ?>

    <div class="p-acc-flags">
      <span class="p-badge p-b-<?= e(status_class($status)) ?>"><?= e(status_label($status)) ?></span>
      <?php if (!empty($report['referred_to'])): ?>
        <span class="p-badge p-b-violet"><?= e(t('Escalated to ', 'In-escalate sa ')) . e($report['referred_to']) ?></span>
      <?php endif; ?>
      <?php if (!empty($report['resolution_submitted_at'])): ?>
        <span class="p-badge p-b-pending"><?= e(t('Resolution awaiting approval', 'Naghihintay ng pag-apruba ang resolusyon')) ?></span>
      <?php endif; ?>
      <?php if ($escRequest): ?>
        <span class="p-badge p-b-pending"><?= e(t('Escalation requested', 'Hiniling na i-escalate')) ?></span>
      <?php endif; ?>
      <?php if (!empty($report['is_public'])): ?>
        <span class="p-badge p-b-grey"><?= e(t("On residents' map", 'Nasa mapa ng mga residente')) ?></span>
      <?php endif; ?>
      <?php if (!empty($report['followed_up_at'])): ?>
        <span class="p-badge p-b-pending" title="<?= e(t('Last follow-up ', 'Huling follow-up ') . relative_time($report['followed_up_at'])) ?>">
          <?= e(t('Resident followed up', 'Nag-follow up ang residente')) ?><?= (int) ($report['follow_up_count'] ?? 0) > 1 ? ' ' . (int) $report['follow_up_count'] . '&times;' : '' ?>
        </span>
      <?php endif; ?>
      <?php if (!empty($report['awaiting_unit_since']) && !$active): ?>
        <span class="p-badge p-b-denied"><?= e(t('Awaiting a unit since', 'Naghihintay ng tanod mula')) ?> <?= e(relative_time($report['awaiting_unit_since'])) ?></span>
      <?php endif; ?>
      <?php if (($report['reopened_count'] ?? 0) > 0): ?>
        <span class="p-badge p-b-pending"><?= e(t('Reopened', 'Binuksang muli')) ?> <?= (int) $report['reopened_count'] ?>&times;</span>
      <?php endif; ?>
      <?php if (!empty($report['appealed_at'])): ?>
        <span class="p-badge p-b-pending" title="<?= e(t('Reinstated on appeal', 'Ibinalik dahil sa apela')) ?>"><?= e(t('Appealed', 'Inapela')) ?></span>
      <?php endif; ?>
    </div>

    <div class="p-sec">
      <p class="p-eyebrow"><?= e(t('Subject', 'Paksa')) ?></p>
      <p class="p-desc"><?= e($report['subject']) ?></p>
    </div>

    <div class="p-sec">
      <p class="p-eyebrow"><?= e(t('Problem Description', 'Paglalarawan ng Problema')) ?></p>
      <p class="p-desc"><?= nl2br(e($report['description'])) ?></p>
    </div>

    <div class="p-sec">
      <p class="p-eyebrow"><?= e(t('Attached Evidence', 'Kalakip na Ebidensya')) ?></p>
      <?php if (!$media): ?>
        <p class="p-none-line"><?= e(t('No photo or video was attached to this complaint.', 'Walang larawan o video na kalakip sa sumbong na ito.')) ?></p>
      <?php else: ?>
        <div class="p-media">
          <?php foreach ($media as $m): ?>
            <?php $mime = (string) ($m['mime_type'] ?? ''); ?>
            <?php if (str_starts_with($mime, 'video/')): ?>
              <!-- Video support has existed since 0033, but this viewer used to
                   render every attachment as an <img> regardless of mime_type —
                   a video just showed as a broken image with no way to watch
                   it. Not wrapped in the usual <a>: a click on the native
                   controls would otherwise also fire the anchor's navigation. -->
              <div class="p-media-thumb p-media-video">
                <video controls preload="metadata" playsinline>
                  <source src="<?= e($m['media_url']) ?>" type="<?= e($mime) ?>">
                  <?= e(t('Your browser cannot play this video.', 'Hindi ma-play ng browser ang video na ito.')) ?>
                  <a href="<?= e($m['media_url']) ?>" target="_blank" rel="noopener"><?= e(t('Open it directly', 'Buksan ito nang direkta')) ?></a>.
                </video>
                <span class="p-media-size"><?= e(byte_size((int) $m['bytes'])) ?></span>
              </div>
            <?php else: ?>
              <a class="p-media-thumb" href="<?= e($m['media_url']) ?>" target="_blank" rel="noopener">
                <img src="<?= e(cld_thumb($m['media_url'], 480)) ?>" alt="<?= e(t('Evidence submitted with ', 'Ebidensyang isinumite kasama ng ') . $report['tracking_id']) ?>" loading="lazy">
                <span class="p-media-size"><?= e(byte_size((int) $m['bytes'])) ?></span>
              </a>
            <?php endif; ?>
          <?php endforeach; ?>
        </div>
      <?php endif; ?>
    </div>

    <?php if ($evidence): ?>
      <div class="p-sec">
        <p class="p-eyebrow"><?= e(t("Barangay's Photos", 'Mga Larawan ng Barangay')) ?></p>
        <div class="p-media">
          <?php foreach ($evidence as $m): ?>
            <a class="p-media-thumb" href="<?= e($m['media_url']) ?>" target="_blank" rel="noopener">
              <img src="<?= e(cld_thumb($m['media_url'], 480)) ?>" alt="<?= e($m['kind'] === 'resolution' ? t('Resolution proof', 'Patunay ng resolusyon') : t('Barangay update photo', 'Larawan ng update ng barangay')) ?>" loading="lazy">
              <span class="p-media-size"><?= e($m['kind'] === 'resolution' ? t('Resolution', 'Resolusyon') : t('Update', 'Update')) ?> · <?= e(byte_size((int) $m['bytes'])) ?></span>
            </a>
          <?php endforeach; ?>
        </div>
      </div>
    <?php endif; ?>

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
      <div class="p-sec">
        <p class="p-eyebrow"><?= e(t('Field Report', 'Ulat mula sa Lugar')) ?></p>
        <?php foreach ($resolved as $d): ?>
          <?php $shots = $proof[$d['id']] ?? []; ?>
          <p class="p-meta-line">
            <?= e(formal_or($d['tanod']['full_name'] ?? null, t('Barangay tanod', 'Tanod ng barangay'))) ?>
            <?php if (!empty($d['resolved_at'])): ?>
              &middot; <?= e(long_datetime($d['resolved_at'])) ?>
            <?php endif; ?>
          </p>
          <?php if (!empty($d['field_report_text'])): ?>
            <p class="p-desc"><?= nl2br(e($d['field_report_text'])) ?></p>
          <?php else: ?>
            <p class="p-none-line"><?= e(t('No narrative was submitted.', 'Walang isinumiteng salaysay.')) ?></p>
          <?php endif; ?>

          <?php if ($shots): ?>
            <div class="p-media">
              <?php foreach ($shots as $m): ?>
                <a class="p-media-thumb" href="<?= e($m['media_url']) ?>"
                   target="_blank" rel="noopener">
                  <img src="<?= e(cld_thumb($m['media_url'], 480)) ?>"
                       alt="<?= e(t('Proof photo for ', 'Larawang patunay para sa ') . $report['tracking_id']) ?>"
                       loading="lazy">
                  <span class="p-media-size"><?= e(byte_size((int) $m['bytes'])) ?></span>
                </a>
              <?php endforeach; ?>
            </div>
          <?php else: ?>
            <p class="p-none-line"><?= e(t('No photo proof was attached.', 'Walang kalakip na larawang patunay.')) ?></p>
          <?php endif; ?>
        <?php endforeach; ?>
      </div>
    <?php endif; ?>
    </article>

  <!-- ---------- the register row, as designed ---------- -->
  <div class="p-card p-meta-strip">
    <div><small><?= e(t('Resident', 'Residente')) ?></small><b><?= !empty($report['is_anonymous'])
              ? '<span class="p-anon">' . e(t('Anonymous', 'Hindi nagpakilala')) . '</span>'
              : e(formal_or($report['resident']['full_name'] ?? null, t('Unknown', 'Hindi kilala'))) ?></b></div>
    <div><small><?= e(t('Complaint ID', 'ID ng Sumbong')) ?></small><b class="p-num"><?= e($report['tracking_id']) ?></b></div>
    <div><small><?= e(t('Category', 'Kategorya')) ?></small><b><?= e(category_label($report['category'])) ?></b></div>
    <div><small><?= e(t('Filed', 'Naisampa')) ?></small><b class="p-num"><?= e(short_date($report['created_at'])) ?></b></div>
  </div>


  </div>
  <!-- ---------- timeline ---------- -->
  <section class="p-card p-card-pad">
    <p class="p-eyebrow"><?= e(t('Activity Timeline', 'Takbo ng Aktibidad')) ?></p>

    <?php
    $trail  = $trail ?? [];
    $broken = array_values(array_filter($trail, fn($t) => empty($t['intact'])));
    ?>
    <?php if ($trail && !$broken): ?>
      <p class="p-trail-ok">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2"
             stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
          <path d="M12 3l7 3v6c0 4.5-3 7.5-7 9-4-1.5-7-4.5-7-9V6z"/><polyline points="9 12 11 14 15 10"/>
        </svg>
        <?= e(t('Trail verified — ', 'Beripikado ang talaan — ')) ?><?= count($trail) ?><?= e(t(' entries, none altered since they were written.', ' tala, walang binago mula nang isulat.')) ?>
      </p>
    <?php elseif ($broken): ?>
      <p class="p-trail-bad" role="alert">
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
    // Rose (7 Oct 2026): Ask the barangay belongs in the activity too.
    foreach ($messages as $m) {
        $timeline[] = ['msg' => true, 'from_barangay' => !empty($m['from_barangay']),
                       'remark' => $m['body'] ?? '', 'created_at' => $m['created_at'],
                       'repeat' => 1, 'last_at' => null];
    }
    usort($timeline, fn($a, $b) => strcmp((string) $a['created_at'], (string) $b['created_at']));
    ?>
    <ul class="p-timeline">
      <?php foreach ($timeline as $l): ?>
        <li>
          <span class="p-tl-dot" aria-hidden="true"><svg width="13" height="13"><use href="#i-flag"/></svg></span>
          <b class="p-tl-title"><?= e(!empty($l['msg'])
                ? ($l['from_barangay'] ? t('Barangay replied to the resident', 'Sumagot ang barangay sa residente') : t('Resident asked the barangay', 'Nagtanong ang residente sa barangay'))
                : timeline_title($l)) ?><?php if ($l['repeat'] > 1): ?> <span class="p-sub">&times; <?= (int) $l['repeat'] ?></span><?php endif; ?></b>
          <small class="p-tl-when"><?= e(long_datetime($l['created_at'])) ?><?php if ($l['repeat'] > 1): ?> &ndash; <?= e(t('last', 'huli')) ?> <?= e(long_datetime($l['last_at'])) ?><?php endif; ?></small>
          <?php if (!empty($l['remark'])): ?>
            <div class="p-quote"><?= e(preg_replace(['/\b1 time\(s\)/', '/time\(s\)/'], ['1 time', 'times'], (string) $l['remark'])) ?></div>
          <?php endif; ?>
          <small class="p-tl-who">
            <?= !empty($l['msg'])
                ? e($l['from_barangay'] ? t('Barangay', 'Barangay') : formal_or($report['resident']['full_name'] ?? null, t('Resident', 'Residente')))
                : (!empty($l['is_system'])
                ? e(t('System', 'System'))
                : e(name_or($l['by']['full_name'] ?? null, t('Barangay staff', 'Kawani ng barangay')))) ?>
          </small>
        </li>
      <?php endforeach; ?>

      <li class="p-now">
        <span class="p-tl-dot p-orange" aria-hidden="true"><svg width="13" height="13"><use href="#i-clock"/></svg></span>
        <small class="p-tl-when"><?= e(t('Today', 'Ngayon')) ?> &middot; <?= e((new DateTimeImmutable('now', new DateTimeZone('Asia/Manila')))->format('g:i A')) ?></small>
      </li>
    </ul>
  </section>

  <!-- ---------- resident feedback ---------- -->
  <!-- Only ever possible on a finished report — feedback_insert (0003)
       requires status in (resolved, closed), same gate the resident
       app's own feedback card uses. Shown either way once finished, so
       "no rating yet" reads as a fact, not a missing feature. -->
  <?php if (in_array($status, ['resolved', 'closed'], true)): ?>
  <section class="p-card p-card-pad">
    <p class="p-eyebrow"><?= e(t('Resident Feedback', 'Puna ng Residente')) ?></p>
    <?php if ($feedback): ?>
      <div class="p-fb-stars" role="img"
           aria-label="<?= e(t('Rated ', 'Rating na ')) ?><?= (int) $feedback['rating'] ?><?= e(t(' out of 5 stars', ' sa 5 bituin')) ?>">
        <?php for ($i = 1; $i <= 5; $i++): ?>
          <svg class="p-fb-star<?= $i <= (int) $feedback['rating'] ? ' p-filled' : '' ?>"
               viewBox="0 0 24 24" aria-hidden="true">
            <path d="M12 2l3.09 6.26L22 9.27l-5 4.87L18.18 21 12 17.77 5.82 21 7 14.14 2 9.27l6.91-1.01L12 2z"/>
          </svg>
        <?php endfor; ?>
      </div>
      <?php if (!empty($feedback['comment'])): ?>
        <p class="p-quote">&ldquo;<?= nl2br(e($feedback['comment'])) ?>&rdquo;</p>
      <?php endif; ?>
      <small class="p-tl-when"><?= e(t('Submitted', 'Isinumite')) ?> <?= e(long_datetime($feedback['submitted_at'])) ?></small>
    <?php else: ?>
      <p class="p-none-line"><?= e(t('The resident has not left feedback on this complaint yet.', 'Hindi pa nag-iiwan ng puna ang residente sa sumbong na ito.')) ?></p>
    <?php endif; ?>
  </section>
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
      <div class="p-card p-card-pad p-thread-card">
        <p class="p-eyebrow"><?= e(t('Dispatch Updates', 'Mga Update sa Dispatch')) ?></p>
        <?php foreach ($threaded as $d): ?>
          <?php $tanodName = $d['tanod']['full_name'] ?? t('Tanod', 'Tanod'); ?>
          <p class="p-meta-line"><?= e($tanodName) ?></p>
          <?php if (empty($thread[$d['id']])): ?>
            <p class="p-none-line"><?= e(t('No updates yet.', 'Wala pang update.')) ?></p>
          <?php else: ?>
            <ol class="p-thread">
              <?php foreach ($thread[$d['id']] as $u): ?>
                <?php if ($u['kind'] === 'step'): ?>
                  <li class="p-step">
                    <?= e($u['step'] === 'arrived'
                        ? t('Tanod arrived', 'Nakarating ang tanod')
                        : t('Tanod on the way', 'Papunta na ang tanod')) ?>
                    &middot; <?= e(long_datetime($u['created_at'])) ?>
                  </li>
                <?php else: ?>
                  <?php $fromTanod = $u['author_id'] === ($d['tanod']['id'] ?? null); ?>
                  <li class="p-bubble <?= $fromTanod ? 'p-them' : 'p-me' ?>">
                    <span class="p-who-s"><?= e($fromTanod ? $tanodName : t('Barangay', 'Barangay')) ?></span>
                    <?php if (!empty($u['body'])): ?>
                      <p><?= nl2br(e($u['body'])) ?></p>
                    <?php endif; ?>
                    <?php if (!empty($threadMedia[$u['id']])): ?>
                      <div class="p-thread-media">
                        <?php foreach ($threadMedia[$u['id']] as $m): ?>
                          <a href="<?= e($m['media_url']) ?>" target="_blank" rel="noopener">
                            <img src="<?= e(cld_thumb($m['media_url'], 480)) ?>" alt="<?= e(t('Update photo', 'Larawan ng update')) ?>" loading="lazy">
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
            <form method="post" class="p-composer">
              <input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>">
              <input type="hidden" name="action" value="dispatch_reply">
              <input type="hidden" name="dispatch" value="<?= e($d['id']) ?>">
              <textarea class="p-note" name="body" rows="2" maxlength="2000" required
                        placeholder="<?= e(t('Reply to the tanod…', 'Sumagot sa tanod…')) ?>"></textarea>
              <button type="submit" class="p-btn p-btn-primary p-btn-sm"><?= e(t('Send', 'Ipadala')) ?></button>
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
      <div class="p-card p-card-pad p-thread-card" id="resident-messages">
        <p class="p-eyebrow"><?= e(t('Questions from the Resident', 'Mga Tanong ng Residente')) ?></p>
        <?php if (!$messages): ?>
          <p class="p-none-line"><?= e(t('No questions yet. The resident can ask from their app, and you can write to them first.', 'Wala pang tanong. Maaaring magtanong ang residente mula sa app, at maaari mo rin silang sulatan muna.')) ?></p>
        <?php else: ?>
          <ol class="p-thread">
            <?php foreach ($messages as $m): ?>
              <li class="p-bubble <?= !empty($m['from_barangay']) ? 'p-me' : 'p-them' ?>">
                <span class="p-who-s"><?= e(!empty($m['from_barangay']) ? t('Barangay', 'Barangay') : t('Resident', 'Residente')) ?></span>
                <p><?= nl2br(e($m['body'])) ?></p>
                <time><?= e(long_datetime($m['created_at'])) ?></time>
              </li>
            <?php endforeach; ?>
          </ol>
        <?php endif; ?>
        <?php if ($canMessage): ?>
          <form method="post" class="p-composer">
            <input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>">
            <input type="hidden" name="action" value="resident_reply">
            <textarea class="p-note" name="body" rows="2" maxlength="1000" required
                      placeholder="<?= e(t('Answer the resident…', 'Sagutin ang residente…')) ?>"></textarea>
            <button type="submit" class="p-btn p-btn-primary p-btn-sm"><?= e(t('Send', 'Ipadala')) ?></button>
          </form>
        <?php endif; ?>
      </div>
    <?php endif; ?>
  </div>

  <!-- ---------- admin controls ---------- -->
  <?php
    $hid     = (string) ($report['handler_id'] ?? '');
    $mine    = $hid !== '' && $hid === $admin['id'];
    $theirs  = $hid !== '' && !$mine;
    $hName   = (string) ($report['handler']['full_name'] ?? '');
    $GLOBALS['ss_case'] = ['id' => $id, 'tracking' => $report['tracking_id']];
  ?>
  <aside class="p-card p-controls<?= $theirs ? ' ss-readonly' : '' ?>">
    <p class="p-eyebrow"><?= e(t('Admin Controls', 'Kontrol ng Admin')) ?></p>

    <?php // 0087: who handles this case. ?>
    <?php if ($hid === ''): ?>
      <div class="ss-handler"><div><b><?= e(t('Nobody is handling this case yet', 'Wala pang humahawak sa kasong ito')) ?></b><span class="p-hint"><?= e(t('Accepting it, or any action on it, makes it yours.', 'Kapag tinanggap mo ito o kumilos ka rito, ikaw na ang hahawak.')) ?></span></div></div>
    <?php elseif ($mine): ?>
      <div class="ss-handler"><?= admin_chip($hid, $hName, 32) ?><div><b><?= e(t('You are handling this case', 'Ikaw ang humahawak sa kasong ito')) ?></b><span class="p-hint"><?= e(t('since', 'mula')) ?> <?= e(long_datetime($report['handled_since'])) ?></span></div></div>
    <?php else: ?>
      <div class="ss-handler"><?= admin_chip($hid, $hName, 32) ?><div><b><?= e($hName) ?></b><span class="p-hint"><?= e(t('handling since', 'humahawak mula')) ?> <?= e(long_datetime($report['handled_since'])) ?></span></div></div>
      <div class="ss-locked"><?= e(sprintf(t('Only %s can act on this case while they handle it. You can still read everything.', 'Si %s lang ang makakakilos sa kasong ito habang hawak niya. Mababasa mo pa rin ang lahat.'), $hName)) ?></div>
      <details class="p-fix" data-keep-details>
        <summary><?= e(t('Take over', 'Kunin')) ?></summary>
        <form method="post" class="p-ctl-stack" data-keep>
          <input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>">
          <input type="hidden" name="action" value="take_over">
          <div class="p-cfield"><label class="p-flabel" for="to-reason"><?= e(sprintf(t('Reason — %s sees it', 'Dahilan — makikita ni %s'), $hName)) ?></label>
            <input class="p-input-plain" id="to-reason" name="reason" required minlength="3" maxlength="300" placeholder="<?= e(t('e.g. Rose is off shift today.', 'hal. Wala si Rose ngayong araw.')) ?>"></div>
          <button class="p-btn p-btn-primary p-btn-sm" type="submit"><?= e(t('Take over', 'Kunin')) ?></button>
        </form>
      </details>
    <?php endif; ?>
    <div id="ss-also" hidden></div>
    <?php if ($handlerLog): ?>
      <ul class="ss-hist">
        <?php foreach ($handlerLog as $h): ?>
          <li><?= e(name_or($h['admin']['full_name'] ?? null, '')) ?> <?= e(match ($h['action']) {
              'take' => t('took the case', 'kinuha ang kaso'),
              'release' => t('released it', 'binitawan ito'),
              default => t('took over from', 'kinuha mula kay') . ' ' . ($h['prev']['full_name'] ?? ''),
          }) ?> · <?= e(long_datetime($h['created_at'])) ?><?= !empty($h['reason']) ? ' — “' . e($h['reason']) . '”' : '' ?></li>
        <?php endforeach; ?>
      </ul>
    <?php endif; ?>

    <?php if ($canJudge): ?>
      <form method="post" class="p-ctl-stack" id="review-form">
        <input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>">

        <p class="p-ctl-note"><?= e(t('Press', 'Pindutin ang')) ?> <kbd>A</kbd> <?= e(t('to accept,', 'para tanggapin,')) ?> <kbd>D</kbd> <?= e(t('to deny.', 'para tanggihan.')) ?></p>

        <!-- formnovalidate: the hidden denial reason must never stop an
             Accept (Rose, 27 Sep 2026 — Accept did nothing). -->
        <button class="p-btn p-btn-primary p-btn-block" type="submit" name="action" value="accept" formnovalidate>
          <?= p_icon('i-check', 18) ?>
          <?= e(t('Accept Report', 'Tanggapin ang Ulat')) ?>
        </button>

        <button class="p-btn p-btn-danger-soft p-btn-block" type="button" id="deny-toggle" aria-expanded="false"
                aria-controls="deny-panel">
          <?= p_icon('i-x', 18) ?>
          <?= e(t('Reject Report', 'Tanggihan ang Ulat')) ?>
        </button>

        <div class="p-reveal" id="deny-panel" hidden>
          <label class="p-flabel" for="reason">
            <?= e(t('Reason for denial — the resident sees this', 'Dahilan ng pagtanggi — makikita ito ng residente')) ?>
          </label>
          <textarea class="p-note" id="reason" name="reason" rows="3" maxlength="200"
                    placeholder="<?= e(t('e.g. Outside barangay jurisdiction — refer to the city ENRO.', 'hal. Labas sa sakop ng barangay — i-refer sa ENRO ng lungsod.')) ?>"></textarea>

          <label class="p-check">
            <input type="checkbox" name="abusive" value="1">
            <?= e(t('Flag as abusive or fabricated', 'Markahang mapang-abuso o gawa-gawa')) ?>
          </label>
          <p class="p-ctl-note">
            <?= e(t('Only for a fake, malicious, or bad-faith report — not an honest mistake like the wrong barangay or a duplicate. Three flagged reports from the same resident automatically restrict their account from filing new ones, the same way Suspend does today.',
                    'Para lamang sa pekeng ulat, may masamang layunin, o hindi tapat — hindi sa tapat na pagkakamali gaya ng maling barangay o doble. Kapag tatlong ulat ng iisang residente ang namarkahan, awtomatikong hindi na siya makakapagsampa ng bago, gaya ng Suspend.')) ?>
            <?php if (count($abuseHistory) > 0): ?>
              <?= e(t('This resident already has', 'Mayroon nang')) ?>
              <strong><?= (int) count($abuseHistory) ?></strong>
              <?= e(t('on file', 'na naitala sa residenteng ito')) ?><?= count($abuseHistory) >= 2
                  ? e(t(' — one more will restrict them.', ' — isa pa at mapipigilan na siya.')) : '.' ?>
            <?php endif; ?>
          </p>

          <button class="p-btn p-btn-danger-solid p-btn-sm" type="submit" name="action" value="deny">
            <?= e(t('Confirm denial', 'Kumpirmahin ang pagtanggi')) ?>
          </button>
        </div>
      </form>

    <?php elseif ($canAssign): ?>
      <form method="post" class="p-ctl-stack" id="assign-form">
        <input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>">

        <p class="p-eyebrow" style="margin:0"><?= e(t('Assign Tanod', 'Mag-assign ng Tanod')) ?></p>

        <?php if (!$roster): ?>
          <p class="p-none-line"><?= e(t('No tanod accounts exist yet. Add them under Personnel.', 'Wala pang account ng tanod. Idagdag sila sa Mga Tanod.')) ?></p>
        <?php endif; ?>

        <div class="p-roster">
          <?php foreach ($roster as $i => $t): ?>
            <?php $ok = !empty($t['assignable']) && !empty($t['location_fresh']); $idle = !empty($t['assignable']) && empty($t['location_fresh']); ?>
            <label class="p-tanod-opt<?= $ok ? '' : ' p-out' ?>">
              <input type="radio" name="tanod" value="<?= e($t['tanod_id']) ?>"
                     <?= $ok ? '' : 'disabled' ?>>
              <span class="p-who">
                <?= e(formal_name($t['full_name'])) ?>
                <?php if ($ok && $t['metres'] !== null): ?>
                  <small class="<?= empty($t['location_fresh']) ? 'p-stale' : '' ?>">
                    <?= e(distance_label((float) $t['metres'])) ?><?= e(t(' away', ' ang layo')) ?><?php
                      if (empty($t['location_fresh'])) echo e(t(', last seen a while ago', ', matagal nang huling nakita')); ?>
                  </small>
                <?php endif; ?>
              </span>
              <span class="p-status-dot <?= $ok ? 'p-on-c' : 'p-off-c' ?>">
                <?= $ok ? 'ONLINE' : ($idle ? e(t('NOT ACTIVE', 'HINDI AKTIBO')) : e(strtoupper((string) ($t['unavailable_why'] ?? 'OFFLINE')))) ?>
              </span>
              <span class="p-pick"><?= $ok ? e(t('Assign', 'I-assign')) : '&mdash;' ?></span>
            </label>
          <?php endforeach; ?>
        </div>

        <div class="p-cfield">
          <!-- 0071 (Rose, 27 Sep 2026): the admin, not the system, gives the
               tanod their instructions and the complaint its deadline. -->
          <label class="p-flabel" for="note"><?= e(t('Instructions for the tanod', 'Mga tagubilin para sa tanod')) ?></label>
          <textarea class="p-note" id="note" name="note" rows="2" maxlength="500" required
                    placeholder="<?= e(t('What to check, who to talk to, what to bring back.', 'Ano ang titingnan, sino ang kakausapin, ano ang iuulat.')) ?>"></textarea>
        </div>

        <div class="p-cfield">
          <label class="p-flabel" for="target"><?= e(t('Target date resolution', 'Target na petsa ng paglutas')) ?></label>
          <input class="p-input-plain" type="datetime-local" id="target" name="target" required
                 min="<?= e((new DateTimeImmutable('now', new DateTimeZone('Asia/Manila')))->format('Y-m-d\TH:i')) ?>"
                 value="<?= e(local_input_value($report['due_at'])) ?>">
          <p class="p-hint" style="margin:6px 0 0">
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
        <?php if (!empty($report['due_at'])): ?>
          <div class="p-cfield">
            <label class="p-flabel" for="target-reason"><?= e(t('Reason, if you move the date later', 'Dahilan, kung iuurong ang petsa')) ?></label>
            <input class="p-input-plain" type="text" id="target-reason" name="target_reason" maxlength="300">
            <p class="p-hint" style="margin:6px 0 0"><?= e(sprintf(t('Extensions used: %d of %d.', 'Nagamit na extension: %d sa %d.'), $extUsed, $extCap)) ?></p>
          </div>
        <?php endif; ?>

        <?php $anyActive = (bool) array_filter($roster, fn($t) => !empty($t['assignable']) && !empty($t['location_fresh'])); ?>
        <?php if (!$anyActive): ?>
          <p class="p-clock p-late" style="margin:0"><?= e(t('No tanod is active right now. Dispatch opens when a tanod is on duty with their app open.', 'Walang aktibong tanod ngayon. Mabubuksan ang dispatch kapag may tanod na naka-duty at bukas ang app.')) ?></p>
        <?php endif; ?>
        <button class="p-btn p-btn-orange p-btn-block" type="submit" name="action" value="dispatch"<?= $anyActive ? '' : ' disabled' ?>><?= e(t('Dispatch', 'I-dispatch')) ?></button>
      </form>

    <?php elseif ($status === 'rejected' && $appealReason !== null): ?>
      <!-- 0057 — the resident disputed this denial. Granting hands the
           case straight back to the roster (canAssign becomes true on
           reload, same as any freshly validated complaint) rather than
           adding a second review step the design never asked for. -->
      <form method="post" class="p-ctl-stack" id="appeal-form">
        <input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>">

        <p class="p-ctl-note"><?= e(t('The resident is appealing this denial.', 'Inaapela ng residente ang pagtangging ito.')) ?></p>

        <div class="p-cfield">
          <label class="p-flabel"><?= e(t("Resident's reason", 'Dahilan ng residente')) ?></label>
          <p class="p-desc"><?= e($appealReason) ?></p>
        </div>

        <div class="p-cfield">
          <label class="p-flabel" for="remark">
            <?= e(t('Note for the trail (optional)', 'Tala para sa talaan (opsyonal)')) ?>
          </label>
          <textarea class="p-note" id="remark" name="remark" rows="2" maxlength="300"
                    placeholder="<?= e(t('e.g. New photos confirm the report — reinstating.', 'hal. Kinukumpirma ng bagong larawan ang ulat — ibinabalik.')) ?>"></textarea>
        </div>

        <button class="p-btn p-btn-success p-btn-block" type="submit" name="action" value="appeal_grant">
          <?= p_icon('i-check', 18) ?>
          <?= e(t('Grant Appeal', 'Pagbigyan ang Apela')) ?>
        </button>
        <p class="p-ctl-note">
          <?= e(t('Moves this complaint back to Validated with a fresh resolution window. To decline, simply leave this as is — the complaint stays denied.',
                  'Ibabalik ang sumbong sa Tinanggap na may bagong palugit sa paglutas. Para tanggihan, hayaan lamang ito — mananatiling tinanggihan ang sumbong.')) ?>
        </p>
      </form>

    <?php else: ?>
      <?php if ($active): ?>
        <div class="p-tanod-card">
          <p class="p-eyebrow" style="margin:0"><?= e(t('Currently with', 'Kasalukuyang hawak ni')) ?></p>
          <p class="p-assigned-name"><?= e(formal_or($active['tanod']['full_name'] ?? null, t('Unknown tanod', 'Hindi kilalang tanod'))) ?></p>
          <p class="p-kv-line">
            <?= e(status_label($active['state'])) ?>
            &middot; <?= e(t('assigned', 'na-assign')) ?> <?= e(relative_time($active['assigned_at'])) ?>
          </p>
          <?php if ($active['state'] === 'assigned' && !empty($active['accept_due_at'])): ?>
            <p class="p-kv-line">
              <?= e(t('Must accept by', 'Dapat tanggapin bago')) ?> <?= e(long_datetime($active['accept_due_at'])) ?>
            </p>
          <?php endif; ?>
          <?php if (!empty($active['admin_instructions'])): ?>
            <p class="p-quote"><?= e($active['admin_instructions']) ?></p>
          <?php endif; ?>
          <?php if (!empty($report['due_at'])): ?>
            <p class="p-kv-line"><?= e(t('Resolution target:', 'Target na paglutas:')) ?> <strong><?= e(long_datetime($report['due_at'])) ?></strong></p>
          <?php endif; ?>
        </div>

        <?php // 0070: the admin's reroute. The system's own (a tanod's
              // hand-back, a lapsed acceptance window) needs nothing here. ?>
        <details class="p-fix">
          <summary><?= e(t('Reroute this dispatch', 'Ilipat ang dispatch na ito')) ?></summary>
          <form method="post" class="p-ctl-stack">
            <input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>">
            <input type="hidden" name="action" value="reroute">
            <input type="hidden" name="dispatch" value="<?= e($active['id']) ?>">
            <div class="p-roster">
              <label class="p-tanod-opt">
                <input type="radio" name="to" value="" checked>
                <span class="p-who"><?= e(t('Let the system find the nearest tanod', 'Hayaang hanapin ng sistema ang pinakamalapit na tanod')) ?></span>
                <span class="p-pick"><?= e(t('Auto', 'Auto')) ?></span>
              </label>
              <?php foreach ($roster as $t): ?>
                <?php if (($t['tanod_id'] ?? null) === ($active['tanod']['id'] ?? null)) continue; ?>
                <?php $ok = !empty($t['assignable']) && !empty($t['location_fresh']); $idle = !empty($t['assignable']) && empty($t['location_fresh']); ?>
                <label class="p-tanod-opt<?= $ok ? '' : ' p-out' ?>">
                  <input type="radio" name="to" value="<?= e($t['tanod_id']) ?>" <?= $ok ? '' : 'disabled' ?>>
                  <span class="p-who">
                    <?= e(formal_name($t['full_name'])) ?>
                    <?php if ($ok && $t['metres'] !== null): ?>
                      <small class="<?= empty($t['location_fresh']) ? 'p-stale' : '' ?>">
                        <?= e(distance_label((float) $t['metres'])) ?><?= e(t(' away', ' ang layo')) ?>
                      </small>
                    <?php endif; ?>
                  </span>
                  <span class="p-status-dot <?= $ok ? 'p-on-c' : 'p-off-c' ?>">
                    <?= $ok ? 'ONLINE' : ($idle ? e(t('NOT ACTIVE', 'HINDI AKTIBO')) : e(strtoupper((string) ($t['unavailable_why'] ?? 'OFFLINE')))) ?>
                  </span>
                  <span class="p-pick"><?= $ok ? e(t('Move', 'Ilipat')) : '&mdash;' ?></span>
                </label>
              <?php endforeach; ?>
            </div>
            <div class="p-cfield">
              <label class="p-flabel" for="reroute-reason"><?= e(t('Reason', 'Dahilan')) ?></label>
              <textarea class="p-note" id="reroute-reason" name="reason" rows="2" maxlength="300" required
                        placeholder="<?= e(t('e.g. Tanod is needed at another emergency.', 'hal. Kailangan ang tanod sa ibang emergency.')) ?>"></textarea>
            </div>
            <button class="p-btn p-btn-primary p-btn-sm" type="submit"><?= e(t('Reroute', 'Ilipat')) ?></button>
          </form>
        </details>
      <?php else: ?>
        <p class="p-none-line">
          <?= $status === 'rejected'
              ? e(t('This complaint was denied. Nothing further is required.', 'Tinanggihan ang sumbong na ito. Wala nang kailangang gawin.'))
              : e(t('No action is available at this stage.', 'Walang aksyong magagawa sa yugtong ito.')) ?>
        </p>
      <?php endif; ?>

      <?php if (!empty($report['due_at']) && !$active): ?>
        <p class="p-kv-line"><?= e(t('Resolution target:', 'Target na paglutas:')) ?> <strong><?= e(long_datetime($report['due_at'])) ?></strong></p>
      <?php endif; ?>
    <?php endif; ?>

    <?php if (!empty($report['resolution_submitted_at'])): ?>
      <?php // 0073 — Approve Complaint Resolution: the tanod's report is in the Field Report block. ?>
      <div class="p-req-card">
        <p class="p-eyebrow" style="margin:0"><?= e(t('Resolution waiting for approval', 'Resolusyong naghihintay ng pag-apruba')) ?></p>
        <p class="p-ctl-note"><?= e(t("Check the tanod's report and proof under Field Report, then approve it or send it back.", 'Suriin ang ulat at patunay ng tanod sa Field Report, saka aprubahan o ibalik.')) ?></p>
        <form method="post" class="p-ctl-stack">
          <input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>">
          <button class="p-btn p-btn-success p-btn-block" type="submit" name="action" value="approve_resolution"><?= e(t('Approve Resolution', 'Aprubahan ang Resolusyon')) ?></button>
        </form>
        <details class="p-fix">
          <summary><?= e(t('Return to the tanod', 'Ibalik sa tanod')) ?></summary>
          <form method="post" class="p-ctl-stack">
            <input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>">
            <input type="hidden" name="action" value="reject_resolution">
            <div class="p-cfield">
              <label class="p-flabel" for="return-reason"><?= e(t('What still needs doing — the tanod sees this', 'Ano pa ang kailangang gawin — makikita ito ng tanod')) ?></label>
              <textarea class="p-note" id="return-reason" name="reason" rows="2" maxlength="300" required></textarea>
            </div>
            <button class="p-btn p-btn-danger-solid p-btn-sm" type="submit"><?= e(t('Return to Tanod', 'Ibalik sa Tanod')) ?></button>
          </form>
        </details>
      </div>
    <?php endif; ?>

    <?php if ($escRequest && empty($report['referred_to'])): ?>
      <?php // 0073 — Manage Escalation Request. ?>
      <div class="p-req-card">
        <p class="p-eyebrow" style="margin:0"><?= e(t('Escalation request', 'Hiling na i-escalate')) ?></p>
        <p class="p-kv-line">
          <?= e(name_or($escRequest['requester']['full_name'] ?? null, t('Tanod', 'Tanod'))) ?> &middot; <?= e(relative_time($escRequest['created_at'])) ?>
        </p>
        <p class="p-quote"><?= nl2br(e($escRequest['reason'])) ?></p>
        <details class="p-fix" open>
          <summary><?= e(t('Approve: escalate', 'Aprubahan: i-escalate')) ?></summary>
          <form method="post" class="p-ctl-stack">
            <input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>">
            <input type="hidden" name="action" value="approve_escalation">
            <input type="hidden" name="request" value="<?= e($escRequest['id']) ?>">
            <?php office_picker('esc-agency', $escRequest['suggested_office'] ?? null); ?>
            <div class="p-cfield">
              <label class="p-flabel" for="esc-note"><?= e(t('Note — the resident sees this', 'Tala — makikita ito ng residente')) ?></label>
              <textarea class="p-note" id="esc-note" name="note" rows="2" maxlength="300"></textarea>
            </div>
            <button class="p-btn p-btn-danger-solid p-btn-sm" type="submit"><?= e(t('Approve and escalate', 'Aprubahan at i-escalate')) ?></button>
          </form>
        </details>
        <details class="p-fix">
          <summary><?= e(t('Deny the request', 'Tanggihan ang hiling')) ?></summary>
          <form method="post" class="p-ctl-stack">
            <input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>">
            <input type="hidden" name="action" value="deny_escalation">
            <input type="hidden" name="request" value="<?= e($escRequest['id']) ?>">
            <div class="p-cfield">
              <label class="p-flabel" for="esc-deny"><?= e(t('Reason — the tanod sees this', 'Dahilan — makikita ito ng tanod')) ?></label>
              <textarea class="p-note" id="esc-deny" name="reason" rows="2" maxlength="300" required></textarea>
            </div>
            <button class="p-btn p-btn-primary p-btn-sm" type="submit"><?= e(t('Deny', 'Tanggihan')) ?></button>
          </form>
        </details>
      </div>
    <?php endif; ?>

    <?php if (in_array($status, ['validated', 'assigned', 'in_progress', 'offline_investigation'], true)
              && empty($report['resolution_submitted_at'])): ?>
      <?php // 0073 + 0079, one form (Rose, 7 Oct 2026). ?>
      <details class="p-fix">
        <summary><?= e(t('Update status', 'I-update ang katayuan')) ?></summary>
        <form method="post" class="p-ctl-stack" enctype="multipart/form-data">
          <input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>">
          <input type="hidden" name="action" value="set_status">
          <div class="p-cfield">
            <label class="p-flabel" for="set-status"><?= e(t('New status', 'Bagong katayuan')) ?></label>
            <select class="p-input-plain" id="set-status" name="status">
              <option value=""><?= e(t('No change — just post an update', 'Walang pagbabago — mag-post lang ng update')) ?></option>
              <?php foreach (['in_progress', 'offline_investigation', 'resolved'] as $opt): ?>
                <?php if ($opt === $status) continue; ?>
                <option value="<?= e($opt) ?>"><?= e($opt === 'resolved' ? t('Resolved/Completed', 'Nalutas/Nakumpleto') : status_label($opt)) ?></option>
              <?php endforeach; ?>
            </select>
          </div>
          <div class="p-cfield">
            <label class="p-flabel" for="set-remark"><?= e(t('Remark — the resident sees this', 'Tala — makikita ito ng residente')) ?></label>
            <textarea class="p-note" id="set-remark" name="remark" rows="2" maxlength="500"
                      placeholder="<?= e(t('e.g. The barangay talked to the store owner; the sidewalk will be cleared by Friday.', 'hal. Nakausap ng barangay ang may-ari ng tindahan; malilinis ang bangketa sa Biyernes.')) ?>"></textarea>
          </div>
          <div class="p-cfield">
            <label class="p-flabel" for="set-photos"><?= e(t('Proof photos (optional, up to 6) — the resident sees these', 'Mga larawang patunay (opsyonal, hanggang 6) — makikita ito ng residente')) ?></label>
            <input class="p-input-plain" type="file" id="set-photos" name="photos[]" accept="image/jpeg,image/png,image/webp" multiple>
          </div>
          <?php if (empty($report['referred_to'])): ?>
          <div class="p-cfield">
            <label class="p-flabel" for="set-target"><?= e(t('Target date (optional)', 'Target na petsa (opsyonal)')) ?></label>
            <input class="p-input-plain" type="datetime-local" id="set-target" name="target"
                   min="<?= e((new DateTimeImmutable('now', new DateTimeZone('Asia/Manila')))->format('Y-m-d\TH:i')) ?>">
            <p class="p-hint" style="margin:6px 0 0">
              <?php if (!empty($report['due_at'])): ?>
                <?= e(t('Currently due', 'Kasalukuyang takdang oras:')) ?> <?= e(long_datetime($report['due_at'])) ?>.
                <?= e(sprintf(t('Extensions used: %d of %d.', 'Nagamit na extension: %d sa %d.'), $extUsed, $extCap)) ?>
              <?php else: ?>
                <?= e(t('No target date yet. The resident is told the one you set.', 'Wala pang target na petsa. Sasabihin sa residente ang itatakda mo.')) ?>
              <?php endif; ?>
            </p>
          </div>
          <?php if (!empty($report['due_at'])): ?>
            <div class="p-cfield">
              <label class="p-flabel" for="set-reason"><?= e(t('Reason (optional), required if you move the date later', 'Dahilan (opsyonal), kailangan kung iuurong ang petsa')) ?></label>
              <input class="p-input-plain" type="text" id="set-reason" name="target_reason" maxlength="300">
            </div>
          <?php endif; ?>
          <?php endif; ?>
          <button class="p-btn p-btn-primary p-btn-sm" type="submit"><?= e(t('Update status', 'I-update ang katayuan')) ?></button>
        </form>
      </details>
    <?php endif; ?>

    <?php $openCase = in_array($status, ['validated', 'assigned', 'in_progress', 'offline_investigation'], true) && empty($report['referred_to']); ?>
    <?php if (!empty($report['higher_official'])): ?>
      <div class="p-esc-card">
        <p class="p-eyebrow" style="margin:0"><?= e(t('Handled by', 'Hawak ni')) ?></p>
        <p class="p-assigned-name"><?= e($report['higher_official']) ?></p>
        <p class="p-kv-line"><?= e(long_datetime($report['handed_up_at'])) ?></p>
        <?php if (!empty($report['higher_official_note'])): ?>
          <p class="p-quote"><?= e($report['higher_official_note']) ?></p>
        <?php endif; ?>
      </div>
    <?php endif; ?>

    <?php if ($openCase): ?>
      <?php // "Post an update" is now part of Update status (Rose, 7 Oct 2026). ?>

      <?php if ($extUsed >= $extCap && !empty($report['due_at'])): ?>
        <?php // 0079 (Rose) — no extensions left: hand it to a higher official. ?>
        <details class="p-fix" open>
          <summary><?= e(t('Hand to a higher official', 'Ipasa sa mas mataas na opisyal')) ?></summary>
          <form method="post" class="p-ctl-stack">
            <input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>">
            <input type="hidden" name="action" value="hand_up">
            <p class="p-ctl-note"><?= e(sprintf(t('The target date has been extended %d of %d times. It cannot move again; hand the case to an official instead.', 'Naiurong na ang target na petsa nang %d sa %d beses. Hindi na ito maiuurong; ipasa ang kaso sa isang opisyal.'), $extUsed, $extCap)) ?></p>
            <div class="p-cfield">
              <label class="p-flabel" for="hand-official"><?= e(t('Hand to', 'Ipasa kay')) ?></label>
              <select class="p-input-plain" id="hand-official" name="official" required data-office>
                <option value=""><?= e(t('Choose an official', 'Pumili ng opisyal')) ?></option>
                <option value="Punong Barangay"><?= e(t('Punong Barangay', 'Punong Barangay')) ?></option>
                <option value="Barangay Kagawad (Peace and Order)"><?= e(t('Barangay Kagawad (Peace and Order)', 'Barangay Kagawad (Kapayapaan at Kaayusan)')) ?></option>
                <option value="Barangay Kagawad"><?= e(t('Barangay Kagawad (another committee)', 'Barangay Kagawad (ibang komite)')) ?></option>
                <option value="Barangay Secretary"><?= e(t('Barangay Secretary', 'Kalihim ng Barangay')) ?></option>
                <option value="other"><?= e(t('Another official…', 'Ibang opisyal…')) ?></option>
              </select>
            </div>
            <div class="p-cfield" hidden>
              <label class="p-flabel" for="hand-official-other"><?= e(t('Name or position', 'Pangalan o posisyon')) ?></label>
              <input class="p-input-plain" type="text" id="hand-official-other" name="official_other" maxlength="80">
            </div>
            <div class="p-cfield">
              <label class="p-flabel" for="hand-note"><?= e(t('Note — the resident sees this', 'Tala — makikita ito ng residente')) ?></label>
              <textarea class="p-note" id="hand-note" name="note" rows="2" maxlength="300"></textarea>
            </div>
            <p class="p-ctl-note"><?= e(t('Any tanod on the case is stood down. The case stays open under the official, with a fresh set of extensions.', 'Ititigil ang sinumang tanod sa kaso. Mananatiling bukas ang kaso sa ilalim ng opisyal, na may bagong bilang ng extension.')) ?></p>
            <button class="p-btn p-btn-danger-solid p-btn-sm" type="submit"><?= e(t('Hand over', 'Ipasa')) ?></button>
          </form>
        </details>
      <?php endif; ?>
    <?php endif; ?>

    <?php if (!in_array($status, ['rejected', 'cancelled'], true)): ?>
      <?php // 0073 — the resident map shows published incidents: category and status only. ?>
      <form method="post" class="publish-toggle">
        <input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>">
        <input type="hidden" name="action" value="set_public">
        <label class="p-pub"><span><b><?= e(t("Show on residents' map", 'Ipakita sa mapa ng mga residente')) ?></b><small><?= e(t('Category and status only.', 'Kategorya at katayuan lamang.')) ?></small></span><input type="checkbox" role="switch" name="public" value="1" <?= !empty($report['is_public']) ? 'checked' : '' ?> data-autosubmit></label>
      </form>
    <?php endif; ?>

    <?php if (!empty($report['referred_to'])): ?>
      <div class="p-esc-card">
        <p class="p-eyebrow" style="margin:0"><?= e(t('Escalated to', 'In-escalate sa')) ?></p>
        <p class="p-assigned-name"><?= e($report['referred_to']) ?></p>
        <p class="p-kv-line"><?= e(long_datetime($report['referred_at'])) ?></p>
        <?php if (!empty($report['referral_note'])): ?>
          <p class="p-quote"><?= e($report['referral_note']) ?></p>
        <?php endif; ?>
        <a class="p-btn p-btn-ghost p-btn-block" target="_blank" rel="noopener" href="certificate.php?id=<?= e($id) ?>">
          <?= e(t('Certification of Lack of Jurisdiction', 'Sertipikasyon ng Kawalan ng Hurisdiksyon')) ?>
        </a>
      </div>
    <?php elseif (!in_array($status, ['resolved', 'closed', 'archived', 'rejected', 'cancelled'], true)): ?>
      <?php // 0072: escalation = referral to an office outside the barangay. ?>
      <details class="p-fix">
        <summary><?= e(t('Escalate to an outside office', 'I-escalate sa ibang tanggapan')) ?></summary>
        <form method="post" class="p-ctl-stack">
          <input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>">
          <input type="hidden" name="action" value="refer">
          <?php office_picker('refer-agency'); ?>
          <div class="p-cfield">
            <label class="p-flabel" for="refer-note"><?= e(t('Note — the resident sees this', 'Tala — makikita ito ng residente')) ?></label>
            <textarea class="p-note" id="refer-note" name="note" rows="2" maxlength="300"
                      placeholder="<?= e(t('e.g. Please visit the VAWC desk at the barangay hall with a valid ID.', 'hal. Pumunta sa VAWC desk sa barangay hall na may dalang valid ID.')) ?>"></textarea>
          </div>
          <p class="p-ctl-note"><?= e(t('This closes the complaint here and stands down any tanod on it. Afterwards you can print the Certification of Lack of Jurisdiction for the resident.', 'Isasara nito ang sumbong dito at ititigil ang sinumang tanod na nakatalaga. Pagkatapos, maaari mong i-print ang Sertipikasyon ng Kawalan ng Hurisdiksyon para sa residente.')) ?></p>
          <button class="p-btn p-btn-danger-solid p-btn-sm" type="submit"><?= e(t('Escalate', 'I-escalate')) ?></button>
        </form>
      </details>
    <?php endif; ?>

    <!-- ---------- map preview ---------- -->
    <!-- Martin's note / Rose's feedback: the preview had no way to get
         bigger — it is deliberately a non-interactive thumbnail (see the
         JS below), so "expanding" here means the Fullscreen API, same
         mechanism spatial.php's own expand button already uses, not
         panning or zooming this small a widget. -->
    <div class="p-minimap" id="case-map-preview">
      <div id="case-map"></div>
      <button class="p-dock-btn p-mini-expand" id="case-map-expand" type="button"
              title="<?= e(t('Expand map to full screen', 'I-full screen ang mapa')) ?>">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"
             stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
          <path d="M15 3h6v6M9 21H3v-6M21 3l-7 7M3 21l7-7"/>
        </svg>
      </button>
      <span class="p-tag"><?php if (!empty($report['location_label'])): ?><span class="p-tag-place"><?= e($report['location_label']) ?></span><?php endif; ?><?= e(coord_label((float) $report['latitude'], (float) $report['longitude'])) ?></span>
    </div>
  </aside>

</div>

<script>
// 0087 (D): every form on this page says which version of the case it saw.
document.querySelectorAll('form[method="post"]').forEach(function (f) {
  var v = document.createElement('input'); v.type = 'hidden'; v.name = 'v'; v.value = <?= json_encode((string) ($report['version'] ?? '0')) ?>; f.appendChild(v);
});
</script>
<link rel="stylesheet" href="assets/vendor/maplibre/maplibre-gl.css">
<script src="assets/vendor/maplibre/maplibre-gl.js"></script>
<script src="assets/js/map-theme.js?v=<?= e(asset_version('../js/map-theme.js')) ?>"></script>
<script>
(function () {
  // ---- copy the tracking id ----
  document.querySelectorAll('[data-copy]').forEach(function (btn) {
    btn.addEventListener('click', function () {
      navigator.clipboard.writeText(btn.dataset.copy).then(function () {
        btn.classList.add('p-done');
        setTimeout(function () { btn.classList.remove('p-done'); }, 1400);
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
      sla.classList.toggle('p-late', late);
      sla.classList.toggle('p-close', !late && a < 21600000);   // under six hours
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
    var wrap = sel.closest('.p-cfield').nextElementSibling;
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
        preview.classList.toggle('p-full', active);
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

<script src="assets/vendor/supabase/supabase.js?v=2.117.3"></script>
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
    document.getElementById('update-banner').classList.add('p-on');
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
        badge.classList.remove('p-down'); text.textContent = T('Live', 'Live');
      } else if (status === 'CHANNEL_ERROR' || status === 'TIMED_OUT' || status === 'CLOSED') {
        badge.classList.add('p-down'); text.textContent = T('Reconnecting…', 'Kumokonekta muli…');
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
