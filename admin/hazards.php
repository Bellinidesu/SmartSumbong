<?php
/**
 * Hazard feed for the widgets (17 Oct 2026): what PAGASA and GDACS say right now about
 * Barangay 183, in one small answer. The browser does not call them itself; the portal's
 * content-security policy lists only the hosts it may talk to, and this keeps it that way.
 *
 *   PAGASA   the warnings its own site draws on the home-page map (/api/ActiveWarning:
 *            rainfall warnings, general flood advisories, thunderstorm advisories), the
 *            cyclone tracks (/api/CycloneTrack) and the hourly forecast for Port Area, Manila
 *            (/api/meteogram/425/0). PAGASA publishes these for its own pages; it documents
 *            no public API, so every reading is tolerant and the last good copy is kept.
 *   PAGASA NCR  the Metro Manila desk's page (/regional-forecast/ncrprsd): its rainfall and
 *            thunderstorm advisories, read as jakewarren/pagasa-feeds (MIT) found them laid out.
 *   GDACS    the UN / EU disaster alert feed: a second opinion on any cyclone near the
 *            Philippines, with the wind speed.
 *
 * NDRRMC publishes no machine-readable feed (its situation reports are PDFs behind a bot
 * check), so it is not read here; the widgets link to it instead.
 *
 * Wind signals (21 Oct 2026): a storm comes in ActiveWarning under its own name, one block
 * per signal (class tcws1..tcws5) listing the regions and areas under it. cyclone.signal is
 * the signal over Metro Manila (null when none), cyclone.signalTop the highest anywhere.
 * BagyoAPI (edwardguevarra/bagyo-api, MIT) parses the full bulletins into PSGC areas, but it
 * is a self-hosted stack (Postgres, Redis, a worker) with no public instance, too much to run
 * for one barangay; its idea, signals read per area, is what this follows.
 *
 *   hazards.php            -> {ok, at, stale, warnings[], cyclone, forecast[], ncr, sources{}}
 */
declare(strict_types=1);

require_once __DIR__ . '/includes/auth.php';

header('Content-Type: application/json');
header('Cache-Control: private, max-age=120');

if (!current_admin() || $_SERVER['REQUEST_METHOD'] !== 'GET') {
    http_response_code(403);
    echo json_encode(['error' => 'forbidden']);
    exit;
}
session_write_close();

require_once __DIR__ . '/includes/hazards.php';

echo json_encode(hazards_read(), JSON_UNESCAPED_UNICODE);
