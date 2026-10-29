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
    try {
        foreach ((array) db()->select('complaint_options', ['select' => 'category,label_en', 'order' => 'category.asc,sort.asc,id.asc']) as $o) {
            $memo[(string) $o['category']][] = (string) $o['label_en'];
        }
    } catch (Throwable) {}
    return $memo;
}
