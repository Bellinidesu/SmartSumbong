<?php
/**
 * The specific issues under each complaint category, as the resident app's picker lists them
 * (mobile/resident/lib/models/complaint_category.dart). A report's subject holds the issue the resident
 * picked, so Case Reports filters on it (panel ask 3a, 7 Sep 2026). Since 0146 the list is a table both read.
 */
declare(strict_types=1);

/**
 * The options under each category, English names (0146: complaint_options, edited in Settings > Complaint types), read once
 * per request; switched-off ones are kept, so a filter still finds the reports filed under them. category => [names].
 */
function category_issues(): array
{
    static $memo = null;
    if ($memo !== null) return $memo;
    $memo = [];
    foreach (complaint_options_rows() as $o) { $memo[(string) $o['category']][] = (string) $o['label_en']; }
    return $memo;
}

/** Every complaint option's row, in order (category, sort, id), from the shared cache (shared_cache.php); Settings drops it on a save. */
function complaint_options_rows(): array
{
    static $memo = null;
    if ($memo !== null) return $memo;
    return $memo = shared_cache('complaint_options',
        static fn (): array => (array) db()->select('complaint_options', ['select' => 'id,category,label_en,label_fil,active', 'order' => 'category.asc,sort.asc,id.asc']),
        access_token() !== null);
}

/**
 * Every option by category, with its id, names and whether residents can pick it (0163: a concern points at its option by id, so
 * a renamed option still finds the cases filed under its old name). category => [id => [en, fil, active]].
 */
function category_options(): array
{
    static $memo = null;
    if ($memo !== null) return $memo;
    $memo = [];
    foreach (complaint_options_rows() as $o) {
        $memo[(string) $o['category']][(int) $o['id']] = ['en' => (string) $o['label_en'], 'fil' => (string) $o['label_fil'], 'active' => !empty($o['active'])];
    }
    return $memo;
}

/**
 * A concern's name for the page, and what it was filed as when that differs (0163): renamed, or switched off since.
 * @return array{0:string,1:?string} [the name today, the "filed as" line or null]
 */
function concern_names(array $c): array
{
    $cat = (string) ($c['category'] ?? '');
    $cur = categories_all()[$cat] ?? null;
    $catNow = category_label($cat);
    $oid = isset($c['option_id']) ? (int) $c['option_id'] : 0;
    $opt = $oid ? (category_options()[$cat][$oid] ?? null) : null;
    $optNow = $opt ? t($opt['en'], $opt['fil']) : null;
    $name = $catNow . ($optNow !== null ? ': ' . $optNow : (!empty($c['filed_option_en']) ? ': ' . t((string) $c['filed_option_en'], (string) ($c['filed_option_fil'] ?? $c['filed_option_en'])) : ''));
    $filedCat = (string) ($c['filed_category_en'] ?? '');
    $filedOpt = (string) ($c['filed_option_en'] ?? '');
    $changed = ($filedCat !== '' && $cur && $filedCat !== $cur['en']) || ($filedOpt !== '' && $opt && $filedOpt !== $opt['en']);
    $off = ($cur && empty($cur['active'])) || ($oid && $opt && empty($opt['active'])) || ($filedOpt !== '' && $oid === 0);
    if (!$changed && !$off) return [$name, null];
    $was = ($filedCat !== '' ? t($filedCat, (string) ($c['filed_category_fil'] ?? $filedCat)) : $catNow)
         . ($filedOpt !== '' ? ': ' . t($filedOpt, (string) ($c['filed_option_fil'] ?? $filedOpt)) : '');
    $why = $off ? t('no longer offered', 'hindi na inaalok') : t('renamed since', 'pinalitan ang pangalan mula noon');
    return [$name, sprintf(t('Filed as "%s" (%s)', 'Isinampa bilang "%s" (%s)'), $was, $why)];
}
