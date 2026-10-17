<?php
/**
 * One widget on its own, with live data: the preview behind the View button in the widget library. The same panel as the Workspace,
 * without the rail, and it never saves the person's own widgets. widget-view.php?w=flood
 */
declare(strict_types=1);

require_once __DIR__ . '/includes/auth.php';
require_once __DIR__ . '/includes/layout.php';
require_once __DIR__ . '/includes/widget_panel.php';

$admin = require_admin();
$id = (string) ($_GET['w'] ?? '');
if (!isset(widget_catalogue()[$id])) {
    http_response_code(404);
    exit;
}
?><!DOCTYPE html>
<html lang="<?= html_lang() ?>">
<head>
<meta charset="utf-8">
<?= theme_head(false) ?>
<meta name="viewport" content="width=device-width, initial-scale=1">
<link href="assets/css/fonts.css?v=<?= e(asset_version('fonts.css')) ?>" rel="stylesheet">
<link href="assets/css/p.css?v=<?= e(asset_version('p.css')) ?>" rel="stylesheet">
<link href="assets/css/p-portal.css?v=<?= e(asset_version('p-portal.css')) ?>" rel="stylesheet">
<link href="assets/css/flair.css?v=<?= e(asset_version('flair.css')) ?>" rel="stylesheet">
<link href="assets/css/widget-view.css?v=<?= e(asset_version('widget-view.css')) ?>" rel="stylesheet">
</head>
<body class="p-body wsv">
<?php render_widget_panel(db(), $admin, $id); ?>
</body>
</html>
