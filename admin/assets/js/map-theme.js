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

// Landmarks (branch B): the barangay hall, schools, chapels, police and
// fire posts, clinics, parks, malls, terminals — reference points an
// admin or tanod steers by ("two streets past the chapel"). From
// OpenStreetMap, fetched once and curated into assets/map/landmarks.geojson
// (edit that file to add or correct a place). Dots always; names from
// zoom 15.5, so the map stays readable zoomed out. Drawn under the
// complaint pins.
(function () {
  var COLOURS = ['match', ['get', 'group'],
    'hall', '#ff9800', 'school', '#7c3aed', 'worship', '#0891b2',
    'safety', '#dc2626', 'health', '#16a34a', 'park', '#65a30d',
    'shop', '#db2777', 'transport', '#475569', 'military', '#57534e',
    'government', '#1d4ed8', '#64748b'];
  function dark() { return document.documentElement.getAttribute('data-theme') === 'dark'; }

  window.mapLandmarks = function (map, opts) {
    opts = opts || {};
    function add() {
      if (map.getSource('landmarks')) return;
      map.addSource('landmarks', { type: 'geojson', data: 'assets/map/landmarks.geojson',
                                   attribution: '&copy; OpenStreetMap contributors' });
      var before = opts.before && map.getLayer(opts.before) ? opts.before : undefined;
      map.addLayer({ id: 'landmarks-dot', type: 'circle', source: 'landmarks',
        layout: { visibility: opts.hidden ? 'none' : 'visible' },
        paint: {
          'circle-radius': ['interpolate', ['linear'], ['zoom'], 14, 3.5, 18, 7],
          'circle-color': COLOURS,
          'circle-stroke-color': '#ffffff',
          'circle-stroke-width': 1.5,
        } }, before);
      map.addLayer({ id: 'landmarks-label', type: 'symbol', source: 'landmarks', minzoom: 15.5,
        layout: {
          visibility: opts.hidden ? 'none' : 'visible',
          'text-field': ['get', 'name'],
          'text-font': ['Noto Sans Bold'],
          'text-size': ['interpolate', ['linear'], ['zoom'], 15.5, 10.5, 18, 13],
          'text-offset': [0, 0.9],
          'text-anchor': 'top',
          'text-max-width': 9,
          'text-optional': true,
        },
        paint: {
          'text-color': dark() ? '#eaf0ff' : '#1f2937',
          'text-halo-color': dark() ? 'rgba(13,27,51,.9)' : 'rgba(255,255,255,.95)',
          'text-halo-width': 1.4,
        } }, before);
    }
    // isStyleLoaded() stays false while tiles are still arriving, even
    // inside the map's own load handler — so try, and wait only if the
    // style itself is not there yet.
    try { add(); } catch (e) { map.once('load', add); }
    window.addEventListener('themechange', function () {
      if (!map.getLayer('landmarks-label')) return;
      map.setPaintProperty('landmarks-label', 'text-color', dark() ? '#eaf0ff' : '#1f2937');
      map.setPaintProperty('landmarks-label', 'text-halo-color', dark() ? 'rgba(13,27,51,.9)' : 'rgba(255,255,255,.95)');
    });
    return {
      show: function (on) {
        ['landmarks-dot', 'landmarks-label'].forEach(function (id) {
          if (map.getLayer(id)) map.setLayoutProperty(id, 'visibility', on ? 'visible' : 'none');
        });
      },
    };
  };
})();

// Hazard overlay (branch B): Project NOAH's 100-year flood map and its
// worst-case storm surge (Storm Surge Advisory 4), clipped to Barangay
// 183 — open data from the UP NOAH Center (ODbL), in
// assets/map/hazards.geojson. NOAH's own colours for flood (yellow,
// orange, red for low, medium, high); purples for surge so the two read
// apart. Off until asked for; drawn under the heat, landmarks and pins.
(function () {
  var FILL = ['match', ['concat', ['get', 'hazard'], '-', ['to-string', ['get', 'level']]],
    'flood-1', '#facc15', 'flood-2', '#f97316', 'flood-3', '#dc2626',
    'surge-1', '#c4b5fd', 'surge-2', '#8b5cf6', 'surge-3', '#5b21b6', '#94a3b8'];
  var data = null;
  window.hazardData = function () {
    return data || (data = fetch('assets/map/hazards.geojson').then(function (r) { return r.json(); }));
  };

  window.mapHazards = function (map, opts) {
    opts = opts || {};
    function add() {
      if (map.getSource('hazards')) return;
      map.addSource('hazards', { type: 'geojson', data: 'assets/map/hazards.geojson',
                                 attribution: 'Hazard maps &copy; UP NOAH Center (Project NOAH)' });
      var before = opts.before && map.getLayer(opts.before) ? opts.before : undefined;
      map.addLayer({ id: 'hazard-fill', type: 'fill', source: 'hazards',
        layout: { visibility: opts.hidden ? 'none' : 'visible' },
        paint: { 'fill-color': FILL, 'fill-opacity': 0.38, 'fill-antialias': false } }, before);
    }
    try { add(); } catch (e) { map.once('load', add); }
    return {
      show: function (on) {
        if (map.getLayer('hazard-fill')) map.setLayoutProperty('hazard-fill', 'visibility', on ? 'visible' : 'none');
      },
    };
  };

  // Which hazard levels a point sits in: {flood: 0-3, surge: 0-3}.
  function inRing(ring, x, y) {
    var c = false;
    for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
      var xi = ring[i][0], yi = ring[i][1], xj = ring[j][0], yj = ring[j][1];
      if ((yi > y) !== (yj > y) && x < (xj - xi) * (y - yi) / (yj - yi) + xi) c = !c;
    }
    return c;
  }
  function inPolygon(poly, x, y) {
    if (!inRing(poly[0], x, y)) return false;
    for (var k = 1; k < poly.length; k++) if (inRing(poly[k], x, y)) return false;
    return true;
  }
  window.hazardAt = function (lng, lat) {
    return hazardData().then(function (fc) {
      var out = { flood: 0, surge: 0 };
      fc.features.forEach(function (f) {
        var g = f.geometry, polys = g.type === 'Polygon' ? [g.coordinates] : g.coordinates;
        if (polys.some(function (p) { return inPolygon(p, lng, lat); })) {
          var k = f.properties.hazard;
          out[k] = Math.max(out[k], f.properties.level);
        }
      });
      return out;
    });
  };
})();
