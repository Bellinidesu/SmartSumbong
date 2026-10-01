<?php
/**
 * Personnel — Figma "TanodLists" (12:5382) and
 * "Responder Verification" (12:5531).
 *
 * Frame names still say "Responder"; the panel reverted the actor name
 * to Tanod, so the screen does too. The design is unchanged.
 */
declare(strict_types=1);

require_once __DIR__ . '/includes/accounts.php';

render_account_screen('tanod');
