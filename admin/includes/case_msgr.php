<?php
/**
 * The Inbox's Case chats (12 Nov 2026, Ace: "Messenger one to one, but the looks from Apple").
 *
 * What Messenger does, in Apple's Messages look: a sidebar of conversations (a search field, a segmented filter, one row per person with a
 * round picture, the last words, the time and a blue dot when unread, the open one filled blue); the conversation in the middle (the
 * person centred over the thread, blue bubbles for the barangay and grey for them, tails on the last bubble of a run, the day in bold
 * before the time, a pill field that grows with an emoji button, and an arrow that appears with the first letter); and Details on the
 * right (grouped lists, "Hide Alerts" as a switch, the photos). The data is the chat head's (report_messages, dispatch_updates);
 * sending goes through the same two case actions, so the handler lock still applies. Only what is true is drawn: no "Delivered",
 * "Read", typing dots or reactions, because nothing records them.
 */
declare(strict_types=1);

require_once __DIR__ . '/case_chat.php';

/** The day and time between runs of messages, Messages style: "Today 9:41 AM", "Thursday 10:41 AM", "Nov 5, 10:41 AM" (Manila time). */
function msgr_sepline(string $iso): string
{
    $tz = new DateTimeZone('Asia/Manila');
    $d = (new DateTimeImmutable($iso))->setTimezone($tz);
    $now = new DateTimeImmutable('now', $tz);
    $days = (int) $d->setTime(0, 0)->diff($now->setTime(0, 0))->format('%r%a');
    $time = $d->format('g:i A');
    if ($days <= 0) return '<b>' . e(t('Today', 'Ngayon')) . '</b> ' . e($time);
    if ($days === 1) return '<b>' . e(t('Yesterday', 'Kahapon')) . '</b> ' . e($time);
    if ($days < 7) return '<b>' . e($d->format('l')) . '</b> ' . e($time);
    return '<b>' . e($d->format($d->format('Y') === $now->format('Y') ? 'M j' : 'M j, Y')) . '</b> ' . e($time);
}

/** What a row of the list shows for the time: the hour today, "Yesterday", the weekday this week, else the date. */
function msgr_short(string $iso): string
{
    $tz = new DateTimeZone('Asia/Manila');
    $d = (new DateTimeImmutable($iso))->setTimezone($tz);
    $now = new DateTimeImmutable('now', $tz);
    $days = (int) $d->setTime(0, 0)->diff($now->setTime(0, 0))->format('%r%a');
    if ($days <= 0) return $d->format('g:i A');
    if ($days === 1) return t('Yesterday', 'Kahapon');
    if ($days < 7) return $d->format('l');
    return $d->format('n/j/y');
}

function msgr_avatar(string $name, string $kind, string $size = ''): string
{
    return '<span class="mg-av mg-av--' . e($kind) . ($size !== '' ? ' mg-av--' . e($size) : '') . '" aria-hidden="true">' . e(case_chat_initials($name)) . '</span>';
}

/** The sidebar's rows. */
function msgr_list(array $rows, string $selKey): string
{
    ob_start();
    foreach ($rows as $r):
        $sel = $r['key'] === $selKey;
        $href = 'inbox.php?app=chats&c=' . e($r['case']) . '&k=' . e($r['conv']); ?>
      <a class="mg-conv<?= $sel ? ' mg-sel' : '' ?>" href="<?= $href ?>" data-mg-row data-key="<?= e($r['key']) ?>" data-report="<?= e($r['case']) ?>" data-conv="<?= e($r['conv']) ?>"
         data-mine="<?= $r['mine'] ? '1' : '0' ?>" data-search="<?= e(mb_strtolower($r['name'] . ' ' . $r['tracking'] . ' ' . $r['subject'])) ?>" data-feed="<?= e((string) json_encode($r['feed'])) ?>"<?= $sel ? ' aria-current="true"' : '' ?>>
        <i class="mg-udot" hidden aria-hidden="true"></i><span class="p-sr mg-usr" hidden><?= e(t('Unread', 'Hindi pa nababasa')) ?></span>
        <?= msgr_avatar($r['name'], $r['kind'], 'lg') ?>
        <span class="mg-ctext">
          <span class="mg-cname"><b><?= e($r['name']) ?></b><time><?= e(msgr_short($r['last'])) ?></time></span>
          <span class="mg-ctag"><?= e($r['tracking']) ?></span>
          <span class="mg-cprev"><?= $r['out'] ? e(t('You: ', 'Ikaw: ')) : '' ?><?= e($r['text']) ?></span>
        </span>
      </a>
    <?php endforeach;
    return (string) ob_get_clean();
}

/** The thread's messages (also what the live refresh swaps): grouped bubbles with a day and time between runs. */
function msgr_messages(array $conv, array $report, string $caseId): string
{
    ob_start();
    $items = $conv['items']; $lastTs = null;
    foreach ($items as $i => $it) {
        $ts = strtotime($it['ts']) ?: 0;
        if ($lastTs === null || $ts - $lastTs > 3600) { echo '<div class="mg-sep">' . msgr_sepline($it['ts']) . '</div>'; }
        $lastTs = $ts;
        if ($it['type'] === 'sys') { echo '<div class="mg-sys" data-ts="' . e($it['ts']) . '">' . e($it['text']) . ' · ' . e(case_chat_clock($it['ts'])) . '</div>'; continue; }
        $prev = $items[$i - 1] ?? null; $next = $items[$i + 1] ?? null;
        $sameP = $prev && $prev['type'] === 'msg' && $prev['out'] === $it['out'] && $ts - (strtotime($prev['ts']) ?: 0) < 3600;
        $sameN = $next && $next['type'] === 'msg' && $next['out'] === $it['out'] && (strtotime($next['ts']) ?: 0) - $ts < 3600;
        $pos = $sameP ? ($sameN ? 'mid' : 'last') : ($sameN ? 'first' : 'only');
        $full = (new DateTimeImmutable($it['ts']))->setTimezone(new DateTimeZone('Asia/Manila'))->format('l, F j, Y \a\t g:i A');
        echo '<div class="mg-row ' . ($it['out'] ? 'mg-out' : 'mg-in') . ' mg-' . $pos . '" data-ts="' . e($it['ts']) . '"' . ($it['out'] ? '' : ' data-in="1"') . '>';
        echo '<div class="mg-b' . (trim($it['body']) === '' ? ' mg-b--ph' : '') . '" title="' . e($full) . '">';
        if (trim($it['body']) !== '') echo '<p>' . nl2br(e($it['body'])) . '</p>';
        foreach ($it['media'] as $url) {
            echo '<a class="mg-ph" href="' . e($url) . '" target="_blank" rel="noopener"><img src="' . e(cld_thumb($url, 480)) . '" alt="' . e(t('Photo in the chat', 'Larawan sa usapan')) . '" loading="lazy"></a>';
        }
        echo '</div>';
        if (trim($it['body']) !== '') echo '<button type="button" class="mg-more" data-mg="copy" aria-label="' . e(t('Copy this message', 'Kopyahin ang mensaheng ito')) . '" title="' . e(t('Copy', 'Kopyahin')) . '"><svg viewBox="0 0 24 24" width="15" height="15" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect x="9" y="9" width="11" height="11" rx="2"/><path d="M5 15V5a2 2 0 0 1 2-2h10"/></svg></button>';
        echo '</div>';
    }
    if (!$items) echo '<p class="mg-none">' . e(t('No messages yet.', 'Wala pang mensahe.')) . '</p>';
    return (string) ob_get_clean();
}

/** The composer: a pill field with the emoji button inside, and the blue arrow that appears with the first letter. */
function msgr_composer(array $conv, string $caseId): string
{
    ob_start();
    if (!$conv['open']): ?>
      <p class="mg-closed"><?= e($conv['closed']) ?></p>
    <?php else: ?>
      <form method="post" action="case.php?id=<?= e(urlencode($caseId)) ?>" class="mg-form" data-mg="form">
        <input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>"><input type="hidden" name="action" value="<?= e($conv['action']) ?>">
        <?php if ($conv['dispatch'] !== ''): ?><input type="hidden" name="dispatch" value="<?= e($conv['dispatch']) ?>"><?php endif; ?>
        <div class="mg-input">
          <textarea name="body" rows="1" maxlength="<?= (int) $conv['max'] ?>" placeholder="<?= e($conv['ph']) ?>" aria-label="<?= e($conv['ph']) ?>"></textarea>
          <button type="button" class="mg-emoji" data-mg="emoji" aria-label="<?= e(t('Choose an emoji', 'Pumili ng emoji')) ?>" aria-haspopup="dialog"><svg viewBox="0 0 24 24" width="22" height="22" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" aria-hidden="true"><circle cx="12" cy="12" r="9"/><path d="M8.5 14.2c.9 1.1 2 1.7 3.5 1.7s2.6-.6 3.5-1.7"/><circle cx="9" cy="10" r=".6" fill="currentColor"/><circle cx="15" cy="10" r=".6" fill="currentColor"/></svg></button>
          <button type="submit" class="mg-send" aria-label="<?= e(t('Send', 'Ipadala')) ?>"><svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12 19V5M5 12l7-7 7 7"/></svg></button>
        </div>
      </form>
    <?php endif;
    return (string) ob_get_clean();
}

/** Details, on the right: who this is, then grouped lists the way Apple draws them. */
function msgr_info(array $conv, array $report, array $evidence, string $caseId): string
{
    $name = $conv['name'];
    $photos = [];
    foreach ($conv['items'] as $it) { if ($it['type'] === 'msg') foreach ($it['media'] as $u) $photos[] = $u; }
    if ($conv['kind'] === 'resident') foreach ($evidence as $m) { if (str_starts_with((string) ($m['mime_type'] ?? ''), 'image')) $photos[] = (string) $m['media_url']; }
    $photos = array_slice(array_values(array_unique($photos)), 0, 9);
    ob_start(); ?>
      <div class="mg-ihead">
        <?= msgr_avatar($name, $conv['kind'], 'xl') ?>
        <b class="mg-iname2"><?= e($name) ?></b>
        <span class="mg-isub"><?= e($conv['sub']) ?></span>
      </div>
      <ul class="mg-grp">
        <li class="mg-li"><span><?= e(t('Hide Alerts', 'Itago ang mga alerto')) ?></span>
          <button type="button" class="mg-sw" role="switch" aria-checked="false" data-mg="mute" aria-label="<?= e(t('Hide Alerts for this case', 'Itago ang mga alerto para sa kasong ito')) ?>"><i></i></button></li>
        <li class="mg-li mg-li--btn"><button type="button" data-mg="find"><?= e(t('Search in conversation', 'Hanapin sa usapan')) ?></button></li>
        <li class="mg-li mg-li--btn"><a href="case.php?id=<?= e($caseId) ?>"><?= e(t('Open the case', 'Buksan ang kaso')) ?></a></li>
      </ul>
      <p class="mg-gh"><?= e(t('Case', 'Kaso')) ?></p>
      <dl class="mg-grp mg-dl">
        <div class="mg-li"><dt><?= e(t('Number', 'Numero')) ?></dt><dd><?= e((string) ($report['tracking_id'] ?? '')) ?></dd></div>
        <div class="mg-li"><dt><?= e(t('About', 'Tungkol sa')) ?></dt><dd><?= e((string) ($report['subject'] ?? '')) ?></dd></div>
        <div class="mg-li"><dt><?= e(t('Status', 'Katayuan')) ?></dt><dd><?= e(status_label((string) ($report['status'] ?? ''))) ?></dd></div>
        <?php if (!empty($report['handler']['full_name'])): ?><div class="mg-li"><dt><?= e(t('Handled by', 'Hawak ni')) ?></dt><dd><?= e((string) $report['handler']['full_name']) ?></dd></div><?php endif; ?>
        <?php if ($conv['kind'] === 'resident' && !empty($report['resident']['mobile_number'])): ?><div class="mg-li"><dt><?= e(t('Mobile number', 'Numero ng cellphone')) ?></dt><dd><?= e((string) $report['resident']['mobile_number']) ?></dd></div><?php endif; ?>
      </dl>
      <p class="mg-gh"><?= e(t('Photos', 'Mga larawan')) ?></p>
      <?php if (!$photos): ?><p class="mg-hint"><?= e(t('No photos in this chat yet.', 'Wala pang larawan sa chat na ito.')) ?></p>
      <?php else: ?><div class="mg-media"><?php foreach ($photos as $u): ?><a href="<?= e($u) ?>" target="_blank" rel="noopener"><img src="<?= e(cld_thumb($u, 240, true)) ?>" alt="<?= e(t('Photo', 'Larawan')) ?>" loading="lazy"></a><?php endforeach; ?></div><?php endif; ?>
      <p class="mg-hint mg-hint--foot"><?= !empty($report['is_anonymous'])
          ? e(t('The resident filed as anonymous: only the barangay office sees the name. Tanods, the map and the printouts do not.', 'Hindi nagpakilala ang residente: ang opisina lang ng barangay ang nakakakita ng pangalan. Hindi ito nakikita ng mga tanod, ng mapa at ng mga print.'))
          : e(t('Messages here are kept with the case. The resident sees the barangay\'s answers in their app; the tanod sees theirs in the field.', 'Nakatala sa kaso ang mga mensahe rito. Nakikita ng residente ang mga sagot ng barangay sa app niya; nakikita ng tanod ang sa kanya sa lugar.')) ?></p>
    <?php
    return (string) ob_get_clean();
}

/** The middle and the right for one open conversation: what the page and the "open this conversation" call both return. */
function msgr_detail(array $load, string $convId, string $caseId): string
{
    $conv = null;
    foreach ($load['convs'] as $c) { if ($c['id'] === $convId) { $conv = $c; break; } }
    if ($conv === null) return '<div class="mg-blank"><b>' . e(t('That conversation is not here.', 'Wala ang usapang iyan.')) . '</b></div>';
    $report = $load['report'];
    ob_start(); ?>
    <section class="mg-center" aria-label="<?= e(t('Conversation with ', 'Usapan kay ') . $conv['name']) ?>" data-report="<?= e($caseId) ?>" data-conv="<?= e($convId) ?>" data-tracking="<?= e((string) ($report['tracking_id'] ?? '')) ?>" data-thread-url="inbox.php?app=chats&amp;part=thread&amp;c=<?= e($caseId) ?>&amp;k=<?= e($convId) ?>">
      <header class="mg-chead">
        <a class="mg-back" href="inbox.php?app=chats" data-mg="back" aria-label="<?= e(t('Back to messages', 'Bumalik sa mga mensahe')) ?>"><svg viewBox="0 0 24 24" width="22" height="22" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M15 5l-7 7 7 7"/></svg></a>
        <span class="mg-ctitle"><?= msgr_avatar($conv['name'], $conv['kind'], 'sm') ?><b><?= e($conv['name']) ?></b><small><?= e($conv['sub']) ?> · <?= e((string) ($report['tracking_id'] ?? '')) ?></small></span>
        <button type="button" class="mg-infobtn" data-mg="info" aria-pressed="true" aria-label="<?= e(t('Details', 'Mga detalye')) ?>"><svg viewBox="0 0 24 24" width="22" height="22" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" aria-hidden="true"><circle cx="12" cy="12" r="9"/><path d="M12 11v5"/><circle cx="12" cy="8" r=".7" fill="currentColor"/></svg></button>
      </header>
      <div class="mg-find" hidden><input type="search" class="mg-findin" placeholder="<?= e(t('Search in conversation', 'Hanapin sa usapan')) ?>" aria-label="<?= e(t('Search in conversation', 'Hanapin sa usapan')) ?>"><button type="button" class="mg-findx" data-mg="findx"><?= e(t('Done', 'Tapos na')) ?></button></div>
      <div class="mg-msgs" role="log" aria-live="polite" aria-label="<?= e(t('Messages', 'Mga mensahe')) ?>" tabindex="0"><?= msgr_messages($conv, $report, $caseId) ?></div>
      <?= msgr_composer($conv, $caseId) ?>
    </section>
    <aside class="mg-info" aria-label="<?= e(t('Details', 'Mga detalye')) ?>"><?= msgr_info($conv, $report, $load['evidence'], $caseId) ?></aside>
    <?php
    return (string) ob_get_clean();
}
