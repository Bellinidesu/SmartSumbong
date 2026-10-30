<?php
/**
 * Inbox — the portal's intranet mail (0155; docs/ROLES_AND_PAGES.md, "Inbox").
 *
 * Mail runs along the ladder: staff write to their own Kagawad; a Kagawad to their staff, other Kagawads and the super admins;
 * a super admin to anyone; a captain to the super admins. The database checks it (send_mail) and lets only the sender and the
 * recipient read a message. A message can carry a case. The system writes here too: forwards, staff flags, and the reroute
 * question (no tanod of the case's committee is free: pick one, or let the system send the nearest from any committee).
 *
 *   inbox.php                 the messages to me      ?box=sent  the ones I sent      ?new=1  write one
 *   inbox.php?m=<id>          one message (marked read); a reroute question shows its answer form
 */
declare(strict_types=1);

require_once __DIR__ . '/includes/auth.php';
require_once __DIR__ . '/includes/layout.php';
require_once __DIR__ . '/includes/forwarding.php';

$admin = require_admin();
$db    = db();
$me    = (string) $admin['id'];
session_start_once();

// ---------- actions ----------
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $back = 'inbox.php';
    $flash = null; $level = 'ok';
    if (!csrf_check($_POST['csrf'] ?? null)) {
        $flash = t('That form expired. Please try again.', 'Nag-expire ang form. Subukan muli.'); $level = 'error';
    } else {
        try {
            switch ((string) ($_POST['action'] ?? '')) {
                case 'send':
                    $to = array_values(array_filter((array) ($_POST['to'] ?? []), fn ($x) => is_string($x) && preg_match('/^[0-9a-f-]{36}$/i', $x)));
                    $report = null;
                    $track = strtoupper(trim((string) ($_POST['case'] ?? '')));
                    if ($track !== '') {
                        $found = (array) $db->select('reports', ['select' => 'id', 'tracking_id' => 'eq.' . $track, 'deleted_at' => 'is.null', 'limit' => '1']);
                        if (!$found) { throw new SupabaseError(t('No case you can see has that tracking ID.', 'Walang kasong nakikita mo na may ganyang tracking ID.')); }
                        $report = (string) $found[0]['id'];
                    }
                    $reply = ctype_digit((string) ($_POST['reply_to'] ?? '')) ? (int) $_POST['reply_to'] : null;
                    $db->rpc('send_mail', ['p_to' => '{' . implode(',', $to) . '}', 'p_subject' => (string) ($_POST['subject'] ?? ''),
                        'p_body' => (string) ($_POST['body'] ?? ''), 'p_report' => $report, 'p_reply_to' => $reply]);
                    $flash = t('Sent.', 'Naipadala.');
                    $back = 'inbox.php?box=sent';
                    break;

                case 'answer':
                    $q = (int) ($_POST['question'] ?? 0);
                    $tanod = (string) ($_POST['tanod'] ?? '');
                    $any = ($_POST['pick'] ?? '') === 'any';
                    $d = $db->rpc('answer_reroute_question', ['p_question' => $q, 'p_tanod' => $any || $tanod === '' ? null : $tanod]);
                    $flash = $d ? t('Sent. The tanod is told.', 'Naipadala. Nasabihan ang tanod.')
                                : t('Nobody is free right now. The case waits in line and is offered as soon as a tanod is free.', 'Walang bakante ngayon. Maghihintay sa pila ang kaso at iaalok agad kapag may bakanteng tanod.');
                    $back = 'inbox.php?m=' . (int) ($_POST['m'] ?? 0);
                    break;

                default:
                    $flash = t('Unknown action.', 'Hindi kilalang aksyon.'); $level = 'error';
            }
        } catch (SupabaseError $ex) {
            $flash = safe_error($ex); $level = 'error';
            if (($_POST['action'] ?? '') === 'send') { $_SESSION['inbox_draft'] = array_intersect_key($_POST, array_flip(['to', 'subject', 'body', 'case', 'reply_to'])); $back = 'inbox.php?new=1'; }
        }
    }
    unset($_SESSION['nav_counts']);
    $_SESSION['inbox_flash'] = ['text' => $flash, 'level' => $level];
    header('Location: ' . $back, true, 303);
    exit;
}

$flash = $_SESSION['inbox_flash'] ?? null; unset($_SESSION['inbox_flash']);
$box   = ($_GET['box'] ?? '') === 'sent' ? 'sent' : 'in';
$open  = ctype_digit((string) ($_GET['m'] ?? '')) ? (int) $_GET['m'] : 0;
$new   = isset($_GET['new']) || isset($_GET['reply']);
$error = null;

/** Who a message is from: a person, or SmartSumbong itself. */
function inbox_from(array $m): string
{
    return $m['kind'] === 'system' ? t('SmartSumbong', 'SmartSumbong') : formal_name((string) ($m['from']['full_name'] ?? t('An administrator', 'Isang administrator')));
}

$unread = 0;
try { $unread = $db->count('inbox_messages', ['recipient' => 'eq.' . $me, 'read_at' => 'is.null']); } catch (SupabaseError) {}

// the list on the left runs for every view of the page
    $per = 20;
    $page = max(1, (int) ($_GET['page'] ?? 1));
    $rows = []; $total = 0; $listError = null; $dueByQ = [];
    try {
        if ($box === 'in') {
            $q = ['recipient' => 'eq.' . $me];
            $total = $db->count('inbox_messages', $q);
            $rows = (array) $db->select('inbox_messages', $q + ['select' => 'id,kind,subject,created_at,read_at,question_id,from:users!inbox_messages_sender_fkey(full_name),report:reports!inbox_messages_report_id_fkey(tracking_id)',
                'order' => 'created_at.desc', 'limit' => (string) $per, 'offset' => (string) (($page - 1) * $per)]);
        } else {
            // one row per message sent, with everyone it went to
            $sent = (array) $db->select('inbox_messages', ['sender' => 'eq.' . $me, 'select' => 'id,batch,subject,created_at,to:users!inbox_messages_recipient_fkey(full_name),report:reports!inbox_messages_report_id_fkey(tracking_id)',
                'order' => 'created_at.desc', 'limit' => '600']);
            $byBatch = [];
            foreach ($sent as $s) {
                $byBatch[$s['batch']] ??= $s + ['names' => []];
                $byBatch[$s['batch']]['names'][] = formal_name((string) ($s['to']['full_name'] ?? ''));
            }
            $total = count($byBatch);
            $rows = array_slice(array_values($byBatch), ($page - 1) * $per, $per);
        }
        // the questions that still wait for an answer carry their clock into the list
        $qids = array_values(array_filter(array_map(fn ($r) => (int) ($r['question_id'] ?? 0), $rows)));
        if ($box === 'in' && $qids) {
            foreach ((array) $db->select('reroute_questions', ['select' => 'id,state,due_at', 'id' => 'in.(' . implode(',', $qids) . ')']) as $qq) {
                if (($qq['state'] ?? '') === 'open') { $dueByQ[(int) $qq['id']] = (string) $qq['due_at']; }
            }
        }
    } catch (SupabaseError $ex) { $listError = safe_error($ex); }

layout_head(t('Inbox', 'Mga Liham'), 'inbox.php');
?>
<div class="p-topbar"><h1><?= e(t('Inbox', 'Mga Liham')) ?></h1></div>
<nav class="st-tabs ib-tabs" aria-label="<?= e(t('Inbox', 'Mga Liham')) ?>">
  <a class="st-link<?= $box === 'in' && !$new && !$open ? ' p-on' : '' ?>" href="inbox.php"><?= e(t('Inbox', 'Mga Liham')) ?><?php if ($unread): ?> <span class="p-badge-n"><?= (int) $unread ?></span><?php endif; ?></a>
  <a class="st-link<?= $box === 'sent' && !$new && !$open ? ' p-on' : '' ?>" href="inbox.php?box=sent"><?= e(t('Sent', 'Naipadala')) ?></a>
  <a class="st-link<?= $new ? ' p-on' : '' ?>" href="inbox.php?new=1"><?= e(t('Write', 'Sumulat')) ?></a>
</nav>
<?php if ($flash && $flash['text']): ?><div class="p-flash p-flash--<?= $flash['level'] === 'error' ? 'error' : 'ok' ?>" role="status"><?= e($flash['text']) ?></div><?php endif; ?>

<div class="ib-split<?= !$rows && !$new && !$open ? ' ib-empty' : '' ?>">
<section class="ib-list" aria-label="<?= e($box === 'in' ? t('Messages to you', 'Mga mensaheng para sa iyo') : t('Messages you sent', 'Mga mensaheng naipadala mo')) ?>">
  <?php if ($listError): ?><div class="p-flash p-flash--error" role="alert"><?= e($listError) ?></div><?php endif; ?>
  <div class="p-card ib-rows-card">
    <?php if (!$rows): ?><p class="p-empty"><?= e($box === 'in' ? t('Nothing here yet.', 'Wala pang laman.') : t('You have not sent anything yet.', 'Wala ka pang naipadala.')) ?></p><?php endif; ?>
    <nav class="ib-rows" aria-label="<?= e($box === 'in' ? t('Messages to you', 'Mga mensaheng para sa iyo') : t('Messages you sent', 'Mga mensaheng naipadala mo')) ?>">
    <?php foreach ($rows as $r):
        $unreadRow = $box === 'in' && empty($r['read_at']);
        $isSys = $box === 'in' && $r['kind'] === 'system';
        $who = $box === 'in' ? inbox_from($r) : (implode(', ', array_slice($r['names'], 0, 3)) . (count($r['names']) > 3 ? ' +' . (count($r['names']) - 3) : ''));
        $needs = !empty($r['question_id']) && $unreadRow; ?>
      <a class="fr ib-row<?= $unreadRow ? ' ib-unread is-unread' : '' ?><?= $needs ? ' ib-needs' : '' ?><?= $open === (int) $r['id'] ? ' ib-sel' : '' ?>" data-sev="<?= $needs ? 'high' : ($isSys ? 'info' : ($unreadRow ? 'act' : 'info')) ?>" href="inbox.php?m=<?= (int) $r['id'] ?><?= $box === 'sent' ? '&box=sent' : '' ?>">
        <span class="ib-av<?= $isSys ? ' is-sys' : '' ?>" aria-hidden="true"><?= $isSys ? smart_brain(18) : e(admin_initials($box === 'in' ? (string) ($r['from']['full_name'] ?? '') : (string) ($r['names'][0] ?? ''))) ?></span>
        <span class="ib-top"><b class="ib-name"><?= e($who) ?></b><span class="ib-when"><?= e(relative_time((string) $r['created_at'])) ?></span></span>
        <span class="ib-line"><span class="ib-subj"><?= e((string) $r['subject']) ?></span><?php if (!empty($r['question_id'])): ?><span class="p-badge p-b-pending"><?= e(t('Needs your answer', 'Kailangan ng sagot mo')) ?></span><?php endif; ?><?php if (!empty($dueByQ[(int) ($r['question_id'] ?? 0)])): ?><span class="ib-due" data-due="<?= e($dueByQ[(int) $r['question_id']]) ?>"><?= p_icon('i-clock', 13) ?><b></b></span><?php endif; ?><?php if (!empty($r['report']['tracking_id'])): ?><span class="p-mono-id ib-case"><?= e($r['report']['tracking_id']) ?></span><?php endif; ?></span>
      </a>
    <?php endforeach; ?>
    </nav>
  </div>
  <?= pager($total, $page, 'page', $per) ?>
</section>
<div class="ib-pane">
<?php if ($new):
    // ---------- write ----------
    $draft = $_SESSION['inbox_draft'] ?? []; unset($_SESSION['inbox_draft']);
    try { $people = (array) $db->rpc('mail_recipients'); } catch (SupabaseError $ex) { $people = []; $error = safe_error($ex); }
    $replyTo = null;
    if (ctype_digit((string) ($_GET['reply'] ?? ''))) {
        $rr = (array) $db->select('inbox_messages', ['select' => 'id,sender,subject,report:reports!inbox_messages_report_id_fkey(tracking_id)', 'id' => 'eq.' . (int) $_GET['reply'], 'limit' => '1']);
        if ($rr) {
            $replyTo = $rr[0];
            $draft += ['to' => array_filter([(string) ($replyTo['sender'] ?? '')]), 'subject' => (str_starts_with((string) $replyTo['subject'], 'Re: ') ? '' : 'Re: ') . $replyTo['subject'],
                       'case' => (string) ($replyTo['report']['tracking_id'] ?? ''), 'reply_to' => (string) $replyTo['id']];
        }
    }
    $picked = array_flip((array) ($draft['to'] ?? []));
    $tierLabel = ['super' => t('Super admins', 'Mga super admin'), 'committee' => t('Kagawads', 'Mga Kagawad'), 'moderator' => t('Staff', 'Mga kawani'), 'captain' => t('Captains', 'Mga kapitan')];
    $byTier = [];
    foreach ($people as $p) { $byTier[(string) $p['tier']][] = $p; } ?>
  <?php if ($error): ?><div class="p-flash p-flash--error" role="alert"><?= e($error) ?></div><?php endif; ?>
  <form method="post" class="p-card p-card-pad ib-compose">
    <input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>"><input type="hidden" name="action" value="send">
    <?php if (!empty($draft['reply_to'])): ?><input type="hidden" name="reply_to" value="<?= e((string) $draft['reply_to']) ?>"><?php endif; ?>
    <fieldset class="ib-to">
      <legend class="p-flabel"><?= e(t('To', 'Para kay')) ?></legend>
      <?php if (!$people): ?><p class="p-hint"><?= e(t('There is nobody you can write to yet.', 'Wala ka pang masusulatan.')) ?></p><?php endif; ?>
      <?php foreach ($byTier as $tier => $list): ?>
        <div class="ib-group"><span class="ib-gl"><?= e($tierLabel[$tier] ?? $tier) ?></span>
          <?php foreach ($list as $p): ?>
            <label class="ib-person"><input type="checkbox" name="to[]" value="<?= e($p['id']) ?>"<?= isset($picked[$p['id']]) ? ' checked' : '' ?>>
              <span><?= e(formal_name((string) $p['full_name'])) ?></span><?= !empty($p['committee']) ? committee_pill((string) $p['committee']) : '' ?></label>
          <?php endforeach; ?>
        </div>
      <?php endforeach; ?>
      <p class="p-hint"><?= e(t('Mail runs along the ladder: staff write to their Kagawad; a Kagawad to their staff, other Kagawads and the super admins; a super admin to anyone.',
          'Sumusunod sa hagdan ang sulat: sumusulat ang kawani sa kanilang Kagawad; ang Kagawad sa kanilang kawani, ibang Kagawad at mga super admin; ang super admin sa kahit sino.')) ?></p>
    </fieldset>
    <div class="p-cfield"><label class="p-flabel" for="ib-subject"><?= e(t('Subject', 'Paksa')) ?></label>
      <input class="p-input-plain" id="ib-subject" name="subject" maxlength="140" required value="<?= e((string) ($draft['subject'] ?? '')) ?>"></div>
    <div class="p-cfield"><label class="p-flabel" for="ib-body"><?= e(t('Message', 'Mensahe')) ?></label>
      <textarea class="p-input-plain" id="ib-body" name="body" rows="7" maxlength="4000" required><?= e((string) ($draft['body'] ?? '')) ?></textarea></div>
    <div class="p-cfield"><label class="p-flabel" for="ib-case"><?= e(t('About a case (tracking ID, optional)', 'Tungkol sa kaso (tracking ID, opsyonal)')) ?></label>
      <input class="p-input-plain" id="ib-case" name="case" maxlength="20" placeholder="SS-2610-1001" value="<?= e((string) ($draft['case'] ?? '')) ?>"></div>
    <div class="ib-act"><a class="p-btn p-btn-ghost p-btn-sm" href="inbox.php"><?= e(t('Cancel', 'Kanselahin')) ?></a>
      <button class="p-btn p-btn-primary p-btn-sm" type="submit"><?= p_icon('i-send', 15) ?><?= e(t('Send', 'Ipadala')) ?></button></div>
  </form>

<?php elseif ($open):
    // ---------- one message ----------
    $m = null;
    try {
        $rows = (array) $db->select('inbox_messages', ['select' => 'id,batch,sender,recipient,kind,subject,body,created_at,read_at,report_id,question_id,reply_to,'
            . 'from:users!inbox_messages_sender_fkey(full_name),to:users!inbox_messages_recipient_fkey(full_name),report:reports!inbox_messages_report_id_fkey(id,tracking_id,subject)',
            'id' => 'eq.' . $open, 'limit' => '1']);
        $m = $rows[0] ?? null;
        if ($m && $m['recipient'] === $me && empty($m['read_at'])) { $db->rpc('mark_mail_read', ['p_ids' => '{' . (int) $m['id'] . '}']); unset($_SESSION['nav_counts']); }
    } catch (SupabaseError $ex) { $error = safe_error($ex); } ?>
  <?php if ($error): ?><div class="p-flash p-flash--error" role="alert"><?= e($error) ?></div><?php endif; ?>
  <?php if (!$m): ?><div class="p-card p-empty"><?= e(t('That message is not yours to read.', 'Hindi para sa iyo ang mensaheng iyan.')) ?></div>
  <?php else: ?>
  <article class="p-card p-card-pad ib-read">
    <a class="p-back" href="inbox.php<?= $m['sender'] === $me ? '?box=sent' : '' ?>"><?= p_icon('i-back', 18) ?><?= e($m['sender'] === $me ? t('Sent', 'Naipadala') : t('Inbox', 'Mga Liham')) ?></a>
    <h2><?= e((string) $m['subject']) ?></h2>
    <div class="ib-head"><span class="ib-av<?= $m['kind'] === 'system' ? ' is-sys' : '' ?>" aria-hidden="true"><?= $m['kind'] === 'system' ? smart_brain(18) : e(admin_initials((string) ($m['from']['full_name'] ?? ''))) ?></span>
      <p class="ib-meta"><?php if ($m['kind'] === 'system'): ?><span class="p-badge p-b-grey"><?= e(t('System', 'Sistema')) ?></span> <?php endif; ?>
        <?= e(t('From', 'Mula kay')) ?> <b><?= e(inbox_from($m)) ?></b> &middot; <?= e(t('to', 'para kay')) ?> <?= e(formal_name((string) ($m['to']['full_name'] ?? ''))) ?><br><span class="ib-date"><?= e(long_datetime((string) $m['created_at'])) ?></span></p></div>
    <div class="ib-body"><?= nl2br(e((string) $m['body'])) ?></div>
    <?php
    // the conversation: the message this one answers, and every reply to it (what the database lets this person read)
    $thread = [];
    try {
        $tsel = 'id,batch,sender,kind,subject,body,created_at,reply_to,from:users!inbox_messages_sender_fkey(full_name)';
        if (!empty($m['reply_to'])) {
            foreach ((array) $db->select('inbox_messages', ['select' => $tsel, 'id' => 'eq.' . (int) $m['reply_to'], 'limit' => '1']) as $tm) { if ((int) $tm['id'] === (int) $m['reply_to']) { $tm['dir'] = 'before'; $thread[] = $tm; } }
        }
        $seen = [];
        foreach ((array) $db->select('inbox_messages', ['select' => $tsel, 'reply_to' => 'eq.' . (int) $m['id'], 'order' => 'created_at.asc', 'limit' => '20']) as $tm) {
            if ((int) ($tm['reply_to'] ?? 0) !== (int) $m['id'] || isset($seen[$tm['batch']])) { continue; }
            $seen[$tm['batch']] = true; $tm['dir'] = 'after'; $thread[] = $tm;
        }
    } catch (SupabaseError) { $thread = []; }
    if ($thread): ?>
      <section class="ib-thread" aria-label="<?= e(t('The conversation', 'Ang usapan')) ?>">
        <p class="p-eyebrow"><?= e(t('The conversation', 'Ang usapan')) ?></p>
        <?php foreach ($thread as $tm): $mine = ($tm['sender'] ?? '') === $me; ?>
          <a class="ib-msg<?= $mine ? ' is-mine' : '' ?>" href="inbox.php?m=<?= (int) $tm['id'] ?>">
            <span class="ib-av" aria-hidden="true"><?= e(admin_initials((string) ($tm['from']['full_name'] ?? ''))) ?></span>
            <span class="ib-msg-top"><b><?= e($mine ? t('You', 'Ikaw') : inbox_from($tm)) ?></b><span class="ib-when"><?= e(($tm['dir'] === 'before' ? t('Earlier', 'Nauna') : t('Reply', 'Sagot')) . ' · ' . relative_time((string) $tm['created_at'])) ?></span></span>
            <span class="ib-msg-body"><?= e(mb_strimwidth((string) $tm['body'], 0, 220, '…')) ?></span>
          </a>
        <?php endforeach; ?>
      </section>
    <?php endif; ?>
    <?php if (!empty($m['report'])): ?>
      <p><a class="p-btn p-btn-ghost p-btn-sm" href="case.php?id=<?= e($m['report']['id']) ?>"><?= p_icon('i-doc', 15) ?><?= e(sprintf(t('Open case %s', 'Buksan ang kaso %s'), $m['report']['tracking_id'])) ?></a></p>
    <?php elseif (!empty($m['report_id'])): ?>
      <p class="p-hint"><?= e(t('This message is about a case you can no longer see (it may have been forwarded).', 'Tungkol ito sa kasong hindi mo na nakikita (maaaring naipasa na).')) ?></p>
    <?php endif; ?>

    <?php if (!empty($m['question_id'])):
        $q = ((array) $db->select('reroute_questions', ['select' => 'id,state,due_at,committee,report_id,answered_at,by:users!reroute_questions_answered_by_fkey(full_name)', 'id' => 'eq.' . (int) $m['question_id'], 'limit' => '1']))[0] ?? null; ?>
      <?php if ($q && $q['state'] === 'open'):
          try { $roster = (array) $db->rpc('tanod_roster', ['p_report' => $q['report_id']]); } catch (SupabaseError) { $roster = []; }
          usort($roster, fn ($a, $b) => [!$a['assignable'], $a['metres'] ?? 1e9] <=> [!$b['assignable'], $b['metres'] ?? 1e9]); ?>
        <form method="post" class="ib-q" id="ib-question">
          <input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>"><input type="hidden" name="action" value="answer">
          <input type="hidden" name="question" value="<?= (int) $q['id'] ?>"><input type="hidden" name="m" value="<?= (int) $m['id'] ?>">
          <p class="ib-q-due" data-due="<?= e((string) $q['due_at']) ?>"><?= p_icon('i-clock', 16) ?><span><?= e(sprintf(t('Answer by %s, or the nearest tanod from any committee is sent.', 'Sumagot bago mag-%s, o ipapadala ang pinakamalapit na tanod mula sa kahit anong komite.'),
              (new DateTimeImmutable((string) $q['due_at']))->setTimezone(new DateTimeZone('Asia/Manila'))->format('g:i A'))) ?></span></p>
          <label class="p-flabel" for="ib-tanod"><?= e(t('Send this tanod', 'Ipadala ang tanod na ito')) ?></label>
          <div class="tc-row">
            <select class="p-input-plain" id="ib-tanod" name="tanod">
              <?php foreach ($roster as $tn): ?>
                <option value="<?= e($tn['tanod_id']) ?>"<?= empty($tn['assignable']) ? ' disabled' : '' ?>><?= e(formal_name((string) $tn['full_name'])) ?><?= isset($tn['metres']) ? ' · ' . (int) round((float) $tn['metres']) . ' m' : '' ?><?= empty($tn['assignable']) && !empty($tn['unavailable_why']) ? ' · ' . e((string) $tn['unavailable_why']) : '' ?></option>
              <?php endforeach; ?>
            </select>
            <button class="p-btn p-btn-primary p-btn-sm" type="submit" name="pick" value="tanod"><?= e(t('Send', 'Ipadala')) ?></button>
          </div>
          <button class="p-btn p-btn-ghost p-btn-sm" type="submit" name="pick" value="any"><?= e(t('Send the nearest from any committee now', 'Ipadala na ang pinakamalapit mula sa kahit anong komite')) ?></button>
        </form>
      <?php elseif ($q): ?>
        <p class="p-ctl-note ib-q-done"><?= e(match ($q['state']) {
            'picked'    => sprintf(t('Answered by %s: they picked the tanod.', 'Sinagot ni %s: pumili sila ng tanod.'), formal_name((string) ($q['by']['full_name'] ?? ''))),
            'any'       => sprintf(t('Answered by %s: the nearest from any committee was sent.', 'Sinagot ni %s: ipinadala ang pinakamalapit mula sa kahit anong komite.'), formal_name((string) ($q['by']['full_name'] ?? ''))),
            'timed_out' => t('Nobody answered in time: the nearest tanod from any committee was sent.', 'Walang sumagot sa oras: ipinadala ang pinakamalapit na tanod mula sa kahit anong komite.'),
            default     => t('No longer needed: the case already has a tanod, or was closed.', 'Hindi na kailangan: may tanod na ang kaso, o naisara na.'),
        }) ?></p>
      <?php endif; ?>
    <?php endif; ?>

    <?php if ($m['kind'] === 'mail' && $m['recipient'] === $me): ?>
      <div class="ib-act"><a class="p-btn p-btn-primary p-btn-sm" href="inbox.php?reply=<?= (int) $m['id'] ?>"><?= e(t('Reply', 'Sumagot')) ?></a></div>
    <?php endif; ?>
  </article>
  <?php endif; ?>

<?php else: ?>
  <div class="p-card ib-none"><span class="ib-none-ic" aria-hidden="true"><?= p_icon('i-send', 22) ?></span><?php if ($rows): ?><b><?= e(t('Pick a message to read it here', 'Pumili ng mensahe para mabasa rito')) ?></b>
    <span><?= e(t('Or write a new one.', 'O sumulat ng bago.')) ?></span><?php else: ?><b><?= e(t('No messages yet', 'Wala pang mensahe')) ?></b>
    <span><?= e(t('Replies from your team, forwards and questions from the system land here.', 'Dito lalabas ang mga sagot ng koponan, ipinasa at tanong ng sistema.')) ?></span><?php endif; ?><a class="p-btn p-btn-primary p-btn-sm" href="inbox.php?new=1"><?= e(t('Write', 'Sumulat')) ?></a></div>
<?php endif; ?>
</div>
</div>
<script>
// the countdown on messages that wait for an answer
(function () {
  var els = document.querySelectorAll('.ib-due[data-due]'); if (!els.length) return;
  function tick() {
    els.forEach(function (el) {
      var left = Math.floor((new Date(el.getAttribute('data-due')).getTime() - Date.now()) / 1000), b = el.querySelector('b');
      el.classList.toggle('is-late', left <= 0);
      b.textContent = left <= 0 ? <?= json_encode(t('time is up', 'tapos na ang oras')) ?> : Math.floor(left / 60) + ':' + ('0' + (left % 60)).slice(-2) + ' <?= e(t('left', 'natitira')) ?>';
    });
  }
  tick(); setInterval(tick, 1000);
})();
</script>
<?php layout_foot();
