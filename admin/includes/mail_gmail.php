<?php
/**
 * BarangayMail, the way Gmail's web app works (12 Nov 2026, Ace: "BarangayMail imitates Gmail one to one").
 *
 * The data layer and the pieces of HTML the page asks for (mail.php is the door; assets/js/gmail.js is the page). Mail is one row per
 * recipient of a message (a batch per message sent); a conversation is the thread_id (0173). Everything a person does to it, they do
 * to their own copy: the marks (star, archive, trash, snooze) and the labels are theirs alone (mail_state, mail_labels, 0173), written only
 * through mail_flag and the label functions. The window is the person's newest 500 messages in each direction, which is more than the
 * Inbox ever holds (it is cleared after the barangay's retention period).
 */
declare(strict_types=1);

require_once __DIR__ . '/layout.php';

const GM_PER = 50;
const GM_KEEP = 500;

/** The reads for the person's mailbox, all in one batch. */
function gm_reads(string $me): array
{
    $sel = 'id,batch,thread_id,sender,recipient,role,kind,subject,body,created_at,read_at,report_id,question_id,reply_to,'
         . 'from:users!inbox_messages_sender_fkey(id,full_name),to:users!inbox_messages_recipient_fkey(id,full_name),'
         . 'report:reports!inbox_messages_report_id_fkey(id,tracking_id,subject)';
    return [
        'rec' => ['inbox_messages', ['select' => $sel, 'recipient' => 'eq.' . $me, 'order' => 'created_at.desc', 'limit' => (string) GM_KEEP]],
        'snt' => ['inbox_messages', ['select' => $sel, 'sender' => 'eq.' . $me, 'order' => 'created_at.desc', 'limit' => (string) GM_KEEP]],
        'st'  => ['mail_state', ['select' => 'batch,starred,archived,trashed_at,purged,snoozed_until', 'user_id' => 'eq.' . $me, 'limit' => '2000']],
        'lb'  => ['mail_labels', ['select' => 'id,name,colour', 'user_id' => 'eq.' . $me, 'order' => 'name.asc']],
        'll'  => ['mail_label_links', ['select' => 'batch,label_id', 'user_id' => 'eq.' . $me, 'limit' => '4000']],
        'dr'  => ['mail_drafts', ['select' => 'id,to_ids,cc_ids,bcc_ids,subject,body,report_id,reply_to,updated_at', 'user_id' => 'eq.' . $me, 'order' => 'updated_at.desc', 'limit' => '100']],
    ];
}

/**
 * The mailbox as conversations, newest first.
 *
 * @return array{threads:list<array>,labels:array<int,array>,drafts:list<array>,now:int}
 */
function gm_build(array $got, string $me): array
{
    $now = time();
    $st = [];
    foreach ((array) ($got['st'] ?? []) as $s) { $st[(string) $s['batch']] = $s; }
    $labels = [];
    foreach ((array) ($got['lb'] ?? []) as $l) { $labels[(int) $l['id']] = ['id' => (int) $l['id'], 'name' => (string) $l['name'], 'colour' => (string) $l['colour']]; }
    $links = [];
    foreach ((array) ($got['ll'] ?? []) as $l) { $links[(string) $l['batch']][] = (int) $l['label_id']; }

    // one item per message (per batch): what I received, and what I sent (its recipients collected)
    $items = [];
    foreach ((array) ($got['rec'] ?? []) as $m) {
        $b = (string) $m['batch'];
        $items[$b] = ['batch' => $b, 'thread' => (string) ($m['thread_id'] ?? $b), 'id' => (int) $m['id'], 'mine' => false, 'role' => (string) ($m['role'] ?? 'to'),
            'from' => (string) ($m['from']['full_name'] ?? ''), 'from_id' => (string) ($m['sender'] ?? ''), 'system' => ($m['kind'] ?? '') === 'system', 'to' => [],
            'subject' => (string) $m['subject'], 'body' => (string) $m['body'], 'at' => (string) $m['created_at'], 'unread' => empty($m['read_at']),
            'report' => $m['report'] ?? null, 'report_id' => $m['report_id'] ?? null, 'question' => $m['question_id'] ?? null, 'reply_to' => $m['reply_to'] ?? null];
    }
    foreach ((array) ($got['snt'] ?? []) as $m) {
        $b = (string) $m['batch'];
        if (!isset($items[$b])) {
            $items[$b] = ['batch' => $b, 'thread' => (string) ($m['thread_id'] ?? $b), 'id' => (int) $m['id'], 'mine' => true, 'role' => 'to',
                'from' => '', 'from_id' => $me, 'system' => false, 'to' => [], 'subject' => (string) $m['subject'], 'body' => (string) $m['body'], 'at' => (string) $m['created_at'],
                'unread' => false, 'report' => $m['report'] ?? null, 'report_id' => $m['report_id'] ?? null, 'question' => null, 'reply_to' => $m['reply_to'] ?? null];
        }
        if (($m['role'] ?? 'to') !== 'bcc') { $items[$b]['to'][] = (string) ($m['to']['full_name'] ?? ''); }
    }

    $threads = [];
    foreach ($items as $it) {
        $it['state'] = $st[$it['batch']] ?? [];
        $it['labels'] = $links[$it['batch']] ?? [];
        $threads[$it['thread']]['items'][] = $it;
    }
    $out = [];
    foreach ($threads as $tid => $th) {
        $its = $th['items'];
        usort($its, static fn ($a, $b) => strcmp($a['at'], $b['at']));
        $first = $its[0]; $last = $its[count($its) - 1];
        $in = $sent = $star = $snooze = $trash = $any = false; $unread = 0; $lab = []; $names = [];
        foreach ($its as $it) {
            $s = $it['state'];
            $trashed = !empty($s['trashed_at']); $purged = !empty($s['purged']); $archived = !empty($s['archived']);
            $snz = !empty($s['snoozed_until']) && strtotime((string) $s['snoozed_until']) > $now;
            if ($purged) continue;
            if ($trashed) { if (strtotime((string) $s['trashed_at']) > $now - 30 * 86400) $trash = true; continue; }
            $any = true;
            if (!$it['mine'] && !$archived && !$snz) $in = true;
            if ($it['mine']) $sent = true;
            if (!empty($s['starred'])) $star = true;
            if ($snz) $snooze = true;
            if ($it['unread']) $unread++;
            foreach ($it['labels'] as $l) { $lab[$l] = true; }
            $names[] = $it['mine'] ? t('me', 'ako') : ($it['system'] ? 'SmartSumbong' : formal_name($it['from']));
        }
        $out[] = ['id' => (string) $tid, 'items' => $its, 'subject' => (string) $first['subject'], 'last' => $last, 'at' => $last['at'], 'unread' => $unread,
            'in' => $in, 'sent' => $sent, 'star' => $star, 'snooze' => $snooze, 'trash' => $trash, 'any' => $any, 'labels' => array_keys($lab),
            'names' => array_values(array_unique($names)), 'count' => count($its), 'system' => !empty($last['system']) && count($its) === 1];
    }
    usort($out, static fn ($a, $b) => strcmp($b['at'], $a['at']));
    return ['threads' => $out, 'labels' => $labels, 'drafts' => (array) ($got['dr'] ?? []), 'now' => $now];
}

/** Whether a conversation belongs in a folder (inbox, starred, snoozed, sent, drafts are separate, all, trash, label:<id>). */
function gm_in_folder(array $th, string $folder): bool
{
    return match (true) {
        $folder === 'inbox'   => $th['in'],
        $folder === 'starred' => $th['star'],
        $folder === 'snoozed' => $th['snooze'],
        $folder === 'sent'    => $th['sent'],
        $folder === 'trash'   => $th['trash'],
        $folder === 'all'     => $th['any'],
        str_starts_with($folder, 'label:') => $th['any'] && in_array((int) substr($folder, 6), $th['labels'], true),
        default => false,
    };
}

/** Gmail's search box: free words plus from: to: subject: label: is: in: before: after:. */
function gm_search_parse(string $q): array
{
    $out = ['text' => [], 'from' => [], 'to' => [], 'subject' => [], 'label' => [], 'is' => [], 'in' => null, 'before' => null, 'after' => null];
    preg_match_all('/(\w+):("[^"]*"|\S+)|"([^"]*)"|(\S+)/u', $q, $m, PREG_SET_ORDER);
    foreach ($m as $x) {
        if (($x[1] ?? '') !== '') {
            $k = strtolower($x[1]); $v = trim($x[2], '"');
            if (in_array($k, ['from', 'to', 'subject', 'label', 'is'], true)) { $out[$k][] = mb_strtolower($v); continue; }
            if ($k === 'in') { $out['in'] = strtolower($v); continue; }
            if ($k === 'before' || $k === 'after') { $ts = strtotime(str_replace('/', '-', $v)); if ($ts) $out[$k] = $ts; continue; }
        }
        $w = ($x[3] ?? '') !== '' ? $x[3] : ($x[4] ?? '');
        if ($w !== '') $out['text'][] = mb_strtolower($w);
    }
    return $out;
}

function gm_search_match(array $th, array $q, array $labels): bool
{
    $hay = mb_strtolower($th['subject'] . ' ' . implode(' ', array_map(static fn ($i) => $i['body'], $th['items'])));
    foreach ($q['text'] as $w) { if (!str_contains($hay, $w) && !str_contains(mb_strtolower(implode(' ', $th['names'])), $w)) return false; }
    foreach ($q['subject'] as $w) { if (!str_contains(mb_strtolower($th['subject']), $w)) return false; }
    foreach ($q['from'] as $w) {
        $ok = false; foreach ($th['items'] as $i) { if (str_contains(mb_strtolower($i['mine'] ? 'me' : $i['from']), $w)) { $ok = true; break; } }
        if (!$ok) return false;
    }
    foreach ($q['to'] as $w) {
        $ok = false; foreach ($th['items'] as $i) { if (str_contains(mb_strtolower(($i['mine'] ? implode(' ', $i['to']) : 'me')), $w)) { $ok = true; break; } }
        if (!$ok) return false;
    }
    foreach ($q['label'] as $w) {
        $ok = false; foreach ($th['labels'] as $l) { if (isset($labels[$l]) && mb_strtolower($labels[$l]['name']) === $w) { $ok = true; break; } }
        if (!$ok) return false;
    }
    foreach ($q['is'] as $w) {
        if ($w === 'unread' && $th['unread'] === 0) return false;
        if ($w === 'read' && $th['unread'] > 0) return false;
        if ($w === 'starred' && !$th['star']) return false;
    }
    $ts = strtotime($th['at']) ?: 0;
    if ($q['before'] !== null && $ts >= $q['before']) return false;
    if ($q['after'] !== null && $ts < $q['after']) return false;
    return true;
}

/** The conversations of one view: a folder (or the words typed in the search box), the tab, the page. */
function gm_view(array $box, string $folder, string $q, string $tab, int $page): array
{
    $labels = $box['labels']; $rows = [];
    $parsed = trim($q) !== '' ? gm_search_parse($q) : null;
    $f = $parsed && $parsed['in'] ? ($parsed['in'] === 'anywhere' ? 'all' : $parsed['in']) : $folder;
    if ($parsed && !$parsed['in']) { $f = 'all'; }
    foreach ($box['threads'] as $th) {
        if (!gm_in_folder($th, $f)) continue;
        if (!$parsed && $folder === 'inbox') {   // the two tabs of the Inbox: people, and the system's own mail
            if (($tab === 'updates') !== $th['system']) continue;
        }
        if ($parsed && !gm_search_match($th, $parsed, $labels)) continue;
        $rows[] = $th;
    }
    $total = count($rows);
    $page = max(1, min($page, max(1, (int) ceil($total / GM_PER))));
    return ['rows' => array_slice($rows, ($page - 1) * GM_PER, GM_PER), 'total' => $total, 'page' => $page, 'folder' => $f];
}

/** What the rail counts: unread conversations in the Inbox (people and system), drafts, unread per label. */
function gm_counts(array $box): array
{
    $c = ['inbox' => 0, 'updates' => 0, 'drafts' => count($box['drafts']), 'labels' => []];
    foreach ($box['threads'] as $th) {
        if ($th['in'] && $th['unread'] > 0) { if ($th['system']) $c['updates']++; else $c['inbox']++; }
        if ($th['any'] && $th['unread'] > 0) { foreach ($th['labels'] as $l) { $c['labels'][$l] = ($c['labels'][$l] ?? 0) + 1; } }
    }
    return $c;
}

/** The time in a row: the hour today, "Nov 12" this year, the date before that. */
function gm_when(string $iso): string
{
    $tz = new DateTimeZone('Asia/Manila');
    $d = (new DateTimeImmutable($iso))->setTimezone($tz); $now = new DateTimeImmutable('now', $tz);
    if ($d->format('Y-m-d') === $now->format('Y-m-d')) return $d->format('g:i A');
    if ($d->format('Y') === $now->format('Y')) return $d->format('M j');
    return $d->format('n/j/y');
}

/** The long time in a message's header: "Thu, Nov 12, 10:41 AM (2 hours ago)". */
function gm_long(string $iso): string
{
    $d = (new DateTimeImmutable($iso))->setTimezone(new DateTimeZone('Asia/Manila'));
    return $d->format('D, M j, Y, g:i A') . ' (' . relative_time($iso) . ')';
}

/** A message's text, with the few marks the compose window writes (bold, italic, lists, quotes, links); everything else is escaped first. */
function gm_body_html(string $text): string
{
    $out = []; $list = null;
    foreach (preg_split('/\r\n|\r|\n/', $text) ?: [] as $line) {
        $h = e($line);
        $h = preg_replace('/\*\*(.+?)\*\*/u', '<b>$1</b>', $h);
        $h = preg_replace('/(?<![\w*])\*(?!\s)(.+?)(?<!\s)\*(?![\w*])/u', '<i>$1</i>', $h);
        $h = preg_replace('/(?<![\w])_(?!\s)(.+?)(?<!\s)_(?![\w])/u', '<i>$1</i>', $h);
        $h = preg_replace('~(https?://[^\s<]+)~u', '<a href="$1" target="_blank" rel="noopener noreferrer">$1</a>', $h);
        if (preg_match('/^\s*[-•]\s+(.*)$/u', $h, $m)) { if ($list !== 'ul') { if ($list) $out[] = '</' . $list . '>'; $out[] = '<ul>'; $list = 'ul'; } $out[] = '<li>' . $m[1] . '</li>'; continue; }
        if (preg_match('/^\s*\d+[.)]\s+(.*)$/u', $h, $m)) { if ($list !== 'ol') { if ($list) $out[] = '</' . $list . '>'; $out[] = '<ol>'; $list = 'ol'; } $out[] = '<li>' . $m[1] . '</li>'; continue; }
        if ($list) { $out[] = '</' . $list . '>'; $list = null; }
        if (preg_match('/^&gt;\s?(.*)$/u', $h, $m)) { $out[] = '<blockquote>' . $m[1] . '</blockquote>'; continue; }
        $out[] = $h === '' ? '<br>' : '<p>' . $h . '</p>';
    }
    if ($list) $out[] = '</' . $list . '>';
    return implode('', $out);
}

function gm_snippet(string $body): string
{
    $s = trim(preg_replace('/\s+/u', ' ', preg_replace('/[*_>]+/u', '', $body)) ?? '');
    return mb_strimwidth($s, 0, 140, '…');
}

function gm_avatar(string $name, bool $system = false): string
{
    return '<span class="gm-av' . ($system ? ' gm-av--sys' : '') . '" aria-hidden="true">' . e($system ? '✦' : admin_initials($name)) . '</span>';
}

/** One label chip. */
function gm_chip(array $l): string
{
    return '<span class="gm-chip" style="--lc:' . e($l['colour']) . '">' . e($l['name']) . '</span>';
}

/** The rows of the list. */
function gm_rows(array $rows, array $labels, string $folder): string
{
    ob_start();
    foreach ($rows as $th):
        $batches = array_map(static fn ($i) => $i['batch'], $th['items']);
        $ids = array_map(static fn ($i) => $i['id'], array_filter($th['items'], static fn ($i) => !$i['mine'] && $i['unread']));
        $rids = array_map(static fn ($i) => $i['id'], array_filter($th['items'], static fn ($i) => !$i['mine']));
        $names = $th['names'] ?: [t('me', 'ako')];
        $nm = count($names) > 2 ? $names[0] . ', ' . t('me', 'ako') : implode(', ', $names);
        $snip = gm_snippet($th['last']['body']); ?>
      <div class="gm-row<?= $th['unread'] > 0 ? ' gm-unread' : '' ?>" role="listitem" tabindex="0" data-t="<?= e($th['id']) ?>" data-b="<?= e(implode(',', $batches)) ?>" data-u="<?= e(implode(',', $ids)) ?>" data-r="<?= e(implode(',', $rids)) ?>" data-star="<?= $th['star'] ? '1' : '0' ?>" data-l="<?= e(implode(',', $th['labels'])) ?>">
        <span class="gm-ck"><input type="checkbox" aria-label="<?= e(t('Select', 'Piliin')) ?>"></span>
        <button type="button" class="gm-star<?= $th['star'] ? ' on' : '' ?>" data-gm="star" aria-pressed="<?= $th['star'] ? 'true' : 'false' ?>" aria-label="<?= e($th['star'] ? t('Starred', 'May bituin') : t('Not starred', 'Walang bituin')) ?>"><svg viewBox="0 0 24 24" width="20" height="20" aria-hidden="true"><path d="M12 3.2l2.7 5.6 6.1.8-4.5 4.2 1.1 6.1L12 17l-5.4 2.9 1.1-6.1L3.2 9.6l6.1-.8z"/></svg></button>
        <span class="gm-from"><?= e($nm) ?><?php if ($th['count'] > 1): ?> <small><?= (int) $th['count'] ?></small><?php endif; ?></span>
        <a class="gm-subj" href="inbox.php?app=mail#t/<?= e($th['id']) ?>">
          <?php foreach ($th['labels'] as $lid): if (isset($labels[$lid])) echo gm_chip($labels[$lid]); endforeach; ?>
          <?php if (!empty($th['last']['report'])): ?><span class="gm-chip gm-chip--case"><?= e((string) $th['last']['report']['tracking_id']) ?></span><?php endif; ?>
          <b><?= e($th['subject']) ?></b><span class="gm-snip"> — <?= e($snip) ?></span></a>
        <time class="gm-when" datetime="<?= e($th['at']) ?>" title="<?= e(gm_long($th['at'])) ?>"><?= e(gm_when($th['at'])) ?></time>
        <span class="gm-hov" role="group" aria-label="<?= e(t('Actions', 'Mga aksyon')) ?>">
          <?php if ($folder !== 'trash'): ?>
            <button type="button" data-gm="archive" title="<?= e(t('Archive', 'I-archive')) ?>" aria-label="<?= e(t('Archive', 'I-archive')) ?>"><svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="4" width="18" height="4" rx="1"/><path d="M5 8v11a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1V8M10 12h4"/></svg></button>
            <button type="button" data-gm="trash" title="<?= e(t('Delete', 'Burahin')) ?>" aria-label="<?= e(t('Delete', 'Burahin')) ?>"><svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"><path d="M4 7h16M9 7V4h6v3M6 7l1 13h10l1-13M10 11v6M14 11v6"/></svg></button>
          <?php endif; ?>
          <button type="button" data-gm="toggleread" title="<?= e($th['unread'] > 0 ? t('Mark as read', 'Markahang nabasa') : t('Mark as unread', 'Markahang hindi pa nababasa')) ?>" aria-label="<?= e($th['unread'] > 0 ? t('Mark as read', 'Markahang nabasa') : t('Mark as unread', 'Markahang hindi pa nababasa')) ?>"><svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="5" width="18" height="14" rx="2"/><path d="M3 7l9 6 9-6"/></svg></button>
          <button type="button" data-gm="snooze" title="<?= e(t('Snooze', 'I-snooze')) ?>" aria-label="<?= e(t('Snooze', 'I-snooze')) ?>"><svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="13" r="8"/><path d="M12 9v4l2.5 2M5 4 3 6M19 4l2 2"/></svg></button>
        </span>
      </div>
    <?php endforeach;
    if (!$rows): ?><p class="gm-empty" role="listitem"><?= e(t('No conversations here.', 'Walang usapan dito.')) ?></p><?php endif;
    return (string) ob_get_clean();
}

/** The drafts folder's rows. */
function gm_draft_rows(array $drafts): string
{
    ob_start();
    foreach ($drafts as $d): ?>
      <div class="gm-row gm-draft" role="listitem" tabindex="0" data-draft="<?= (int) $d['id'] ?>">
        <span class="gm-ck"><input type="checkbox" aria-label="<?= e(t('Select', 'Piliin')) ?>"></span><span class="gm-star-sp"></span>
        <span class="gm-from gm-draftlbl"><?= e(t('Draft', 'Draft')) ?></span>
        <a class="gm-subj" href="#draft/<?= (int) $d['id'] ?>" data-gm="opendraft"><b><?= e((string) ($d['subject'] !== '' ? $d['subject'] : t('(no subject)', '(walang paksa)'))) ?></b><span class="gm-snip"> — <?= e(gm_snippet((string) $d['body'])) ?></span></a>
        <time class="gm-when" datetime="<?= e((string) $d['updated_at']) ?>"><?= e(gm_when((string) $d['updated_at'])) ?></time>
        <span class="gm-hov"><button type="button" data-gm="deldraft" title="<?= e(t('Discard draft', 'Itapon ang draft')) ?>" aria-label="<?= e(t('Discard draft', 'Itapon ang draft')) ?>"><svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"><path d="M4 7h16M9 7V4h6v3M6 7l1 13h10l1-13"/></svg></button></span>
      </div>
    <?php endforeach;
    if (!$drafts): ?><p class="gm-empty"><?= e(t('No drafts.', 'Walang draft.')) ?></p><?php endif;
    return (string) ob_get_clean();
}

/**
 * One conversation, open: its messages (older ones collapsed to a line, the newest and every unread one open), with who it went to,
 * the case it is about, a reroute question's answer form, and the reply bar.
 *
 * @param array $th      one thread from gm_build
 * @param array $people  batch => list of [user_id, full_name, role] (mail_batch_people)
 * @param array $qs      question id => its row (with the roster for an open one)
 */
function gm_thread_html(array $th, array $labels, array $people, array $qs, string $me, string $myName): string
{
    ob_start();
    $n = count($th['items']);
    ?>
    <header class="gm-th-head">
      <h2 class="gm-th-subj"><?= e($th['subject']) ?></h2>
      <span class="gm-th-labels"><?php foreach ($th['labels'] as $lid): if (isset($labels[$lid])) echo gm_chip($labels[$lid]); endforeach; ?></span>
    </header>
    <div class="gm-msgs">
    <?php foreach ($th['items'] as $i => $it):
        $open = $i === $n - 1 || $it['unread'];
        $who = $it['mine'] ? $myName : ($it['system'] ? 'SmartSumbong' : formal_name($it['from']));
        $ppl = $people[$it['batch']] ?? [];
        $to = []; $cc = [];
        foreach ($ppl as $p) { $nm = $p['user_id'] === $me ? t('me', 'ako') : formal_name((string) $p['full_name']); if ($p['role'] === 'cc') $cc[] = $nm; elseif ($p['role'] === 'to') $to[] = $nm; else $to[] = $nm . ' (bcc)'; }
        if (!$ppl) { $to = $it['mine'] ? ($it['to'] ?: []) : [t('me', 'ako')]; }
        $starred = !empty($it['state']['starred']); ?>
      <article class="gm-msg<?= $open ? ' open' : '' ?><?= $it['unread'] ? ' unread' : '' ?>" data-b="<?= e($it['batch']) ?>" data-id="<?= (int) $it['id'] ?>">
        <header class="gm-m-head">
          <button type="button" class="gm-m-toggle" aria-expanded="<?= $open ? 'true' : 'false' ?>">
          <?= gm_avatar($who, $it['system']) ?>
          <span class="gm-m-who"><b><?= e($it['mine'] ? t('me', 'ako') : $who) ?></b><span class="gm-m-to"><?= e(t('to ', 'kay ')) . e(implode(', ', $to)) ?><?= $cc ? e(' · cc ' . implode(', ', $cc)) : '' ?></span>
            <span class="gm-m-snip"><?= e(gm_snippet($it['body'])) ?></span></span>
          <time class="gm-m-when" datetime="<?= e($it['at']) ?>" title="<?= e(gm_long($it['at'])) ?>"><?= e(gm_when($it['at'])) ?></time>
          </button>
          <button type="button" class="gm-star<?= $starred ? ' on' : '' ?>" data-gm="mstar" aria-pressed="<?= $starred ? 'true' : 'false' ?>" aria-label="<?= e(t('Star this message', 'Bituin ang mensaheng ito')) ?>"><svg viewBox="0 0 24 24" width="20" height="20" aria-hidden="true"><path d="M12 3.2l2.7 5.6 6.1.8-4.5 4.2 1.1 6.1L12 17l-5.4 2.9 1.1-6.1L3.2 9.6l6.1-.8z"/></svg></button>
        </header>
        <div class="gm-m-body">
          <p class="gm-m-detail"><span><?= e(t('From', 'Mula kay')) ?></span> <?= e($who) ?> · <span><?= e(t('To', 'Para kay')) ?></span> <?= e(implode(', ', $to)) ?><?= $cc ? ' · <span>Cc</span> ' . e(implode(', ', $cc)) : '' ?> · <?= e(gm_long($it['at'])) ?></p>
          <div class="gm-text"><?= gm_body_html($it['body']) ?></div>
          <?php if (!empty($it['report'])): ?><p><a class="gm-casebtn" href="case.php?id=<?= e((string) $it['report']['id']) ?>"><?= e(sprintf(t('Open case %s', 'Buksan ang kaso %s'), (string) $it['report']['tracking_id'])) ?></a></p>
          <?php elseif (!empty($it['report_id'])): ?><p class="gm-hint"><?= e(t('This message is about a case you can no longer see (it may have been forwarded).', 'Tungkol ito sa kasong hindi mo na nakikita (maaaring naipasa na).')) ?></p><?php endif; ?>
          <?php if (!empty($it['question']) && isset($qs[(int) $it['question']])): $q = $qs[(int) $it['question']]; ?>
            <?php if (($q['state'] ?? '') === 'open'): ?>
              <form class="gm-q" data-gm="answer" data-question="<?= (int) $q['id'] ?>">
                <p class="gm-q-due" data-due="<?= e((string) $q['due_at']) ?>"><span><?= e(sprintf(t('Answer by %s, or the nearest tanod from any committee is sent.', 'Sumagot bago mag-%s, o ipapadala ang pinakamalapit na tanod mula sa kahit anong komite.'),
                    (new DateTimeImmutable((string) $q['due_at']))->setTimezone(new DateTimeZone('Asia/Manila'))->format('g:i A'))) ?></span> <b></b></p>
                <label class="gm-q-l" for="gm-tanod-<?= (int) $q['id'] ?>"><?= e(t('Send this tanod', 'Ipadala ang tanod na ito')) ?></label>
                <div class="gm-q-row">
                  <select id="gm-tanod-<?= (int) $q['id'] ?>" name="tanod">
                    <?php foreach ((array) ($q['roster'] ?? []) as $tn): ?><option value="<?= e((string) $tn['tanod_id']) ?>"<?= empty($tn['assignable']) ? ' disabled' : '' ?>><?= e(formal_name((string) $tn['full_name'])) ?><?= isset($tn['metres']) ? ' · ' . (int) round((float) $tn['metres']) . ' m' : '' ?></option><?php endforeach; ?>
                  </select>
                  <button type="button" class="gm-btn gm-btn--blue" data-gm="answer-go" data-pick="tanod"><?= e(t('Send', 'Ipadala')) ?></button>
                </div>
                <button type="button" class="gm-btn" data-gm="answer-go" data-pick="any"><?= e(t('Send the nearest from any committee now', 'Ipadala na ang pinakamalapit mula sa kahit anong komite')) ?></button>
              </form>
            <?php else: ?>
              <p class="gm-hint"><?= e(match ($q['state'] ?? '') {
                  'picked'    => sprintf(t('Answered by %s: they picked the tanod.', 'Sinagot ni %s: pumili sila ng tanod.'), formal_name((string) ($q['by']['full_name'] ?? ''))),
                  'any'       => sprintf(t('Answered by %s: the nearest from any committee was sent.', 'Sinagot ni %s: ipinadala ang pinakamalapit mula sa kahit anong komite.'), formal_name((string) ($q['by']['full_name'] ?? ''))),
                  'timed_out' => t('Nobody answered in time: the nearest tanod from any committee was sent.', 'Walang sumagot sa oras: ipinadala ang pinakamalapit na tanod mula sa kahit anong komite.'),
                  default     => t('No longer needed: the case already has a tanod, or was closed.', 'Hindi na kailangan: may tanod na ang kaso, o naisara na.'),
              }) ?></p>
            <?php endif; ?>
          <?php endif; ?>
        </div>
      </article>
    <?php endforeach; ?>
    </div>
    <?php $lastIt = $th['items'][$n - 1]; if (!$lastIt['system'] || !$lastIt['mine']): ?>
    <div class="gm-reply">
      <?php if (!$lastIt['system']): ?>
        <button type="button" class="gm-btn gm-btn--out" data-gm="reply"><svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M9 14 4 9l5-5"/><path d="M4 9h9a7 7 0 0 1 7 7v3"/></svg><?= e(t('Reply', 'Sumagot')) ?></button>
        <button type="button" class="gm-btn gm-btn--out" data-gm="replyall"><?= e(t('Reply all', 'Sumagot sa lahat')) ?></button>
      <?php endif; ?>
      <button type="button" class="gm-btn gm-btn--out" data-gm="forward"><?= e(t('Forward', 'I-forward')) ?><svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M15 14l5-5-5-5"/><path d="M20 9h-9a7 7 0 0 0-7 7v3"/></svg></button>
    </div>
    <?php endif;
    return (string) ob_get_clean();
}
