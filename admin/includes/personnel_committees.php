<?php
/**
 * Personnel by committee and the punch card (0153; docs/ROLES_AND_PAGES.md, "Personnel").
 *
 * A Kagawad proposes a tanod for their committee and a super admin approves (a super admin's own assignment is approved at once).
 * A tanod can be in several committees, each with its own role for them. Kagawads and staff get an automatic punch card: their
 * portal sign-ins and sign-outs and the cases they touched each day. The database decides who sees what; this file draws it.
 *
 *   tc_by_tanod($rows)           personnel_committees() keyed by tanod
 *   tc_pills($row)               a tanod's committees as pills, and the committee of the case they are on
 *   render_tc_strip()            above the list: proposals waiting (super admin), or propose a tanod (Kagawad)
 *   render_tc_card()             on a tanod's page: their committees, with what the viewer may change
 *   personnel_tabs($on)          Tanods | Committee staff
 *   render_punch_page($db)       the Committee staff tab: the punch cards
 */
declare(strict_types=1);

require_once __DIR__ . '/forwarding.php';

/** @return array<string, array{committees: list<array{key:string,status:string,role:?string}>, busy: ?string}> */
function tc_by_tanod(mixed $rows): array
{
    $out = [];
    foreach (is_array($rows) ? $rows : [] as $r) {
        $out[(string) $r['tanod_id']] = ['committees' => (array) ($r['committees'] ?? []), 'busy' => $r['busy_committee'] ?? null];
    }
    return $out;
}

/** One committee of a tanod: in its colour, with the committee's role for them; a proposal is dashed. */
function tc_pill(array $c): string
{
    $k = (string) $c['key'];
    $name = (string) (committees_all()[$k]['short_en'] ?? $k);
    $role = trim((string) ($c['role'] ?? ''));
    $prop = ($c['status'] ?? '') === 'proposed';
    return '<span class="cm-pill' . ($prop ? ' cm-prop' : '') . '" style="--cc:' . e(committee_colour($k)) . '" title="' . e($name . ($role !== '' ? ' · ' . $role : '')) . '"><i></i>'
        . e($name) . ($role !== '' ? '<small>' . e($role) . '</small>' : '') . ($prop ? '<small>' . e(t('proposed', 'iminungkahi')) . '</small>' : '') . '</span>';
}

/** A tanod's committees, and "On a case" with that case's committee (other committees see the pill, never the case). */
function tc_pills(?array $row): string
{
    $o = '';
    foreach ((array) ($row['committees'] ?? []) as $c) { $o .= tc_pill($c); }
    if ($o === '') {
        $o = '<span class="p-sub">' . e(is_scoped() ? '—' : t('No committee', 'Walang komite')) . '</span>';
    }
    if (!empty($row['busy'])) {
        $o .= '<span class="tc-busy">' . e(t('On a case:', 'May kaso:')) . ' ' . committee_pill((string) $row['busy']) . '</span>';
    }
    return '<div class="tc-pills">' . $o . '</div>';
}

/** Personnel's Committees column: at most two lines, so every row is as tall as the next; the rest is "+N more" (names in its tooltip). tcPills() in the list's script mirrors this. */
function tc_list_pills(?array $row): string
{
    $cs = array_values((array) ($row['committees'] ?? []));
    if (!$cs) return '<div class="tc-pills"><span class="p-sub">' . e(is_scoped() ? '—' : t('No committee', 'Walang komite')) . '</span></div>';
    $show = count($cs) > 2 ? 1 : count($cs);
    $o = '';
    foreach (array_slice($cs, 0, $show) as $c) { $o .= tc_pill($c); }
    if (count($cs) > $show) {
        $rest = array_map(fn ($c) => (string) (committees_all()[(string) $c['key']]['short_en'] ?? $c['key']), array_slice($cs, $show));
        $o .= '<span class="cm-more" title="' . e(implode(', ', $rest)) . '">+' . count($rest) . ' ' . e(t('more', 'pa')) . '</span>';
    }
    return '<div class="tc-pills">' . $o . '</div>';
}

/** Tanods | Committee staff, for the people who see both. */
function personnel_tabs(string $on): string
{
    if (!(is_super() || is_captain() || is_committee())) return '';
    $tabs = ['' => t('Tanods', 'Mga Tanod'), 'staff' => is_committee() ? t('My staff', 'Aking mga kawani') : t('Committee staff', 'Mga kawani ng komite')];
    if (is_committee()) { $tabs['retire'] = t('Retirement requests', 'Mga hiling magretiro'); }
    $o = '<nav class="st-tabs tc-tabs" aria-label="' . e(t('Personnel', 'Mga Tanod')) . '">';
    foreach ($tabs as $k => $label) {
        $o .= '<a class="st-link' . ($on === $k ? ' p-on' : '') . '" href="personnel.php' . ($k !== '' ? '?view=' . $k : '') . '"' . ($on === $k ? ' aria-current="page"' : '') . '>' . e($label) . '</a>';
    }
    return $o . '</nav>';
}

/** Above the list: a super admin's proposals to decide, or a Kagawad's form to propose a tanod for their committee. */
function render_tc_strip(Supabase $db, array $tc, array $accounts): void
{
    $names = array_column($accounts, 'full_name', 'id');
    if (is_super()) {
        $waiting = [];
        foreach ($tc as $tid => $row) {
            foreach ($row['committees'] as $c) { if (($c['status'] ?? '') === 'proposed') $waiting[] = [$tid, $c]; }
        }
        if (!$waiting) return; ?>
      <div class="p-card p-card-pad tc-strip" id="tc-waiting">
        <p class="p-eyebrow"><?= e(t('Tanods proposed for a committee', 'Mga tanod na iminungkahi para sa komite')) ?> · <?= count($waiting) ?></p>
        <?php foreach ($waiting as [$tid, $c]): ?>
          <form method="post" class="tc-row">
            <input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>"><input type="hidden" name="id" value="<?= e($tid) ?>">
            <input type="hidden" name="action" value="tc_decide"><input type="hidden" name="committee" value="<?= e($c['key']) ?>"><input type="hidden" name="to_list" value="1">
            <b><?= e(formal_name((string) ($names[$tid] ?? ''))) ?></b><?= tc_pill($c) ?>
            <label class="p-sr" for="tcn-<?= e($tid . $c['key']) ?>"><?= e(t('Note (optional)', 'Paalala (opsyonal)')) ?></label>
            <input class="p-input-plain" id="tcn-<?= e($tid . $c['key']) ?>" name="note" maxlength="300" placeholder="<?= e(t('Note (optional)', 'Paalala (opsyonal)')) ?>">
            <button class="p-btn p-btn-success p-btn-sm" type="submit" name="decision" value="approve"><?= e(t('Approve', 'Aprubahan')) ?></button>
            <button class="p-btn p-btn-danger-soft p-btn-sm" type="submit" name="decision" value="deny"><?= e(t('Decline', 'Tanggihan')) ?></button>
          </form>
        <?php endforeach; ?>
      </div>
    <?php return;
    }
    if (!is_committee()) return;
    $myCom = (string) (current_admin()['committee'] ?? '');
    try { $pick = (array) $db->rpc('tanod_pick_list'); } catch (SupabaseError) { $pick = []; }
    $pick = array_values(array_filter($pick, fn ($p) => !isset($tc[(string) $p['id']]))); ?>
      <details class="p-card p-card-pad tc-strip" id="tc-propose">
        <summary><?= e(sprintf(t('Propose a tanod for %s', 'Magmungkahi ng tanod para sa %s'), (string) (committees_all()[$myCom]['short_en'] ?? ''))) ?></summary>
        <?php if (!$pick): ?>
          <p class="p-hint"><?= e(t('Every active tanod is already in your committee or waiting for approval.', 'Nasa komite mo na o naghihintay ng pag-apruba ang bawat aktibong tanod.')) ?></p>
        <?php else: ?>
        <form method="post" class="tc-row">
          <input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>"><input type="hidden" name="action" value="tc_propose">
          <input type="hidden" name="committee" value="<?= e($myCom) ?>"><input type="hidden" name="to_list" value="1">
          <label class="p-sr" for="tc-who"><?= e(t('Tanod', 'Tanod')) ?></label>
          <select class="p-input-plain" id="tc-who" name="id" required><option value="" disabled selected><?= e(t('Choose a tanod', 'Pumili ng tanod')) ?></option>
            <?php foreach ($pick as $p): ?><option value="<?= e($p['id']) ?>"><?= e(formal_name((string) $p['full_name'])) ?></option><?php endforeach; ?></select>
          <label class="p-sr" for="tc-role"><?= e(t('Their role in the committee (optional)', 'Ang papel nila sa komite (opsyonal)')) ?></label>
          <input class="p-input-plain" id="tc-role" name="role" maxlength="60" placeholder="<?= e(t('Their role in the committee (optional)', 'Ang papel nila sa komite (opsyonal)')) ?>">
          <button class="p-btn p-btn-primary p-btn-sm" type="submit"><?= e(t('Send to the super admins', 'Ipadala sa mga super admin')) ?></button>
        </form>
        <p class="p-hint"><?= e(t('A super admin approves it. Until then the tanod shows here as proposed.', 'Aaprubahan ito ng isang super admin. Hanggang doon, makikita rito ang tanod bilang iminungkahi.')) ?></p>
        <?php endif; ?>
      </details>
    <?php
}

/** On a tanod's page: their committees, and the forms the viewer may use (a super admin: all; a Kagawad: their own committee). */
function render_tc_card(array $p, ?array $row): void
{
    $rows = (array) ($row['committees'] ?? []);
    $myCom = is_committee() ? (string) (current_admin()['committee'] ?? '') : '';
    $have = array_column($rows, 'key');
    $csrf = '<input type="hidden" name="csrf" value="' . e(csrf_token()) . '"><input type="hidden" name="id" value="' . e($p['id']) . '">'; ?>
        <div class="p-card p-card-pad" id="tc-card">
          <p class="p-eyebrow"><?= e(t('Committees', 'Mga komite')) ?></p>
          <?php if (!$rows): ?><p class="p-none-line"><?= e(t('Not in a committee yet. Only the super admins see this tanod.', 'Wala pa sa komite. Ang mga super admin lang ang nakakakita sa tanod na ito.')) ?></p><?php endif; ?>
          <?php foreach ($rows as $c): $mine = is_super() || $c['key'] === $myCom; ?>
            <div class="tc-line">
              <?= tc_pill($c) ?>
              <?php if ($mine && !is_captain()): ?>
                <form method="post" class="tc-row"><?= $csrf ?><input type="hidden" name="action" value="tc_propose"><input type="hidden" name="committee" value="<?= e($c['key']) ?>">
                  <label class="p-sr" for="tcr-<?= e($c['key']) ?>"><?= e(t('Role in the committee', 'Papel sa komite')) ?></label>
                  <input class="p-input-plain" id="tcr-<?= e($c['key']) ?>" name="role" maxlength="60" value="<?= e((string) ($c['role'] ?? '')) ?>" placeholder="<?= e(t('Role in the committee', 'Papel sa komite')) ?>">
                  <button class="p-btn p-btn-ghost p-btn-sm" type="submit"><?= e(t('Save role', 'I-save ang papel')) ?></button></form>
                <?php if (is_super() && ($c['status'] ?? '') === 'proposed'): ?>
                  <form method="post" class="tc-row"><?= $csrf ?><input type="hidden" name="action" value="tc_decide"><input type="hidden" name="committee" value="<?= e($c['key']) ?>">
                    <button class="p-btn p-btn-success p-btn-sm" type="submit" name="decision" value="approve"><?= e(t('Approve', 'Aprubahan')) ?></button>
                    <button class="p-btn p-btn-danger-soft p-btn-sm" type="submit" name="decision" value="deny"><?= e(t('Decline', 'Tanggihan')) ?></button></form>
                <?php else: ?>
                  <form method="post" class="tc-row"><?= $csrf ?><input type="hidden" name="action" value="tc_remove"><input type="hidden" name="committee" value="<?= e($c['key']) ?>">
                    <button class="p-btn p-btn-danger-soft p-btn-sm" type="submit"><?= e(($c['status'] ?? '') === 'proposed' ? t('Withdraw', 'Bawiin') : t('Take out of the committee', 'Alisin sa komite')) ?></button></form>
                <?php endif; ?>
              <?php endif; ?>
            </div>
          <?php endforeach; ?>
          <?php if (!empty($row['busy'])): ?><p class="p-hint tc-busy"><?= e(t('On a case now:', 'May kaso ngayon:')) ?> <?= committee_pill((string) $row['busy']) ?></p><?php endif; ?>
          <?php $free = is_super() ? array_diff_key(committees_active(), array_flip($have)) : ($myCom !== '' && !in_array($myCom, $have, true) ? [$myCom => (string) (committees_all()[$myCom]['short_en'] ?? $myCom)] : []); ?>
          <?php if ($free && !is_captain()): ?>
            <form method="post" class="tc-row tc-add"><?= $csrf ?><input type="hidden" name="action" value="tc_propose">
              <label class="p-sr" for="tc-com"><?= e(t('Committee', 'Komite')) ?></label>
              <select class="p-input-plain" id="tc-com" name="committee" required><?php foreach ($free as $k => $label): ?><option value="<?= e($k) ?>"><?= e($label) ?></option><?php endforeach; ?></select>
              <label class="p-sr" for="tc-newrole"><?= e(t('Role in the committee (optional)', 'Papel sa komite (opsyonal)')) ?></label>
              <input class="p-input-plain" id="tc-newrole" name="role" maxlength="60" placeholder="<?= e(t('Role in the committee (optional)', 'Papel sa komite (opsyonal)')) ?>">
              <button class="p-btn p-btn-primary p-btn-sm" type="submit"><?= e(is_super() ? t('Add to the committee', 'Idagdag sa komite') : t('Propose', 'Imungkahi')) ?></button>
            </form>
          <?php endif; ?>
        </div>
    <?php
}

/**
 * A Kagawad's Retirement requests tab (0157): their committee's tanods' requests (row level security keeps the rest out), to
 * read and to endorse to the super admins, who decide.
 */
function render_retire_page(Supabase $db): void
{
    $error = null;
    try { $rows = (array) $db->rpc('retirement_requests_queue'); } catch (SupabaseError $ex) { $rows = []; $error = safe_error($ex); }
    $flash = $_SESSION['flash'] ?? null; unset($_SESSION['flash']);
    layout_head(t('Personnel', 'Mga Tanod'), 'personnel.php'); ?>
    <div class="p-topbar"><h1><?= e(t('Personnel', 'Mga Tanod')) ?></h1></div>
    <?= personnel_tabs('retire') ?>
    <?php if ($flash): ?><div class="p-flash p-flash--<?= e($flash['level']) ?>" role="status"><?= e((string) $flash['text']) ?></div><?php endif; ?>
    <?php if ($error): ?><div class="p-flash p-flash--error" role="alert"><?= e($error) ?></div><?php endif; ?>
    <p class="p-hint tc-lede"><?= e(t('Your committee\'s tanods who asked to retire. You can endorse a request to the super admins; they decide.', 'Ang mga tanod ng iyong komite na humiling magretiro. Maaari mong i-endorso ang hiling sa mga super admin; sila ang magpapasya.')) ?></p>
    <div class="p-card p-table-card"><div class="p-tscroll"><table class="p-t" id="rt-k">
      <thead><tr><th scope="col">Tanod</th><th scope="col"><?= e(t('Asked', 'Humiling')) ?></th><th scope="col"><?= e(t('Status', 'Katayuan')) ?></th><th scope="col" class="p-right"><?= e(t('Your endorsement', 'Iyong pag-endorso')) ?></th></tr></thead>
      <tbody>
      <?php if (!$rows): ?><tr><td colspan="4" class="p-empty"><?= e(t('None of your committee\'s tanods has asked to retire.', 'Walang tanod ng iyong komite ang humiling magretiro.')) ?></td></tr><?php endif; ?>
      <?php foreach ($rows as $r): ?>
        <tr>
          <td><b><?= e(formal_name((string) $r['full_name'])) ?></b></td>
          <td class="p-num"><?= e(long_datetime((string) $r['requested_at'])) ?></td>
          <td><?= retirement_status_pill((string) $r['status']) ?></td>
          <td class="p-right">
            <?php if (!empty($r['endorsed_at'])): ?>
              <span class="p-badge p-b-progress" title="<?= e((string) ($r['endorse_note'] ?? '')) ?>"><?= e(sprintf(t('Endorsed by %s', 'In-endorso ni %s'), formal_name((string) ($r['endorsed_by_name'] ?? '')))) ?></span>
            <?php elseif ($r['status'] === 'pending'): ?>
              <form method="post" class="tc-row rt-endorse">
                <input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>"><input type="hidden" name="action" value="endorse_retire">
                <input type="hidden" name="request" value="<?= e($r['id']) ?>"><input type="hidden" name="to_view" value="retire">
                <label class="p-sr" for="rt-n-<?= e($r['id']) ?>"><?= e(t('Note for the super admins (optional)', 'Paalala para sa mga super admin (opsyonal)')) ?></label>
                <input class="p-input-plain" id="rt-n-<?= e($r['id']) ?>" name="note" maxlength="500" placeholder="<?= e(t('Note for the super admins (optional)', 'Paalala para sa mga super admin (opsyonal)')) ?>">
                <button class="p-btn p-btn-primary p-btn-sm" type="submit"><?= e(t('Endorse', 'I-endorso')) ?></button>
              </form>
            <?php else: ?><span class="p-sub">&mdash;</span><?php endif; ?>
          </td>
        </tr>
      <?php endforeach; ?>
      </tbody>
    </table></div></div>
    <?php layout_foot();
}

/** A time of day in Manila, or a dash. */
function punch_time(?string $iso): string
{
    if (!$iso) return '—';
    try { return (new DateTimeImmutable($iso))->setTimezone(new DateTimeZone('Asia/Manila'))->format('g:i A'); } catch (Exception) { return '—'; }
}

/** The Committee staff tab: every Kagawad's and staff member's punch card the viewer may see, by committee. */
function render_punch_page(Supabase $db): void
{
    $error = null;
    try { $cards = (array) $db->rpc('punch_cards', ['p_days' => 7, 'p_user' => null]); } catch (SupabaseError $ex) { $cards = []; $error = safe_error($ex); }
    $groups = [];
    foreach ($cards as $c) { $groups[(string) ($c['committee'] ?? '')][] = $c; }
    layout_head(t('Personnel', 'Mga Tanod'), 'personnel.php'); ?>
    <div class="p-topbar"><h1><?= e(t('Personnel', 'Mga Tanod')) ?></h1></div>
    <?= personnel_tabs('staff') ?>
    <?php if ($error): ?><div class="p-flash p-flash--error" role="alert"><?= e($error) ?></div><?php endif; ?>
    <p class="p-hint tc-lede"><?= e(t('The punch card fills itself: when each person signed in and out of the portal, and the cases they touched that day (status changes, taking a case, forwarding, messages).',
        'Kusang napupuno ang punch card: kung kailan nag-sign in at nag-sign out sa portal ang bawat isa, at ang mga kasong hinawakan nila sa araw na iyon (pagbabago ng katayuan, pagkuha ng kaso, pagpasa, mga mensahe).')) ?></p>
    <?php if (!$cards && !$error): ?><div class="p-card p-empty"><?= e(t('No Kagawad or staff yet.', 'Wala pang Kagawad o kawani.')) ?></div><?php endif; ?>
    <?php foreach ($groups as $ck => $people): ?>
      <section class="pc-group" aria-label="<?= e($ck !== '' ? (string) (committees_all()[$ck]['short_en'] ?? $ck) : t('No committee', 'Walang komite')) ?>">
        <div class="p-band"><h2><?= $ck !== '' ? committee_pill($ck) : e(t('No committee', 'Walang komite')) ?></h2></div>
        <div class="pc-grid">
        <?php foreach ($people as $c): $days = (array) ($c['days'] ?? []); $today = $days[0] ?? []; ?>
          <article class="p-card pc-card" id="pc-<?= e($c['id']) ?>">
            <header><b><?= e(formal_name((string) $c['name'])) ?></b><?= rank_chip(($c['tier'] ?? '') === 'committee' ? 'kagawad' : ($c['position'] ?? null)) ?></header>
            <div class="pc-today">
              <div><small><?= e(t('In today', 'Pasok ngayon')) ?></small><b><?= e(punch_time($today['first_in'] ?? null)) ?></b></div>
              <div><small><?= e(t('Out', 'Labas')) ?></small><b><?= e(!empty($today['first_in']) && empty($today['last_out']) ? t('Still in', 'Nasa loob pa') : punch_time($today['last_out'] ?? null)) ?></b></div>
              <div><small><?= e(t('Cases touched', 'Mga kasong hinawakan')) ?></small><b><?= (int) ($today['touched'] ?? 0) ?></b></div>
            </div>
            <details class="pc-week">
              <summary><?= e(t('Last 7 days', 'Nakaraang 7 araw')) ?></summary>
              <div class="p-tscroll"><table class="p-t pc-t">
                <thead><tr><th scope="col"><?= e(t('Day', 'Araw')) ?></th><th scope="col"><?= e(t('In', 'Pasok')) ?></th><th scope="col"><?= e(t('Out', 'Labas')) ?></th><th scope="col"><?= e(t('Cases', 'Mga kaso')) ?></th></tr></thead>
                <tbody>
                <?php foreach ($days as $d): ?>
                  <tr><td><?= e((new DateTimeImmutable((string) $d['day']))->format('D M j')) ?></td><td class="p-num"><?= e(punch_time($d['first_in'] ?? null)) ?></td><td class="p-num"><?= e(punch_time($d['last_out'] ?? null)) ?></td>
                    <td><?= (int) ($d['touched'] ?? 0) ?><?php if (!empty($d['cases'])): ?> <span class="p-sub"><?= e(implode(', ', array_slice((array) $d['cases'], 0, 6))) ?><?= count((array) $d['cases']) > 6 ? '…' : '' ?></span><?php endif; ?></td></tr>
                <?php endforeach; ?>
                </tbody>
              </table></div>
            </details>
          </article>
        <?php endforeach; ?>
        </div>
      </section>
    <?php endforeach; ?>
    <?php layout_foot();
}
