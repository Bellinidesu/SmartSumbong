<?php
// Every label of the portal and the app, for Settings > Wording (0149): the English and Tagalog each is written with, and where
// it appears. Settings searches this list, so a super admin picks a label instead of typing it exactly.
//
//   php .github/scripts/wording-catalog.php           write admin/includes/wording_catalog.json
//   php .github/scripts/wording-catalog.php --check   fail when the file is out of date (CI, portal job)
//
// Portal: t('English', 'Tagalog') / T(...) with two literal strings (PHP's own tokenizer, as i18n-check.php).
// App: _t('English', 'Tagalog') and context.tr('English', 'Tagalog'), each side one literal or several written side by side;
// a side with ${...} in it is built at run time and is left out.
declare(strict_types=1);

$repo = dirname(__DIR__, 2);
$out = $repo . '/admin/includes/wording_catalog.json';
$cat = [];
$add = static function (string $en, string $fil, string $where) use (&$cat): void {
    $en = trim(str_replace("\r\n", "\n", $en)); $fil = str_replace("\r\n", "\n", $fil);
    if ($en === '' || mb_strlen($en) > 600) return;
    $cat[$en] ??= ['en' => $en, 'fil' => $fil, 'in' => []];
    if (!in_array($where, $cat[$en]['in'], true)) $cat[$en]['in'][] = $where;
};

/** Files under $dir with the extension $ext, relative, in one order on every machine (the first Tagalog seen for a label wins). */
function files_in(string $dir, string $ext): array
{
    $out = [];
    foreach (new RecursiveIteratorIterator(new RecursiveDirectoryIterator($dir, FilesystemIterator::SKIP_DOTS)) as $f) {
        if ($f->getExtension() === $ext) $out[] = str_replace(DIRECTORY_SEPARATOR, '/', substr($f->getPathname(), strlen($dir) + 1));
    }
    sort($out, SORT_STRING);
    return $out;
}

// ---- the portal
foreach (files_in($repo . '/admin', 'php') as $rel) {
    $tk = array_values(array_filter(token_get_all(file_get_contents($repo . '/admin/' . $rel)),
        fn($t) => !(is_array($t) && in_array($t[0], [T_WHITESPACE, T_COMMENT, T_DOC_COMMENT], true))));
    for ($i = 1; $i < count($tk) - 4; $i++) {
        if (!is_array($tk[$i]) || $tk[$i][0] !== T_STRING || !in_array($tk[$i][1], ['t', 'T'], true) || $tk[$i + 1] !== '(') continue;
        if (is_array($tk[$i - 1]) && in_array($tk[$i - 1][0], [T_FUNCTION, T_OBJECT_OPERATOR, T_DOUBLE_COLON], true)) continue;
        [$a, $c, $b] = [$tk[$i + 2], $tk[$i + 3], $tk[$i + 4]];
        if (!is_array($a) || $a[0] !== T_CONSTANT_ENCAPSED_STRING || $c !== ',' || !is_array($b) || $b[0] !== T_CONSTANT_ENCAPSED_STRING) continue;
        $add(stripcslashes(substr($a[1], 1, -1)), stripcslashes(substr($b[1], 1, -1)), 'portal');
    }
}

// ---- the app
/** Reads literals written side by side from $s at $i: [value, next index], or null (not literals, or interpolated). */
function dart_literals(string $s, int $i): ?array
{
    $val = ''; $n = 0; $len = strlen($s);
    while (true) {
        while ($i < $len && ctype_space($s[$i])) $i++;
        if ($i + 1 < $len && $s[$i] === '/' && $s[$i + 1] === '/') { $i = strpos($s, "\n", $i) ?: $len; continue; }
        if ($i >= $len || ($s[$i] !== "'" && $s[$i] !== '"')) break;
        $q = $s[$i++];
        while ($i < $len && $s[$i] !== $q) {
            if ($s[$i] === '$') return null;
            if ($s[$i] === '\\' && $i + 1 < $len) {
                $e = $s[$i + 1];
                $val .= match ($e) { 'n' => "\n", 't' => "\t", default => $e };
                $i += 2;
                continue;
            }
            $val .= $s[$i++];
        }
        $i++; $n++;
    }
    return $n ? [$val, $i] : null;
}
foreach (files_in($repo . '/mobile/resident/lib', 'dart') as $rel) {
    if (str_starts_with($rel, 'preview/')) continue;
    $s = str_replace("\r\n", "\n", file_get_contents($repo . '/mobile/resident/lib/' . $rel));
    preg_match_all('/(?<![A-Za-z0-9_])(?:_t|\.tr)\(/', $s, $m, PREG_OFFSET_CAPTURE);
    foreach ($m[0] as [$hit, $at]) {
        $a = dart_literals($s, $at + strlen($hit));
        if ($a === null) continue;
        $j = $a[1];
        while ($j < strlen($s) && ctype_space($s[$j])) $j++;
        if (($s[$j] ?? '') !== ',') continue;
        $b = dart_literals($s, $j + 1);
        if ($b === null) continue;
        $add($a[0], $b[0], 'app');
    }
}

foreach ($cat as &$e) sort($e['in']);
unset($e);
ksort($cat, SORT_STRING);
$json = "[\n" . implode(",\n", array_map(fn($e) => json_encode($e, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES), array_values($cat))) . "\n]\n";
if (in_array('--check', $argv, true)) {
    if (!is_file($out) || file_get_contents($out) !== $json) {
        fwrite(STDERR, "admin/includes/wording_catalog.json is out of date: run php .github/scripts/wording-catalog.php and commit it\n");
        exit(1);
    }
    echo 'ok   ', count($cat), " labels in the wording catalogue\n";
    exit(0);
}
file_put_contents($out, $json);
echo 'wrote ', count($cat), " labels (portal ", count(array_filter($cat, fn($e) => in_array('portal', $e['in'], true))),
     ', app ', count(array_filter($cat, fn($e) => in_array('app', $e['in'], true))), ")\n";
