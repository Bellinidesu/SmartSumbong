<?php
// Keep-awake target (0091): Render's free plan sleeps after ~15 minutes
// idle and the next visitor waits ~50 s. The database pings this every
// 10 minutes. No session, no database call — it only has to answer.
//
// Memory (0138): Render's free plan hides its metrics, so the answer also
// carries the container's own counters in a header (MB: in use now, the
// highest since it started, the limit). The database files them with each
// check and Settings → System status shows them. The body stays "ok".
header('Content-Type: text/plain');
header('Cache-Control: no-store');
$mb = static function (string $file): ?int {
    $v = @file_get_contents($file);
    return ($v === false || !ctype_digit(trim($v))) ? null : (int) round((int) trim($v) / 1048576);
};
$used  = $mb('/sys/fs/cgroup/memory.current') ?? $mb('/sys/fs/cgroup/memory/memory.usage_in_bytes');
$peak  = $mb('/sys/fs/cgroup/memory.peak') ?? $mb('/sys/fs/cgroup/memory/memory.max_usage_in_bytes');
$limit = $mb('/sys/fs/cgroup/memory.max') ?? $mb('/sys/fs/cgroup/memory/memory.limit_in_bytes');
if ($limit !== null && $limit > 65536) $limit = null;   // "no limit" reads as a huge number
if ($used !== null) {
    header('X-Portal-Memory: used=' . $used . ($peak !== null ? ';peak=' . $peak : '') . ($limit !== null ? ';limit=' . $limit : ''));
}
echo 'ok';
