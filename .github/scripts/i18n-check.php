<?php
// Every English string in the portal has a Tagalog one (CI, portal job).
// Uses PHP's own tokenizer to find each t('English', 'Tagalog') / T(...)
// call with two literal strings, and fails when the Tagalog side is
// missing, empty, or the English copied over (names and loanwords aside).
declare(strict_types=1);

$sameInBoth = ['SmartSumbong', 'Tanod', 'Email', 'OK', 'Online', 'Offline', 'Barangay', 'Supabase',
    'Cloudinary', 'Render', 'Password', 'Email address', 'Status', 'Dashboard', 'Admin', 'Server',
    'Browser', 'Function', 'Facebook', 'GitHub', 'Firebase', 'Semaphore', 'Uptime', 'PDF', 'Account',
    'Live', 'Heatmap', 'OCR flag', 'Mobile number', 'System', 'Update', 'Auto',
    // Filipino already: titles and offices with no English to translate from.
    'Punong Barangay', 'Katarungang Pambarangay (Lupong Tagapamayapa)'];

$root = dirname(__DIR__, 2) . '/admin';
$files = new RecursiveIteratorIterator(new RecursiveDirectoryIterator($root, FilesystemIterator::SKIP_DOTS));
$pairs = 0;
$bad = [];
foreach ($files as $file) {
    if ($file->getExtension() !== 'php') continue;
    $tokens = array_values(array_filter(token_get_all(file_get_contents($file->getPathname())),
        fn($t) => !(is_array($t) && in_array($t[0], [T_WHITESPACE, T_COMMENT, T_DOC_COMMENT], true))));
    $rel = substr($file->getPathname(), strlen(dirname($root)) + 1);
    for ($i = 0; $i < count($tokens) - 4; $i++) {
        $tk = $tokens[$i];
        if (!is_array($tk) || $tk[0] !== T_STRING || !in_array($tk[1], ['t', 'T'], true) || $tokens[$i + 1] !== '(') continue;
        $prev = $tokens[$i - 1] ?? null;
        if (is_array($prev) && in_array($prev[0], [T_FUNCTION, T_OBJECT_OPERATOR, T_DOUBLE_COLON], true)) continue;
        $a = $tokens[$i + 2];
        if (!is_array($a) || $a[0] !== T_CONSTANT_ENCAPSED_STRING) continue;
        $en = stripcslashes(substr($a[1], 1, -1));
        $line = $a[2];
        if ($tokens[$i + 3] === '.') continue; // built from pieces: not checkable here
        if ($tokens[$i + 3] !== ',') { $bad[] = "$rel:$line  no Tagalog for \"$en\""; continue; }
        $b = $tokens[$i + 4];
        if (!is_array($b) || $b[0] !== T_CONSTANT_ENCAPSED_STRING) continue;
        $pairs++;
        $tl = stripcslashes(substr($b[1], 1, -1));
        if (trim($tl) === '') $bad[] = "$rel:$line  empty Tagalog for \"$en\"";
        elseif ($tl === $en && preg_match('/[a-z]{3}/', $en) && !in_array(trim($en), $sameInBoth, true)) {
            $bad[] = "$rel:$line  Tagalog copied from English: \"$en\"";
        }
    }
}
if ($pairs < 500) { fwrite(STDERR, "only $pairs pairs found: is the check still reading the portal?\n"); exit(1); }
if ($bad) { echo implode("\n", $bad), "\n", count($bad), " problem(s) in $pairs pairs\n"; exit(1); }
echo "ok   $pairs English/Tagalog pairs\n";
