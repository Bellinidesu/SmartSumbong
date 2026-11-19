<?php
/**
 * The case hierarchy (19 Nov 2026, Rose; 0175): who holds a case, who may take it over, and who it may be assigned to.
 *
 *   super admin   accepts a case, assigns it to a councilor or a staff member, takes over from councilors and staff
 *   councilor     (Kagawad) accepts, assigns to their own staff, takes over from their staff, escalates to the super admins
 *   staff         is assigned a case by their councilor and accepts or declines it; escalates to the councilor
 *
 * The database decides all of it (assign_case, answer_case_assignment, take_over_case); this file only draws the same rules, so
 * the portal never shows a button the database would refuse.
 */
declare(strict_types=1);

/** The rung of the ladder an administrator's tier stands on: chair (the super admins), kagawad, staff. A null tier reads as super. */
function tier_rung(?string $tier): string
{
    return match ($tier ?? 'super') { 'committee' => 'kagawad', 'moderator' => 'staff', default => 'chair' };
}

/** A rung's name, as the ladder shows it. */
function rung_label(string $rung): string
{
    return match ($rung) {
        'chair'   => t('Chairman', 'Punong Barangay'),
        'kagawad' => t('Councilor', 'Kagawad'),
        'staff'   => t('Staff', 'Kawani'),
        default   => t('Tanod', 'Tanod'),
    };
}

/**
 * May the signed-in person take this case over from its handler? A super admin from anyone; a Kagawad only from the staff of
 * their own committee; staff never (take_over_case refuses the rest).
 */
function may_take_over_from(?array $handler): bool
{
    if (!is_super() && !is_committee()) return false;
    if (is_super()) return true;
    return ($handler['admin_tier'] ?? null) === 'moderator'
        && (string) ($handler['committee'] ?? '') !== ''
        && (string) ($handler['committee'] ?? '') === (string) (current_admin()['committee'] ?? '');
}

/** May the signed-in person assign cases at all (a super admin, a Kagawad)? Staff are assigned; a captain only reads. */
function may_assign(): bool
{
    return is_super() || is_committee();
}

/**
 * Where a case is, from who actually holds it: ['rung' => chair|kagawad|staff, 'wait' => it waits for someone to accept it,
 * 'text' => one sentence naming who]. A tanod on the case is told apart by the page (it is not a rung anyone holds).
 */
function case_holder(array $r, string $me): array
{
    $name = static fn (?array $u): string => display_name((string) ($u['full_name'] ?? ''));   // a sentence: the casual name
    $com = (string) ($r['case_committee'] ?? '');
    $comName = $com !== '' ? (string) (committees_all()[$com]['short_en'] ?? $com) : '';
    if (!empty($r['assigned_to'])) {
        $rung = tier_rung($r['assignee']['admin_tier'] ?? null);
        if ((string) $r['assigned_to'] === $me) {
            return ['rung' => $rung, 'wait' => true, 'text' => t('Assigned to you, waiting for you to accept it', 'Itinalaga sa iyo, hinihintay na tanggapin mo')];
        }
        return ['rung' => $rung, 'wait' => true, 'text' => sprintf(t('Assigned to %s (%s), waiting for them to accept it', 'Itinalaga kay %s (%s), hinihintay na tanggapin niya'), $name($r['assignee'] ?? null), rung_label($rung))];
    }
    if (!empty($r['handler_id'])) {
        $rung = tier_rung($r['handler']['admin_tier'] ?? null);
        $who = (string) $r['handler_id'] === $me ? t('you', 'ikaw') : $name($r['handler'] ?? null);
        return ['rung' => $rung, 'wait' => false, 'text' => sprintf(t('With %s (%s)', 'Hawak ni %s (%s)'), $who, rung_label($rung))];
    }
    if (!empty($r['awaiting_placement']) || $com === '') {
        return ['rung' => 'chair', 'wait' => true, 'text' => t('With the super admins, to place with a committee', 'Nasa mga super admin, para ilagay sa isang komite')];
    }
    if ((int) ($r['tier'] ?? 0) >= 2) {
        return ['rung' => 'chair', 'wait' => true, 'text' => t('With the Chairman, waiting to be taken', 'Nasa Punong Barangay, hinihintay na kunin')];
    }
    return ['rung' => 'kagawad', 'wait' => true, 'text' => sprintf(t('With %s, waiting for its Kagawad to accept it', 'Nasa %s, hinihintay na tanggapin ng Kagawad nito'), $comName)];
}

/** The Assign picker's options from case_assignees(): councilors first, then staff, each under its committee's name. */
function assign_options(array $people): string
{
    $groups = [];
    foreach ($people as $p) {
        $com = (string) ($p['committee'] ?? '');
        $key = (($p['tier'] ?? '') === 'committee' ? 'k' : 's') . '|' . $com;
        $groups[$key][] = $p;
    }
    // councilors before staff; otherwise the database's order (the case's own committee first)
    $groups = array_filter($groups, static fn ($k) => $k[0] === 'k', ARRAY_FILTER_USE_KEY) + array_filter($groups, static fn ($k) => $k[0] === 's', ARRAY_FILTER_USE_KEY);
    $o = '';
    foreach ($groups as $key => $list) {
        [$kind, $com] = explode('|', $key, 2);
        $comName = $com !== '' ? (string) (committees_all()[$com]['short_en'] ?? $com) : '';
        $label = ($kind === 'k' ? t('Councilors', 'Mga Kagawad') : t('Staff', 'Mga kawani')) . ($comName !== '' ? ' · ' . $comName : '');
        $o .= '<optgroup label="' . e($label) . '">';
        foreach ($list as $p) {
            $o .= '<option value="' . e((string) $p['id']) . '">' . e(formal_name((string) $p['full_name'])) . (!empty($p['is_test']) ? ' · TEST' : '') . '</option>';
        }
        $o .= '</optgroup>';
    }
    return $o;
}
