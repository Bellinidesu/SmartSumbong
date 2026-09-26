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

        $raw    = curl_exec($ch);
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
        ]);
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
        ]);
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
        $qs = $query ? '?' . http_build_query($query) : '';
        return $this->request('GET', "/rest/v1/{$table}{$qs}");
    }

    /**
     * Several selects at once (branch B), over curl_multi: the portal's
     * database is a round trip away in Mumbai, and a page that made its
     * requests one after another spent most of its load time waiting on
     * each in turn. Keys are kept; each value is that select's rows.
     * With $count, each value is instead the exact row count (only the
     * Content-Range header is transferred). Throws on the first failure,
     * except for an entry marked optional (a third element, true), whose
     * value is then the SupabaseError instead. A table named 'rpc/fn'
     * calls that function, its query array being the arguments.
     *
     * @param array<string, array{0:string, 1:array<string,mixed>, 2?:bool}> $selects
     * @return array<string, mixed>
     */
    public function selectMany(array $selects, bool $count = false, int $concurrency = 8): array
    {
        $headers = [
            'apikey: ' . supabase_key(),
            'Accept: application/json',
            'Authorization: Bearer ' . ($this->accessToken ?? supabase_key()),
        ];
        if ($count) {
            $headers[] = 'Prefer: count=exact';
            $headers[] = 'Range: 0-0';
        }
        $mh = curl_multi_init();
        $queue = $selects;
        $optional = array_map(fn($s) => !empty($s[2]), $selects);
        $running = [];   // (int) handle id => [key, handle]
        $out = [];

        $start = function () use (&$queue, &$running, $mh, $headers, $count): void {
            $key = array_key_first($queue);
            [$table, $query] = $queue[$key];
            unset($queue[$key]);
            $isRpc = str_starts_with($table, 'rpc/');
            if ($count) { $query['select'] = 'id'; }
            $qs = ($query && !$isRpc) ? '?' . http_build_query($query) : '';
            $ch = curl_init(supabase_url() . "/rest/v1/{$table}{$qs}");
            curl_setopt_array($ch, [
                CURLOPT_RETURNTRANSFER => true,
                CURLOPT_HEADER         => $count,
                CURLOPT_HTTPHEADER     => $isRpc ? [...$headers, 'Content-Type: application/json'] : $headers,
                CURLOPT_TIMEOUT        => 20,
                CURLOPT_CONNECTTIMEOUT => 8,
            ]);
            if ($isRpc) {
                curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($query ?: new stdClass()));
            }
            curl_multi_add_handle($mh, $ch);
            $running[spl_object_id($ch)] = [$key, $ch];
        };

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
                    if ($raw === null || $raw === '' && $status === 0) {
                        throw new SupabaseError('Could not reach the database: ' . $err);
                    }
                    if ($count) {
                        $out[$key] = preg_match('#Content-Range:\s*[\d*-]+/(\d+)#i', (string) $raw, $m)
                            ? (int) $m[1] : 0;
                    } else {
                        $data = json_decode((string) $raw, true);
                        if ($status >= 400) {
                            throw new SupabaseError((string) ($data['message'] ?? "Request failed ({$status})"), $status);
                        }
                        // A function may return a bare scalar; a table never does.
                        $out[$key] = (is_array($data) || str_starts_with($selects[$key][0], 'rpc/')) ? $data : [];
                    }
                } catch (SupabaseError $ex) {
                    if (!$optional[$key]) { throw $ex; }
                    $out[$key] = $ex;
                }
                if ($queue) { $start(); }
            }
        } while ($running);
        return $out;
    }

    /** Row count without transferring the rows. */
    public function count(string $table, array $query = []): int
    {
        $query['select'] = 'id';
        $qs = '?' . http_build_query($query);

        $ch = curl_init(supabase_url() . "/rest/v1/{$table}{$qs}");
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
        $raw = curl_exec($ch);
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
    public function rpc(string $fn, array $args = []): array|string|int|float|bool|null
    {
        return $this->request('POST', "/rest/v1/rpc/{$fn}", $args);
    }
}
