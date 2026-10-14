<?php
/**
 * The case actions both the case page and the work board perform, in one place so the board can never do less
 * checking than the page: dispatching a tanod and passing a case up the ladder. Each throws SupabaseError with a
 * message fit to show, and returns the message to flash when it worked.
 */
declare(strict_types=1);

/** Dispatch a tanod: on duty AND reporting now, instructions and a target date required (0071). */
function op_dispatch(Supabase $db, string $id, array $in): string
{
    $tanod = trim((string) ($in['tanod'] ?? ''));
    if ($tanod === '') {
        throw new SupabaseError(t('Choose a tanod before dispatching.', 'Pumili muna ng tanod bago mag-dispatch.'));
    }
    // Rose (2 Oct 2026): only a tanod who is on duty AND whose app is reporting right now.
    $live = null;
    foreach ((array) $db->rpc('tanod_roster', ['p_report' => $id]) as $t) {
        if (($t['tanod_id'] ?? null) === $tanod) { $live = $t; break; }
    }
    if (!$live || empty($live['assignable']) || empty($live['location_fresh'])) {
        throw new SupabaseError(t('That tanod is not active right now — their app is not reporting. Choose a tanod shown as ONLINE.',
                                  'Hindi aktibo ang tanod na iyan ngayon — hindi nag-uulat ang kanilang app. Pumili ng tanod na ONLINE.'));
    }
    $target = trim((string) ($in['target'] ?? ''));
    if ($target === '') {
        throw new SupabaseError(t('Set a target resolution date before dispatching.', 'Magtakda muna ng target na petsa bago mag-dispatch.'));
    }
    if (trim((string) ($in['note'] ?? '')) === '') {
        throw new SupabaseError(t('Write instructions for the tanod before dispatching.', 'Sumulat muna ng tagubilin para sa tanod bago mag-dispatch.'));
    }
    $iso = (new DateTimeImmutable($target, new DateTimeZone('Asia/Manila')))->format(DateTimeInterface::ATOM);
    $db->rpc('set_resolution_target', [
        'p_report' => $id,
        'p_due'    => $iso,
        'p_reason' => trim((string) ($in['target_reason'] ?? '')) ?: null,   // 0079: moving a date later is an extension and needs a reason
    ]);
    $db->rpc('admin_dispatch', [
        'p_report'       => $id,
        'p_tanod'        => $tanod,
        'p_instructions' => trim((string) ($in['note'] ?? '')) ?: null,
    ]);
    return t('Dispatched. The tanod has been notified.', 'Na-dispatch. Naabisuhan na ang tanod.');
}

/** Pass a case up one rung (0130): a Kagawad by committee, then the Chairman. The reason is shown to the official and the resident. */
function op_escalate(Supabase $db, string $id, array $in): string
{
    $reason = trim((string) ($in['reason'] ?? ''));
    if (mb_strlen($reason) < 3) {
        throw new SupabaseError(t('Say why, in a few words. The official and the resident will see it.', 'Sabihin kung bakit, sa ilang salita. Makikita ito ng opisyal at ng residente.'));
    }
    $comm = (string) ($in['committee'] ?? '');
    $db->rpc('escalate_in_barangay', ['p_report' => $id, 'p_reason' => $reason, 'p_committee' => $comm === '' ? null : $comm]);
    return t('The case was passed up. The official has it now, and the resident was told.', 'Naipasa ang kaso pataas. Hawak na ito ng opisyal, at nasabihan ang residente.');
}
