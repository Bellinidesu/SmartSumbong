<?php
/**
 * Notifications: what needs doing next (SMART's queue) and the admin's own notifications.
 *
 * Case Reports is only the register of real cases (the panel's ask, 7 Sep 2026); this page holds
 * everything that is about a case rather than a case. It shares cases.php's queries and live
 * refresh, so there is one copy of that code: cases.php shows the Next up and Notifications tabs
 * when it is loaded from here.
 */
declare(strict_types=1);

const NOTICES_PAGE = true;
chdir(__DIR__);
require __DIR__ . '/cases.php';
