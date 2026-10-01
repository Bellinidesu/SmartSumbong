<?php
/**
 * Residents — Figma "Resident Lists" (2:3703) and
 * "Resident Verification" (2:3969).
 *
 * The screen itself lives in includes/accounts.php; Personnel is the
 * same screen with the other role.
 */
declare(strict_types=1);

require_once __DIR__ . '/includes/accounts.php';

render_account_screen('resident');
