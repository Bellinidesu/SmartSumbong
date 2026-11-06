<?php
/**
 * The speed work's own tests (7 Nov 2026): the database client's batch modes and read memo, the Server-Timing header's
 * value, the shared cache, and the key guard (the portal never runs on a secret key). Run: php tests/php/perf_test.php  (CI runs it too).
 *
 * It never reaches a real project: the portal's includes are copied into a throwaway folder with their own .env pointing at
 * a stand-in for PostgREST (fake_rest.php) on a local port, and every request it receives is logged and counted.
 */
declare(strict_types=1);

if (!in_array($argv[1] ?? '', ['child', 'child-key'], true)) {   // the parent; a child never starts another
    // ---- the parent: set the stage, run the checks in a child process, clean up
    $root = dirname(__DIR__, 2);
    $tmp = sys_get_temp_dir() . '/ss-perf-test-' . bin2hex(random_bytes(4));
    $port = 54800 + random_int(0, 150);
    mkdir($tmp . '/admin/includes', 0777, true);
    foreach (glob($root . '/admin/includes/*.php') as $f) copy($f, $tmp . '/admin/includes/' . basename($f));
    copy(__DIR__ . '/fake_rest.php', $tmp . '/fake_rest.php');
    copy(__FILE__, $tmp . '/perf_test.php');
    file_put_contents($tmp . '/.env', "SUPABASE_URL=http://127.0.0.1:{$port}\nSUPABASE_PUBLISHABLE_KEY=test\nFEATURE_CACHE_TTL=20\n");
    $srv = proc_open([PHP_BINARY, '-S', "127.0.0.1:{$port}", $tmp . '/fake_rest.php'], [['pipe', 'r'], ['file', $tmp . '/srv.out', 'w'], ['file', $tmp . '/srv.err', 'w']], $pipes, $tmp);
    for ($i = 0; $i < 50 && !@fsockopen('127.0.0.1', $port); $i++) usleep(100000);
    passthru(escapeshellarg(PHP_BINARY) . ' ' . escapeshellarg($tmp . '/perf_test.php') . ' child', $code);
    // the key guard: a .env whose only key is a secret one must stop the portal, without the key in the message
    file_put_contents($tmp . '/.env', "SUPABASE_URL=http://127.0.0.1:{$port}
SUPABASE_ANON_KEY=sb_secret_never_shown_123
");
    passthru(escapeshellarg(PHP_BINARY) . ' ' . escapeshellarg($tmp . '/perf_test.php') . ' child-key', $code2);
    $code = $code ?: $code2;
    proc_terminate($srv);
    proc_close($srv);
    $it = new RecursiveIteratorIterator(new RecursiveDirectoryIterator($tmp, FilesystemIterator::SKIP_DOTS), RecursiveIteratorIterator::CHILD_FIRST);
    foreach ($it as $x) { $x->isDir() ? @rmdir($x->getPathname()) : @unlink($x->getPathname()); }
    @rmdir($tmp);
    exit($code);
}

// ---- the second child: the portal refuses to run on a secret key
if (($argv[1] ?? '') === 'child-key') {
    require __DIR__ . '/admin/includes/config.php';
    $ok = [];
    $ok['a secret key is recognised'] = supabase_key_is_secret('sb_secret_x') && !supabase_key_is_secret('sb_publishable_x');
    $jwt = fn (string $role): string => 'eyJh.' . rtrim(strtr(base64_encode(json_encode(['role' => $role])), '+/', '-_'), '=') . '.sig';
    $ok['a legacy service_role key is recognised, a legacy anon key is not'] = supabase_key_is_secret($jwt('service_role')) && !supabase_key_is_secret($jwt('anon'));
    try { supabase_key(); $ok['a .env with only a secret key stops the portal'] = false; }
    catch (RuntimeException $ex) {
        $ok['a .env with only a secret key stops the portal'] = str_contains($ex->getMessage(), 'SUPABASE_ANON_KEY holds a secret key');
        $ok['the message never shows the key'] = !str_contains($ex->getMessage(), 'never_shown');
    }
    $f = 0;
    foreach ($ok as $what => $pass) { echo ($pass ? 'ok    ' : 'FAIL  ') . $what . "
"; $f += $pass ? 0 : 1; }
    exit($f ? 1 : 0);
}

// ---- the child: the checks
require __DIR__ . '/admin/includes/supabase.php';

$fails = 0; $n = 0;
function check(string $what, bool $ok): void { global $fails, $n; $n++; if (!$ok) { $fails++; echo "FAIL  {$what}\n"; } else { echo "ok    {$what}\n"; } }
function requests(): array { $f = __DIR__ . '/requests.log'; return is_file($f) ? array_map(fn ($l) => json_decode($l, true), file($f, FILE_IGNORE_NEW_LINES)) : []; }
function reset_log(): void { @unlink(__DIR__ . '/requests.log'); Supabase::forgetReads(); }

$db = new Supabase('token-a');

// the batch modes
reset_log();
$got = $db->selectMany([
    'rows'  => ['reports', ['select' => 'id', 'limit' => '3'], false, 'total'],
    'n'     => ['reports', ['status' => 'eq.open'], false, 'count'],
    'plain' => ['users', ['select' => 'id']],
    'fn'    => ['rpc/smart_module', []],
]);
check('a "total" entry gives its rows', count($got['rows']) === 3);
check('a "total" entry gives the total behind them', ($got['rows:total'] ?? null) === 57);
check('a "count" entry gives a number', $got['n'] === 57);
check('a plain entry gives rows and no total', count($got['plain']) === 3 && !isset($got['plain:total']));
check('a function in a batch gives its answer', ($got['fn']['fn'] ?? '') === 'smart_module');
check('the answers keep the order asked, a total right after its rows', array_keys($got) === ['rows', 'rows:total', 'n', 'plain', 'fn']);
$r = requests();
check('one request per entry', count($r) === 4);
$byPath = []; foreach ($r as $x) { $byPath[$x[1] . '?' . $x[2]] = $x; }
$cnt = array_values(array_filter($r, fn ($x) => str_contains($x[2], 'status=eq.open')))[0] ?? null;
check('a count asks for one row and counts ids', $cnt && $cnt[4] === '0-0' && str_contains($cnt[3], 'count=exact') && str_contains(urldecode($cnt[2]), 'select=id'));
$tot = array_values(array_filter($r, fn ($x) => str_contains($x[2], 'limit=3')))[0] ?? null;
check('a total asks for the count without a range', $tot && str_contains($tot[3], 'count=exact') && $tot[4] === '');
$pl = array_values(array_filter($r, fn ($x) => $x[1] === '/rest/v1/users'))[0] ?? null;
check('a plain entry does not ask for a count', $pl && $pl[3] === '');

// a whole batch of counts, as before
reset_log();
$c = $db->selectMany(['a' => ['reports', ['select' => 'id,cn:report_concerns!inner(category)']], 'b' => ['users', []]], true);
check('a batch of counts gives numbers', $c === ['a' => 57, 'b' => 57]);
check('a batch of counts counts ids, as it always has', count(array_filter(requests(), fn ($x) => urldecode($x[2]) === 'select=id')) === 2);
$c = $db->selectMany(['x' => ['broken', [], false, 'count']]);
check('a count that fails reads 0, as before', $c['x'] === 0);

// the read memo
reset_log();
$db->select('reports', ['select' => 'id', 'limit' => '3']);
$db->select('reports', ['select' => 'id', 'limit' => '3']);
check('the same read twice goes once', count(requests()) === 1);
$db->selectMany(['again' => ['reports', ['select' => 'id', 'limit' => '3']], 'new' => ['users', ['select' => 'x']]]);
check('a batch sends only what was not read yet', count(requests()) === 2);
$db->selectMany(['again' => ['reports', ['select' => 'id', 'limit' => '3']]]);
check('a batch read already costs no request', count(requests()) === 2);
$db->selectMany(['m' => ['rpc/smart_module', []]]);
$before = count(requests());
$m = $db->rpc('smart_module');
check('a function read in a batch is answered from the memo', count(requests()) === $before && ($m['fn'] ?? '') === 'smart_module');
(new Supabase('token-b'))->select('reports', ['select' => 'id', 'limit' => '3']);
check('another session never gets this one\'s reads', count(requests()) === $before + 1);
$db->insert('reports', ['subject' => 'x']);
$db->select('reports', ['select' => 'id', 'limit' => '3']);
check('a write empties the memo: the read after it goes to the database', count(requests()) === $before + 3);
$db->rpc('forward_case', ['p_report' => 'r']);
$db->select('reports', ['select' => 'id', 'limit' => '3']);
check('a function call not in the memo may write: the read after it goes again', count(requests()) === $before + 5);
try { $db->selectMany(['bad' => ['broken', [], true]]); } catch (SupabaseError) {}
try { $db->selectMany(['bad' => ['broken', [], true]]); } catch (SupabaseError) {}
check('a failed read is never kept: asking again asks the database', count(array_filter(requests(), fn ($x) => $x[1] === '/rest/v1/broken')) === 2);
reset_log();
$t1 = $db->selectMany(['p' => ['reports', ['limit' => '3'], false, 'total']]);
$t2 = $db->selectMany(['q' => ['reports', ['limit' => '3'], false, 'total']]);
check('a total read twice goes once, with its total', count(requests()) === 1 && ($t2['q:total'] ?? null) === 57 && count($t2['q']) === 3);

// the Server-Timing header's value
[$waits, $calls, $ms] = server_timing_db();
$v = server_timing_value();
check('Server-Timing names the server and the database', (bool) preg_match('/^app;dur=[\d.]+, db;dur=[\d.]+;desc="\d+ waits, \d+ calls"$/', $v));
check('Server-Timing counts a batch as one wait of several calls', $calls > $waits && $waits > 0);

// the shared cache
$calls = 0;
$load = function () use (&$calls) { $calls++; return [['key' => 'a']]; };
shared_forget('t_list');
check('a reader who may not fill it reads for themselves', shared_cache('t_list', $load, false) === [['key' => 'a']] && $calls === 1 && !is_file(shared_cache_file('t_list')));
shared_cache('t_list', $load, true);
shared_cache('t_list', $load, true);
check('an administrator fills it once and then reads the copy', $calls === 2 && is_file(shared_cache_file('t_list')));
check('the copy is never handed to someone who may not fill it', shared_cache('t_list', fn () => [], false) === []);
shared_forget('t_list');
shared_cache('t_list', $load, true);
check('a save drops the copy: the next read loads again', $calls === 3);
touch(shared_cache_file('t_list'), time() - 60);
check('an old copy is used when the read fails', shared_cache('t_list', function () { throw new RuntimeException('down'); }, true) === [['key' => 'a']]);
shared_forget('t_empty');
shared_cache('t_empty', fn () => [], true);
check('an empty answer is never kept', !is_file(shared_cache_file('t_empty')));
shared_forget('t_list', 't_empty');

echo "\n{$n} checks, {$fails} failed\n";
exit($fails ? 1 : 0);
