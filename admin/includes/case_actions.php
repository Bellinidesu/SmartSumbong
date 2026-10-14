<?php
/**
 * case.php's form actions: run in case.php's scope (it requires this file
 * where the actions used to be), so $db, $id and $admin are case.php's.
 * Post-redirect-get: every path ends in a redirect back to the case.
 */
declare(strict_types=1);

if (!isset($db, $id, $admin)) {
    http_response_code(404);  // opened directly, not from its page
    exit;
}

// ---------- actions ----------
// Post-redirect-get: a refresh after accepting must not accept again.
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $flash = null;
    $level = 'ok';

    if (!csrf_check($_POST['csrf'] ?? null)) {
        $flash = t('That form expired. Please try again.', 'Nag-expire ang form. Subukan muli.');
        $level = 'error';
    } else {
        try {
            $act = (string) ($_POST['action'] ?? '');
            // 0087 (D): an action from a page that is out of date is held
            // back, and the admin is shown what changed first.
            if (!in_array($act, ['take_over'], true) && isset($_POST['v'])) {
                $now = $db->select('reports', ['select' => 'version', 'id' => 'eq.' . $id, 'limit' => '1']);
                if ($now && (string) $now[0]['version'] !== (string) $_POST['v']) {
                    $last = $db->select('status_logs', [
                        'select'    => 'remark,created_at,by:users!status_logs_changed_by_fkey(full_name)',
                        'report_id' => 'eq.' . $id, 'order' => 'created_at.desc', 'limit' => '1',
                    ]);
                    $who  = $last[0]['by']['full_name'] ?? t('Someone', 'May isang tao');
                    $what = trim((string) ($last[0]['remark'] ?? ''));
                    $_SESSION['flash'] = ['level' => 'warn', 'text' => sprintf(
                        t('This case changed while you were looking: %s%s. Nothing you pressed was sent; here is the latest.', 'Nagbago ang kasong ito habang tinitingnan mo: %s%s. Walang naipadala sa pinindot mo; narito ang pinakabago.'),
                        $who, $what !== '' ? ' — ' . $what : '')];
                    header('Location: case.php?id=' . urlencode($id));
                    exit;
                }
            }
            switch ($act) {
                // 0087: taking, releasing and taking over a case.
                case 'take_over':
                    $db->rpc('take_over_case', ['p_report' => $id, 'p_reason' => trim((string) ($_POST['reason'] ?? ''))]);
                    $flash = t('You took over this case. The previous handler has been told.', 'Kinuha mo na ang kasong ito. Nasabihan na ang dating humahawak.');
                    break;

                case 'accept':
                    $db->rpc('review_report', [
                        'p_report'   => $id,
                        'p_decision' => 'validate',
                    ]);
                    $flash = t('Complaint accepted. Assign a tanod when you are ready.', 'Tinanggap ang sumbong. Mag-assign ng tanod kapag handa ka na.');
                    break;

                case 'deny':
                    $db->rpc('review_report', [
                        'p_report'   => $id,
                        'p_decision' => 'reject',
                        'p_remark'   => trim((string) ($_POST['reason'] ?? '')),
                        // Checkbox, so its mere presence in $_POST means
                        // checked — absent means unchecked, never sent
                        // by the browser at all, so an ordinary honest-
                        // mistake denial never touches the resident's
                        // strike count.
                        'p_abusive'  => isset($_POST['abusive']),
                    ]);
                    $flash = t('Complaint denied. The resident has been told why.', 'Tinanggihan ang sumbong. Nasabihan na ang residente kung bakit.');
                    break;

                case 'dispatch':
                    $tanod = trim((string) ($_POST['tanod'] ?? ''));
                    if ($tanod === '') {
                        throw new SupabaseError(t('Choose a tanod before dispatching.', 'Pumili muna ng tanod bago mag-dispatch.'));
                    }
                    // Rose (2 Oct 2026): only a tanod who is on duty AND whose app
                    // is reporting right now. On duty with the app closed is not
                    // someone who will see the ticket.
                    $live = null;
                    foreach ((array) $db->rpc('tanod_roster', ['p_report' => $id]) as $t) {
                        if (($t['tanod_id'] ?? null) === $tanod) { $live = $t; break; }
                    }
                    if (!$live || empty($live['assignable']) || empty($live['location_fresh'])) {
                        throw new SupabaseError(t('That tanod is not active right now — their app is not reporting. Choose a tanod shown as ONLINE.',
                                                  'Hindi aktibo ang tanod na iyan ngayon — hindi nag-uulat ang kanilang app. Pumili ng tanod na ONLINE.'));
                    }

                    // The target date is required (0071): set before the
                    // dispatch, told to the resident, and on the tanod's
                    // ticket. Instructions are checked here and by the RPC.
                    $target = trim((string) ($_POST['target'] ?? ''));
                    if ($target === '') {
                        throw new SupabaseError(t('Set a target resolution date before dispatching.', 'Magtakda muna ng target na petsa bago mag-dispatch.'));
                    }
                    if (trim((string) ($_POST['note'] ?? '')) === '') {
                        throw new SupabaseError(t('Write instructions for the tanod before dispatching.', 'Sumulat muna ng tagubilin para sa tanod bago mag-dispatch.'));
                    }
                    $iso = (new DateTimeImmutable($target, new DateTimeZone('Asia/Manila')))
                        ->format(DateTimeInterface::ATOM);
                    $db->rpc('set_resolution_target', [
                        'p_report' => $id,
                        'p_due'    => $iso,
                        // 0079: moving an existing date later is an
                        // extension and needs a reason.
                        'p_reason' => trim((string) ($_POST['target_reason'] ?? '')) ?: null,
                    ]);

                    $db->rpc('admin_dispatch', [
                        'p_report'       => $id,
                        'p_tanod'        => $tanod,
                        'p_instructions' => trim((string) ($_POST['note'] ?? '')) ?: null,
                    ]);
                    $flash = t('Dispatched. The tanod has been notified.', 'Na-dispatch. Naabisuhan na ang tanod.');
                    break;

                // 0057 — the resident's appeal of a denial. Grants it
                // straight to 'validated' with a fresh SLA window; there
                // is no separate "deny the appeal" action because
                // declining is simply not acting on it, the same way an
                // unactioned reopen request just stays finished.
                case 'appeal_grant':
                    $db->rpc('appeal_report', [
                        'p_report' => $id,
                        'p_remark' => trim((string) ($_POST['remark'] ?? '')) ?: null,
                    ]);
                    $flash = t('Appeal granted. The complaint is back with the barangay.', 'Pinagbigyan ang apela. Nasa barangay na muli ang sumbong.');
                    break;

                // 0070 — the admin moves a live dispatch: to a named
                // tanod, or back to the system's nearest-tanod routing.
                case 'reroute':
                    $to = trim((string) ($_POST['to'] ?? ''));
                    $db->rpc('admin_reroute_dispatch', [
                        'p_dispatch' => (string) ($_POST['dispatch'] ?? ''),
                        'p_reason'   => trim((string) ($_POST['reason'] ?? '')),
                        'p_to'       => $to !== '' ? $to : null,
                    ]);
                    $flash = $to !== ''
                        ? t('Rerouted. The new tanod has been notified.', 'Nailipat. Naabisuhan na ang bagong tanod.')
                        : t('Rerouted. The system is finding the nearest available tanod.', 'Nailipat. Hinahanap ng sistema ang pinakamalapit na available na tanod.');
                    break;

                // 0072 — escalation is the admin's referral to an outside
                // office. The complaint closes here; the resident is told
                // where it went.
                // 0073 — Approve Complaint Resolution.
                case 'approve_resolution':
                    $db->rpc('approve_resolution', ['p_report' => $id]);
                    $flash = t('Resolution approved. The resident has been told the complaint is resolved.', 'Naaprubahan ang resolusyon. Nasabihan na ang residente na nalutas na ang sumbong.');
                    break;

                case 'reject_resolution':
                    $db->rpc('reject_resolution', [
                        'p_report' => $id,
                        'p_reason' => trim((string) ($_POST['reason'] ?? '')),
                    ]);
                    $flash = t('Returned to the tanod with your reason.', 'Ibinalik sa tanod kasama ang iyong dahilan.');
                    break;

                // 0073 — Update Resolution Status.
                // Rose (7 Oct 2026): Update status and Post an update are one
                // form — new status (or none), remark, proof photos, and an
                // optional target date with its reason.
                case 'set_status':
                    $newStatus = (string) ($_POST['status'] ?? '');
                    $remark    = trim((string) ($_POST['remark'] ?? ''));
                    $target    = trim((string) ($_POST['target'] ?? ''));
                    $photos    = cloudinary_upload_files('photos');
                    if ($newStatus === '' && $remark === '' && !$photos && $target === '') {
                        throw new SupabaseError(t('Choose a new status, write a remark, attach a photo or set a target date.', 'Pumili ng bagong katayuan, sumulat ng tala, maglakip ng larawan, o magtakda ng target na petsa.'));
                    }
                    // The date first: if the extension is refused, nothing else is posted.
                    if ($target !== '') {
                        $db->rpc('set_resolution_target', [
                            'p_report' => $id,
                            'p_due'    => (new DateTimeImmutable($target, new DateTimeZone('Asia/Manila')))->format(DateTimeInterface::ATOM),
                            'p_reason' => trim((string) ($_POST['target_reason'] ?? '')) ?: null,
                        ]);
                    }
                    if ($newStatus !== '') {
                        $db->rpc('admin_set_status', [
                            'p_report' => $id,
                            'p_status' => $newStatus,
                            'p_remark' => $remark !== '' ? $remark : null,
                            'p_media'  => $photos,
                        ]);
                    } elseif ($remark !== '' || $photos) {
                        $db->rpc('admin_barangay_update', [
                            'p_report' => $id,
                            'p_body'   => $remark !== '' ? $remark : null,
                            'p_media'  => $photos,
                        ]);
                    }
                    $flash = t('Updated. The resident has been told.', 'Na-update. Nasabihan na ang residente.');
                    break;

                // 0079 (Rose) — an update, photos and/or a target date from
                // the barangay, with no tanod needed.
                case 'barangay_update':
                    $body   = trim((string) ($_POST['body'] ?? ''));
                    $target = trim((string) ($_POST['target'] ?? ''));
                    $photos = cloudinary_upload_files('photos');
                    if ($body === '' && !$photos && $target === '') {
                        throw new SupabaseError(t('Write an update, attach a photo or set a target date.', 'Sumulat ng update, maglakip ng larawan, o magtakda ng target na petsa.'));
                    }
                    // The date first: if the extension is refused, nothing
                    // else has been posted.
                    if ($target !== '') {
                        $iso = (new DateTimeImmutable($target, new DateTimeZone('Asia/Manila')))
                            ->format(DateTimeInterface::ATOM);
                        $db->rpc('set_resolution_target', [
                            'p_report' => $id,
                            'p_due'    => $iso,
                            'p_reason' => trim((string) ($_POST['target_reason'] ?? '')) ?: null,
                        ]);
                    }
                    if ($body !== '' || $photos) {
                        $db->rpc('admin_barangay_update', [
                            'p_report' => $id,
                            'p_body'   => $body !== '' ? $body : null,
                            'p_media'  => $photos,
                        ]);
                    }
                    $flash = t('Posted. The resident has been told.', 'Naipost na. Nasabihan na ang residente.');
                    break;

                // 0079 (Rose) — the extensions are used up: the case goes to
                // a higher official and any tanod on it stands down.
                case 'hand_up':
                    $official = trim((string) ($_POST['official'] ?? ''));
                    if ($official === 'other') {
                        $official = trim((string) ($_POST['official_other'] ?? ''));
                    }
                    $db->rpc('hand_to_higher_official', [
                        'p_report'   => $id,
                        'p_official' => $official,
                        'p_note'     => trim((string) ($_POST['note'] ?? '')) ?: null,
                    ]);
                    $flash = t('Handed to the official. The resident has been told.', 'Naipasa na sa opisyal. Nasabihan na ang residente.');
                    break;

                // 0073 — Manage Escalation Request.
                case 'approve_escalation':
                    $agency = trim((string) ($_POST['agency'] ?? ''));
                    if ($agency === 'other') {
                        $agency = trim((string) ($_POST['agency_other'] ?? ''));
                    }
                    $db->rpc('approve_escalation', [
                        'p_request' => (string) ($_POST['request'] ?? ''),
                        'p_office'  => $agency,
                        'p_note'    => trim((string) ($_POST['note'] ?? '')) ?: null,
                    ]);
                    $flash = t('Escalation approved. The resident and the tanod have been told.', 'Naaprubahan ang pag-escalate. Nasabihan na ang residente at ang tanod.');
                    break;

                case 'deny_escalation':
                    $db->rpc('deny_escalation', [
                        'p_request' => (string) ($_POST['request'] ?? ''),
                        'p_reason'  => trim((string) ($_POST['reason'] ?? '')),
                    ]);
                    $flash = t('Escalation request denied. The tanod has been told why.', 'Tinanggihan ang hiling na i-escalate. Nasabihan na ang tanod kung bakit.');
                    break;

                // 0073 — Monitor Real-Time Map (resident): published incidents.
                case 'set_public':
                    $db->rpc('set_report_public', [
                        'p_report' => $id,
                        'p_public' => !empty($_POST['public']),
                    ]);
                    $flash = !empty($_POST['public'])
                        ? t("Shown on residents' map (category and status only).", 'Ipinapakita na sa mapa ng mga residente (kategorya at katayuan lamang).')
                        : t("Removed from residents' map.", 'Inalis sa mapa ng mga residente.');
                    break;

                case 'refer':
                    $agency = trim((string) ($_POST['agency'] ?? ''));
                    if ($agency === 'other') {
                        $agency = trim((string) ($_POST['agency_other'] ?? ''));
                    }
                    $db->rpc('refer_report', [
                        'p_report' => $id,
                        'p_agency' => $agency,
                        'p_note'   => trim((string) ($_POST['note'] ?? '')) ?: null,
                    ]);
                    $flash = t('Escalated. The resident has been told where their complaint went.', 'Na-escalate na. Nasabihan na ang residente kung saan napunta ang sumbong.');
                    break;

                // 0072 — the barangay's answer in the resident's question thread.
                case 'resident_reply':
                    $db->rpc('post_report_message', [
                        'p_report' => $id,
                        'p_body'   => trim((string) ($_POST['body'] ?? '')),
                    ]);
                    $flash = t('Reply sent to the resident.', 'Naipadala ang sagot sa residente.');
                    break;

                // 0069 — a reply into the tanod's dispatch window. The
                // tanod is notified; the resident never sees it.
                case 'dispatch_reply':
                    $db->rpc('post_dispatch_update', [
                        'p_dispatch' => (string) ($_POST['dispatch'] ?? ''),
                        'p_body'     => trim((string) ($_POST['body'] ?? '')),
                    ]);
                    $flash = t('Sent to the tanod.', 'Naipadala sa tanod.');
                    break;

                default:
                    $flash = t('Unknown action.', 'Hindi kilalang aksyon.');
                    $level = 'error';
            }
        } catch (SupabaseError $ex) {
            $flash = safe_error($ex);
            $level = 'error';
        } catch (Exception $ex) {
            $flash = t('That date could not be read. Use the date picker.', 'Hindi mabasa ang petsang iyon. Gamitin ang date picker.');
            $level = 'error';
        }
    }

    $_SESSION['flash'] = ['text' => $flash, 'level' => $level];
    header('Location: case.php?id=' . urlencode($id));
    exit;
}
