<?php
/**
 * Workspace: the work board. What needs doing, stage by stage, with who has each case.
 *
 * It shares cases.php's queries and live refresh (loaded in workspace mode), the way notifications.php does; Case
 * Reports stays the register of cases and Notifications the messages. Ace, 15 Oct 2026: the board gets its own page.
 */
declare(strict_types=1);

const WORKSPACE_PAGE = true;
chdir(__DIR__);
require __DIR__ . '/cases.php';
