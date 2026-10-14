<?php
/**
 * render_account_screen()'s form actions: required inside that function,
 * so it runs in its scope ($db, $admin, $role, $isTanod, $noun, $self...).
 * Post-redirect-get: every path ends in a redirect back to the screen.
 */
declare(strict_types=1);

if (!isset($db, $admin, $role)) {
    http_response_code(404);  // opened directly, not from its page
    exit;
}

// ---------- actions ----------
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $target = (string) ($_POST['id'] ?? '');
    $flash  = null;
    $level  = 'ok';

    if (!csrf_check($_POST['csrf'] ?? null)) {
        $flash = t('That form expired. Please try again.', 'Nag-expire ang form. Subukan muli.');
        $level = 'error';
    } else {
        try {
            $action = (string) ($_POST['action'] ?? '');
            if (!ID_OCR_ENABLED && $action === 'request_ocr_rescan') {
                $action = '';   // falls through to "Unknown action."
            }
            switch ($action) {
                // 0086 (Martin): a name change or a new ID photo.
                case 'profile_request':
                    $approve = ($_POST['decision'] ?? '') === 'approve';
                    $db->rpc('decide_profile_request', [
                        'p_request' => (string) ($_POST['request'] ?? ''),
                        'p_approve' => $approve,
                        'p_note'    => trim((string) ($_POST['note'] ?? '')) ?: null,
                    ]);
                    $flash = $approve
                        ? t('Approved. They have been told.', 'Naaprubahan. Nasabihan na sila.')
                        : t('Declined. They have been told why.', 'Tinanggihan. Nasabihan na sila kung bakit.');
                    break;

                case 'approve':
                    $db->rpc('verify_user_account', [
                        'p_user' => $target, 'p_decision' => 'approve',
                    ]);
                    $flash = t('Account verified. They can file a complaint now.', 'Beripikado na ang account. Makakapagsampa na sila ng sumbong.');
                    break;

                case 'deny':
                    $db->rpc('verify_user_account', [
                        'p_user'     => $target,
                        'p_decision' => 'deny',
                        'p_reason'   => trim((string) ($_POST['reason'] ?? '')),
                    ]);
                    $flash = t('Registration denied. The applicant has been told why.', 'Tinanggihan ang rehistro. Nasabihan na ang aplikante kung bakit.');
                    break;

                case 'suspend':
                    $db->rpc('set_account_suspension', [
                        'p_user'    => $target,
                        'p_suspend' => true,
                        'p_reason'  => trim((string) ($_POST['reason'] ?? '')),
                    ]);
                    $flash = t('Account suspended. Any incident they were holding went back to the queue.', 'Na-suspend ang account. Ibinalik sa pila ang anumang insidenteng hawak nila.');
                    break;

                case 'reinstate':
                    $db->rpc('set_account_suspension', [
                        'p_user' => $target, 'p_suspend' => false,
                    ]);
                    $flash = t('Account reinstated.', 'Naibalik ang account.');
                    break;

                case 'request_ocr_rescan':
                    // 0050. OCR runs on-device only, once, at
                    // registration — this just flags the account so
                    // the resident's own app re-runs it against the
                    // already-uploaded photo next time it's open.
                    $db->rpc('request_ocr_rescan', [
                        'p_user' => $target,
                    ]);
                    $flash = t('Re-check requested. It will run automatically next time they open the app.', 'Humiling ng muling pagsuri. Awtomatiko itong tatakbo sa susunod nilang pagbukas ng app.');
                    break;

                // 0073 — Manage User Account (3.2): correct a
                // resident's or tanod's name and email.
                case 'correct_profile':
                    $db->rpc('admin_update_user', [
                        'p_user'      => $target,
                        'p_full_name' => trim((string) ($_POST['full_name'] ?? '')),
                        'p_email'     => trim((string) ($_POST['email'] ?? '')) ?: null,
                    ]);
                    $flash = t('Profile corrected. The account holder has been told.', 'Naitama ang profile. Nasabihan na ang may-ari ng account.');
                    break;

                case 'reset_password':
                    // Re-authenticated for the same reason promote
                    // and step_down are: this hands working
                    // credentials for someone else's account to
                    // whoever is at the keyboard, and the database
                    // only knows that an admin is calling.
                    Supabase::signIn($admin['email'], (string) ($_POST['password'] ?? ''));
                    $issued = $db->rpc('admin_reset_password', [
                        'p_user' => $target,
                    ]);
                    // The RPC returns the password once and never
                    // stores it. If it is lost between here and the
                    // counter, the only remedy is another reset.
                    $_SESSION['issued_password'] = is_array($issued)
                        ? (string) reset($issued)
                        : (string) $issued;
                    $flash = t('Temporary password issued. Read it to them in person and do not send it by message.',
                               'Naibigay ang pansamantalang password. Basahin ito sa kanila nang personal at huwag ipadala sa mensahe.');
                    break;

                default:
                    $flash = t('Unknown action.', 'Hindi kilalang aksyon.');
                    $level = 'error';
            }
        } catch (SupabaseError $ex) {
            // Same fix as login.php: GoTrue's own wrong-password error
            // says "Invalid login credentials", but admin_reset_password()
            // has its own, unrelated exception for an account with no
            // auth.users row at all -- "has no credential to reset" --
            // and the old broad `str_contains(..., 'credential')` check
            // caught that one too, so a reset against a seeded test
            // account (no real login) always came back "That password
            // is not right," even typed correctly. Narrowed to the
            // actual GoTrue phrase so the real reason surfaces instead.
            $msg   = safe_error($ex);
            $flash = str_contains(strtolower($msg), 'invalid login')
                ? t('That password is not right. Nothing was changed.', 'Mali ang password na iyan. Walang binago.')
                : $msg;
            $level = 'error';
        }
    }

    $_SESSION['flash'] = ['text' => $flash, 'level' => $level];
    header('Location: ' . $self . ($target !== '' ? '?id=' . urlencode($target) : ''));
    exit;
}
