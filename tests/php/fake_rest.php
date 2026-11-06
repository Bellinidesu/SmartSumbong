<?php
// A tiny stand-in for PostgREST, for perf_test.php only: every request is written to the log beside it (method, path and the
// Prefer and Range headers), and the answer is a fixed set of rows with the total in Content-Range, as PostgREST sends it.
declare(strict_types=1);

$log = __DIR__ . '/requests.log';
$path = (string) parse_url((string) ($_SERVER['REQUEST_URI'] ?? '/'), PHP_URL_PATH);
$prefer = (string) ($_SERVER['HTTP_PREFER'] ?? '');
$range = (string) ($_SERVER['HTTP_RANGE'] ?? '');
file_put_contents($log, json_encode([$_SERVER['REQUEST_METHOD'], $path, (string) ($_SERVER['QUERY_STRING'] ?? ''), $prefer, $range,
    (string) ($_SERVER['HTTP_AUTHORIZATION'] ?? '')]) . "\n", FILE_APPEND | LOCK_EX);

header('Content-Type: application/json');
if (str_starts_with($path, '/rest/v1/rpc/')) {
    echo json_encode(['fn' => substr($path, strlen('/rest/v1/rpc/')), 'n' => 7]);
    exit;
}
if ($path === '/rest/v1/broken') {
    http_response_code(400);
    echo json_encode(['message' => 'no such table']);
    exit;
}
$rows = [['id' => 1], ['id' => 2], ['id' => 3]];
if (str_contains($prefer, 'count=exact')) {
    header('Content-Range: ' . ($range === '0-0' ? '0-0' : '0-2') . '/57');
}
if ($_SERVER['REQUEST_METHOD'] === 'POST' || $_SERVER['REQUEST_METHOD'] === 'PATCH') {
    http_response_code(201);
    echo json_encode([['id' => 99]]);
    exit;
}
echo json_encode($range === '0-0' ? array_slice($rows, 0, 1) : $rows);
