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
    ): array {
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
        curl_close($ch);

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

        return is_array($data) ? $data : [];
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
        curl_close($ch);

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

    /** Call a Postgres function. This is how dispatch actions are performed. */
    public function rpc(string $fn, array $args = []): array
    {
        return $this->request('POST', "/rest/v1/rpc/{$fn}", $args);
    }
}
