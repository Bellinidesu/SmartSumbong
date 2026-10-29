<?php
/**
 * The Workspace widgets' write door (17 Oct 2026). POST only, administrators only, the page's CSRF token, JSON back.
 * Every write runs as the signed-in administrator, so the row-level security in 0132 decides what each person may do
 * (notices and settings only for the Chairman or the Secretary, own rows only for the personal widgets); this file
 * only checks the shape of what was sent and turns refusals into plain words.
 *
 *   action=prefs        tabs (comma list of widget ids, in order), tab          my widgets and the tab left open
 *   action=mine         mine (JSON object, up to 30 KB)                         checklist, sticky note, countdown, habits, notes, water, goal
 *   action=feeds        feeds (one https address per line), keywords (comma)    my RSS feeds and watch words; each feed is tried
 *   action=post         kind (notice|announcement|handover|board), body, pin_hours
 *   action=post_remove  id;   action=post_pin  id, hours (0 unpins);   action=post_read  ids (comma)
 *   action=poll         question, options (one per line, 2 to 6), close_hours;   action=vote  poll_id, choice;   action=poll_close  id
 *   action=birthday     user_id, date (YYYY-MM-DD, empty clears)
 *   action=leave_add    user_id, from, to, reason;            action=leave_remove  id
 *   action=cred_add     user_id, kind, label, expires;        action=cred_remove   id
 *   action=roster_add   user_id, date, shift;                 action=roster_remove id
 *   action=cp_add       name, lat, lng;   action=cp_remove  id;   action=scan  checkpoint_id, tanod_id
 *   action=mood         mood (calm|busy|tired)
 *   action=relief_add   event, street, packs, date;           action=relief_remove id
 *   action=safe_note    osm_id, name, capacity, status, note
 *   action=settings     alarm_rules (comma), games_enabled (0|1), shift_starts (3 hours, comma), fares (JSON)
 *   action=score        game, score
 */
declare(strict_types=1);

require_once __DIR__ . '/includes/auth.php';
require_once __DIR__ . '/includes/widgets.php';

$admin = require_admin_api();
feature_require('workspace', true);

header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store');

function aout(array $a, int $code = 200): never
{
    http_response_code($code);
    echo json_encode($a, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    exit;
}

/** A refusal in plain words. */
function refuse(string $en, string $fil, int $code = 400): never
{
    aout(['error' => t($en, $fil)], $code);
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    aout(['error' => 'method'], 405);
}
if (!csrf_check($_POST['csrf'] ?? null)) {
    refuse('That form expired. Reload the page and try again.', 'Nag-expire ang form. I-reload ang pahina at subukan muli.', 403);
}
session_write_close();

$db  = db();
$me  = (string) $admin['id'];
$act = (string) ($_POST['action'] ?? '');
$in  = static fn (string $k, int $max = 1000): string => mb_substr(trim((string) ($_POST[$k] ?? '')), 0, $max);
$uuid = static function (string $k): string {
    $v = strtolower(trim((string) ($_POST[$k] ?? '')));
    if (!preg_match('/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/', $v)) {
        refuse('Something in that request was not recognised. Reload the page and try again.', 'May hindi nakilala sa kahilingan. I-reload ang pahina at subukan muli.');
    }
    return $v;
};
$date = static function (string $k, bool $optional = false): ?string {
    $v = trim((string) ($_POST[$k] ?? ''));
    if ($v === '' && $optional) return null;
    if (!preg_match('/^(\d{4})-(\d{2})-(\d{2})$/', $v, $m) || !checkdate((int) $m[2], (int) $m[3], (int) $m[1])) {
        refuse('Enter the date as year-month-day.', 'Ilagay ang petsa bilang taon-buwan-araw.');
    }
    return $v;
};
$manila = static fn (int $hours): string => (new DateTimeImmutable('now', new DateTimeZone('Asia/Manila')))->modify("+{$hours} hours")->format(DATE_ATOM);

try {
    switch ($act) {
        case 'prefs': {
            $cat = widget_catalogue();
            $tabs = array_values(array_unique(array_filter(explode(',', $in('tabs', 4000)), static fn ($id) => $id !== '')));
            $tab = $in('tab', 16);
            if ($tabs) {
                if (count($tabs) > 120 || array_diff($tabs, array_keys($cat))) {
                    refuse('One of those widgets is not in the library.', 'Wala sa aklatan ang isa sa mga widget na iyon.');
                }
            }
            if ($tab !== '' && !isset($cat[$tab])) {
                refuse('That widget is not in the library.', 'Wala sa aklatan ang widget na iyon.');
            }
            $db->rpc('workspace_save', ['p_tabs' => $tabs ?: null, 'p_tab' => $tab !== '' ? $tab : null]);
            aout(['ok' => true]);
        }

        case 'mine': {
            $raw = (string) ($_POST['mine'] ?? '');
            $mine = json_decode($raw, true);
            if (strlen($raw) > 30000 || !is_array($mine) || array_is_list($mine) && $mine !== []) {
                refuse('Your notes could not be saved: they are too long.', 'Hindi nai-save ang iyong mga tala: masyadong mahaba.');
            }
            $db->rpc('workspace_save', ['p_mine' => $mine ?: new stdClass()]);
            aout(['ok' => true]);
        }

        case 'feeds': {
            $lines = array_values(array_unique(array_filter(array_map('trim', preg_split('/[\r\n]+/', $in('feeds', 7000)) ?: []))));
            $words = array_values(array_unique(array_filter(array_map(static fn ($w) => mb_substr(trim($w), 0, 40), explode(',', $in('keywords', 1200))))));
            if (count($lines) > 12) refuse('Follow up to 12 feeds.', 'Hanggang 12 feed lamang.');
            if (count($words) > 20) refuse('Watch up to 20 words.', 'Hanggang 20 salita lamang ang mababantayan.');
            $keep = []; $report = [];
            foreach ($lines as $url) {
                if (!feed_url_allowed($url)) {
                    $report[] = ['url' => $url, 'ok' => false, 'why' => 'address'];
                    continue;
                }
                $r = feed_read_url($url);
                $keep[] = $url;
                $report[] = ['url' => $url, 'ok' => $r['ok'], 'why' => $r['ok'] ? null : 'unreadable',
                             'title' => $r['data']['title'] ?? null, 'items' => $r['ok'] ? count((array) ($r['data']['items'] ?? [])) : 0];
            }
            $db->rpc('workspace_save', ['p_feeds' => $keep, 'p_keywords' => $words]);
            aout(['ok' => true, 'feeds' => $report, 'note' => t('Only https addresses on the public internet are followed.', 'Ang mga https na address lamang sa pampublikong internet ang sinusundan.')]);
        }

        case 'post': {
            $kind = $in('kind', 20);
            if (!in_array($kind, ['notice', 'announcement', 'handover', 'board'], true)) refuse('Choose what kind of message it is.', 'Piliin kung anong uri ng mensahe ito.');
            $body = $in('body', 1000);
            if ($body === '') refuse('Write the message first.', 'Isulat muna ang mensahe.');
            if ($kind === 'board' && mb_strlen($body) > 280) refuse('A board line is at most 280 characters.', 'Hanggang 280 titik lamang ang isang linya sa board.');
            $row = ['kind' => $kind, 'body' => $body, 'author_id' => $me];
            $hours = (int) ($_POST['pin_hours'] ?? 0);
            if ($hours > 0 && in_array($kind, ['notice', 'announcement'], true)) {
                $row['pinned_until'] = $manila(min($hours, 24 * 14));
            }
            try {
                $r = $db->insert('team_posts', $row);
            } catch (SupabaseError $e) {
                if ($e->status === 403 || $e->status === 401) {
                    refuse('Only the Chairman or the Secretary can post a notice or an announcement.', 'Ang Punong Barangay o ang Kalihim lamang ang maaaring mag-post ng paunawa o anunsyo.', 403);
                }
                throw $e;
            }
            aout(['ok' => true, 'id' => $r[0]['id'] ?? null]);
        }

        case 'post_remove':
        case 'post_pin': {
            $id = $uuid('id');
            $patch = $act === 'post_remove' ? ['removed_at' => gmdate('c')]
                   : ['pinned_until' => ((int) ($_POST['hours'] ?? 0)) > 0 ? $manila(min((int) $_POST['hours'], 24 * 14)) : null];
            $r = $db->update('team_posts', ['id' => 'eq.' . $id], $patch);
            if (!$r) refuse('Only the person who posted it, the Chairman or the Secretary can change it.', 'Ang nag-post, ang Punong Barangay o ang Kalihim lamang ang makapagbabago nito.', 403);
            aout(['ok' => true]);
        }

        case 'post_read': {
            $ids = array_slice(array_filter(explode(',', $in('ids', 3000)), static fn ($v) => preg_match('/^[0-9a-f-]{36}$/', $v)), 0, 60);
            foreach ($ids as $id) {
                try {
                    $db->insert('team_post_reads', ['post_id' => $id, 'user_id' => $me]);
                } catch (SupabaseError $e) {
                    if ($e->status !== 409) throw $e;   // already seen
                }
            }
            aout(['ok' => true]);
        }

        case 'poll': {
            $q = $in('question', 200);
            $opts = array_values(array_filter(array_map(static fn ($o) => mb_substr(trim($o), 0, 60), preg_split('/[\r\n]+/', $in('options', 600)) ?: [])));
            if (mb_strlen($q) < 3) refuse('Write the question.', 'Isulat ang tanong.');
            if (count($opts) < 2 || count($opts) > 6) refuse('Give two to six answers, one per line.', 'Magbigay ng dalawa hanggang anim na sagot, isa bawat linya.');
            $row = ['question' => $q, 'options' => $opts, 'created_by' => $me];
            $h = (int) ($_POST['close_hours'] ?? 0);
            if ($h > 0) $row['closes_at'] = $manila(min($h, 24 * 30));
            $r = $db->insert('polls', $row);
            aout(['ok' => true, 'id' => $r[0]['id'] ?? null]);
        }

        case 'vote': {
            $id = $uuid('poll_id');
            $choice = (int) ($_POST['choice'] ?? -1);
            if ($choice < 0 || $choice > 5) refuse('Choose one of the answers.', 'Pumili ng isa sa mga sagot.');
            try {
                $db->rpc('poll_vote', ['p_poll' => $id, 'p_choice' => $choice]);
            } catch (SupabaseError $e) {
                refuse('This poll is closed, or that answer is not in it.', 'Sarado na ang botohang ito, o wala roon ang sagot na iyon.');
            }
            aout(['ok' => true]);
        }

        case 'poll_close': {
            $r = $db->update('polls', ['id' => 'eq.' . $uuid('id')], ['closed_at' => gmdate('c')]);
            if (!$r) refuse('Only the person who asked, the Chairman or the Secretary can close it.', 'Ang nagtanong, ang Punong Barangay o ang Kalihim lamang ang makapagsasara nito.', 403);
            aout(['ok' => true]);
        }

        case 'birthday': {
            $uid = $uuid('user_id');
            $d = $date('date', true);
            if ($d === null) {
                $db->delete('staff_dates', ['user_id' => 'eq.' . $uid]);
            } else {
                $db->upsert('staff_dates', ['user_id' => $uid, 'birthday' => $d, 'updated_by' => $me, 'updated_at' => gmdate('c')], 'user_id');
            }
            aout(['ok' => true]);
        }

        case 'leave_add': {
            $from = $date('from'); $to = $date('to');
            if ($to < $from) refuse('The last day comes before the first.', 'Nauuna ang huling araw sa unang araw.');
            $reason = $in('reason', 200);
            $r = $db->insert('staff_leave', ['user_id' => $uuid('user_id'), 'starts_on' => $from, 'ends_on' => $to,
                                             'reason' => $reason !== '' ? $reason : null, 'created_by' => $me]);
            aout(['ok' => true, 'id' => $r[0]['id'] ?? null]);
        }

        case 'cred_add': {
            $kind = $in('kind', 20);
            if (!in_array($kind, ['first_aid', 'tanod_id', 'training', 'other'], true)) refuse('Choose what kind it is.', 'Piliin kung anong uri ito.');
            $label = $in('label', 120);
            if ($label === '') refuse('Name it, for example "Red Cross first aid".', 'Pangalanan ito, halimbawa "Red Cross first aid".');
            $r = $db->insert('staff_credentials', ['user_id' => $uuid('user_id'), 'kind' => $kind, 'label' => $label,
                                                   'expires_on' => $date('expires', true), 'created_by' => $me]);
            aout(['ok' => true, 'id' => $r[0]['id'] ?? null]);
        }

        case 'roster_add': {
            $shift = $in('shift', 12);
            if (!in_array($shift, ['morning', 'afternoon', 'night'], true)) refuse('Choose the shift.', 'Piliin ang shift.');
            try {
                $r = $db->insert('duty_roster', ['user_id' => $uuid('user_id'), 'shift_date' => $date('date'), 'shift' => $shift, 'created_by' => $me]);
            } catch (SupabaseError $e) {
                if ($e->status === 409) refuse('That person is already on that shift.', 'Nasa shift na iyon na ang taong iyon.', 409);
                throw $e;
            }
            aout(['ok' => true, 'id' => $r[0]['id'] ?? null]);
        }

        case 'leave_remove':
        case 'cred_remove':
        case 'roster_remove':
        case 'relief_remove': {
            $table = ['leave_remove' => 'staff_leave', 'cred_remove' => 'staff_credentials', 'roster_remove' => 'duty_roster', 'relief_remove' => 'relief_tally'][$act];
            $r = $db->delete($table, ['id' => 'eq.' . $uuid('id')]);
            if (!$r) refuse('That could not be removed. It may already be gone.', 'Hindi ito matanggal. Maaaring wala na ito.', 404);
            aout(['ok' => true]);
        }

        case 'cp_add': {
            $name = $in('name', 120);
            $lat = (float) ($_POST['lat'] ?? 0); $lng = (float) ($_POST['lng'] ?? 0);
            if ($name === '') refuse('Name the checkpoint.', 'Pangalanan ang checkpoint.');
            if ($lat < 4 || $lat > 22 || $lng < 116 || $lng > 127) refuse('Pick the spot on the map.', 'Piliin ang lugar sa mapa.');
            $r = $db->insert('patrol_checkpoints', ['name' => $name, 'lat' => $lat, 'lng' => $lng, 'sort_order' => (int) ($_POST['order'] ?? 0)]);
            aout(['ok' => true, 'id' => $r[0]['id'] ?? null]);
        }

        case 'cp_remove': {
            $r = $db->update('patrol_checkpoints', ['id' => 'eq.' . $uuid('id')], ['is_active' => false]);
            if (!$r) refuse('That checkpoint could not be found.', 'Hindi mahanap ang checkpoint na iyon.', 404);
            aout(['ok' => true]);
        }

        case 'scan': {
            $r = $db->insert('checkpoint_scans', ['checkpoint_id' => $uuid('checkpoint_id'), 'tanod_id' => $uuid('tanod_id'), 'recorded_by' => $me]);
            aout(['ok' => true, 'id' => $r[0]['id'] ?? null]);
        }

        case 'mood': {
            $mood = $in('mood', 10);
            if (!in_array($mood, ['calm', 'busy', 'tired'], true)) refuse('Choose calm, busy or tired.', 'Piliin ang kalmado, abala o pagod.');
            $db->rpc('shift_checkin', ['p_mood' => $mood]);
            aout(['ok' => true]);
        }

        case 'relief_add': {
            $event = $in('event', 120); $street = $in('street', 120); $packs = (int) ($_POST['packs'] ?? 0);
            if ($event === '' || $street === '') refuse('Name the event and the street.', 'Pangalanan ang pangyayari at ang kalye.');
            if ($packs < 1 || $packs > 100000) refuse('Enter how many packs.', 'Ilagay kung ilang pakete.');
            $row = ['event' => $event, 'street' => $street, 'packs' => $packs, 'recorded_by' => $me];
            if (trim((string) ($_POST['date'] ?? '')) !== '') $row['given_on'] = $date('date');
            $r = $db->insert('relief_tally', $row);
            aout(['ok' => true, 'id' => $r[0]['id'] ?? null]);
        }

        case 'safe_note': {
            $osm = $in('osm_id', 40);
            if (!preg_match('/^(node|way|relation)\/[0-9]{1,15}$/', $osm)) refuse('That safe point was not recognised.', 'Hindi nakilala ang ligtas na lugar na iyon.');
            $status = $in('status', 10) ?: 'unknown';
            if (!in_array($status, ['open', 'closed', 'full', 'unknown'], true)) refuse('Choose open, closed or full.', 'Piliin ang bukas, sarado o puno.');
            $cap = trim((string) ($_POST['capacity'] ?? ''));
            if ($cap !== '' && (!ctype_digit($cap) || (int) $cap > 100000)) refuse('Enter the number of people it takes.', 'Ilagay ang bilang ng taong kaya nito.');
            $name = $in('name', 160); $note = $in('note', 300);
            try {
                $db->upsert('safe_point_notes', ['osm_id' => $osm, 'name' => $name !== '' ? $name : null, 'capacity' => $cap !== '' ? (int) $cap : null,
                                                 'status' => $status, 'note' => $note !== '' ? $note : null, 'updated_by' => $me, 'updated_at' => gmdate('c')], 'osm_id');
            } catch (SupabaseError $e) {
                if (in_array($e->status, [401, 403], true)) {
                    refuse('Only the Chairman or the Secretary can change a safe point.', 'Ang Punong Barangay o ang Kalihim lamang ang makapagbabago ng ligtas na lugar.', 403);
                }
                throw $e;
            }
            aout(['ok' => true]);
        }

        case 'settings': {
            $patch = ['updated_by' => $me, 'updated_at' => gmdate('c')];
            if (isset($_POST['alarm_rules'])) {
                $rules = array_values(array_unique(array_filter(explode(',', $in('alarm_rules', 100)))));
                if (array_diff($rules, ['red', 'sig3', 'urgent2h', 'deadline'])) refuse('One of those alarm rules is not known.', 'Hindi kilala ang isa sa mga patakaran ng alarma.');
                $patch['alarm_rules'] = $rules;
            }
            if (isset($_POST['games_enabled'])) {
                $patch['games_enabled'] = (string) $_POST['games_enabled'] === '1';
            }
            if (isset($_POST['shift_starts'])) {
                $hs = array_map('intval', explode(',', $in('shift_starts', 20)));
                if (count($hs) !== 3 || min($hs) < 0 || max($hs) > 23) refuse('Give the three shift start hours, 0 to 23.', 'Ibigay ang tatlong oras ng simula ng shift, 0 hanggang 23.');
                $patch['shift_starts'] = $hs;
            }
            if (isset($_POST['fares'])) {
                $f = json_decode((string) $_POST['fares'], true);
                $keys = ['trike_base', 'trike_base_km', 'trike_per_km', 'jeep_min', 'jeep_min_km', 'jeep_per_km', 'special_trip'];
                if (!is_array($f) || array_diff(array_keys($f), $keys)) refuse('The fares were not recognised.', 'Hindi nakilala ang mga pamasahe.');
                foreach ($f as $k => $v) {
                    if (!is_numeric($v) || $v < 0 || $v > 1000) refuse('Each fare is a number from 0 to 1,000.', 'Ang bawat pamasahe ay numero mula 0 hanggang 1,000.');
                    $f[$k] = round((float) $v, 2);
                }
                $patch['fares'] = $f ?: new stdClass();
            }
            $r = $db->update('workspace_settings', ['id' => 'eq.1'], $patch);
            if (!$r) refuse('Only the Chairman or the Secretary can change these.', 'Ang Punong Barangay o ang Kalihim lamang ang makapagbabago ng mga ito.', 403);
            aout(['ok' => true, 'settings' => $r[0]]);
        }

        case 'score': {
            $game = $in('game', 12);
            if (!in_array($game, WS_GAMES, true)) refuse('That game is not in the library.', 'Wala sa aklatan ang larong iyon.');
            $score = $_POST['score'] ?? '';
            if (!is_numeric($score)) refuse('That score was not recognised.', 'Hindi nakilala ang iskor na iyon.');
            try {
                $r = $db->rpc('record_game_score', ['p_game' => $game, 'p_score' => (float) $score]);
            } catch (SupabaseError $e) {
                if (str_contains($e->getMessage(), 'switched off')) refuse('Minigames are switched off. The Chairman or the Secretary can turn them on in Settings.', 'Naka-off ang mga minigame. Maaaring buksan ito ng Punong Barangay o ng Kalihim sa Mga Setting.', 403);
                refuse('That score could not be saved.', 'Hindi nai-save ang iskor na iyon.');
            }
            aout(['ok' => true] + (is_array($r) ? $r : []));
        }

        default:
            refuse('Unknown action.', 'Hindi kilalang aksyon.');
    }
} catch (SupabaseError $e) {
    if (in_array($e->status, [401, 403], true)) {
        refuse('You cannot do that from your account.', 'Hindi mo ito magagawa mula sa iyong account.', 403);
    }
    aout(['error' => t('That was not saved. Check what you entered and try again.', 'Hindi ito nai-save. Suriin ang inilagay mo at subukan muli.'),
          'detail' => mb_substr($e->getMessage(), 0, 200)], 400);
}
