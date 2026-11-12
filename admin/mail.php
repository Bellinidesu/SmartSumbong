<?php
/**
 * BarangayMail's door (12 Nov 2026): what the Gmail-style page (assets/js/gmail.js) asks for, as JSON, run as the signed-in administrator.
 *
 *   GET  ?v=list&f=<folder>&q=<search>&tab=people|updates&p=<page>    the rows of a folder or a search, with the counts for the rail
 *        ?v=thread&t=<thread id>                                       one conversation, open (its unread messages are marked read)
 *        ?v=people&q=<words>                                           who the person may write to (mail_recipients)
 *        ?v=draft&id=<id>                                              one draft
 *        ?v=find&m=<message id>                                        the thread of a message (old links to a letter)
 *   POST (JSON, with the page's CSRF token) act = flag | read | label_apply | label_save | label_delete | draft_save | draft_delete | send | answer
 *
 * Everything a person does here is to their own copy, through the 0173 functions; sending still goes through send_mail along the ladder.
 */
declare(strict_types=1);

require_once __DIR__ . '/includes/auth.php';
require_once __DIR__ . '/includes/layout.php';
require_once __DIR__ . '/includes/mail_gmail.php';

$admin = require_admin_api();
header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store');

function mj(array $a, int $code = 200): never
{
    http_response_code($code);
    echo json_encode($a, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_INVALID_UTF8_SUBSTITUTE);
    exit;
}

$db = db();
$me = (string) $admin['id'];
$uuid = '/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i';
$ids = static fn ($v): array => array_values(array_filter(is_array($v) ? $v : explode(',', (string) $v), static fn ($x) => is_string($x) || is_int($x)));
$pgArr = static fn (array $a): string => '{' . implode(',', $a) . '}';

try {
    if ($_SERVER['REQUEST_METHOD'] === 'POST') {
        $in = json_decode((string) file_get_contents('php://input'), true);
        if (!is_array($in)) { $in = $_POST; }
        if (!csrf_check($in['csrf'] ?? null)) { mj(['ok' => false, 'text' => t('That form expired. Reload the page and try again.', 'Nag-expire ang form. I-reload ang pahina at subukan muli.')], 403); }
        session_write_close();
        $act = (string) ($in['act'] ?? '');
        $uuids = static function ($v) use ($ids, $uuid): array { return array_values(array_filter(array_map('strval', $ids($v)), static fn ($x) => preg_match($uuid, $x) === 1)); };
        $ints = static fn ($v): array => array_values(array_map('intval', array_filter($ids($v), static fn ($x) => ctype_digit((string) $x))));
        $reportOf = static function (string $track) use ($db): ?string {
            $track = strtoupper(trim($track));
            if ($track === '') return null;
            $f = (array) $db->select('reports', ['select' => 'id', 'tracking_id' => 'eq.' . $track, 'deleted_at' => 'is.null', 'limit' => '1']);
            if (!$f) { throw new SupabaseError(t('No case you can see has that tracking ID.', 'Walang kasong nakikita mo na may ganyang tracking ID.')); }
            return (string) $f[0]['id'];
        };
        switch ($act) {
            case 'flag':
                $p = ['p_batches' => $pgArr($uuids($in['batches'] ?? []))];
                foreach (['starred' => 'p_starred', 'archived' => 'p_archived', 'trashed' => 'p_trashed', 'purged' => 'p_purged'] as $k => $f) { if (array_key_exists($k, $in)) $p[$f] = (bool) $in[$k]; }
                if (!empty($in['snooze'])) { $ts = strtotime((string) $in['snooze']); if (!$ts || $ts < time()) throw new SupabaseError(t('Pick a time that has not passed.', 'Pumili ng oras na hindi pa lumilipas.')); $p['p_snooze'] = gmdate('c', $ts); }
                if (!empty($in['unsnooze'])) { $p['p_unsnooze'] = true; }
                mj(['ok' => true, 'n' => $db->rpc('mail_flag', $p)]);
            case 'read':
                mj(['ok' => true, 'n' => $db->rpc('mail_set_read', ['p_ids' => $pgArr($ints($in['ids'] ?? [])), 'p_read' => (bool) ($in['read'] ?? true)])]);
            case 'label_apply':
                mj(['ok' => true, 'n' => $db->rpc('mail_label_apply', ['p_batches' => $pgArr($uuids($in['batches'] ?? [])), 'p_label' => (int) ($in['label'] ?? 0), 'p_on' => (bool) ($in['on'] ?? true)])]);
            case 'label_save':
                $id = isset($in['id']) && $in['id'] !== '' ? (int) $in['id'] : null;
                mj(['ok' => true, 'id' => $db->rpc('mail_label_save', ['p_id' => $id, 'p_name' => (string) ($in['name'] ?? ''), 'p_colour' => (string) ($in['colour'] ?? '#5F6368')])]);
            case 'label_delete':
                $db->rpc('mail_label_delete', ['p_id' => (int) ($in['id'] ?? 0)]);
                mj(['ok' => true]);
            case 'draft_save':
                $rid = isset($in['id']) && $in['id'] !== '' && $in['id'] !== null ? (int) $in['id'] : null;
                $id = $db->rpc('mail_draft_save', ['p_id' => $rid, 'p_to' => $pgArr($uuids($in['to'] ?? [])), 'p_cc' => $pgArr($uuids($in['cc'] ?? [])), 'p_bcc' => $pgArr($uuids($in['bcc'] ?? [])),
                    'p_subject' => (string) ($in['subject'] ?? ''), 'p_body' => (string) ($in['body'] ?? ''), 'p_report' => $reportOf((string) ($in['case'] ?? '')),
                    'p_reply_to' => isset($in['reply_to']) && $in['reply_to'] !== '' ? (int) $in['reply_to'] : null]);
                mj(['ok' => true, 'id' => $id]);
            case 'draft_delete':
                $db->rpc('mail_draft_delete', ['p_id' => (int) ($in['id'] ?? 0)]);
                mj(['ok' => true]);
            case 'send':
                $batch = $db->rpc('send_mail', ['p_to' => $pgArr($uuids($in['to'] ?? [])), 'p_subject' => (string) ($in['subject'] ?? ''), 'p_body' => (string) ($in['body'] ?? ''),
                    'p_report' => $reportOf((string) ($in['case'] ?? '')), 'p_reply_to' => isset($in['reply_to']) && $in['reply_to'] !== '' ? (int) $in['reply_to'] : null,
                    'p_cc' => $pgArr($uuids($in['cc'] ?? [])), 'p_bcc' => $pgArr($uuids($in['bcc'] ?? [])), 'p_draft' => isset($in['draft']) && $in['draft'] !== '' ? (int) $in['draft'] : null]);
                unset($_SESSION['nav_counts']);
                mj(['ok' => true, 'batch' => $batch, 'text' => t('Message sent.', 'Naipadala ang mensahe.')]);
            case 'answer':
                $any = ($in['pick'] ?? '') === 'any'; $tanod = (string) ($in['tanod'] ?? '');
                $d = $db->rpc('answer_reroute_question', ['p_question' => (int) ($in['question'] ?? 0), 'p_tanod' => $any || $tanod === '' ? null : $tanod]);
                unset($_SESSION['nav_counts']);
                mj(['ok' => true, 'text' => $d ? t('Sent. The tanod is told.', 'Naipadala. Nasabihan ang tanod.')
                    : t('Nobody is free right now. The case waits in line and is offered as soon as a tanod is free.', 'Walang bakante ngayon. Maghihintay sa pila ang kaso at iaalok agad kapag may bakanteng tanod.')]);
            default:
                mj(['ok' => false, 'text' => t('Unknown action.', 'Hindi kilalang aksyon.')], 400);
        }
    }

    session_write_close();
    $v = (string) ($_GET['v'] ?? 'list');

    if ($v === 'people') {
        $q = mb_strtolower(trim((string) ($_GET['q'] ?? '')));
        $out = [];
        foreach ((array) $db->rpc('mail_recipients') as $p) {
            if ($q !== '' && !str_contains(mb_strtolower((string) $p['full_name'] . ' ' . (string) ($p['committee'] ?? '') . ' ' . (string) ($p['official_role'] ?? '')), $q)) continue;
            $out[] = ['id' => (string) $p['id'], 'name' => formal_name((string) $p['full_name']), 'tier' => (string) ($p['tier'] ?? ''), 'committee' => (string) ($p['committee'] ?? ''), 'role' => (string) ($p['official_role'] ?? '')];
        }
        mj(['ok' => true, 'people' => $out]);
    }
    if ($v === 'draft') {
        $r = (array) $db->select('mail_drafts', ['select' => 'id,to_ids,cc_ids,bcc_ids,subject,body,report_id,reply_to,report:reports!mail_drafts_report_id_fkey(tracking_id)', 'id' => 'eq.' . (int) ($_GET['id'] ?? 0), 'limit' => '1']);
        mj(['ok' => (bool) $r, 'draft' => $r[0] ?? null]);
    }
    if ($v === 'find') {
        $r = (array) $db->select('inbox_messages', ['select' => 'thread_id,batch', 'id' => 'eq.' . (int) ($_GET['m'] ?? 0), 'limit' => '1']);
        mj(['ok' => (bool) $r, 'thread' => $r ? (string) ($r[0]['thread_id'] ?? $r[0]['batch']) : null]);
    }

    $got = $db->selectMany(gm_reads($me));
    $box = gm_build($got, $me);
    $counts = gm_counts($box);
    $labels = [];
    foreach ($box['labels'] as $l) { $labels[] = $l + ['n' => $counts['labels'][$l['id']] ?? 0]; }

    if ($v === 'thread') {
        $tid = strtolower((string) ($_GET['t'] ?? ''));
        $th = null; foreach ($box['threads'] as $x) { if ($x['id'] === $tid) { $th = $x; break; } }
        if (!$th) { mj(['ok' => false, 'text' => t('That conversation is not here.', 'Wala ang usapang iyan.')], 404); }
        $reads = []; foreach ($th['items'] as $it) { $reads['p:' . $it['batch']] = ['rpc/mail_batch_people', ['p_batch' => $it['batch']], true]; }
        $qIds = array_values(array_unique(array_filter(array_map(static fn ($i) => $i['question'], $th['items']))));
        foreach ($qIds as $qi) { $reads['q:' . $qi] = ['reroute_questions', ['select' => 'id,state,due_at,committee,report_id,answered_at,by:users!reroute_questions_answered_by_fkey(full_name)', 'id' => 'eq.' . (int) $qi, 'limit' => '1'], true]; }
        $more = $reads ? $db->selectMany($reads) : [];
        $people = [];
        foreach ($th['items'] as $it) { $people[$it['batch']] = is_array($more['p:' . $it['batch']] ?? null) ? $more['p:' . $it['batch']] : []; }
        $qs = [];
        foreach ($qIds as $qi) {
            $row = is_array($more['q:' . $qi] ?? null) ? ($more['q:' . $qi][0] ?? null) : null;
            if (!$row) continue;
            if (($row['state'] ?? '') === 'open') { try { $row['roster'] = (array) $db->rpc('tanod_roster', ['p_report' => $row['report_id']]); } catch (SupabaseError) { $row['roster'] = []; } usort($row['roster'], static fn ($a, $b) => [!$a['assignable'], $a['metres'] ?? 1e9] <=> [!$b['assignable'], $b['metres'] ?? 1e9]); }
            $qs[$qi] = $row;
        }
        $unreadIds = array_values(array_map(static fn ($i) => $i['id'], array_filter($th['items'], static fn ($i) => !$i['mine'] && $i['unread'])));
        if ($unreadIds) { $db->rpc('mail_set_read', ['p_ids' => $pgArr($unreadIds), 'p_read' => true]); unset($_SESSION['nav_counts']); }
        $last = $th['items'][count($th['items']) - 1];
        mj(['ok' => true, 'html' => gm_thread_html($th, $box['labels'], $people, $qs, $me, formal_name((string) ($admin['full_name'] ?? ''))), 'subject' => $th['subject'],
            'batches' => array_map(static fn ($i) => $i['batch'], $th['items']), 'ids' => array_map(static fn ($i) => $i['id'], array_filter($th['items'], static fn ($i) => !$i['mine'])),
            'labels' => $th['labels'], 'star' => $th['star'],
            'reply' => ['reply_to' => $last['id'], 'subject' => $th['subject'], 'from_id' => $last['from_id'], 'mine' => $last['mine'], 'system' => $last['system'], 'report' => $last['report']['tracking_id'] ?? null,
                        'quote' => ['who' => $last['mine'] ? (string) ($admin['full_name'] ?? '') : formal_name($last['from']), 'at' => $last['at'], 'body' => $last['body']],
                        'people' => array_map(static fn ($p) => ['id' => (string) $p['user_id'], 'name' => formal_name((string) $p['full_name']), 'role' => (string) $p['role']], $people[$last['batch']] ?? []),
                        'from' => ['id' => $last['from_id'], 'name' => $last['mine'] ? formal_name((string) ($admin['full_name'] ?? '')) : formal_name($last['from'])]],
            'counts' => $counts, 'labelsList' => $labels]);
    }

    // list
    $folder = (string) ($_GET['f'] ?? 'inbox');
    $folder = preg_match('/^(inbox|starred|snoozed|sent|drafts|all|trash|label:\d+)$/', $folder) ? $folder : 'inbox';
    $q = trim((string) ($_GET['q'] ?? ''));
    $tab = (string) ($_GET['tab'] ?? 'people') === 'updates' ? 'updates' : 'people';
    if ($folder === 'drafts' && $q === '') {
        $html = gm_draft_rows($box['drafts']); $total = count($box['drafts']); $page = 1; $rowsN = $total;
    } else {
        $view = gm_view($box, $folder, $q, $tab, max(1, (int) ($_GET['p'] ?? 1)));
        $html = gm_rows($view['rows'], $box['labels'], $view['folder']); $total = $view['total']; $page = $view['page']; $rowsN = count($view['rows']);
    }
    mj(['ok' => true, 'html' => $html, 'total' => $total, 'page' => $page, 'per' => GM_PER, 'from' => $total ? ($page - 1) * GM_PER + 1 : 0, 'to' => ($page - 1) * GM_PER + $rowsN,
        'counts' => $counts, 'labels' => $labels, 'folder' => $folder, 'tab' => $tab]);
} catch (SupabaseError $ex) {
    mj(['ok' => false, 'text' => safe_error($ex)], 400);
}
