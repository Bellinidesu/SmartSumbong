<?php
/**
 * Home was retired on 15 Nov 2026 (Rose): a Kagawad and staff land on Notifications, a Captain account on the Dashboard.
 * An old link or bookmark to Home still arrives somewhere useful instead of an error.
 */
declare(strict_types=1);

require_once __DIR__ . '/includes/auth.php';

require_admin();
header('Location: ' . landing_page(), true, 302);
exit;
