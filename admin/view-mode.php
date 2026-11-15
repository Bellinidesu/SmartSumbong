<?php
/**
 * Switches viewing mode on and off (15 Nov 2026, Rose): the Chairman, a super admin, can look without being able to change anything. The page the person
 * lands on is the Dashboard when viewing, Notifications when editing. Only the Chairman has the switch (can_view_mode); it is kept in the session, so signing
 * in again starts in editing mode.
 */
declare(strict_types=1);

require_once __DIR__ . '/includes/auth.php';
require_once __DIR__ . '/includes/layout.php';

$admin = require_admin();
if (($_SERVER['REQUEST_METHOD'] ?? 'GET') === 'POST' && csrf_check($_POST['csrf'] ?? null) && can_view_mode()) {
    $_SESSION['view_mode'] = (string) ($_POST['action'] ?? '') === 'on';
    unset($_SESSION['nav_counts']);
    $_SESSION['flash'] = ['level' => 'info', 'text' => $_SESSION['view_mode']
        ? t('Viewing mode is on: nothing can be changed. Switch back to editing from the bar at the top.', 'Naka-on ang viewing mode: walang mababago. Bumalik sa pag-edit mula sa bar sa itaas.')
        : t('You can edit again.', 'Maaari ka nang mag-edit muli.')];
}
header('Location: ' . landing_page(), true, 303);
exit;
