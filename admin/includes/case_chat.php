<?php
/**
 * The case page's chat head (12 Nov 2026, Ace: "an Apple-style chat for the tanod and the resident").
 *
 * One floating button on the case page opens a Messages-style panel: a list of the case's conversations (each tanod
 * dispatch, and the resident's questions), then one conversation at a time as grouped bubbles with a composer.
 * It reads what the page already has (dispatch_updates, report_messages) and sends through the same two actions as before
 * (dispatch_reply, resident_reply), so nothing in the database or its rules changes: a case's handler lock still applies.
 */
declare(strict_types=1);

/** "Today", "Yesterday" or "Nov 12", in Manila time. */
function case_chat_day(string $iso): string
{
    $tz = new DateTimeZone('Asia/Manila');
    $d = (new DateTimeImmutable($iso))->setTimezone($tz);
    $now = new DateTimeImmutable('now', $tz);
    $days = (int) $now->setTime(0, 0)->diff($d->setTime(0, 0))->format('%r%a');
    if ($days === 0) return t('Today', 'Ngayon');
    if ($days === -1) return t('Yesterday', 'Kahapon');
    return $d->format('M j');
}

function case_chat_clock(string $iso): string
{
    return (new DateTimeImmutable($iso))->setTimezone(new DateTimeZone('Asia/Manila'))->format('g:i A');
}

function case_chat_initials(string $name): string
{
    $parts = preg_split('/[\s,]+/', trim($name), -1, PREG_SPLIT_NO_EMPTY) ?: [];
    $out = '';
    foreach (array_slice($parts, 0, 2) as $p) { $out .= mb_strtoupper(mb_substr($p, 0, 1)); }
    return $out !== '' ? $out : '?';
}

/**
 * The conversations of one case, newest activity first.
 *
 * @return list<array{id:string,kind:string,name:string,sub:string,items:list<array>,open:bool,closed:string,action:string,dispatch:string,last:string}>
 */
function case_chat_conversations(array $report, array $dispatches, array $thread, array $threadMedia, array $messages, string $status): array
{
    $convs = [];
    foreach ($dispatches as $d) {
        if (empty($thread[$d['id']]) && ($d['state'] ?? '') !== 'accepted') continue;
        $name = (string) ($d['tanod']['full_name'] ?? t('Tanod', 'Tanod'));
        $items = [];
        foreach ($thread[$d['id']] ?? [] as $u) {
            if (($u['kind'] ?? '') === 'step') {
                $items[] = ['ts' => (string) $u['created_at'], 'type' => 'sys',
                    'text' => ($u['step'] ?? '') === 'arrived' ? t('Tanod arrived', 'Nakarating ang tanod') : t('Tanod on the way', 'Papunta na ang tanod')];
                continue;
            }
            $items[] = ['ts' => (string) $u['created_at'], 'type' => 'msg', 'out' => ($u['author_id'] ?? null) !== ($d['tanod']['id'] ?? ($d['tanod_id'] ?? null)),
                'body' => (string) ($u['body'] ?? ''), 'media' => array_map(static fn ($m) => (string) $m['media_url'], $threadMedia[$u['id']] ?? [])];
        }
        $isOpen = ($d['state'] ?? '') === 'accepted';
        $convs[] = ['id' => 'd-' . $d['id'], 'kind' => 'tanod', 'name' => $name,
            'sub' => t('Tanod', 'Tanod') . ' · ' . status_label((string) ($d['state'] ?? '')),
            'items' => $items, 'open' => $isOpen, 'closed' => t('This dispatch is closed, so replies are off.', 'Sarado na ang dispatch na ito, kaya hindi na maaaring sumagot.'),
            'action' => 'dispatch_reply', 'dispatch' => (string) $d['id'], 'max' => 2000,
            'ph' => t('Message the tanod', 'Mag-message sa tanod')];
    }
    $items = [];
    foreach ($messages as $m) {
        $items[] = ['ts' => (string) $m['created_at'], 'type' => 'msg', 'out' => !empty($m['from_barangay']), 'body' => (string) $m['body'], 'media' => []];
    }
    $canMessage = !in_array($status, ['archived', 'cancelled'], true);
    if ($items || $canMessage) {
        $rName = formal_or($report['resident']['full_name'] ?? null, t('Resident', 'Residente'));
        $convs[] = ['id' => 'r', 'kind' => 'resident', 'name' => $rName,
            'sub' => !empty($report['is_anonymous']) ? t('Resident · anonymous to others', 'Residente · hindi nagpakilala sa iba') : t('Resident', 'Residente'),
            'items' => $items, 'open' => $canMessage, 'closed' => t('This case is closed to messages.', 'Sarado na ang kasong ito sa mga mensahe.'),
            'action' => 'resident_reply', 'dispatch' => '', 'max' => 1000,
            'ph' => t('Message the resident', 'Mag-message sa residente')];
    }
    foreach ($convs as &$c) {
        $c['last'] = $c['items'] ? (string) end($c['items'])['ts'] : '';
    }
    unset($c);
    usort($convs, static fn ($a, $b) => strcmp($b['last'], $a['last']));
    return $convs;
}

/** What a conversation row shows under the name. */
function case_chat_preview(array $c): string
{
    if (!$c['items']) return t('No messages yet', 'Wala pang mensahe');
    $l = end($c['items']);
    if ($l['type'] === 'sys') return (string) $l['text'];
    $t = trim((string) $l['body']);
    if ($t === '' && !empty($l['media'])) $t = t('Photo', 'Larawan');
    return (($l['out'] ?? false) ? t('You: ', 'Ikaw: ') : '') . $t;
}

/** The panel's inside: the list, then every conversation (hidden until opened). The page and the live refresh both use it. */
function case_chat_body(array $convs, string $id): string
{
    ob_start();
    $more = '<button type="button" class="ch-x ch-more" data-ch="menu" aria-haspopup="menu" aria-label="' . e(t('Chat options', 'Mga opsyon ng chat')) . '"><svg viewBox="0 0 24 24" width="18" height="18" fill="currentColor" aria-hidden="true"><circle cx="5" cy="12" r="2"/><circle cx="12" cy="12" r="2"/><circle cx="19" cy="12" r="2"/></svg></button>';
    $close = '<svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" aria-hidden="true"><path d="M6 6l12 12M18 6L6 18"/></svg>';
    ?>
    <div class="ch-view ch-listview" data-view="list">
      <header class="ch-head"><h2 class="ch-title"><?= e(t('Messages', 'Mga Mensahe')) ?></h2>
        <span class="ch-hbtns"><?= $more ?><button type="button" class="ch-x" data-ch="close" aria-label="<?= e(t('Close messages', 'Isara ang mga mensahe')) ?>"><?= $close ?></button></span></header>
      <ul class="ch-rows">
        <?php foreach ($convs as $c): $unread = 0; ?>
          <li><button type="button" class="ch-row" data-ch="open" data-conv="<?= e($c['id']) ?>">
            <i class="ch-dot" aria-hidden="true"></i>
            <span class="ch-av ch-av--<?= e($c['kind']) ?>" aria-hidden="true"><?= e(case_chat_initials($c['name'])) ?></span>
            <span class="ch-rowtxt">
              <span class="ch-rowtop"><b><?= e($c['name']) ?></b><time><?= $c['last'] !== '' ? e(case_chat_day($c['last']) === t('Today', 'Ngayon') ? case_chat_clock($c['last']) : case_chat_day($c['last'])) : '' ?></time></span>
              <span class="ch-rowsub"><?= e($c['sub']) ?></span>
              <span class="ch-rowprev"><?= e(case_chat_preview($c)) ?></span>
            </span>
          </button></li>
        <?php endforeach; ?>
      </ul>
      <?php if (!$convs): ?><p class="ch-empty"><?= e(t('No conversations yet. They start when a tanod is dispatched or the resident writes.', 'Wala pang usapan. Magsisimula ito kapag may na-dispatch na tanod o sumulat ang residente.')) ?></p><?php endif; ?>
    </div>
    <?php foreach ($convs as $c): ?>
      <div class="ch-view ch-conv" data-view="conv" data-conv="<?= e($c['id']) ?>" hidden>
        <header class="ch-head ch-head--conv">
          <button type="button" class="ch-back" data-ch="back" aria-label="<?= e(t('Back to messages', 'Bumalik sa mga mensahe')) ?>"><svg viewBox="0 0 24 24" width="22" height="22" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M15 5l-7 7 7 7"/></svg></button>
          <div class="ch-who"><span class="ch-av ch-av--<?= e($c['kind']) ?> ch-av--sm" aria-hidden="true"><?= e(case_chat_initials($c['name'])) ?></span><b><?= e($c['name']) ?></b><small><?= e($c['sub']) ?></small></div>
          <span class="ch-hbtns"><?= $more ?><button type="button" class="ch-x" data-ch="close" aria-label="<?= e(t('Close messages', 'Isara ang mga mensahe')) ?>"><?= $close ?></button></span>
        </header>
        <div class="ch-msgs" tabindex="0" role="log" aria-live="polite" aria-label="<?= e(t('Conversation with ', 'Usapan kay ') . $c['name']) ?>">
          <?php
            $items = $c['items']; $n = count($items); $lastTs = null; $lastDay = null;
            foreach ($items as $i => $it) {
                $ts = strtotime($it['ts']) ?: 0;
                $day = case_chat_day($it['ts']);
                if ($lastTs === null || $ts - $lastTs > 3600 || $day !== $lastDay) {
                    echo '<div class="ch-sep"><b>' . e($day) . '</b> ' . e(case_chat_clock($it['ts'])) . '</div>';
                }
                $lastTs = $ts; $lastDay = $day;
                if ($it['type'] === 'sys') { echo '<div class="ch-sys" data-ts="' . e($it['ts']) . '">' . e($it['text']) . ' · ' . e(case_chat_clock($it['ts'])) . '</div>'; continue; }
                $prev = $items[$i - 1] ?? null; $next = $items[$i + 1] ?? null;
                $sameP = $prev && $prev['type'] === 'msg' && $prev['out'] === $it['out'] && $ts - (strtotime($prev['ts']) ?: 0) < 300;
                $sameN = $next && $next['type'] === 'msg' && $next['out'] === $it['out'] && (strtotime($next['ts']) ?: 0) - $ts < 300;
                $cls = 'ch-b ' . ($it['out'] ? 'ch-out' : 'ch-in') . ($sameN ? '' : ' ch-last') . ($sameP ? '' : ' ch-first');
                echo '<div class="' . $cls . '" data-ts="' . e($it['ts']) . '"' . ($it['out'] ? '' : ' data-in="1"') . '>';
                if (trim($it['body']) !== '') echo '<p>' . nl2br(e($it['body'])) . '</p>';
                foreach ($it['media'] as $url) {
                    echo '<a class="ch-ph" href="' . e($url) . '" target="_blank" rel="noopener"><img src="' . e(cld_thumb($url, 480)) . '" alt="' . e(t('Photo in the chat', 'Larawan sa usapan')) . '" loading="lazy"></a>';
                }
                echo '</div>';
            }
            if (!$items) echo '<p class="ch-none">' . e(t('No messages yet.', 'Wala pang mensahe.')) . '</p>';
          ?>
        </div>
        <?php if ($c['open']): ?>
          <form method="post" action="case.php?id=<?= e(urlencode($id)) ?>" class="ch-form" data-ch="form">
            <input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>">
            <input type="hidden" name="action" value="<?= e($c['action']) ?>">
            <?php if ($c['dispatch'] !== ''): ?><input type="hidden" name="dispatch" value="<?= e($c['dispatch']) ?>"><?php endif; ?>
            <div class="ch-input">
              <textarea name="body" rows="1" maxlength="<?= (int) $c['max'] ?>" required placeholder="<?= e($c['ph']) ?>" aria-label="<?= e($c['ph']) ?>"></textarea>
              <button type="submit" class="ch-send" aria-label="<?= e(t('Send', 'Ipadala')) ?>"><svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12 19V5M5 12l7-7 7 7"/></svg></button>
            </div>
          </form>
        <?php else: ?>
          <p class="ch-closed"><?= e($c['closed']) ?></p>
        <?php endif; ?>
      </div>
    <?php endforeach; ?>
    <?php
    return (string) ob_get_clean();
}

/** The floating button and the panel around the body. */
function case_chat_head(array $convs, string $id, string $tracking = ''): string
{
    ob_start();
    ?>
<div class="ch" id="chat-head" data-main="1" data-report="<?= e($id) ?>" data-tracking="<?= e($tracking) ?>" data-url="case.php?id=<?= e(urlencode($id)) ?>&amp;chat=1">
  <section class="ch-panel" id="ch-panel" role="dialog" aria-label="<?= e(t('Messages', 'Mga Mensahe')) ?>" hidden>
    <div class="ch-body" id="ch-body"><?= case_chat_body($convs, $id) ?></div>
  </section>
  <button type="button" class="ch-fab" id="ch-fab" aria-expanded="false" aria-controls="ch-panel" aria-haspopup="menu" aria-label="<?= e(t('Messages. Right-click for options.', 'Mga mensahe. I-right-click para sa mga opsyon.')) ?>">
    <svg viewBox="0 0 24 24" width="26" height="26" fill="currentColor" aria-hidden="true"><path d="M12 3C6.5 3 2 6.8 2 11.5c0 2.5 1.3 4.7 3.4 6.2-.2 1.3-.8 2.6-1.7 3.6a.5.5 0 0 0 .5.8c2-.3 3.7-1.1 4.9-2A11.7 11.7 0 0 0 12 20c5.5 0 10-3.8 10-8.5S17.5 3 12 3z"/></svg>
    <span class="ch-badge" id="ch-badge" hidden>0</span>
  </button>
</div>
    <?php
    return (string) ob_get_clean();
}

/**
 * One case's conversations, read on their own (the Inbox's Case chats; case.php has these in its own batch).
 * Null when the case is not there or not this person's to see.
 *
 * @return null|array{report:array,convs:list<array>,evidence:list<array>}
 */
function case_chat_load_reads(string $id): array
{
    return [
        'report'     => ['reports', ['select' => 'id,tracking_id,subject,status,is_anonymous,handler_id,case_committee,handler:users!reports_handler_id_fkey(id,full_name),resident:users!reports_resident_id_fkey(id,full_name,mobile_number)',
                                     'id' => 'eq.' . $id, 'deleted_at' => 'is.null', 'limit' => '1']],
        'dispatches' => ['dispatches', ['select' => 'id,state,assigned_at,tanod_id,tanod:users!dispatches_tanod_id_fkey(id,full_name)', 'report_id' => 'eq.' . $id, 'order' => 'assigned_at.desc']],
        'messages'   => ['report_messages', ['select' => 'id,from_barangay,body,created_at', 'report_id' => 'eq.' . $id, 'order' => 'created_at.asc']],
        'thread'     => ['dispatch_updates', ['select' => 'id,dispatch_id,author_id,kind,step,body,created_at,d:dispatches!inner(report_id)', 'd.report_id' => 'eq.' . $id, 'order' => 'created_at.asc']],
        'proof'      => ['dispatch_media', ['select' => 'dispatch_id,update_id,media_url,mime_type,bytes,uploaded_at,d:dispatches!inner(report_id)', 'd.report_id' => 'eq.' . $id, 'order' => 'uploaded_at.asc']],
        'evidence'   => ['report_media', ['select' => 'id,media_url,mime_type', 'report_id' => 'eq.' . $id, 'order' => 'uploaded_at.asc']],
    ];
}

/** The conversations of a case from the answers to case_chat_load_reads (read in a batch with other things). */
function case_chat_load_build(array $got): ?array
{
    $report = is_array($got['report'] ?? null) ? ($got['report'][0] ?? null) : null;
    if (!$report) return null;
    $thread = []; $media = [];
    foreach ((array) ($got['thread'] ?? []) as $u) { $thread[$u['dispatch_id']][] = $u; }
    foreach ((array) ($got['proof'] ?? []) as $m) { if (!empty($m['update_id'])) $media[$m['update_id']][] = $m; }
    $convs = case_chat_conversations($report, is_array($got['dispatches'] ?? null) ? $got['dispatches'] : [], $thread, $media,
                                     is_array($got['messages'] ?? null) ? $got['messages'] : [], (string) ($report['status'] ?? ''));
    return ['report' => $report, 'convs' => $convs, 'evidence' => is_array($got['evidence'] ?? null) ? $got['evidence'] : []];
}

function case_chat_load(Supabase $db, string $id): ?array
{
    return case_chat_load_build($db->selectMany(case_chat_load_reads($id)));
}

/**
 * The Inbox's Case chats list, one row per CONVERSATION (the resident of a case, a tanod on one of its dispatches), the newest
 * first, the way Messenger lists people. What the database lets this person read is all there is. Each row carries what the
 * page needs to light its unread dot in the browser (this conversation's last words in and the barangay's last answer).
 *
 * @return list<array{key:string,case:string,conv:string,kind:string,name:string,tracking:string,subject:string,status:string,mine:bool,last:string,text:string,out:bool,feed:array}>
 */
function case_chat_list_reads(int $keep = 300): array
{
    $rep = 'id,tracking_id,subject,status,handler_id';
    return [
        'msgs' => ['report_messages', ['select' => 'report_id,from_barangay,body,created_at,report:reports!report_messages_report_id_fkey(' . $rep . ',resident:users!reports_resident_id_fkey(full_name))',
                                       'order' => 'created_at.desc', 'limit' => (string) $keep]],
        'ups'  => ['dispatch_updates', ['select' => 'dispatch_id,author_id,kind,body,created_at,d:dispatches!inner(report_id,tanod_id,tanod:users!dispatches_tanod_id_fkey(full_name),report:reports!dispatches_report_id_fkey(' . $rep . '))',
                                        'kind' => 'eq.message', 'order' => 'created_at.desc', 'limit' => (string) $keep]],
    ];
}

/** The rows from the answers to case_chat_list_reads. */
function case_chat_list_rows(array $got, string $me): array
{
    $iso = static function (?string $s): string { $t = $s !== null ? strtotime($s) : false; return $t ? gmdate('Y-m-d\TH:i:s\Z', $t) : ''; };
    $rows = [];
    $put = static function (array $r, string $conv, string $kind, string $name, bool $incoming, string $ts, string $text) use (&$rows, $me): void {
        if (empty($r['id']) || $ts === '') return;
        $key = $r['id'] . '|' . $conv;
        $c = &$rows[$key];
        $c ??= ['key' => $key, 'case' => (string) $r['id'], 'conv' => $conv, 'kind' => $kind, 'name' => $name, 'tracking' => (string) ($r['tracking_id'] ?? ''),
                'subject' => (string) ($r['subject'] ?? ''), 'status' => (string) ($r['status'] ?? ''), 'mine' => ($r['handler_id'] ?? null) === $me,
                'last' => '', 'text' => '', 'out' => false, 'feed' => ['in' => [], 'out' => []]];
        if ($ts > $c['last']) { $c['last'] = $ts; $c['text'] = mb_substr(trim($text), 0, 140); $c['out'] = !$incoming; }
        if ($incoming) { if (count($c['feed']['in']) < 30) $c['feed']['in'][] = ['c' => $conv, 'ts' => $ts]; }
        elseif (!isset($c['feed']['out'][$conv]) || $ts > $c['feed']['out'][$conv]) { $c['feed']['out'][$conv] = $ts; }
    };
    foreach ((array) ($got['msgs'] ?? []) as $m) {
        $r = (array) ($m['report'] ?? []);
        $put($r, 'r', 'resident', formal_or($r['resident']['full_name'] ?? null, t('Resident', 'Residente')), empty($m['from_barangay']), $iso($m['created_at'] ?? null), (string) ($m['body'] ?? ''));
    }
    foreach ((array) ($got['ups'] ?? []) as $u) {
        $d = (array) ($u['d'] ?? []);
        $put((array) ($d['report'] ?? []), 'd-' . $u['dispatch_id'], 'tanod', (string) ($d['tanod']['full_name'] ?? t('Tanod', 'Tanod')),
             ($u['author_id'] ?? null) === ($d['tanod_id'] ?? '?'), $iso($u['created_at'] ?? null), (string) ($u['body'] ?? ''));
    }
    $list = array_values($rows);
    usort($list, static fn ($a, $b) => strcmp($b['last'], $a['last']));
    return $list;
}

function case_chat_list(Supabase $db, string $me, int $keep = 300): array
{
    return case_chat_list_rows($db->selectMany(case_chat_list_reads($keep)), $me);
}

/** The reader's chat, drawn in the page (not floating): the conversations of one case, open at once. */
function case_chat_inline(array $convs, string $id, string $tracking): string
{
    ob_start();
    ?>
<div class="ch ch-inline" data-inline="1" data-report="<?= e($id) ?>" data-tracking="<?= e($tracking) ?>" data-url="case.php?id=<?= e(urlencode($id)) ?>&amp;chat=1">
  <section class="ch-panel" role="region" aria-label="<?= e(t('Messages', 'Mga Mensahe')) ?>">
    <div class="ch-body"><?= case_chat_body($convs, $id) ?></div>
  </section>
</div>
    <?php
    return (string) ob_get_clean();
}
