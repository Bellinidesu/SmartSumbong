<?php
/**
 * Report Summary as a spreadsheet (22 Oct 2026): the same rows the page shows, one sheet per section, for a
 * secretary who works in Excel or LibreOffice. Made with OpenSpout (MIT, through Composer; docs/UPDATING.md).
 *
 * It carries nothing the page does not: no complaint text, and an anonymous resident stays "Anonymous". Text from
 * people (names, remarks, notes) always goes in as a text cell, never through Cell::fromValue, which would turn a
 * value starting with "=" into a live formula in the barangay's spreadsheet.
 */
declare(strict_types=1);

require_once __DIR__ . '/vendor/autoload.php';

use OpenSpout\Common\Entity\Cell;
use OpenSpout\Common\Entity\Cell\DateTimeCell;
use OpenSpout\Common\Entity\Cell\NumericCell;
use OpenSpout\Common\Entity\Cell\StringCell;
use OpenSpout\Common\Entity\Row;
use OpenSpout\Common\Entity\Style\Style;
use OpenSpout\Writer\XLSX\Entity\SheetView;
use OpenSpout\Writer\XLSX\Writer;

/** A text cell: never a formula, whatever it starts with. */
function xs(?string $v, ?Style $st = null): Cell
{
    return new StringCell((string) ($v ?? ''), $st);
}

/** A date and time in the barangay's own time, or an empty text cell. */
function xd(?string $iso, Style $st): Cell
{
    if (!$iso) {
        return new StringCell('');
    }
    return new DateTimeCell((new DateTimeImmutable($iso))->setTimezone(new DateTimeZone('Asia/Manila')), $st);
}

/**
 * Streams the workbook to the browser and ends the request.
 *
 * @param list<array> $reports    the ledger rows (summary.php's $reports)
 * @param list<array> $dispatches the tanod activity rows
 * @param list<array> $logs       the case timeline rows, repeats folded as on the page
 */
function summary_spreadsheet(array $reports, array $dispatches, array $logs, DateTimeImmutable $from, DateTimeImmutable $to,
                             string $category, array $admin, array $truncated): never
{
    $head = (new Style())->withFontBold(true)->withFontColor('FFFFFF')->withBackgroundColor('00308F');
    $when = (new Style())->withFormat('yyyy-mm-dd hh:mm');
    $file = 'SmartSumbong-report-' . $from->format('Y-m-d') . '-to-' . $to->format('Y-m-d') . '.xlsx';

    $w = new Writer();
    $w->openToBrowser($file);
    $sheet = static function (string $name, array $cols, array $widths, bool $first = false) use ($w, $head) {
        $s = $first ? $w->getCurrentSheet() : $w->addNewSheetAndMakeItCurrent();
        $s->setName(mb_substr($name, 0, 31));
        $s->setSheetView(new SheetView(freezeRow: 2, tabSelected: $first));
        foreach ($widths as $i => $wd) {
            $s->setColumnWidth($wd, $i + 1);
        }
        $w->addRow(new Row(array_map(static fn ($c) => xs($c, $head), $cols)));
    };

    // ---- Complaints (the Resident Report Ledger)
    $sheet(t('Complaints', 'Mga sumbong'), [t('Complaint ID', 'ID ng Sumbong'), t('Resident', 'Residente'), t('Category', 'Kategorya'),
        t('Status', 'Katayuan'), t('Sensitive', 'Sensitibo'), t('Filed', 'Naisampa'), t('Due', 'Takdang petsa'), t('Resolved', 'Nalutas'),
        t('Days to resolve', 'Araw bago nalutas'), t('Escalated to', 'In-escalate sa')], [16, 28, 26, 22, 11, 17, 17, 17, 14, 26], true);
    foreach ($reports as $r) {
        $end = $r['resolved_at'] ?? $r['closed_at'] ?? null;
        $w->addRow(new Row([
            xs($r['tracking_id'] ?? ''),
            xs(!empty($r['is_anonymous']) ? t('Anonymous', 'Hindi nagpakilala') : formal_or($r['resident']['full_name'] ?? null, t('Unknown', 'Hindi kilala'))),
            xs(category_label((string) $r['category'])),
            xs(status_label((string) $r['status']) . (report_is_overdue($r) ? t(' (overdue)', ' (lampas na)') : '')),
            xs(!empty($r['is_sensitive']) ? t('Yes', 'Oo') : ''),
            xd($r['created_at'] ?? null, $when), xd($r['due_at'] ?? null, $when), xd($end, $when),
            $end ? new NumericCell(round((strtotime($end) - strtotime((string) $r['created_at'])) / 86400, 1)) : xs(''),
            xs($r['referred_to'] ?? ''),
        ]));
    }

    // ---- Escalations to outside offices
    $sheet(t('Escalations', 'Mga escalation'), [t('Complaint ID', 'ID ng Sumbong'), t('Category', 'Kategorya'), t('Escalated to', 'In-escalate sa'),
        t('Date', 'Petsa'), t('Note', 'Tala')], [16, 26, 28, 17, 60]);
    foreach ($reports as $r) {
        if (!empty($r['referred_to'])) {
            $w->addRow(new Row([xs($r['tracking_id'] ?? ''), xs(category_label((string) $r['category'])), xs($r['referred_to']),
                xd($r['referred_at'] ?? null, $when), xs($r['referral_note'] ?? '')]));
        }
    }

    // ---- Tanod activity
    $sheet(t('Tanod activity', 'Gawain ng tanod'), ['Tanod', t('Complaint', 'Sumbong'), t('Assigned', 'Na-assign'), t('Accepted', 'Tinanggap'),
        t('Outcome', 'Kinalabasan')], [28, 16, 17, 17, 18]);
    foreach ($dispatches as $d) {
        $w->addRow(new Row([xs(formal_or($d['tanod']['full_name'] ?? null, t('Unknown', 'Hindi kilala'))), xs($d['report']['tracking_id'] ?? ''),
            xd($d['assigned_at'] ?? null, $when), $d['accepted_at'] ? xd($d['accepted_at'], $when) : xs(t('Not accepted', 'Hindi tinanggap')),
            xs(status_label((string) $d['state']))]));
    }

    // ---- Case timeline
    $sheet(t('Case timeline', 'Takbo ng kaso'), [t('When', 'Kailan'), t('Complaint', 'Sumbong'), t('Change', 'Pagbabago'), t('By', 'Ni'),
        t('Remark', 'Puna'), t('Times', 'Ulit')], [17, 16, 34, 26, 60, 8]);
    foreach ($logs as $l) {
        $w->addRow(new Row([xd($l['created_at'] ?? null, $when), xs($l['report']['tracking_id'] ?? ''), xs(timeline_title($l)),
            xs(!empty($l['is_system']) ? t('System', 'System') : name_or($l['by']['full_name'] ?? null, t('Barangay staff', 'Kawani ng barangay'))),
            xs($l['remark'] ?? ''), new NumericCell((int) ($l['repeat'] ?? 1))]));
    }

    // ---- About this file
    $sheet(t('About', 'Tungkol'), [t('Report Summary', 'Buod ng mga Ulat'), ''], [26, 70]);
    foreach ([
        [t('Barangay', 'Barangay'), brgy_line()],
        [t('Period', 'Panahon'), $from->format('Y-m-d') . t(' to ', ' hanggang ') . $to->format('Y-m-d')],
        [t('Category', 'Kategorya'), $category !== '' ? category_label($category) : t('All', 'Lahat')],
        [t('Made', 'Ginawa'), (new DateTimeImmutable('now', new DateTimeZone('Asia/Manila')))->format('Y-m-d H:i')],
        [t('By', 'Ni'), formal_or($admin['full_name'] ?? null, t('Barangay staff', 'Kawani ng barangay'))],
        [t('Note', 'Tala'), t('The same rows as the Report Summary page. Complaint text is not included; anonymous residents are not named.',
                             'Kapareho ng mga hanay sa pahina ng Buod ng mga Ulat. Walang teksto ng sumbong; hindi pinangangalanan ang mga hindi nagpakilala.')],
    ] as [$k, $v]) {
        $w->addRow(new Row([xs($k), xs($v)]));
    }
    if ($truncated) {
        $w->addRow(new Row([xs(t('Incomplete', 'Hindi kumpleto')), xs(t('More rows than the limit; choose a shorter period.', 'Mas maraming hanay kaysa sa hangganan; pumili ng mas maikling panahon.'))]));
    }

    $w->close();
    exit;
}
