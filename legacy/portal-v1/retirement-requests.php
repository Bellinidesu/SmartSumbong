<?php
/**
 * Retirement Requests — a new dedicated queue (2026-09-08), separate
 * from Personnel's own account-actions menu per the design decision
 * made for this feature. See includes/retirement.php for the actual
 * implementation; this file is the thin wrapper personnel.php and
 * residents.php already are for includes/accounts.php.
 */
declare(strict_types=1);

require_once __DIR__ . '/includes/retirement.php';

render_retirement_queue();
