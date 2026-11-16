<?php
/**
 * Inbox: the portal's case chats, drawn as a community chat (15 Nov 2026, Rose: BarangayMail is gone).
 *
 * A profile per resident or tanod and, under it, one bubble chat per case. The chats read the case's own messages (report_messages) and the
 * tanods' field messages (dispatch_updates); nothing is written here, a reply posts to the case page.
 *
 *   inbox.php                         the profiles and their chats
 *   inbox.php?c=<case>&k=<chat>       one chat open (opens in place; ?part=list|thread|detail gives the pieces)
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

// Nothing is posted to this page any more (the mail it used to take is gone, and a chat reply goes to the case page).
if ($_SERVER['REQUEST_METHOD'] === 'POST') { http_response_code(405); header('Allow: GET'); exit; }

$flash = $_SESSION['inbox_flash'] ?? null; unset($_SESSION['inbox_flash']);
$part   = (string) ($_GET['part'] ?? '');   // the page asks for pieces of itself: the list, one thread, one conversation (list, thread, detail)
$chatId = preg_match('/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i', (string) ($_GET['c'] ?? '')) ? strtolower((string) $_GET['c']) : '';
$listError = null; $chatRows = []; $chatOpen = null; $convId = '';
try {
    // one wait on the database: the list of conversations and the open case ride one batch (speed work, 7 Nov 2026)
    $got = $db->selectMany(($part !== 'thread' && $part !== 'detail' ? case_chat_list_reads() : []) + ($chatId !== '' ? case_chat_load_reads($chatId) : []));
    if ($part !== 'thread' && $part !== 'detail') { $chatRows = case_chat_list_rows($got, $me); }
    $chatOpen = $chatId !== '' ? case_chat_load_build($got) : null;
    $convId = (string) ($_GET['k'] ?? '');
    if ($chatOpen) {
        $ids = array_column($chatOpen['convs'], 'id');
        if (!in_array($convId, $ids, true)) { $convId = (string) ($ids[0] ?? ''); }
    }
} catch (SupabaseError $ex) { $listError = safe_error($ex); }

if (in_array($part, ['list', 'thread', 'detail'], true)) {
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

<?php if ($flash && $flash['text']): ?><div class="p-flash p-flash--<?= $flash['level'] === 'error' ? 'error' : 'ok' ?>" role="status"><?= e($flash['text']) ?></div><?php endif; ?>

<?php
    // ---------- Case chats: the conversations, the open one, its information ----------
    $selKey = $chatOpen ? $chatId . '|' . $convId : ''; ?>
<link rel="stylesheet" href="assets/css/msgr.css?v=<?= e(asset_version('msgr.css')) ?>">
<div class="mg" id="mg" data-list-url="inbox.php?app=chats&amp;part=list" data-detail-url="inbox.php?app=chats&amp;part=detail">
  <section class="mg-left" aria-label="<?= e(t('Chats', 'Mga chat')) ?>">
    <header class="mg-lhead"><h2><?= e(t('Inbox', 'Mga Liham')) ?></h2><span class="ib-sub"><?= e(t('Case chats', 'Mga chat sa kaso')) ?> <span class="p-badge-n" id="ib-chats-n" hidden>0</span></span></header>
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
<script nonce="<?= csp_nonce() ?>" src="assets/js/emoji.js?v=<?= e(asset_version('../js/emoji.js')) ?>" defer></script>
<script nonce="<?= csp_nonce() ?>" src="assets/js/msgr.js?v=<?= e(asset_version('../js/msgr.js')) ?>" defer></script>
</div><?php // #ib-main ?>
<?php layout_foot();
