<?php
/**
 * The command center's JSON door (SMART Iteration 4, 0143). Spatial Distribution asks it for the board of a mode and the
 * feed (GET), and sends it what an administrator does (POST): turn a mode on, hand over, tick the checklist, mark a place,
 * put a suggestion off, turn the mode off. Every rule (one mode at a time, a reason to turn one on, a note to hand over or
 * turn it off, administrators only) is the database's; this file only carries the request and the answer.
 *
 *   GET  command-act.php?do=board[&mode=flood]   -> command_board(mode, PAGASA's wind signal over Metro Manila)
 *   GET  command-act.php?do=feed                 -> command_feed(60)
 *   POST action=start|handover|end|check|place|dismiss (+ csrf)
 */
declare(strict_types=1);

require_once __DIR__ . '/includes/auth.php';
require_once __DIR__ . '/includes/layout.php';

$admin = require_admin();
$db    = db();
session_write_close();

header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store');

function out(array $a, int $code = 200): never
{
    http_response_code($code);
    echo json_encode($a, JSON_UNESCAPED_UNICODE);
    exit;
}

/**
 * The wind signal over Metro Manila, from the hazard feed's saved copy only (includes/hazards.php keeps it; the
 * page's flood watch refreshes it). The board never waits on PAGASA itself; an old or missing copy reads as no signal.
 */
function command_signal(): ?int
{
    $f = sys_get_temp_dir() . '/ss-hazards-v2.json';
    if (!is_file($f) || filemtime($f) < time() - 6 * 3600) return null;
    $h = json_decode((string) @file_get_contents($f), true);
    $s = $h['cyclone']['signal'] ?? null;
    return is_numeric($s) && (int) $s >= 1 ? (int) $s : null;
}

const MODES = ['fire', 'quake', 'flood', 'typhoon'];

try {
    if ($_SERVER['REQUEST_METHOD'] === 'POST') {
        if (!csrf_check($_POST['csrf'] ?? null)) {
            out(['error' => t('That form expired. Reload the page and try again.', 'Nag-expire ang form. I-reload ang pahina at subukan muli.')], 403);
        }
        $p = static fn (string $k): string => trim((string) ($_POST[$k] ?? ''));
        $mode = in_array($p('mode'), MODES, true) ? $p('mode') : '';
        $msg = match ($p('action')) {
            'start' => (function () use ($db, $p, $mode) {
                if ($mode === '') throw new SupabaseError(t('Choose a mode.', 'Pumili ng mode.'));
                $db->rpc('command_start', ['p_mode' => $mode, 'p_reason' => $p('reason') ?: null, 'p_how' => $p('how') === 'suggested' ? 'suggested' : 'admin']);
                return t('The command center is on.', 'Naka-on ang command center.');
            })(),
            'handover' => (function () use ($db, $p) {
                $db->rpc('command_handover', ['p_note' => $p('note')]);
                return t('Handover saved. The other administrators were told.', 'Nai-save ang handover. Nasabihan ang ibang administrator.');
            })(),
            'end' => (function () use ($db, $p) {
                $db->rpc('command_end', ['p_note' => $p('note')]);
                return t('The command center is off. The note is kept with the record.', 'Naka-off ang command center. Nakatala ang note.');
            })(),
            'check' => (function () use ($db, $p) {
                $db->rpc('command_check', ['p_item' => $p('item'), 'p_done' => $p('done') === '1', 'p_note' => $p('note') ?: null]);
                return t('Saved.', 'Nai-save.');
            })(),
            'place' => (function () use ($db, $p) {
                $st = in_array($p('status'), ['ok', 'damage', 'closed'], true) ? $p('status') : null;
                $db->rpc('command_place_check', ['p_place' => (int) $p('place'), 'p_status' => $st, 'p_note' => $p('note') ?: null]);
                return t('Saved.', 'Nai-save.');
            })(),
            'dismiss' => (function () use ($db, $mode) {
                if ($mode === '') throw new SupabaseError(t('Choose a mode.', 'Pumili ng mode.'));
                $db->rpc('command_dismiss', ['p_mode' => $mode, 'p_hours' => 2]);
                return t('SMART will not suggest it again for two hours.', 'Hindi na ito imumungkahi ng SMART sa loob ng dalawang oras.');
            })(),
            default => throw new SupabaseError(t('Unknown action.', 'Hindi kilalang aksyon.')),
        };
        out(['ok' => true, 'message' => $msg]);
    }

    $do = (string) ($_GET['do'] ?? 'board');
    if ($do === 'feed') {
        out(['feed' => $db->rpc('command_feed', ['p_limit' => 60]) ?? []]);
    }
    $mode = in_array((string) ($_GET['mode'] ?? ''), MODES, true) ? (string) $_GET['mode'] : null;
    $signal = command_signal();
    $board = $db->rpc('command_board', ['p_mode' => $mode, 'p_signal' => $signal]);
    out(['board' => $board, 'signal' => $signal]);
} catch (SupabaseError $ex) {
    out(['error' => safe_error($ex)], 400);
}
