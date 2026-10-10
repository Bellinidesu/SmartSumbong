/* Free camera for Spatial Distribution: look at the map from any angle, not locked to north-up and a 58 degree tilt.
 *   right-drag, or Ctrl + left-drag   turn and tilt          (two fingers twisting on a phone)
 *   Shift + arrow keys                turn and tilt
 *   the compass button                back to north (it already does)
 * On by default; spatial.php?free=0 puts the old locks back, ?free=all also lifts the 183 border and the zoom limits so you can fly outside it.
 * (The Tilt button still goes to its own 58 degrees; this only takes the locks off.) */
(function () {
  'use strict';
  if (typeof map === 'undefined' || typeof mapReady === 'undefined') return;
  var q = new URLSearchParams(location.search).get('free');
  if (q === '0') return;
  var all = q === 'all';
  mapReady.then(function () {
    try {
      map.dragRotate._pitchWithRotate = true;   // no public setter: the map was made with pitchWithRotate off, and enable() reads this
      map.dragRotate.disable();
      map.dragRotate.enable();
      map.touchZoomRotate.enableRotation();
      map.touchPitch.enable();
      map.keyboard.enableRotation();
      map.setMaxPitch(85);                 // the default is 60: straight along the street needs more
      map.setMaxZoom(all ? 22 : 20);       // street level, a little past the tiles' own 18 (they overzoom)
      if (all) { map.setMaxBounds(null); map.setMinZoom(11); }
      if (location.search.indexOf('bounds') < 0) console.info('[sd-free] free camera on: right-drag or Ctrl+drag to turn and tilt' + (all ? '; border and zoom limits lifted' : ''));
    } catch (e) { console.warn('[sd-free]', e); }
  });
})();
