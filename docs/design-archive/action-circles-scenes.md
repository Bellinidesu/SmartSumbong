# Archived: the action circles with their little worlds

Spatial Distribution, case card (9-10 Oct 2026). Four circular actions, each with a scene drawn behind its icon:

- Dispatch: a mini map with a dashed route that marches on hover
- Zoom here: street blocks with a lens that tightens on hover and swells on press
- Look around: a street at night with a glowing horizon
- Copy ID: two stacked sheets that slide apart on hover

They were replaced by gradient circles. To bring the scenes back:

    git show archive/action-circles-scenes:admin/spatial.php      # ACT_SCENE, the scenes' SVG
    git show archive/action-circles-scenes:admin/assets/css/flair.css   # the ".bgx" rules

Tagged at commit c71da7b (tag: archive/action-circles-scenes).
