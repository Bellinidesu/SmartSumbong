// Map colours that follow the portal's light/dark switch (branch B).
// The two styles are the apps' own (assets/map/style-{light,dark}.json):
// the same 55 layers, only their paint differs. So a switch repaints the
// base map in place — map.setStyle() would throw away the complaint pins,
// heat and hotspot layers and the pin images added on top of it.
(function () {
  function current() {
    return document.documentElement.getAttribute('data-theme') === 'dark' ? 'dark' : 'light';
  }
  window.mapStyleUrl = function () { return 'assets/map/style-' + current() + '.json'; };

  var cache = {};
  function load(url) { return cache[url] || (cache[url] = fetch(url).then(function (r) { return r.json(); })); }

  window.mapFollowTheme = function (map) {
    window.addEventListener('themechange', function () {
      load(window.mapStyleUrl()).then(function (style) {
        style.layers.forEach(function (l) {
          if (!map.getLayer(l.id)) return;
          Object.keys(l.paint || {}).forEach(function (k) { map.setPaintProperty(l.id, k, l.paint[k]); });
        });
      });
    });
  };
})();
