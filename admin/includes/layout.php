<?php
/**
 * Shared chrome. Every protected page calls layout_head() and
 * layout_foot() around its own markup.
 *
 * Nav items and their order follow the Figma sidebar exactly.
 */
declare(strict_types=1);

function nav_items(): array
{
    return [
        ['dashboard.php',  'Dashboard',           'chart'],
        ['summary.php',    'Report Summary',      'doc'],
        ['spatial.php',    'Spatial Distribution','map'],
        ['cases.php',      'Case Reports',        'chat'],
        ['residents.php',  'Residents',           'users'],
        ['personnel.php',  'Personnel',           'user'],
        ['profile.php',    'Edit Profile',        'gear'],
    ];
}

function nav_icon(string $name): string
{
    $paths = [
        'chart' => '<path d="M3 3v18h18"/><rect x="7" y="10" width="3" height="7"/><rect x="12" y="6" width="3" height="11"/><rect x="17" y="13" width="3" height="4"/>',
        'doc'   => '<path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><polyline points="14 2 14 8 20 8"/>',
        'map'   => '<polygon points="1 6 8 3 16 6 23 3 23 18 16 21 8 18 1 21"/><line x1="8" y1="3" x2="8" y2="18"/><line x1="16" y1="6" x2="16" y2="21"/>',
        'chat'  => '<path d="M21 11.5a8.4 8.4 0 0 1-9 8.4 8.5 8.5 0 0 1-3.8-.9L3 21l1.9-5.2A8.4 8.4 0 0 1 12 3a8.4 8.4 0 0 1 9 8.5z"/>',
        'users' => '<path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M23 21v-2a4 4 0 0 0-3-3.9"/>',
        'user'  => '<path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2"/><circle cx="12" cy="7" r="4"/>',
        'gear'  => '<circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-2.9 1.2 2 2 0 1 1-4 0 1.7 1.7 0 0 0-2.9-1.2l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1A1.7 1.7 0 0 0 3 15a2 2 0 1 1 0-4 1.7 1.7 0 0 0 1.5-2.6l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1A1.7 1.7 0 0 0 10 4.6a2 2 0 1 1 4 0 1.7 1.7 0 0 0 2.9 1.2l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1A1.7 1.7 0 0 0 21 11a2 2 0 1 1 0 4z"/>',
        'out'   => '<path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4"/><polyline points="16 17 21 12 16 7"/><line x1="21" y1="12" x2="9" y2="12"/>',
        'search'=> '<circle cx="11" cy="11" r="8"/><line x1="21" y1="21" x2="16.65" y2="16.65"/>',
    ];
    $d = $paths[$name] ?? '';
    return '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" '
         . 'stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' . $d . '</svg>';
}

function layout_head(string $title, string $active = ''): void
{
    $admin = current_admin();
    ?><!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title><?= e($title) ?> — Smart Sumbong</title>
<link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/css/bootstrap.min.css" rel="stylesheet">
<link href="https://fonts.googleapis.com/css2?family=Poppins:wght@400;500;600;700&family=Roboto:wght@400;500;700&display=swap" rel="stylesheet">
<link href="assets/css/app.css" rel="stylesheet">
</head>
<body>
<div class="shell">
  <nav class="sidebar">
    <a class="brand" href="dashboard.php">
      <?php if (is_file(__DIR__ . '/../assets/img/logo-wordmark.png')): ?>
        <img src="assets/img/logo-wordmark.png" alt="Smart Sumbong">
      <?php else: ?>
        <div class="brand-fallback">Sm<span>art</span>Sumbong</div>
      <?php endif; ?>
    </a>

    <?php foreach (nav_items() as [$href, $label, $icon]): ?>
      <a class="nav-item<?= basename($href) === $active ? ' active' : '' ?>" href="<?= e($href) ?>">
        <?= nav_icon($icon) ?><span><?= e($label) ?></span>
      </a>
    <?php endforeach; ?>

    <div class="nav-spacer"></div>

    <a class="nav-item" href="logout.php"><?= nav_icon('out') ?><span>Log out</span></a>
  </nav>

  <main class="main">
<?php
}

function layout_foot(): void
{
    ?>
  </main>
</div>
<script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/js/bootstrap.bundle.min.js"></script>
</body>
</html>
<?php
}

/** Human labels for the enum values the database stores. */
function status_label(string $s): string
{
    return ucwords(str_replace('_', ' ', $s));
}

function status_class(string $s): string
{
    return match ($s) {
        'pending_review'        => 'pending',
        'validated'             => 'validated',
        'assigned'              => 'assigned',
        'in_progress',
        'offline_investigation' => 'progress',
        'resolved'              => 'resolved',
        'closed', 'archived'    => 'closed',
        'rejected'              => 'rejected',
        default                 => 'pending',
    };
}

function category_label(string $c): string
{
    return ucwords(str_replace('_', ' ', $c));
}

function short_date(?string $iso): string
{
    if (!$iso) return '';
    try {
        return (new DateTimeImmutable($iso))
            ->setTimezone(new DateTimeZone('Asia/Manila'))
            ->format('m/d/y');
    } catch (Exception) {
        return '';
    }
}

function relative_time(?string $iso): string
{
    if (!$iso) return '';
    try {
        $then = new DateTimeImmutable($iso);
    } catch (Exception) {
        return '';
    }
    $mins = (int) round((time() - $then->getTimestamp()) / 60);
    if ($mins < 1)    return 'Just now';
    if ($mins < 60)   return "{$mins} min ago";
    if ($mins < 1440) return floor($mins / 60) . ' hr ago';
    return $then->setTimezone(new DateTimeZone('Asia/Manila'))->format('M j \a\t g:i A');
}
