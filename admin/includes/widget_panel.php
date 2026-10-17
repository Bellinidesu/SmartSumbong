<?php
/**
 * The Workspace widget panel (17 Oct 2026): the slim rail of widgets the signed-in person chose, the pane of the one
 * open, and the alarm takeover above. All 120 widgets live in assets/js/widgets-*.js and read widgets.php; this only
 * draws the frame and hands the page what it needs (the person's tabs, the words, the catalogue, the CSRF token).
 */
declare(strict_types=1);

require_once __DIR__ . '/widgets.php';
require_once __DIR__ . '/widget_labels.php';

/** Which script holds each widget. */
function widget_module(string $id, string $group): string
{
    if (in_array($id, ['news', 'fuel'], true) || $group === 'rss') return 'rss';
    if ($id === 'mood') return 'team';
    return $group;
}

function render_widget_panel(Supabase $db, array $admin, ?string $solo = null): void
{
    $cat = widget_catalogue();
    $labels = widget_labels();
    $row = null;
    try {
        $r = $db->select('workspace_prefs', ['select' => 'tabs,tab,mine', 'user_id' => 'eq.' . $admin['id'], 'limit' => '1']);
        $row = $r[0] ?? null;
    } catch (SupabaseError) { /* the defaults show, and saving tries again */ }

    $tabs = array_values(array_filter((array) ($row['tabs'] ?? WS_DEFAULT_TABS), static fn ($id) => isset($cat[$id])));
    if (!$tabs) $tabs = WS_DEFAULT_TABS;
    $tab = (string) ($row['tab'] ?? '');
    if (!in_array($tab, $tabs, true)) $tab = $tabs[0];
    if ($solo !== null && isset($cat[$solo])) {   // the library's preview: this widget only, and nothing is saved
        $tabs = [$solo];
        $tab = $solo;
    } else {
        $solo = null;
    }

    $js = [];
    $catOut = [];
    foreach ($cat as $id => [$group, $status, $needs]) {
        $mod = widget_module($id, $group);
        $js[$mod] = 'assets/js/widgets-' . $mod . '.js?v=' . asset_version('../js/widgets-' . $mod . '.js');
        $catOut[$id] = ['g' => $group, 'n' => $needs, 'm' => $mod, 'x' => $status === 'new' ? 1 : 0];
    }
    $cfg = [
        'solo'     => $solo !== null,
        'lang'     => lang(),
        'csrf'     => csrf_token(),
        'tabs'     => $tabs,
        'tab'      => $tab,
        'defaults' => WS_DEFAULT_TABS,
        'cat'      => $catOut,
        'labels'   => $labels,
        'groups'   => widget_group_labels(),
        'mods'     => $js,
        'mine'     => is_array($row['mine'] ?? null) && $row['mine'] ? $row['mine'] : new stdClass(),
        'me'       => ['id' => $admin['id'], 'name' => display_name((string) ($admin['full_name'] ?? ''))],
    ];
    ?>
<section class="wsx<?= $solo !== null ? ' is-solo' : '' ?>" id="wsx" aria-label="<?= e(t('Your widgets', 'Iyong mga widget')) ?>">
  <div id="wsx-alarm" hidden></div>
  <div class="wx-card">
    <nav class="wx-rail" aria-label="<?= e(t('Widgets', 'Mga widget')) ?>">
      <div class="wx-rail-list" role="tablist" aria-orientation="vertical"></div>
      <button type="button" class="wx-add" data-act="library" aria-haspopup="dialog"><svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" aria-hidden="true"><path d="M12 5v14M5 12h14"/></svg><span><?= e(t('Widgets', 'Mga widget')) ?></span></button>
    </nav>
    <div class="wx-main">
      <header class="wx-phead">
        <h2 class="wx-ptitle"></h2>
        <span class="wx-pago" aria-live="off"></span>
        <button type="button" class="wx-rf" data-act="refresh" aria-label="<?= e(t('Refresh this widget', 'I-refresh ang widget na ito')) ?>" title="<?= e(t('Refresh', 'I-refresh')) ?>"><svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M20 11a8 8 0 0 0-14-4L4 9M4 4v5h5M4 13a8 8 0 0 0 14 4l2-2M20 20v-5h-5"/></svg></button>
      </header>
      <div class="wx-pane" id="wxp" role="tabpanel" tabindex="0"></div>
      <footer class="wx-pfoot"><span class="wx-foot-src"></span></footer>
    </div>
  </div>
</section>
<script>window.SS_WS = <?= json_encode($cfg, JSON_UNESCAPED_UNICODE | JSON_HEX_TAG | JSON_HEX_AMP) ?>;</script>
<link rel="stylesheet" href="assets/css/widgets.css?v=<?= e(asset_version('widgets.css')) ?>">
<link rel="stylesheet" href="assets/css/widgets-x.css?v=<?= e(asset_version('widgets-x.css')) ?>">
<script src="assets/js/widgets-core.js?v=<?= e(asset_version('../js/widgets-core.js')) ?>" defer></script>
<?php
}
