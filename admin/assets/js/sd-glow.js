// Spatial Distribution, City view: emissive light (Bellinist, 10 Oct 2026).
// MapLibre has no emissive material, so a lit window or a lamp can only ever look like a tinted wall. This draws them as lights:
// a custom WebGL layer that puts a soft sprite of light at every lit window and every street lamp, in the world, and adds it
// to the picture (additive blending), so a lit window shines past its own edge and the glow of a lamp spreads over the air round it.
// The sprites are depth tested against the buildings, so a wall hides the windows behind it. Nothing here moves: where each
// light is was worked out once, from the baked data (buildings.json: which buildings have their lights on; city-detail.json:
// the lamps), so the cost is one draw call of a few tens of thousands of points.
// sd-city.js hands it the data when the City view first opens and tells it when it is night.
(function () {
  'use strict';
  const ID = 'cd-emit';
  const VS = 'uniform mat4 u_m; uniform float u_scale; uniform float u_w0; uniform float u_fade; attribute vec3 a_pos; attribute vec4 a_col; attribute float a_size; varying vec4 v_col;' +
    'void main() { vec4 p = u_m * vec4(a_pos, 1.0); gl_Position = p; float px = a_size * u_scale * u_w0 / max(p.w, 0.0001); gl_PointSize = clamp(px, 1.0, 160.0); v_col = vec4(a_col.rgb, a_col.a * u_fade * clamp(px / 4.0, 0.0, 1.0)); }';
  const FS = 'precision mediump float; varying vec4 v_col; void main() { float d = length(gl_PointCoord - vec2(0.5)) * 2.0; if (d > 1.0) discard;' +
    'float halo = pow(1.0 - d, 2.4); float core = 1.0 - smoothstep(0.0, 0.34, d); vec3 c = v_col.rgb * (halo * v_col.a + core * v_col.a * 0.9); gl_FragColor = vec4(c, 1.0); }';
  const hash = (a, b) => { const x = Math.sin(a * 12.9898 + b * 78.233) * 43758.5453; return x - Math.floor(x); };
  const MX = 107500, MY = 110574;
  let pts = null, count = 0, buf = null, prog = null, loc = null, mapRef = null, scaleM = 1;

  // Where the lights are: a sprite for every lit window (a few to a wall, one for each lit storey) and one on every lamp.
  function build(data) {
    const out = [], WARM = [1.0, .72, .42], PALE = [1.0, .88, .66], WHITE = [.8, .88, 1.0];
    const merc = (lng, lat, z) => { const m = maplibregl.MercatorCoordinate.fromLngLat([lng, lat], 0); scaleM = m.meterInMercatorCoordinateUnits(); return [m.x, m.y, z * scaleM]; };
    const add = (lng, lat, z, size, col, k) => { const m = merc(lng, lat, z); out.push(m[0], m[1], m[2], col[0], col[1], col[2], k, size); };
    const bld = data.bld.b, faces = data.faces;
    bld.forEach((b, idx) => {
      const g = b[12] || 0, h = b[1], row = faces && faces.f[idx];
      if (g < .2 || h < 2.6 || !row) return;
      const ring = b[0], k = ring.length / 2;
      let area = 0; for (let i = 0; i < k; i++) { const j = (i + 1) % k; area += ring[2 * i] * MX * ring[2 * j + 1] * MY - ring[2 * j] * MX * ring[2 * i + 1] * MY; }
      const sg = area > 0 ? 1 : -1, floors = Math.max(1, Math.min(8, Math.floor((h - 1.0) / 3.1)));
      for (let i = 0; i < k; i++) {
        const j = (i + 1) % k, x0 = ring[2 * i] * MX, y0 = ring[2 * i + 1] * MY, dx = ring[2 * j] * MX - x0, dy = ring[2 * j + 1] * MY - y0, ln = Math.hypot(dx, dy);
        if (ln < 2.2) continue;
        const nx = sg * dy / ln, ny = -sg * dx / ln, n = Math.max(1, Math.min(10, Math.floor(ln / 3.6)));
        for (let f = 0; f < floors; f++) {
          const z = 1.7 + f * 3.1; if (z > h - .5) break;
          for (let w = 0; w < n; w++) {
            if (hash(b[4] * 1e4 + i * 3.1 + w, f * 7.7 + b[5] * 1e4) > g) continue;
            const t = (w + .5) / n, x = x0 + dx * t + nx * .7, y = y0 + dy * t + ny * .7, c = hash(w * 9.1 + i, f + b[4] * 1e3) < .22 ? PALE : WARM;
            add(x / MX, y / MY, z, 1.7 + hash(f, w + i) * .9 + (h > 12 ? .5 : 0), c, (h > 12 ? .55 : .34) + .2 * hash(i, w * 3 + f));
          }
        }
      }
    });
    (data.lamps || []).forEach(l => add(l[0], l[1], 7.2, l[3] ? 10 : 8, l[3] ? WHITE : WARM, .75 * Math.min(1, .55 + l[2])));
    return new Float32Array(out);
  }

  const layer = {
    id: ID, type: 'custom', renderingMode: '3d',
    onAdd(map, gl) {
      const sh = (t, s) => { const o = gl.createShader(t); gl.shaderSource(o, s); gl.compileShader(o); if (!gl.getShaderParameter(o, gl.COMPILE_STATUS)) throw new Error(gl.getShaderInfoLog(o)); return o; };
      prog = gl.createProgram(); gl.attachShader(prog, sh(gl.VERTEX_SHADER, VS)); gl.attachShader(prog, sh(gl.FRAGMENT_SHADER, FS)); gl.linkProgram(prog);
      loc = { m: gl.getUniformLocation(prog, 'u_m'), scale: gl.getUniformLocation(prog, 'u_scale'), w0: gl.getUniformLocation(prog, 'u_w0'), fade: gl.getUniformLocation(prog, 'u_fade'),
        pos: gl.getAttribLocation(prog, 'a_pos'), col: gl.getAttribLocation(prog, 'a_col'), size: gl.getAttribLocation(prog, 'a_size') };
      buf = gl.createBuffer(); gl.bindBuffer(gl.ARRAY_BUFFER, buf); gl.bufferData(gl.ARRAY_BUFFER, pts, gl.STATIC_DRAW);
    },
    render(gl, args) {
      if (!pts || !prog) return;
      const m = (args && args.defaultProjectionData && args.defaultProjectionData.mainMatrix) || (args && args.mainMatrix) || args;
      const z = mapRef.getZoom(), fade = Math.max(0, Math.min(1, (z - 16) / 1.2)); if (fade <= 0) return;
      const c = mapRef.getCenter(), mc = maplibregl.MercatorCoordinate.fromLngLat(c, 0);
      const w0 = m[3] * mc.x + m[7] * mc.y + m[15], ppm = Math.pow(2, z) * 512 / (40075016.686 * Math.cos(c.lat * Math.PI / 180)) * (window.devicePixelRatio || 1);
      gl.useProgram(prog);
      gl.uniformMatrix4fv(loc.m, false, m); gl.uniform1f(loc.scale, ppm); gl.uniform1f(loc.w0, w0); gl.uniform1f(loc.fade, fade);
      gl.bindBuffer(gl.ARRAY_BUFFER, buf);
      gl.enableVertexAttribArray(loc.pos); gl.vertexAttribPointer(loc.pos, 3, gl.FLOAT, false, 32, 0);
      gl.enableVertexAttribArray(loc.col); gl.vertexAttribPointer(loc.col, 4, gl.FLOAT, false, 32, 12);
      gl.enableVertexAttribArray(loc.size); gl.vertexAttribPointer(loc.size, 1, gl.FLOAT, false, 32, 28);
      gl.enable(gl.DEPTH_TEST); gl.depthFunc(gl.LEQUAL); gl.depthMask(false);
      gl.enable(gl.BLEND); gl.blendFunc(gl.ONE, gl.ONE);
      gl.drawArrays(gl.POINTS, 0, count);
      gl.disable(gl.BLEND); gl.depthMask(true);
      gl.disableVertexAttribArray(loc.pos); gl.disableVertexAttribArray(loc.col); gl.disableVertexAttribArray(loc.size);
    },
  };

  window.sdGlow = {
    // data: { bld, faces, lamps }; before: the layer to sit under (the first label)
    init(map, data, before) {
      if (mapRef) return;
      mapRef = map; pts = build(data); count = pts.length / 8;
      map.addLayer(layer, before); map.setLayoutProperty(ID, 'visibility', 'none');
    },
    show(on) { if (mapRef && mapRef.getLayer(ID)) { mapRef.setLayoutProperty(ID, 'visibility', on ? 'visible' : 'none'); mapRef.triggerRepaint(); } },
    count: () => count,
  };
})();
