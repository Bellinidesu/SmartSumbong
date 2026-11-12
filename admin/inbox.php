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
require_once __DIR__ . '/includes/case_chat.php';
require_once __DIR__ . '/includes/case_msgr.php';   // 12 Nov 2026: the Case chats folder reads the chat head's conversations

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
// Two sections (12 Nov 2026, Ace): Case chats, drawn like Messenger, and BarangayMail, the mail. Anything that is about a letter
// (?m=, ?new, ?reply, ?box=sent, ?app=mail) is the mail, so every old link to a letter still opens it.
$mailish = isset($_GET['m']) || isset($_GET['new']) || isset($_GET['reply']) || ($_GET['box'] ?? '') === 'sent' || ($_GET['app'] ?? '') === 'mail';
$app   = $mailish ? 'mail' : 'chats';
$box   = $app === 'chats' ? 'chats' : (($_GET['box'] ?? '') === 'sent' ? 'sent' : 'in');
$part  = (string) ($_GET['part'] ?? '');   // the chat page asks for pieces of itself: the list, one thread, one conversation (list, thread, detail)
$chatId = preg_match('/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i', (string) ($_GET['c'] ?? '')) ? strtolower((string) $_GET['c']) : '';
$open  = ctype_digit((string) ($_GET['m'] ?? '')) ? (int) $_GET['m'] : 0;
$new   = isset($_GET['new']) || isset($_GET['reply']);
$error = null;

/** Who a message is from: a person, or SmartSumbong itself. */
function inbox_from(array $m): string
{
    return $m['kind'] === 'system' ? t('SmartSumbong', 'SmartSumbong') : formal_name((string) ($m['from']['full_name'] ?? t('An administrator', 'Isang administrator')));
}

$unread = 0;
$unreadRead = ['inbox_messages', ['recipient' => 'eq.' . $me, 'read_at' => 'is.null'], true, 'count'];
// Opening a message (speed work, 7 Nov 2026): the message with its reroute question, the replies to it and marking it read all
// ride the list's own batch, so a message opens in one wait (two when it answers an earlier message or asks for a tanod: that
// message and the roster come together in a second). Marking read touches only the reader's own unread mail (mark_mail_read).
$msgSel = 'id,batch,sender,recipient,kind,subject,body,created_at,read_at,report_id,question_id,reply_to,'
        . 'from:users!inbox_messages_sender_fkey(full_name),to:users!inbox_messages_recipient_fkey(full_name),report:reports!inbox_messages_report_id_fkey(id,tracking_id,subject),'
        . 'q:reroute_questions!inbox_messages_question_id_fkey(id,state,due_at,committee,report_id,answered_at,by:users!reroute_questions_answered_by_fkey(full_name))';
$tsel = 'id,batch,sender,kind,subject,body,created_at,reply_to,from:users!inbox_messages_sender_fkey(full_name)';
$openReads = $open ? [
    'om:msg'     => ['inbox_messages', ['select' => $msgSel, 'id' => 'eq.' . $open, 'limit' => '1'], true],
    'om:replies' => ['inbox_messages', ['select' => $tsel, 'reply_to' => 'eq.' . $open, 'order' => 'created_at.asc', 'limit' => '20'], true],
    'om:mark'    => ['rpc/mark_mail_read', ['p_ids' => '{' . $open . '}'], true],
] : [];
$openGot = [];

// the list on the left runs for every view of the page
    $per = 20;
    $page = max(1, (int) ($_GET['page'] ?? 1));
    $rows = []; $total = 0; $listError = null; $dueByQ = []; $chatRows = []; $chatOpen = null; $convId = '';
    try {
        // one wait (speed work, 7 Nov 2026): the unread count, and the page of the list with the total behind its pager
        if ($app === 'mail') {
            // BarangayMail is the Gmail-style page: it asks mail.php for everything; here only the unread count for the tab
            $got = $db->selectMany(['unread' => $unreadRead]);
            $unread = is_int($got['unread'] ?? null) ? $got['unread'] : 0;
        } elseif ($box === 'in') {
            $got = $db->selectMany($openReads + ['unread' => $unreadRead, 'rows' => ['inbox_messages', ['recipient' => 'eq.' . $me,
                'select' => 'id,kind,subject,created_at,read_at,question_id,from:users!inbox_messages_sender_fkey(full_name),report:reports!inbox_messages_report_id_fkey(tracking_id),q:reroute_questions!inbox_messages_question_id_fkey(id,state,due_at)',
                'order' => 'created_at.desc', 'limit' => (string) $per, 'offset' => (string) (($page - 1) * $per)], false, 'total']]);
            $unread = is_int($got['unread'] ?? null) ? $got['unread'] : 0;
            $openGot = $got;
            $total = (int) ($got['rows:total'] ?? 0);
            $rows = (array) $got['rows'];
        } elseif ($box === 'chats') {
            // the case chats (12 Nov 2026): no mail is read here; the mail's unread count still rides along for the tab
            // one wait on the database: the unread mail count, the list of conversations and the open case ride one batch (speed work, 7 Nov 2026)
            $got = $db->selectMany(['unread' => $unreadRead]
                + ($part !== 'thread' && $part !== 'detail' ? case_chat_list_reads() : [])
                + ($chatId !== '' ? case_chat_load_reads($chatId) : []));
            $unread = is_int($got['unread'] ?? null) ? $got['unread'] : 0;
            if ($part !== 'thread' && $part !== 'detail') { $chatRows = case_chat_list_rows($got, $me); }
            $total = count($chatRows);
            $chatOpen = $chatId !== '' ? case_chat_load_build($got) : null;
            $convId = (string) ($_GET['k'] ?? '');
            if ($chatOpen) {
                $ids = array_column($chatOpen['convs'], 'id');
                if (!in_array($convId, $ids, true)) { $convId = (string) ($ids[0] ?? ''); }
            }
        } else {
            // one row per message sent, with everyone it went to
            $got = $db->selectMany($openReads + ['unread' => $unreadRead, 'sent' => ['inbox_messages', ['sender' => 'eq.' . $me, 'select' => 'id,batch,subject,created_at,to:users!inbox_messages_recipient_fkey(full_name),report:reports!inbox_messages_report_id_fkey(tracking_id)',
                'order' => 'created_at.desc', 'limit' => '600']]]);
            $unread = is_int($got['unread'] ?? null) ? $got['unread'] : 0;
            $openGot = $got;
            $sent = (array) $got['sent'];
            $byBatch = [];
            foreach ($sent as $s) {
                $byBatch[$s['batch']] ??= $s + ['names' => []];
                $byBatch[$s['batch']]['names'][] = formal_name((string) ($s['to']['full_name'] ?? ''));
            }
            $total = count($byBatch);
            $rows = array_slice(array_values($byBatch), ($page - 1) * $per, $per);
        }
        // the questions that still wait for an answer carry their clock into the list
        // (read with the list itself, embedded through question_id: no second wait, 7 Nov 2026)
        if ($box === 'in') {
            foreach ($rows as $r) {
                $qq = $r['q'] ?? null;
                if (is_array($qq) && ($qq['state'] ?? '') === 'open') { $dueByQ[(int) $qq['id']] = (string) $qq['due_at']; }
            }
        }
    } catch (SupabaseError $ex) { $listError = safe_error($ex); }

if ($box === 'chats' && in_array($part, ['list', 'thread', 'detail'], true)) {
    header('Content-Type: text/html; charset=utf-8'); header('Cache-Control: no-store');
    if ($part === 'list') { echo msgr_list($chatRows, $chatId . '|' . $convId); }
    elseif ($chatOpen && $part === 'detail') { echo msgr_detail($chatOpen, $convId, $chatId); }
    elseif ($chatOpen) { foreach ($chatOpen['convs'] as $c0) { if ($c0['id'] === $convId) { echo msgr_messages($c0, $chatOpen['report'], $chatId); break; } } }
    exit;
}

layout_head(t('Inbox', 'Mga Liham'), 'inbox.php');
?>
<div class="p-topbar"><h1><?= e(t('Inbox', 'Mga Liham')) ?></h1></div>
<?php // The press flow (7 Nov 2026): the tabs, the list, opening a message and the pager swap in place; the address follows. Only the
      // Inbox's own links are boosted (a link to a case stays an ordinary page change); the forms post as before. ?>
<link rel="stylesheet" href="assets/css/inbox.css?v=<?= e(asset_version('inbox.css')) ?>">
<div id="ib-main" class="press-region" hx-target="#ib-main" hx-select="#ib-main" hx-swap="outerHTML" hx-push-url="true" hx-sync="#ib-main:replace"
     data-announce="<?= e(t('Inbox updated', 'Na-update ang mga liham')) ?>">
<nav class="st-tabs ib-apps" data-title="<?= e(t('Inbox', 'Mga Liham')) ?>" aria-label="<?= e(t('Inbox sections', 'Mga bahagi ng Inbox')) ?>">
  <a class="st-link<?= $app === 'chats' ? ' p-on' : '' ?>" href="inbox.php"<?= $app === 'chats' ? ' aria-current="page"' : '' ?>><?= e(t('Case chats', 'Mga chat sa kaso')) ?> <span class="p-badge-n" id="ib-chats-n" hidden>0</span></a>
  <a class="st-link<?= $app === 'mail' ? ' p-on' : '' ?>" href="inbox.php?app=mail"<?= $app === 'mail' ? ' aria-current="page"' : '' ?>>BarangayMail<?php if ($unread): ?> <span class="p-badge-n"><?= (int) $unread ?></span><?php endif; ?></a>
</nav>
<?php if ($flash && $flash['text']): ?><div class="p-flash p-flash--<?= $flash['level'] === 'error' ? 'error' : 'ok' ?>" role="status"><?= e($flash['text']) ?></div><?php endif; ?>

<?php if ($box === 'chats'):
    // ---------- Case chats, drawn like Messenger: the conversations, the open one, its information ----------
    $selKey = $chatOpen ? $chatId . '|' . $convId : ''; ?>
<link rel="stylesheet" href="assets/css/msgr.css?v=<?= e(asset_version('msgr.css')) ?>">
<div class="mg" id="mg" data-list-url="inbox.php?app=chats&amp;part=list" data-detail-url="inbox.php?app=chats&amp;part=detail">
  <section class="mg-left" aria-label="<?= e(t('Chats', 'Mga chat')) ?>">
    <header class="mg-lhead"><h2><?= e(t('Chats', 'Mga chat')) ?></h2></header>
    <?php if ($listError): ?><div class="p-flash p-flash--error" role="alert"><?= e($listError) ?></div><?php endif; ?>
    <label class="mg-search"><svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" aria-hidden="true"><circle cx="11" cy="11" r="7"/><path d="M20 20l-4-4"/></svg><span class="p-sr"><?= e(t('Search chats', 'Hanapin ang mga chat')) ?></span><input type="search" id="mg-q" placeholder="<?= e(t('Search chats', 'Hanapin ang mga chat')) ?>" autocomplete="off"></label>
    <div class="mg-chips" role="group" aria-label="<?= e(t('Show', 'Ipakita')) ?>">
      <button type="button" class="mg-chip p-on" data-f="all" aria-pressed="true"><?= e(t('All', 'Lahat')) ?></button>
      <button type="button" class="mg-chip" data-f="unread" aria-pressed="false"><?= e(t('Unread', 'Hindi pa nababasa')) ?></button>
      <button type="button" class="mg-chip" data-f="mine" aria-pressed="false"><?= e(t('Cases I handle', 'Mga kasong hawak ko')) ?></button>
    </div>
    <nav class="mg-list" id="mg-list" aria-label="<?= e(t('Chats', 'Mga chat')) ?>"><?= msgr_list($chatRows, $selKey) ?></nav>
    <p class="mg-nomatch" id="mg-nomatch"<?= $chatRows ? ' hidden' : '' ?>><?= $chatRows ? e(t('No chats match.', 'Walang tumutugong chat.')) : e(t('No chats yet. They start when a resident writes about a case or a tanod replies from the field.', 'Wala pang chat. Magsisimula ito kapag sumulat ang residente tungkol sa kaso o sumagot ang tanod mula sa lugar.')) ?></p>
  </section>
  <div class="mg-detail<?= $chatOpen ? ' mg-open' : '' ?>" id="mg-detail">
    <?php if ($chatOpen && $convId !== ''): ?><?= msgr_detail($chatOpen, $convId, $chatId) ?>
    <?php elseif ($chatId !== ''): ?><div class="mg-blank"><b><?= e(t('That case is not yours to read.', 'Hindi para sa iyo ang kasong iyan.')) ?></b></div>
    <?php else: ?><div class="mg-blank"><svg viewBox="0 0 24 24" width="64" height="64" fill="currentColor" aria-hidden="true"><path d="M12 3C6.5 3 2 6.8 2 11.5c0 2.5 1.3 4.7 3.4 6.2-.2 1.3-.8 2.6-1.7 3.6a.5.5 0 0 0 .5.8c2-.3 3.7-1.1 4.9-2A11.7 11.7 0 0 0 12 20c5.5 0 10-3.8 10-8.5S17.5 3 12 3z"/></svg>
      <b><?= e(t('Select a chat', 'Pumili ng chat')) ?></b><span><?= e(t('Choose a conversation on the left to read it and answer here.', 'Pumili ng usapan sa kaliwa para mabasa at masagot dito.')) ?></span></div><?php endif; ?>
  </div>
</div>
<script src="assets/js/emoji.js?v=<?= e(asset_version('../js/emoji.js')) ?>" defer></script>
<script src="assets/js/msgr.js?v=<?= e(asset_version('../js/msgr.js')) ?>" defer></script>
<?php elseif ($app === 'mail'):
    // ---------- BarangayMail, drawn like Gmail's web app (12 Nov 2026): a shell; assets/js/gmail.js fills it from mail.php ---------- ?>
<link rel="stylesheet" href="assets/css/gmail.css?v=<?= e(asset_version('gmail.css')) ?>">
<div class="gm" id="gm" data-csrf="<?= e(csrf_token()) ?>" data-me="<?= e($me) ?>" data-name="<?= e(formal_name((string) ($admin['full_name'] ?? ''))) ?>" data-m="<?= (int) $open ?>" data-new="<?= $new ? '1' : '0' ?>">
  <aside class="gm-rail" aria-label="BarangayMail">
    <button type="button" class="gm-compose" data-gm="compose"><svg viewBox="0 0 24 24" width="24" height="24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M4 20h4L19 9l-4-4L4 16z"/></svg><?= e(t('Compose', 'Sumulat')) ?></button>
    <nav class="gm-nav" aria-label="<?= e(t('Folders', 'Mga folder')) ?>">
      <a href="#inbox" data-f="inbox"><svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M3 13l3-8h12l3 8v6H3zM3 13h5l1 3h6l1-3h5"/></svg><span><?= e(t('Inbox', 'Inbox')) ?></span><span class="gm-n" hidden></span></a>
      <a href="#starred" data-f="starred"><svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12 3.2l2.7 5.6 6.1.8-4.5 4.2 1.1 6.1L12 17l-5.4 2.9 1.1-6.1L3.2 9.6l6.1-.8z"/></svg><span><?= e(t('Starred', 'May bituin')) ?></span><span class="gm-n" hidden></span></a>
      <a href="#snoozed" data-f="snoozed"><svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><circle cx="12" cy="13" r="8"/><path d="M12 9v4l2.5 2M5 4 3 6M19 4l2 2"/></svg><span><?= e(t('Snoozed', 'Naka-snooze')) ?></span><span class="gm-n" hidden></span></a>
      <a href="#sent" data-f="sent"><svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M3 20l18-8L3 4v6l11 2-11 2z"/></svg><span><?= e(t('Sent', 'Naipadala')) ?></span><span class="gm-n" hidden></span></a>
      <a href="#drafts" data-f="drafts"><svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M5 3h10l4 4v14H5zM15 3v4h4M8 13h8M8 17h5"/></svg><span><?= e(t('Drafts', 'Mga draft')) ?></span><span class="gm-n" hidden></span></a>
      <a href="#all" data-f="all"><svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect x="3" y="5" width="18" height="14" rx="2"/><path d="M3 7l9 6 9-6"/></svg><span><?= e(t('All Mail', 'Lahat ng mail')) ?></span><span class="gm-n" hidden></span></a>
      <a href="#trash" data-f="trash"><svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M4 7h16M9 7V4h6v3M6 7l1 13h10l1-13M10 11v6M14 11v6"/></svg><span><?= e(t('Trash', 'Basurahan')) ?></span><span class="gm-n" hidden></span></a>
    </nav>
    <div class="gm-lh"><span><?= e(t('Labels', 'Mga label')) ?></span><button type="button" data-gm="newlabel" aria-label="<?= e(t('Create new label', 'Gumawa ng bagong label')) ?>">+</button></div>
    <nav id="gm-labels" aria-label="<?= e(t('Labels', 'Mga label')) ?>"></nav>
    <button type="button" class="gm-help-link" data-gm="help"><?= e(t('Keyboard shortcuts (?)', 'Mga shortcut sa keyboard (?)')) ?></button>
  </aside>
  <section class="gm-main" id="gm-main" aria-label="<?= e(t('Mail', 'Mail')) ?>">
    <div class="gm-searchbar" role="search">
      <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true"><circle cx="11" cy="11" r="7"/><path d="M20 20l-4-4"/></svg>
      <input id="gm-q" type="search" placeholder="<?= e(t('Search mail', 'Maghanap sa mail')) ?>" aria-label="<?= e(t('Search mail', 'Maghanap sa mail')) ?>" autocomplete="off">
      <button type="button" id="gm-qx" aria-label="<?= e(t('Clear search', 'Burahin ang hinahanap')) ?>"><svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true"><path d="M6 6l12 12M18 6L6 18"/></svg></button>
      <button type="button" id="gm-optsbtn" aria-expanded="false" aria-controls="gm-opts" aria-label="<?= e(t('Show search options', 'Ipakita ang mga opsyon sa paghahanap')) ?>"><svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true"><path d="M4 7h10M18 7h2M4 17h2M10 17h10"/><circle cx="16" cy="7" r="2"/><circle cx="8" cy="17" r="2"/></svg></button>
      <form class="gm-opts" id="gm-opts" hidden>
        <label><?= e(t('From', 'Mula kay')) ?><input type="text" name="from"></label>
        <label><?= e(t('To', 'Para kay')) ?><input type="text" name="to"></label>
        <label><?= e(t('Subject', 'Paksa')) ?><input type="text" name="subject"></label>
        <label><?= e(t('Has the words', 'May mga salitang')) ?><input type="text" name="words"></label>
        <label><?= e(t('Label', 'Label')) ?><select name="label"></select></label>
        <label><?= e(t('Date after', 'Petsa pagkatapos ng')) ?><input type="date" name="after"></label>
        <label><?= e(t('Date before', 'Petsa bago ang')) ?><input type="date" name="before"></label>
        <div class="gm-chk"><label><input type="checkbox" name="unread"> <?= e(t('Unread', 'Hindi pa nababasa')) ?></label><label><input type="checkbox" name="starred"> <?= e(t('Starred', 'May bituin')) ?></label></div>
        <div class="gm-opts-act"><button type="button" class="gm-btn" data-gm="optsclear"><?= e(t('Clear', 'Burahin')) ?></button><button type="submit" class="gm-btn gm-btn--blue"><?= e(t('Search', 'Hanapin')) ?></button></div>
      </form>
    </div>
    <div class="gm-toolbar" id="gm-tb"></div>
    <div class="gm-tabs" id="gm-tabs" role="tablist" hidden>
      <button type="button" role="tab" data-tab="people" class="on"><?= e(t('Primary', 'Pangunahin')) ?> <span class="gm-n" hidden></span></button>
      <button type="button" role="tab" data-tab="updates"><?= e(t('Updates', 'Mga update')) ?> <span class="gm-n" hidden></span></button>
    </div>
    <div class="gm-list" id="gm-list" role="list" aria-label="<?= e(t('Conversations', 'Mga usapan')) ?>"></div>
    <div class="gm-reader" id="gm-reader" hidden></div>
  </section>
  <div class="gm-wins" id="gm-wins"></div>
  <div class="gm-snack" id="gm-snack" role="status" hidden></div>
</div>
<script src="assets/js/emoji.js?v=<?= e(asset_version('../js/emoji.js')) ?>" defer></script>
<script src="assets/js/gmail-compose.js?v=<?= e(asset_version('../js/gmail-compose.js')) ?>" defer></script>
<script src="assets/js/gmail.js?v=<?= e(asset_version('../js/gmail.js')) ?>" defer></script>
<?php endif; // Case chats, or BarangayMail ?>
</div><?php // #ib-main ?>
<script>
// the countdown on messages that wait for an answer
(function () {
  // the clocks are looked up on each tick, so a message opened in place (the press flow) keeps counting
  function tick() {
    document.querySelectorAll('.ib-due[data-due]').forEach(function (el) {
      var left = Math.floor((new Date(el.getAttribute('data-due')).getTime() - Date.now()) / 1000), b = el.querySelector('b');
      el.classList.toggle('is-late', left <= 0);
      b.textContent = left <= 0 ? <?= json_encode(t('time is up', 'tapos na ang oras')) ?> : Math.floor(left / 60) + ':' + ('0' + (left % 60)).slice(-2) + ' <?= e(t('left', 'natitira')) ?>';
    });
  }
  tick(); setInterval(tick, 1000);
})();
</script>
<?php layout_foot();
