<?php
/**
 * Administrative Services (30 Oct 2026, docs/ROLES_AND_PAGES.md): the barangay's people and paperwork, that is
 * the committees and who sees what, the administrators, Planning, and the retirement queue (retirement-requests.php, its own
 * address behind the same tab bar).
 * Its tabs live in settings.php, the portal's one tab engine.
 */
declare(strict_types=1);

const ST_PAGE = 'admin';
require __DIR__ . '/settings.php';
