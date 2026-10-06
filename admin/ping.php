<?php
// Keep-awake target (0091): Render's free plan sleeps after ~15 minutes
// idle and the next visitor waits ~50 s. The database pings this every
// 10 minutes. No session, no database call — it only has to answer.
header('Content-Type: text/plain');
header('Cache-Control: no-store');
echo 'ok';
