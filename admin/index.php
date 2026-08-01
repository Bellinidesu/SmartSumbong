<?php
declare(strict_types=1);
require_once __DIR__ . '/includes/auth.php';
header('Location: ' . (current_admin() ? 'cases.php' : 'login.php'));
exit;
