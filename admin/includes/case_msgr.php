<?php
/**
 * The Inbox's Case chats, drawn the way Messenger's web app is (12 Nov 2026, Ace: "case chats fully imitate Messenger, one to one"):
 * a column of conversations on the left (search, filter chips, one row per person with the last words and an unread dot), the open
 * conversation in the middle (header, the thread in grouped bubbles with the other person's small picture, a time between
 * runs of messages, the composer with the emoji button and the thumbs-up that becomes Send), and the conversation info on the
 * right (who, the case, mute, search, media). The data is the chat head's (report_messages, dispatch_updates); sending goes
 * through the same two case actions, so the handler lock still applies. Only what is true is drawn: no "seen", no typing, no
 * reactions, because nothing records them.
 */
declare(strict_types=1);

require_once __DIR__ . '/case_chat.php';

/** Messenger's time label: the time today, the weekday and time within a week, else the date and time (Manila). */
function msgr_stamp(string $iso): string
{
    $tz = new DateTimeZone('Asia/Manila');
    $d = (new DateTimeImmutable($iso))->setTimezone($tz);
    $now = new DateTimeImmutable('now', $tz);
    $days = (int) $d->setTime(0, 0)->diff($now->setTime(0, 0))->format('%r%a');
    if ($days <= 0) return $d->format('g:i A');
    if ($days < 7) return $d->format('D g:i A');
    return $d->format($d->format('Y') === $now->format('Y') ? 'M j, g:i A' : 'M j, Y, g:i A');
}

/** What a row of the list shows for the time: the hour today, the weekday this week, else the date. */
function msgr_short(string $iso): string
{
    $tz = new DateTimeZone('Asia/Manila');
    $d = (new DateTimeImmutable($iso))->setTimezone($tz);
    $now = new DateTimeImmutable('now', $tz);
    $days = (int) $d->setTime(0, 0)->diff($now->setTime(0, 0))->format('%r%a');
    if ($days <= 0) return $d->format('g:i A');
    if ($days < 7) return $d->format('D');
    return $d->format('M j');
}

function msgr_avatar(string $name, string $kind, string $size = ''): string
{
    return '<span class="mg-av mg-av--' . e($kind) . ($size !== '' ? ' mg-av--' . e($size) : '') . '" aria-hidden="true">' . e(case_chat_initials($name)) . '</span>';
}

/** The left column's rows. */
function msgr_list(array $rows, string $selKey): string
{
    ob_start();
    foreach ($rows as $r):
        $sel = $r['key'] === $selKey;
        $href = 'inbox.php?app=chats&c=' . e($r['case']) . '&k=' . e($r['conv']); ?>
      <a class="mg-conv<?= $sel ? ' mg-sel' : '' ?>" href="<?= $href ?>" data-mg-row data-key="<?= e($r['key']) ?>" data-report="<?= e($r['case']) ?>" data-conv="<?= e($r['conv']) ?>"
         data-mine="<?= $r['mine'] ? '1' : '0' ?>" data-search="<?= e(mb_strtolower($r['name'] . ' ' . $r['tracking'] . ' ' . $r['subject'])) ?>" data-feed="<?= e((string) json_encode($r['feed'])) ?>"<?= $sel ? ' aria-current="true"' : '' ?>>
        <?= msgr_avatar($r['name'], $r['kind'], 'lg') ?>
        <span class="mg-ctext">
          <span class="mg-cname"><b><?= e($r['name']) ?></b><span class="mg-ctag"><?= e($r['tracking']) ?></span></span>
          <span class="mg-cprev"><span class="mg-ctxt"><?= $r['out'] ? e(t('You: ', 'Ikaw: ')) : '' ?><?= e($r['text']) ?></span><span class="mg-ctime">· <?= e(msgr_short($r['last'])) ?></span></span>
        </span>
        <i class="mg-udot" hidden aria-hidden="true"></i><span class="p-sr mg-usr" hidden><?= e(t('Unread', 'Hindi pa nababasa')) ?></span>
      </a>
    <?php endforeach;
    return (string) ob_get_clean();
}

/** The middle: the thread's messages (also what the live refresh swaps). */
function msgr_messages(array $conv, array $report, string $caseId): string
{
    $name = $conv['name'];
    ob_start(); ?>
      <div class="mg-intro">
        <?= msgr_avatar($name, $conv['kind'], 'xl') ?>
        <b class="mg-iname"><?= e($name) ?></b>
        <span class="mg-isub"><?= e($conv['sub']) ?> · <?= e((string) ($report['tracking_id'] ?? '')) ?></span>
        <a class="mg-ibtn" href="case.php?id=<?= e($caseId) ?>"><?= e(t('Open the case', 'Buksan ang kaso')) ?></a>
      </div>
      <?php
      $items = $conv['items']; $lastTs = null;
      foreach ($items as $i => $it) {
          $ts = strtotime($it['ts']) ?: 0;
          if ($lastTs === null || $ts - $lastTs > 3600) { echo '<div class="mg-sep">' . e(msgr_stamp($it['ts'])) . '</div>'; }
          $lastTs = $ts;
          if ($it['type'] === 'sys') { echo '<div class="mg-sys" data-ts="' . e($it['ts']) . '">' . e($it['text']) . ' · ' . e(case_chat_clock($it['ts'])) . '</div>'; continue; }
          $prev = $items[$i - 1] ?? null; $next = $items[$i + 1] ?? null;
          $sameP = $prev && $prev['type'] === 'msg' && $prev['out'] === $it['out'] && $ts - (strtotime($prev['ts']) ?: 0) < 3600;
          $sameN = $next && $next['type'] === 'msg' && $next['out'] === $it['out'] && (strtotime($next['ts']) ?: 0) - $ts < 3600;
          $pos = $sameP ? ($sameN ? 'mid' : 'last') : ($sameN ? 'first' : 'only');
          $full = (new DateTimeImmutable($it['ts']))->setTimezone(new DateTimeZone('Asia/Manila'))->format('l, F j, Y \a\t g:i A');
          echo '<div class="mg-row ' . ($it['out'] ? 'mg-out' : 'mg-in') . ' mg-' . $pos . '" data-ts="' . e($it['ts']) . '"' . ($it['out'] ? '' : ' data-in="1"') . '>';
          if (!$it['out']) echo ($pos === 'last' || $pos === 'only') ? msgr_avatar($name, $conv['kind'], 'sm') : '<span class="mg-avsp"></span>';
          echo '<div class="mg-b' . (trim($it['body']) === '' ? ' mg-b--ph' : '') . '" title="' . e($full) . '">';
          if (trim($it['body']) !== '') echo '<p>' . nl2br(e($it['body'])) . '</p>';
          foreach ($it['media'] as $url) {
              echo '<a class="mg-ph" href="' . e($url) . '" target="_blank" rel="noopener"><img src="' . e(cld_thumb($url, 480)) . '" alt="' . e(t('Photo in the chat', 'Larawan sa usapan')) . '" loading="lazy"></a>';
          }
          echo '</div>';
          if (trim($it['body']) !== '') echo '<button type="button" class="mg-more" data-mg="copy" aria-label="' . e(t('Copy this message', 'Kopyahin ang mensaheng ito')) . '" title="' . e(t('Copy', 'Kopyahin')) . '"><svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect x="9" y="9" width="11" height="11" rx="2"/><path d="M5 15V5a2 2 0 0 1 2-2h10"/></svg></button>';
          echo '</div>';
      }
      if (!$items) echo '<p class="mg-none">' . e(t('No messages yet. Say hello.', 'Wala pang mensahe. Magsimula ng usapan.')) . '</p>';
    return (string) ob_get_clean();
}

/** The composer: the emoji button inside the field, and the thumbs-up that becomes Send once there is text. */
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
          <textarea name="body" rows="1" maxlength="<?= (int) $conv['max'] ?>" placeholder="Aa" aria-label="<?= e($conv['ph']) ?>"></textarea>
          <button type="button" class="mg-emoji" data-mg="emoji" aria-label="<?= e(t('Choose an emoji', 'Pumili ng emoji')) ?>" aria-haspopup="dialog"><svg viewBox="0 0 24 24" width="22" height="22" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" aria-hidden="true"><circle cx="12" cy="12" r="9"/><path d="M8.5 14.2c.9 1.1 2 1.7 3.5 1.7s2.6-.6 3.5-1.7"/><circle cx="9" cy="10" r=".6" fill="currentColor"/><circle cx="15" cy="10" r=".6" fill="currentColor"/></svg></button>
        </div>
        <button type="submit" class="mg-send" aria-label="<?= e(t('Send a thumbs-up', 'Magpadala ng thumbs-up')) ?>" data-like="<?= e(t('Send a thumbs-up', 'Magpadala ng thumbs-up')) ?>" data-send="<?= e(t('Send', 'Ipadala')) ?>">
          <svg class="mg-i-like" viewBox="0 0 24 24" width="26" height="26" fill="currentColor" aria-hidden="true"><path d="M2 11.5A1.5 1.5 0 0 1 3.5 10H6v10H3.5A1.5 1.5 0 0 1 2 18.5v-7zM8 10l3.4-6.3A1.6 1.6 0 0 1 14 4.4V9h5.3a2 2 0 0 1 1.96 2.4l-1.5 7.2A2 2 0 0 1 17.8 20H8V10z"/></svg>
          <svg class="mg-i-send" viewBox="0 0 24 24" width="22" height="22" fill="currentColor" aria-hidden="true"><path d="M3.4 20.4 21 12 3.4 3.6 3.3 10l12.6 2-12.6 2z"/></svg>
        </button>
      </form>
    <?php endif;
    return (string) ob_get_clean();
}

/** The right: who this is, the case, and what a person can do with the conversation. */
function msgr_info(array $conv, array $report, array $evidence, string $caseId): string
{
    $name = $conv['name'];
    $photos = [];
    foreach ($conv['items'] as $it) { if ($it['type'] === 'msg') foreach ($it['media'] as $u) $photos[] = $u; }
    if ($conv['kind'] === 'resident') foreach ($evidence as $m) { if (str_starts_with((string) ($m['mime_type'] ?? ''), 'image')) $photos[] = (string) $m['media_url']; }
    $photos = array_slice(array_values(array_unique($photos)), 0, 9);
    ob_start(); ?>
      <div class="mg-ihead">
        <?= msgr_avatar($name, $conv['kind'], 'xxl') ?>
        <b class="mg-iname2"><?= e($name) ?></b>
        <span class="mg-isub"><?= e($conv['sub']) ?></span>
        <div class="mg-iacts">
          <a class="mg-iact" href="case.php?id=<?= e($caseId) ?>"><span class="mg-ic"><svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M7 3h7l5 5v13H7z"/><path d="M14 3v5h5"/></svg></span><span><?= e(t('Case', 'Kaso')) ?></span></a>
          <button type="button" class="mg-iact" data-mg="mute" aria-pressed="false"><span class="mg-ic"><svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M6 8a6 6 0 0 1 12 0c0 7 3 8 3 8H3s3-1 3-8"/><path d="M10 20a2 2 0 0 0 4 0"/><path class="mg-slash" d="M3 3l18 18"/></svg></span><span data-mute-l><?= e(t('Mute', 'I-mute')) ?></span></button>
          <button type="button" class="mg-iact" data-mg="find"><span class="mg-ic"><svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true"><circle cx="11" cy="11" r="7"/><path d="M20 20l-4-4"/></svg></span><span><?= e(t('Search', 'Hanapin')) ?></span></button>
        </div>
      </div>
      <details class="mg-sec" open>
        <summary><?= e(t('Chat info', 'Impormasyon ng chat')) ?></summary>
        <dl class="mg-dl">
          <dt><?= e(t('Case', 'Kaso')) ?></dt><dd><?= e((string) ($report['tracking_id'] ?? '')) ?></dd>
          <dt><?= e(t('About', 'Tungkol sa')) ?></dt><dd><?= e((string) ($report['subject'] ?? '')) ?></dd>
          <dt><?= e(t('Status', 'Katayuan')) ?></dt><dd><?= e(status_label((string) ($report['status'] ?? ''))) ?></dd>
          <?php if (!empty($report['handler']['full_name'])): ?><dt><?= e(t('Handled by', 'Hawak ni')) ?></dt><dd><?= e((string) $report['handler']['full_name']) ?></dd><?php endif; ?>
          <?php if ($conv['kind'] === 'resident' && !empty($report['resident']['mobile_number'])): ?><dt><?= e(t('Mobile number', 'Numero ng cellphone')) ?></dt><dd><?= e((string) $report['resident']['mobile_number']) ?></dd><?php endif; ?>
        </dl>
      </details>
      <details class="mg-sec" open>
        <summary><?= e(t('Media and files', 'Media at mga file')) ?></summary>
        <?php if (!$photos): ?><p class="mg-hint"><?= e(t('No photos in this chat yet.', 'Wala pang larawan sa chat na ito.')) ?></p>
        <?php else: ?><div class="mg-media"><?php foreach ($photos as $u): ?><a href="<?= e($u) ?>" target="_blank" rel="noopener"><img src="<?= e(cld_thumb($u, 240, true)) ?>" alt="<?= e(t('Photo', 'Larawan')) ?>" loading="lazy"></a><?php endforeach; ?></div><?php endif; ?>
      </details>
      <details class="mg-sec">
        <summary><?= e(t('Privacy and support', 'Privacy at suporta')) ?></summary>
        <p class="mg-hint"><?= !empty($report['is_anonymous'])
            ? e(t('The resident filed as anonymous: only the barangay office sees the name. Tanods, the map and the printouts do not.', 'Hindi nagpakilala ang residente: ang opisina lang ng barangay ang nakakakita ng pangalan. Hindi ito nakikita ng mga tanod, ng mapa at ng mga print.'))
            : e(t('Messages here are kept with the case. The resident sees the barangay\'s answers in their app; the tanod sees theirs in the field.', 'Nakatala sa kaso ang mga mensahe rito. Nakikita ng residente ang mga sagot ng barangay sa app niya; nakikita ng tanod ang sa kanya sa lugar.')) ?></p>
      </details>
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
        <a class="mg-back" href="inbox.php?app=chats" data-mg="back" aria-label="<?= e(t('Back to chats', 'Bumalik sa mga chat')) ?>"><svg viewBox="0 0 24 24" width="22" height="22" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M15 5l-7 7 7 7"/></svg></a>
        <?= msgr_avatar($conv['name'], $conv['kind']) ?>
        <span class="mg-ctitle"><b><?= e($conv['name']) ?></b><small><?= e($conv['sub']) ?> · <?= e((string) ($report['tracking_id'] ?? '')) ?></small></span>
        <button type="button" class="mg-infobtn" data-mg="info" aria-pressed="true" aria-label="<?= e(t('Conversation information', 'Impormasyon ng usapan')) ?>"><svg viewBox="0 0 24 24" width="24" height="24" fill="currentColor" aria-hidden="true"><path d="M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20zm1 15h-2v-6h2v6zm0-8h-2V7h2v2z"/></svg></button>
      </header>
      <div class="mg-find" hidden><input type="search" class="mg-findin" placeholder="<?= e(t('Search in conversation', 'Hanapin sa usapan')) ?>" aria-label="<?= e(t('Search in conversation', 'Hanapin sa usapan')) ?>"><button type="button" class="mg-findx" data-mg="findx" aria-label="<?= e(t('Close search', 'Isara ang paghahanap')) ?>">✕</button></div>
      <div class="mg-msgs" role="log" aria-live="polite" aria-label="<?= e(t('Messages', 'Mga mensahe')) ?>" tabindex="0"><?= msgr_messages($conv, $report, $caseId) ?></div>
      <?= msgr_composer($conv, $caseId) ?>
    </section>
    <aside class="mg-info" aria-label="<?= e(t('Conversation information', 'Impormasyon ng usapan')) ?>"><?= msgr_info($conv, $report, $load['evidence'], $caseId) ?></aside>
    <?php
    return (string) ob_get_clean();
}
