<?php
/**
 * QR codes for printed documents (22 Oct 2026), made with chillerlan/php-qrcode (MIT/Apache-2.0, through Composer).
 * Drawn here as an SVG data address, so nothing leaves the server and the content-security policy needs no new host.
 */
declare(strict_types=1);

require_once __DIR__ . '/vendor/autoload.php';

use chillerlan\QRCode\Common\EccLevel;
use chillerlan\QRCode\QRCode;
use chillerlan\QRCode\QROptions;

/** An SVG data address of a QR code holding $text (low error correction keeps the squares large enough for a phone to read off paper). */
function qr_data_uri(string $text): string
{
    $o = new QROptions([
        'eccLevel'        => EccLevel::L,
        'quietzoneSize'   => 2,
        'connectPaths'    => true,
        'svgAddXmlHeader' => false,
    ]);
    return (new QRCode($o))->render($text);
}

/**
 * This portal's own address for a page, from the request: https behind Render's proxy, the host only if it looks like
 * a host name (a forged Host header cannot put something else into a printed code).
 */
function portal_url(string $path): string
{
    $host = (string) ($_SERVER['HTTP_HOST'] ?? '');
    if (!preg_match('/^[a-z0-9.-]+(:[0-9]{1,5})?$/i', $host)) {
        $host = 'smartsumbong-ph.onrender.com';
    }
    $https = ($_SERVER['HTTPS'] ?? '') === 'on' || strtolower((string) ($_SERVER['HTTP_X_FORWARDED_PROTO'] ?? '')) === 'https';
    return ($https || !str_starts_with($host, '127.0.0.1') && !str_starts_with($host, 'localhost') ? 'https' : 'http') . '://' . $host . '/admin/' . ltrim($path, '/');
}
