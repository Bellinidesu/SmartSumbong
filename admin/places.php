<?php
/**
 * The barangay's places (0134): what search finds that no map has, by the names residents and tanods use.
 *
 * 15 Nov 2026 (Ace): this list moved out of Settings. It is a button on the side of Spatial Distribution, which opens it in a panel; this page is what that panel
 * loads and where its forms post, then it sends the person back to Spatial Distribution. A super admin's to keep (access.php).
 *
 *   places.php?part=1        the list, as a piece of HTML for the panel
 *   POST place_save / place_remove    as before; back to spatial.php?places=1
 */
declare(strict_types=1);

require_once __DIR__ . '/includes/auth.php';
require_once __DIR__ . '/includes/layout.php';

$admin = require_admin();
$db    = db();
session_start_once();

if ($_SERVER['REQUEST_METHOD'] === 'POST' && in_array($_POST['action'] ?? '', ['place_save', 'place_remove'], true)) {
    if (!csrf_check($_POST['csrf'] ?? null)) {
        $_SESSION['st_flash'] = ['level' => 'error', 'text' => t('That form expired. Please try again.', 'Nag-expire ang form. Subukan muli.')];
    } else {
        try {
            if ($_POST['action'] === 'place_remove') {
                $db->rpc('place_remove', ['p_id' => (int) ($_POST['id'] ?? 0)]);
                $_SESSION['st_flash'] = ['level' => 'info', 'text' => t('Removed. Search no longer finds it.', 'Inalis. Hindi na ito mahahanap.')];
            } else {
                $aliases = array_values(array_filter(array_map('trim', explode(',', (string) ($_POST['aliases'] ?? ''))), fn ($a) => $a !== ''));
                $db->rpc('place_save', ['p_id' => (int) ($_POST['id'] ?? 0) ?: null, 'p_name' => trim((string) ($_POST['name'] ?? '')),
                    'p_grp' => (string) ($_POST['grp'] ?? ''), 'p_lat' => (float) ($_POST['lat'] ?? 0), 'p_lng' => (float) ($_POST['lng'] ?? 0),
                    'p_aliases' => array_slice($aliases, 0, 8)]);
                $_SESSION['st_flash'] = ['level' => 'info', 'text' => t('Saved. Search finds it now.', 'Na-save. Mahahanap na ito.')];
            }
        } catch (SupabaseError $ex) {
            $_SESSION['st_flash'] = ['level' => 'error', 'text' => safe_error($ex)];
        }
    }
    header('Location: spatial.php?places=1', true, 303);
    exit;
}

$places = []; $kinds = []; $error = null;
try {
    $got = $db->selectMany([
        'places' => ['places', ['select' => 'id,name,grp,aliases,lat,lng', 'source' => 'eq.barangay', 'active' => 'eq.true', 'order' => 'name.asc', 'limit' => '200'], true],
        'kinds'  => ['place_kinds', ['select' => 'grp,label', 'order' => 'label.asc'], true],
    ]);
    $places = is_array($got['places'] ?? null) ? $got['places'] : [];
    $kinds  = is_array($got['kinds'] ?? null) ? $got['kinds'] : [];
} catch (SupabaseError $ex) { $error = safe_error($ex); }
$flash = $_SESSION['st_flash'] ?? null; unset($_SESSION['st_flash']);

header('Content-Type: text/html; charset=utf-8'); header('Cache-Control: no-store');
?>
<div class="st-places" id="places">
  <?php if ($flash && !empty($flash['text'])): ?><div class="p-flash p-flash--<?= ($flash['level'] ?? '') === 'error' ? 'error' : 'ok' ?>" role="status"><?= e((string) $flash['text']) ?></div><?php endif; ?>
  <?php if ($error): ?><div class="p-flash p-flash--error" role="alert"><?= e($error) ?></div><?php endif; ?>
  <p class="p-eyebrow"><?= e(t('The barangay\'s places', 'Mga lugar ng barangay')) ?><em><?= count($places) ?></em></p>
  <p class="st-note" style="margin-top:0"><?= e(t('Search on the map and in the app finds these first: the landmarks the barangay keeps, and any place no map has, by the names people use (Other names, separated by commas). To add one, right-click the spot on the map (or press and hold), and choose Add a place here. Places only, never anyone’s home.', 'Ito ang unang nahahanap sa mapa at sa app: ang mga landmark ng barangay, at anumang lugar na wala sa mapa, sa pangalang ginagamit ng mga tao (Ibang pangalan, pinaghihiwalay ng kuwit). Para magdagdag, i-right-click ang lugar sa mapa (o pindutin nang matagal), at piliin ang Magdagdag ng lugar dito. Mga lugar lamang, hindi kailanman ang bahay ng sinuman.')) ?></p>
  <?php if (!$places): ?>
    <p class="st-note"><?= e(t('No places yet, or they could not be read just now.', 'Wala pang lugar, o hindi mabasa ngayon.')) ?></p>
  <?php else: ?>
  <ul class="st-plist">
    <?php foreach ($places as $pl): ?>
      <li>
        <form method="post" action="places.php" class="st-prow">
          <input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>"><input type="hidden" name="action" value="place_save">
          <input type="hidden" name="id" value="<?= (int) $pl['id'] ?>"><input type="hidden" name="lat" value="<?= e((string) $pl['lat']) ?>"><input type="hidden" name="lng" value="<?= e((string) $pl['lng']) ?>">
          <label class="p-sr" for="pl-n-<?= (int) $pl['id'] ?>"><?= e(t('Name', 'Pangalan')) ?></label>
          <input class="p-input-plain" id="pl-n-<?= (int) $pl['id'] ?>" name="name" maxlength="120" required value="<?= e((string) $pl['name']) ?>">
          <label class="p-sr" for="pl-k-<?= (int) $pl['id'] ?>"><?= e(t('Kind', 'Uri')) ?></label>
          <select class="p-input-plain" id="pl-k-<?= (int) $pl['id'] ?>" name="grp"><?php foreach ($kinds as $k): ?><option value="<?= e((string) $k['grp']) ?>"<?= $k['grp'] === $pl['grp'] ? ' selected' : '' ?>><?= e((string) $k['label']) ?></option><?php endforeach; ?></select>
          <label class="p-sr" for="pl-a-<?= (int) $pl['id'] ?>"><?= e(t('Other names', 'Ibang pangalan')) ?></label>
          <input class="p-input-plain" id="pl-a-<?= (int) $pl['id'] ?>" name="aliases" maxlength="300" placeholder="<?= e(t('Other names', 'Ibang pangalan')) ?>" value="<?= e(implode(', ', (array) ($pl['aliases'] ?? []))) ?>">
          <button class="p-btn p-btn-ghost p-btn-sm" type="submit"><?= e(t('Save', 'I-save')) ?></button>
        </form>
        <form method="post" action="places.php" class="st-prm">
          <input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>"><input type="hidden" name="action" value="place_remove"><input type="hidden" name="id" value="<?= (int) $pl['id'] ?>">
          <button class="p-btn p-btn-ghost p-btn-sm" type="submit" aria-label="<?= e(t('Remove ', 'Alisin ang ') . $pl['name']) ?>"><?= e(t('Remove', 'Alisin')) ?></button>
        </form>
      </li>
    <?php endforeach; ?>
  </ul>
  <?php endif; ?>
</div>
