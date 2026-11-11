<?php
/**
 * Thin Supabase REST client.
 *
 * Two endpoints matter here: GoTrue (/auth/v1) for sign-in, and
 * PostgREST (/rest/v1) for data. Every data request carries the signed-in
 * admin's access token, which is what makes the database apply their RLS
 * policies. Without it PostgREST would fall back to the anon role and
 * return nothing.
 */
declare(strict_types=1);

require_once __DIR__ . '/config.php';
require_once __DIR__ . '/shared_cache.php';

/**
 * cURL options every database request shares (speed, 7 Oct 2026).
 *
 * The database is a long way from the portal, and opening a new secure
 * connection costs several round trips before the first byte. One shared
 * connection pool (with DNS and TLS sessions) means a page's calls, and on
 * PHP 8.5 the next page's too, reuse the same open connection; HTTP/2 lets
 * parallel calls travel over it together.
 */
function supabase_curl_opts(): array
{
    static $share = null;
    if ($share === null) {
        $what = [CURL_LOCK_DATA_DNS, CURL_LOCK_DATA_SSL_SESSION, CURL_LOCK_DATA_CONNECT];
        if (function_exists('curl_share_init_persistent')) {
            $share = curl_share_init_persistent($what);
        } else {
            $share = curl_share_init();
            foreach ($what as $w) { curl_share_setopt($share, CURLSHOPT_SHARE, $w); }
        }
    }
    return [
        CURLOPT_SHARE         => $share,
        CURLOPT_HTTP_VERSION  => CURL_HTTP_VERSION_2TLS,
        CURLOPT_TCP_KEEPALIVE => 1,
        CURLOPT_ENCODING      => '',
        // A batch's calls wait to ride the one open HTTP/2 connection instead of each opening a new one (7 Nov 2026). Without it,
        // calls that start together found no connection ready and opened their own: two more round trips to the database for each (it was in Mumbai then).
        // Measured from Manila on the live database: a 16-call batch went from 222-700 ms (typically ~440) to 168-443 (~300).
        CURLOPT_PIPEWAIT      => 1,
    ];
}

/**
 * Timing of each database call on this page (speed work, 7 Oct 2026).
 * Printed as an HTML comment at the end of the page only when the URL has
 * ?_trace=1 and an admin is signed in; otherwise it costs nothing.
 */
function supabase_trace(?string $what = null, ?float $since = null): array
{
    static $log = [];
    static $on = null;
    if ($on === null) {
        $on = isset($_GET['_trace']);
        if ($on) {
            $t0 = microtime(true);
            register_shutdown_function(function () use (&$log, $t0) {
                if (empty($_SESSION[SESSION_KEY])) return;
                echo "\n<!-- trace: page " . round((microtime(true) - $t0) * 1000) . " ms\n";
                foreach ($log as $l) echo '  ' . $l . "\n";
                echo "-->";
            });
        }
    }
    if ($what !== null && $since !== null) {
        $ms = (microtime(true) - $since) * 1000;
        server_timing_db($ms, $what);
        if ($on) $log[] = sprintf('%5d ms  %s', (int) round($ms), $what);
    }
    return $log;
}

/**
 * Speed work (perf step 1, 7 Nov 2026): every wait on Supabase is added up for the Server-Timing header, so the browser's
 * network panel shows, for each page and each in-place press, how long the server took, how much of that was spent waiting
 * on the database, and how many times it waited. A batch of parallel reads is one wait holding several calls.
 * Returns [waits, calls, ms].
 */
function server_timing_db(?float $ms = null, string $what = ''): array
{
    static $t = [0, 0, 0.0];
    if ($ms !== null) {
        $t[0]++;
        $t[1] += preg_match('/^batch of (\d+)/', $what, $m) ? (int) $m[1] : 1;
        $t[2] += $ms;
    }
    return $t;
}

/**
 * New connections to Supabase opened while answering this request, and the longest handshake among them (7 Nov 2026). A call that
 * rides an open connection opens none; one that has to open its own pays the TCP and TLS handshakes first (two or three
 * round trips). Read from each call's own cURL figures. Returns [new connections, longest handshake in ms].
 */
function server_timing_conn(?CurlHandle $ch = null): array
{
    static $t = [0, 0.0];
    if ($ch !== null) {
        $n = (int) curl_getinfo($ch, CURLINFO_NUM_CONNECTS);
        if ($n > 0) {
            $t[0] += $n;
            $t[1] = max($t[1], (float) curl_getinfo($ch, CURLINFO_APPCONNECT_TIME_T) / 1000);
        }
    }
    return $t;
}

/**
 * The machine's own account of this request (7 Nov 2026): the CPU time it used (this process, the TLS of its calls included), and
 * how long the container was held back by its CPU quota while it ran (Render's free plan gives about a tenth of a CPU; a request
 * that needs 20 ms of CPU can then take 200 ms). Read once when this file loads and again for the header. Returns [cpu ms, held
 * back ms]; null where the system does not say.
 */
function server_timing_machine(): array
{
    static $start = null;
    $cpu = static function (): ?float {
        $u = function_exists('getrusage') ? @getrusage() : false;
        return is_array($u) ? ($u['ru_utime.tv_sec'] + $u['ru_stime.tv_sec']) * 1000 + ($u['ru_utime.tv_usec'] + $u['ru_stime.tv_usec']) / 1000 : null;
    };
    $held = static function (): ?float {
        $s = @file_get_contents('/sys/fs/cgroup/cpu.stat');                                     // cgroup v2: microseconds
        if (is_string($s) && preg_match('/^throttled_usec (\d+)/m', $s, $m)) return (int) $m[1] / 1000;
        $s = @file_get_contents('/sys/fs/cgroup/cpu/cpu.stat');                                 // cgroup v1: nanoseconds
        if (is_string($s) && preg_match('/^throttled_time (\d+)/m', $s, $m)) return (int) $m[1] / 1e6;
        return null;
    };
    if ($start === null) { $start = [$cpu(), $held()]; return [null, null]; }
    $c = $cpu(); $h = $held();
    return [$c !== null && $start[0] !== null ? $c - $start[0] : null, $h !== null && $start[1] !== null ? $h - $start[1] : null];
}
server_timing_machine();

/** The Server-Timing header's value: app = the whole of the server's work so far, db = the waits on Supabase, conn = new connections,
 *  cpu = the CPU this request used, held = time the container was held back by its CPU quota meanwhile (when the system says). */
function server_timing_value(): string
{
    [$waits, $calls, $ms] = server_timing_db();
    [$conns, $hand] = server_timing_conn();
    [$cpu, $held] = server_timing_machine();
    $start = (float) ($_SERVER['REQUEST_TIME_FLOAT'] ?? microtime(true));
    $app = (microtime(true) - $start) * 1000;
    return sprintf('app;dur=%.1f, db;dur=%.1f;desc="%d waits, %d calls", conn;dur=%.1f;desc="%d new connections (longest handshake)"', $app, $ms, $waits, $calls, $hand, $conns)
        . ($cpu !== null ? sprintf(', cpu;dur=%.1f;desc="CPU used"', $cpu) : '')
        . ($held !== null ? sprintf(', held;dur=%.1f;desc="held back by the CPU quota"', $held) : '');
}

/**
 * The engine's reads, kept per person for a minute (7 Nov 2026, after the move to Singapore).
 *
 * Measured on the live database: smart_module() costs about 330 ms the first time a database connection runs it (its plans and
 * the tables' metadata are loaded cold) and about 10 ms after. The API keeps only a small pool of connections and lets idle
 * ones go, so a person clicking at a human pace kept landing on a cold one, and every page waited the 330 ms for the brain
 * button's module. These functions summarise the whole barangay (counts, deadline risk, quiet cases, spikes, patterns), so
 * their answer for one person is kept for ENGINE_CACHE_TTL seconds (60 by default) in a small file only this server reads.
 *
 * Rules: per person (the user id inside their own sign-in token; no token, no cache); a failed or empty answer is never
 * kept; any form a person sends drops all of their copies at once (engine_forget_mine(), called by require_admin()), so what
 * they just did shows on their next page. What someone else changed reaches the module within the minute.
 */
const ENGINE_RPCS = ['smart_module', 'smart_summary', 'smart_deadline_risk', 'smart_spikes', 'smart_patterns', 'smart_stuck_cases'];

function engine_cache_ttl(): int
{
    return (int) env('ENGINE_CACHE_TTL', '60');
}

/** The person a sign-in token belongs to (its sub claim), or null: the token is only read, never trusted for access. */
function engine_cache_who(?string $token): ?string
{
    if ($token === null || substr_count($token, '.') !== 2) return null;
    $claims = json_decode((string) base64_decode(strtr(explode('.', $token)[1], '-_', '+/')), true);
    $sub = is_array($claims) ? (string) ($claims['sub'] ?? '') : '';
    return preg_match('/^[0-9a-f-]{36}$/i', $sub) ? strtolower($sub) : null;
}

function engine_cache_prefix(string $who): string
{
    return sys_get_temp_dir() . '/ss-engine-' . substr(hash('sha256', $who . '|' . env('SUPABASE_URL', '')), 0, 20) . '-';
}

/** This person's copy of one engine read, as a file path; null when it is not one of the engine's reads or no one is signed in. */
function engine_cache_file(?string $token, string $table, array $query): ?string
{
    if (!str_starts_with($table, 'rpc/') || !in_array(substr($table, 4), ENGINE_RPCS, true) || engine_cache_ttl() <= 0) return null;
    $who = engine_cache_who($token);
    if ($who === null) return null;
    return engine_cache_prefix($who) . substr(hash('sha256', $table . '|' . json_encode($query)), 0, 20) . '.json';
}

function engine_cache_get(?string $file): array
{
    if ($file === null || !is_file($file) || @filemtime($file) <= time() - engine_cache_ttl()) return [false, null];
    $v = json_decode((string) @file_get_contents($file), true);
    return is_array($v) && array_key_exists('v', $v) ? [true, $v['v']] : [false, null];
}

function engine_cache_put(?string $file, mixed $value): void
{
    if ($file === null || $value === null || $value === [] || $value === '') return;
    $tmp = $file . '.' . bin2hex(random_bytes(4));
    if (@file_put_contents($tmp, json_encode(['v' => $value], JSON_UNESCAPED_UNICODE)) !== false) {
        if (!@rename($tmp, $file)) @unlink($tmp);
    }
}

/** Drop every engine copy of the person signed in with this token (they sent a form). */
function engine_forget_mine(?string $token): void
{
    $who = engine_cache_who($token);
    if ($who === null) return;
    foreach (glob(engine_cache_prefix($who) . '*.json') ?: [] as $f) @unlink($f);
}

class SupabaseError extends RuntimeException
{
    public function __construct(string $message, public readonly int $status = 0)
    {
        parent::__construct($message);
    }
}

final class Supabase
{
    public function __construct(private readonly ?string $accessToken = null) {}

    /**
     * The request's read memo (speed work, 7 Nov 2026). Everything read in this request is kept until the request ends or until
     * anything is written, and the same read asked for again (the same table or function, the same filters, the same session) is
     * answered from it without a wait. So a page can read, in its first batch, what its parts read later (the brain button's module,
     * the Right now strip, the pins), and the parts' own calls find it there; and two parts that read the same thing pay once.
     * Any write (insert, update, delete, upsert, an Edge Function, or a function call not answered here) empties it, so a read
     * after a save always goes to the database. Only answers that came back are kept, never an error.
     *
     * @var array<string, mixed>
     */
    private static array $seen = [];

    private function seenKey(string $mode, string $table, array $query): string
    {
        return hash('sha256', ($this->accessToken ?? '') . "\0" . $mode . "\0" . $table . "\0" . json_encode($query, JSON_UNESCAPED_UNICODE));
    }

    /** Empty the memo (a write happened, or a page wants fresh reads). */
    public static function forgetReads(): void
    {
        self::$seen = [];
    }

    /** @param array<string,string> $extraHeaders */
    private function request(
        string $method,
        string $path,
        ?array $body = null,
        array $extraHeaders = []
    ): array|string|int|float|bool|null {
        $headers = [
            'apikey: ' . supabase_key(),
            'Content-Type: application/json',
            'Accept: application/json',
        ];
        $headers[] = 'Authorization: Bearer ' . ($this->accessToken ?? supabase_key());
        foreach ($extraHeaders as $k => $v) {
            $headers[] = "{$k}: {$v}";
        }

        $ch = curl_init(supabase_url() . $path);
        curl_setopt_array($ch, supabase_curl_opts());
        curl_setopt_array($ch, [
            CURLOPT_CUSTOMREQUEST  => $method,
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_HTTPHEADER     => $headers,
            CURLOPT_TIMEOUT        => 15,
            CURLOPT_CONNECTTIMEOUT => 8,
        ]);
        if ($body !== null) {
            curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($body, JSON_UNESCAPED_UNICODE));
        }

        if ($method !== 'GET') { self::$seen = []; }   // a write, or a function that may write: nothing read before it is reused
        $tq     = microtime(true);
        $raw    = curl_exec($ch);
        supabase_trace($method . ' ' . strtok($path, '?'), $tq);
        server_timing_conn($ch);
        $status = (int) curl_getinfo($ch, CURLINFO_HTTP_CODE);
        $err    = curl_error($ch);
        // curl_close() is a deliberate no-op since PHP 8.0 (deprecated in
        // 8.5) -- the handle is freed automatically when it goes out of
        // scope, so the call was removed rather than kept as dead code.

        if ($raw === false) {
            throw new SupabaseError('Could not reach the database: ' . $err);
        }

        $data = json_decode($raw, true);

        if ($status >= 400) {
            // PostgREST returns `message`, GoTrue returns `error_description`
            // or `msg`. Surface whichever is present rather than a bare code.
            $msg = $data['message']
                ?? $data['error_description']
                ?? $data['msg']
                ?? $data['error']
                ?? "Request failed ({$status})";
            throw new SupabaseError((string) $msg, $status);
        }

        // PostgREST's response shape follows the Postgres function's own
        // return type: a JSON array of rows for select/insert/update and
        // for any set- or table-returning RPC, but a bare JSON scalar
        // (string/number/boolean) for an RPC whose function returns a
        // plain scalar -- admin_reset_password() returning text is
        // exactly this case. This used to coerce anything non-array to
        // [], which silently discarded every such scalar: the temporary
        // password admin_reset_password() generated was thrown away here
        // and accounts.php stored an empty string instead, so the reveal
        // block never rendered. Every other rpc() caller in this
        // codebase either ignores the return value or calls a
        // table-returning function (always decodes to an array already),
        // so returning $data as-is is safe everywhere, not just here.
        return $data;
    }

    // ---------- auth ----------

    /** @return array{access_token:string,refresh_token:string,user:array} */
    public static function signIn(string $email, string $password): array
    {
        $client = new self();
        return $client->request('POST', '/auth/v1/token?grant_type=password', [
            'email'    => $email,
            'password' => $password,
        ] + self::captcha());
    }

    /** The bot-check token the submitting form carried (turnstile.js), if any. */
    private static function captcha(): array
    {
        $token = $_POST['cf-turnstile-response'] ?? '';
        return is_string($token) && $token !== '' ? ['gotrue_meta_security' => ['captcha_token' => $token]] : [];
    }

    public static function refresh(string $refreshToken): array
    {
        $client = new self();
        return $client->request('POST', '/auth/v1/token?grant_type=refresh_token', [
            'refresh_token' => $refreshToken,
        ]);
    }

    /**
     * Ask GoTrue to email a password-recovery link to $email.
     *
     * Only ever meaningful for admin accounts: they sign in with a real
     * address (login.php), unlike residents and tanods, whose sign-in
     * address is synthetic and receives no mail (migration 0021) — that
     * is why this lives on the admin side only, and why admin recovery
     * can be self-serve when the resident/tanod one deliberately is not.
     *
     * GoTrue answers 200 whether or not $email belongs to an account, so
     * the caller cannot and must not use this to tell the two apart —
     * show the same message either way.
     */
    public static function recover(string $email, string $redirectTo): void
    {
        $client = new self();
        $client->request('POST', '/auth/v1/recover', [
            'email'       => $email,
            'redirect_to' => $redirectTo,
        ] + self::captcha());
    }

    /**
     * Change something GoTrue owns rather than the users table — in
     * practice the password. Supabase requires a recent session for
     * this, which is why the form asks for the current one first.
     */
    public function updateAuthUser(array $fields): array
    {
        return $this->request('PUT', '/auth/v1/user', $fields);
    }

    /** GoTrue's own record of the signed-in user (profile.php's "Last signed in"). */
    public function authUser(): array
    {
        // a page that put ['auth/user', []] in its batch finds it here, without a wait of its own
        $k = $this->seenKey('', 'auth/user', []);
        if (array_key_exists($k, self::$seen) && is_array(self::$seen[$k])) return self::$seen[$k];
        $user = $this->request('GET', '/auth/v1/user');
        return is_array($user) ? $user : [];
    }

    public function signOut(): void
    {
        try {
            $this->request('POST', '/auth/v1/logout');
        } catch (SupabaseError) {
            // An expired token cannot be revoked and does not need to be.
        }
    }

    // ---------- data ----------

    /**
     * @param array<string,string> $query PostgREST filters, e.g.
     *        ['select' => 'id,subject', 'status' => 'eq.assigned']
     */
    public function select(string $table, array $query = []): array
    {
        $k = $this->seenKey('', $table, $query);
        if (array_key_exists($k, self::$seen)) return (array) self::$seen[$k];
        $qs = $query ? '?' . http_build_query($query) : '';
        $rows = $this->request('GET', "/rest/v1/{$table}{$qs}");
        self::$seen[$k] = $rows;
        return $rows;
    }

    /**
     * Several selects at once (branch B), over curl_multi: the portal's
     * database is a round trip away (in Mumbai until 7 Nov 2026, Singapore since), and a page that made its
     * requests one after another spent most of its load time waiting on
     * each in turn. Keys are kept; each value is that select's rows.
     * With $count, each value is instead the exact row count (only the
     * Content-Range header is transferred). Throws on the first failure,
     * except for an entry marked optional (a third element, true), whose
     * value is then the SupabaseError instead. A table named 'rpc/fn'
     * calls that function, its query array being the arguments.
     *
     * Speed work (perf, 7 Nov 2026): a fourth element sets one entry's mode, so rows and counts share one wait:
     *   'count'  the value is that entry's exact row count, as $count does for the whole batch;
     *   'total'  the value is the rows, and "<key>:total" holds the exact count of every row the filters match (PostgREST sends
     *            it with the rows, in Content-Range), so a page of a list and the total behind its pager come in one request.
     *
     * @param array<string, array{0:string, 1:array<string,mixed>, 2?:bool, 3?:string}> $selects
     * @return array<string, mixed>
     */
    public function selectMany(array $selects, bool $count = false, int $concurrency = 16): array
    {
        $headers = [
            'apikey: ' . supabase_key(),
            'Accept: application/json',
            'Authorization: Bearer ' . ($this->accessToken ?? supabase_key()),
        ];
        $mode = array_map(fn($s) => $count ? 'count' : (string) ($s[3] ?? ''), $selects);
        // what this request has already read is answered from the memo; the rest goes in the batch
        $keyOf = [];
        $out = [];
        foreach ($selects as $key => $s) {
            $q = $s[1];
            if ($mode[$key] === 'count') { $q['select'] = $count ? 'id' : (($q['select'] ?? '') !== '' ? $q['select'] : 'id'); }
            $keyOf[$key] = $this->seenKey($mode[$key], $s[0], $q);
            if ($mode[$key] === '' && !array_key_exists($keyOf[$key], self::$seen)) {
                [$hit, $val] = engine_cache_get(engine_cache_file($this->accessToken, $s[0], $q));
                if ($hit) { self::$seen[$keyOf[$key]] = $val; }
            }
            if (array_key_exists($keyOf[$key], self::$seen)) {
                $hit = self::$seen[$keyOf[$key]];
                if ($mode[$key] === 'total') { [$out[$key], $out[$key . ':total']] = $hit; } else { $out[$key] = $hit; }
            }
        }
        $mh = curl_multi_init();
        curl_multi_setopt($mh, CURLMOPT_PIPELINING, CURLPIPE_MULTIPLEX);
        $queue = array_diff_key($selects, $out);
        $optional = array_map(fn($s) => !empty($s[2]), $selects);
        $running = [];   // (int) handle id => [key, handle]
        $asked = count($queue);
        if ($asked === 0) { return $this->inOrder($selects, $out); }
        $names = implode(', ', array_map(fn($x) => strtok($x[0], '?'), $queue));

        $start = function () use (&$queue, &$running, $mh, $headers, $mode, $count): void {
            $key = array_key_first($queue);
            [$table, $query] = $queue[$key];
            unset($queue[$key]);
            $isRpc = str_starts_with($table, 'rpc/');
            $isAuth = str_starts_with($table, 'auth/');   // GoTrue's own record of the signed-in user ('auth/user'), read with the rest
            $m = $mode[$key];
            $h = $headers;
            // a whole batch of counts counts ids, as it always has; one counted entry keeps its own select (an inner join narrows it)
            if ($m === 'count') { $query['select'] = $count ? 'id' : (($query['select'] ?? '') !== '' ? $query['select'] : 'id'); $h[] = 'Prefer: count=exact'; $h[] = 'Range: 0-0'; }
            elseif ($m === 'total') { $h[] = 'Prefer: count=exact'; }
            $qs = ($query && !$isRpc) ? '?' . http_build_query($query) : '';
            $ch = curl_init(supabase_url() . ($isAuth ? '/auth/v1/' . substr($table, 5) : "/rest/v1/{$table}") . $qs);
            curl_setopt_array($ch, supabase_curl_opts());
            curl_setopt_array($ch, [
                CURLOPT_RETURNTRANSFER => true,
                CURLOPT_HEADER         => $m !== '',
                CURLOPT_HTTPHEADER     => $isRpc ? [...$h, 'Content-Type: application/json'] : $h,
                CURLOPT_TIMEOUT        => 20,
                CURLOPT_CONNECTTIMEOUT => 8,
            ]);
            if ($isRpc) {
                curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($query ?: new stdClass()));
            }
            curl_multi_add_handle($mh, $ch);
            $running[spl_object_id($ch)] = [$key, $ch];
        };

        $tq = microtime(true);
        while ($queue && count($running) < $concurrency) { $start(); }
        do {
            curl_multi_exec($mh, $active);
            curl_multi_select($mh, 0.2);
            while ($info = curl_multi_info_read($mh)) {
                $ch = $info['handle'];
                [$key] = $running[spl_object_id($ch)];
                unset($running[spl_object_id($ch)]);
                $raw = curl_multi_getcontent($ch);
                $status = (int) curl_getinfo($ch, CURLINFO_HTTP_CODE);
                $err = curl_error($ch);
                curl_multi_remove_handle($mh, $ch);
                try {
                    server_timing_conn($ch);
                    if ($raw === null || $raw === '' && $status === 0) {
                        throw new SupabaseError('Could not reach the database: ' . $err);
                    }
                    $raw = (string) $raw;
                    $head = '';
                    if ($mode[$key] !== '') {
                        // the response's headers come first; the last block is the one that answers (a 100 Continue may precede it)
                        $hs = (int) curl_getinfo($ch, CURLINFO_HEADER_SIZE);
                        $head = substr($raw, 0, $hs); $raw = substr($raw, $hs);
                    }
                    $total = preg_match('#Content-Range:\s*[\d*-]+/(\d+)#i', $head, $mm) ? (int) $mm[1] : 0;
                    if ($mode[$key] === 'count') {
                        $out[$key] = $total;   // a count that fails reads 0, as it always has
                    } else {
                        $data = json_decode($raw, true);
                        if ($status >= 400) {
                            throw new SupabaseError((string) ($data['message'] ?? "Request failed ({$status})"), $status);
                        }
                        // A function may return a bare scalar; a table never does.
                        $out[$key] = (is_array($data) || str_starts_with($selects[$key][0], 'rpc/')) ? $data : [];
                        if ($mode[$key] === 'total') { $out[$key . ':total'] = $total; }
                    }
                    self::$seen[$keyOf[$key]] = $mode[$key] === 'total' ? [$out[$key], $out[$key . ':total']] : $out[$key];
                    if ($mode[$key] === '') { engine_cache_put(engine_cache_file($this->accessToken, $selects[$key][0], $selects[$key][1]), $out[$key]); }
                } catch (SupabaseError $ex) {
                    if (!$optional[$key]) { throw $ex; }
                    $out[$key] = $ex;
                }
                if ($queue) { $start(); }
            }
        } while ($running);
        supabase_trace('batch of ' . $asked . ': ' . $names, $tq);
        return $this->inOrder($selects, $out);
    }

    /** The batch's answers in the order it was asked (a ":total" right after its rows), as callers that loop over them expect. */
    private function inOrder(array $selects, array $out): array
    {
        $o = [];
        foreach (array_keys($selects) as $k) {
            if (array_key_exists($k, $out)) $o[$k] = $out[$k];
            if (array_key_exists($k . ':total', $out)) $o[$k . ':total'] = $out[$k . ':total'];
        }
        return $o;
    }

    /** Row count without transferring the rows. */
    public function count(string $table, array $query = []): int
    {
        $query['select'] = $query['select'] ?? 'id';   // a caller may keep its own (an inner join on concerns)
        $qs = '?' . http_build_query($query);

        $ch = curl_init(supabase_url() . "/rest/v1/{$table}{$qs}");
        curl_setopt_array($ch, supabase_curl_opts());
        curl_setopt_array($ch, [
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_NOBODY         => false,
            CURLOPT_HEADER         => true,
            CURLOPT_TIMEOUT        => 15,
            CURLOPT_HTTPHEADER     => [
                'apikey: ' . supabase_key(),
                'Authorization: Bearer ' . ($this->accessToken ?? supabase_key()),
                'Prefer: count=exact',
                'Range: 0-0',
            ],
        ]);
        $tq  = microtime(true);
        $raw = curl_exec($ch);
        supabase_trace('count ' . $table, $tq);
        server_timing_conn($ch);
        // curl_close() removed -- see the comment in request() above.

        // Content-Range comes back as "0-0/57"; the total is after the slash.
        if (is_string($raw) && preg_match('#Content-Range:\s*\d+-\d+/(\d+)#i', $raw, $m)) {
            return (int) $m[1];
        }
        return 0;
    }

    public function insert(string $table, array $row): array
    {
        return $this->request('POST', "/rest/v1/{$table}", $row, ['Prefer' => 'return=representation']);
    }

    public function update(string $table, array $query, array $patch): array
    {
        $qs = '?' . http_build_query($query);
        return $this->request('PATCH', "/rest/v1/{$table}{$qs}", $patch, ['Prefer' => 'return=representation']);
    }

    /** Delete the rows matching $query (row-level security decides which the caller may). Returns the deleted rows. */
    public function delete(string $table, array $query): array
    {
        $qs = '?' . http_build_query($query);
        $r = $this->request('DELETE', "/rest/v1/{$table}{$qs}", null, ['Prefer' => 'return=representation']);
        return is_array($r) ? $r : [];
    }

    /** Insert, or update the row that has the same $onConflict columns (the Workspace's one-row-per-thing tables). */
    public function upsert(string $table, array $row, string $onConflict): array
    {
        $r = $this->request('POST', "/rest/v1/{$table}?on_conflict=" . rawurlencode($onConflict), $row,
                            ['Prefer' => 'resolution=merge-duplicates,return=representation']);
        return is_array($r) ? $r : [];
    }

    /**
     * Call a Postgres function. This is how dispatch actions are
     * performed.
     *
     * Returns whatever the function's own return type produces: an
     * array of rows for a table/set-returning function (account_
     * directory, dashboard_metrics, ...), or the bare scalar for
     * anything that returns a single plain value instead (text, an
     * enum, a boolean, ...) -- admin_reset_password() is the one
     * caller in this codebase that actually reads such a scalar back
     * today. Callers that only care about success/failure can keep
     * ignoring the return value exactly as before.
     */
    /** Calls an Edge Function as this session (0162: level-switch). */
    public function invoke(string $fn, array $body = []): array|string|int|float|bool|null
    {
        return $this->request('POST', '/functions/v1/' . rawurlencode($fn), $body);
    }

    public function rpc(string $fn, array $args = []): array|string|int|float|bool|null
    {
        // a function this request already called in a batch of reads is answered from the memo; any other call may write, so it
        // goes to the database and empties the memo (request() above)
        $k = $this->seenKey('', 'rpc/' . $fn, $args);
        if (array_key_exists($k, self::$seen)) return self::$seen[$k];
        // one of the engine's reads: this person's copy from the last minute, if there is one (engine_cache_file above)
        $file = engine_cache_file($this->accessToken, 'rpc/' . $fn, $args);
        [$hit, $val] = engine_cache_get($file);
        if ($hit) { self::$seen[$k] = $val; return $val; }
        $v = $this->request('POST', "/rest/v1/rpc/{$fn}", $args);
        if ($file !== null) { self::$seen[$k] = $v; engine_cache_put($file, $v); }
        return $v;
    }
}

/**
 * Uploads the photos in $_FILES[$field] (an <input type="file" multiple>)
 * to the barangay's Cloudinary folder and returns them in the shape the
 * evidence functions take: media_url, mime_type, bytes (0079). No photos
 * chosen returns []. The URL shape is pinned in the database by
 * is_barangay_media_url(); the two must change together.
 */
function cloudinary_upload_files(string $field, int $max = 6, string $folder = 'barangay'): array
{
    $f = $_FILES[$field] ?? null;
    if (!$f || !is_array($f['name'])) {
        return [];
    }
    $out = [];
    $allowed = ['image/jpeg' => 'jpg', 'image/png' => 'png', 'image/webp' => 'webp'];
    foreach ($f['name'] as $i => $name) {
        if (($f['error'][$i] ?? UPLOAD_ERR_NO_FILE) === UPLOAD_ERR_NO_FILE) {
            continue;
        }
        if (count($out) >= $max) {
            throw new SupabaseError(t("Attach at most {$max} photos.", "Hanggang {$max} larawan lamang."));
        }
        if ($f['error'][$i] !== UPLOAD_ERR_OK || !is_uploaded_file($f['tmp_name'][$i])) {
            throw new SupabaseError(t('A photo could not be uploaded. Try again.', 'Hindi ma-upload ang isang larawan. Subukan muli.'));
        }
        $bytes = (int) $f['size'][$i];
        if ($bytes <= 0 || $bytes > 10 * 1024 * 1024) {
            throw new SupabaseError(t('Each photo must be under 10 MB.', 'Dapat mas mababa sa 10 MB ang bawat larawan.'));
        }
        $mime = (string) (new finfo(FILEINFO_MIME_TYPE))->file($f['tmp_name'][$i]);
        if (!isset($allowed[$mime])) {
            throw new SupabaseError(t('Only JPEG, PNG or WebP photos can be attached.', 'JPEG, PNG o WebP na larawan lamang ang maaaring ilakip.'));
        }
        // Location and camera data out before it leaves the server, the
        // way the app strips them on the phone.
        strip_photo_metadata($f['tmp_name'][$i], $mime);
        $bytes = (int) filesize($f['tmp_name'][$i]);

        $uuid = sprintf('%s-%s-4%s-%s%s-%s',
            bin2hex(random_bytes(4)), bin2hex(random_bytes(2)), substr(bin2hex(random_bytes(2)), 1),
            dechex(8 + random_int(0, 3)), substr(bin2hex(random_bytes(2)), 1), bin2hex(random_bytes(6)));

        $post = static function (array $fields) use ($f, $i, $mime, $allowed): array {
            $ch = curl_init('https://api.cloudinary.com/v1_1/' . rawurlencode(cloudinary_cloud()) . '/image/upload');
            curl_setopt_array($ch, [
                CURLOPT_POST           => true,
                CURLOPT_RETURNTRANSFER => true,
                CURLOPT_TIMEOUT        => 60,
                CURLOPT_POSTFIELDS     => $fields + ['file' => new CURLFile($f['tmp_name'][$i], $mime, 'photo.' . $allowed[$mime])],
            ]);
            $body = curl_exec($ch);
            $code = (int) curl_getinfo($ch, CURLINFO_RESPONSE_CODE);
            curl_close($ch);
            return [$code, $body];
        };
        $fields = cloudinary_upload_fields($folder . '/' . $uuid);
        [$code, $body] = $post($fields);
        if ($code === 401 && isset($fields['signature'])) {
            // Cloudinary refused the signature (a key or clock problem):
            // the unsigned preset, while it still exists.
            [$code, $body] = $post(cloudinary_preset_fields($folder . '/' . $uuid));
        }
        $json = is_string($body) ? json_decode($body, true) : null;
        if ($code !== 200 || !is_array($json) || empty($json['secure_url'])) {
            throw new SupabaseError(t('The photo service did not accept a photo. Try again.', 'Hindi tinanggap ng serbisyo ng larawan ang isang larawan. Subukan muli.'));
        }
        $out[] = [
            'media_url' => (string) $json['secure_url'],
            'mime_type' => $mime,
            'bytes'     => (int) ($json['bytes'] ?? $bytes),
        ];
    }
    return $out;
}

/**
 * The fields that authorise one photo upload (0116). With the API key and
 * secret in the environment the portal signs the upload itself, fixing the
 * name, formats and resize the unsigned preset used to apply; without them
 * it uses the unsigned preset as before.
 */
function cloudinary_upload_fields(string $publicId): array
{
    $key = env('CLOUDINARY_API_KEY', '');
    $secret = env('CLOUDINARY_API_SECRET', '');
    if ($key === '' || $secret === '') {
        return cloudinary_preset_fields($publicId);
    }
    $params = [  // in sorted order: the signature covers them sorted
        'allowed_formats' => 'jpg,png,webp',
        'format'          => 'jpg',
        'public_id'       => $publicId,
        'timestamp'       => (string) time(),
        'transformation'  => 'c_limit,w_1920,q_auto',
    ];
    $pairs = [];
    foreach ($params as $k => $v) {
        $pairs[] = "$k=$v";
    }
    return $params + ['api_key' => $key, 'signature' => hash('sha256', implode('&', $pairs) . $secret)];
}

function cloudinary_preset_fields(string $publicId): array
{
    return ['upload_preset' => cloudinary_preset(), 'public_id' => $publicId, 'source' => 'smartsumbong-portal'];
}

/**
 * Removes embedded metadata (EXIF, including GPS, XMP, comments) from a
 * JPEG, PNG or WebP file in place, without re-encoding the picture. Pure
 * PHP: the portal's image has no GD or Imagick. Leaves the file untouched
 * if it does not parse as expected.
 */
function strip_photo_metadata(string $path, string $mime): void
{
    $data = @file_get_contents($path);
    if (!is_string($data) || $data === '') {
        return;
    }
    $out = null;

    if ($mime === 'image/jpeg' && substr($data, 0, 2) === "\xFF\xD8") {
        // Copy every segment except APP1..APP15 (EXIF, XMP, maker notes)
        // and COM; APP0 (JFIF) stays. Stop parsing at Start of Scan.
        $out = "\xFF\xD8";
        $i = 2;
        $n = strlen($data);
        while ($i + 4 <= $n && $data[$i] === "\xFF") {
            $marker = ord($data[$i + 1]);
            if ($marker === 0xDA) {
                $out .= substr($data, $i);
                $i = $n;
                break;
            }
            $len = (ord($data[$i + 2]) << 8) | ord($data[$i + 3]);
            if ($len < 2 || $i + 2 + $len > $n) {
                return; // malformed: leave it
            }
            $drop = ($marker >= 0xE1 && $marker <= 0xEF) || $marker === 0xFE;
            if (!$drop) {
                $out .= substr($data, $i, 2 + $len);
            }
            $i += 2 + $len;
        }
        if ($i < $n) {
            return;
        }
    } elseif ($mime === 'image/png' && substr($data, 0, 8) === "\x89PNG\r\n\x1a\n") {
        // Drop the text and EXIF chunks; every other chunk is copied.
        $out = substr($data, 0, 8);
        $i = 8;
        $n = strlen($data);
        while ($i + 12 <= $n) {
            $len  = unpack('N', substr($data, $i, 4))[1];
            $type = substr($data, $i + 4, 4);
            if ($i + 12 + $len > $n) {
                return;
            }
            if (!in_array($type, ['eXIf', 'tEXt', 'zTXt', 'iTXt'], true)) {
                $out .= substr($data, $i, 12 + $len);
            }
            $i += 12 + $len;
        }
    } elseif ($mime === 'image/webp' && substr($data, 0, 4) === 'RIFF' && substr($data, 8, 4) === 'WEBP') {
        // Drop the EXIF and XMP chunks and clear their flags in VP8X.
        $body = '';
        $i = 12;
        $n = strlen($data);
        while ($i + 8 <= $n) {
            $type = substr($data, $i, 4);
            $len  = unpack('V', substr($data, $i + 4, 4))[1];
            $size = 8 + $len + ($len & 1);
            if ($i + 8 + $len > $n) {
                return;
            }
            $chunk = substr($data, $i, $size);
            if ($type === 'VP8X' && strlen($chunk) >= 9) {
                $chunk[8] = chr(ord($chunk[8]) & ~0x0C);
            }
            if ($type !== 'EXIF' && $type !== 'XMP ') {
                $body .= $chunk;
            }
            $i += $size;
        }
        $out = 'RIFF' . pack('V', 4 + strlen($body)) . 'WEBP' . $body;
    }

    if (is_string($out) && $out !== $data) {
        file_put_contents($path, $out);
    }
}
