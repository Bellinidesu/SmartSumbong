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

        $ch = curl_init('https://api.cloudinary.com/v1_1/' . rawurlencode(cloudinary_cloud()) . '/image/upload');
        curl_setopt_array($ch, [
            CURLOPT_POST           => true,
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_TIMEOUT        => 60,
            CURLOPT_POSTFIELDS     => [
                'upload_preset' => cloudinary_preset(),
                'public_id'     => $folder . '/' . $uuid,
                'source'        => 'smartsumbong-portal',
                'file'          => new CURLFile($f['tmp_name'][$i], $mime, 'photo.' . $allowed[$mime]),
            ],
        ]);
        $body = curl_exec($ch);
        $code = (int) curl_getinfo($ch, CURLINFO_RESPONSE_CODE);
        curl_close($ch);
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
