// Spatial Distribution, City view: the landmark models (Bellinist, 10 Oct 2026).
// Real meshes for the landmarks (docs/map-data/landmarks/models.py draws them): a terminal with its canopy, a shrine with its domes, a
// hall with its pitched roof. A fill-extrusion can only be a prism, so these are drawn by a custom WebGL layer: triangles, a facade
// atlas for what repeats (windows, roof sheet), and light that was worked out ahead of time by the graphics card and is stored in
// the vertices (landmarks3d-light.bin: how lit each vertex is by day, and by night). Nothing is lit live and nothing moves.
// The layer stands where the plain buildings of these landmarks stood; sd-city.js leaves those out (sdModels.replaces).
(function () {
  'use strict';
  const ID = 'cd-models';
  const MX = 107500;
  let grow = 0, data = null, bin = null, lightBin = null, atlas = null, emis = null, atlas2 = null, emis2 = null, map = null, night = false;
  const gl_ = { prog: null, loc: null, vbuf: null, ibuf: null, lbuf: null, tex: null, texE: null, ready: false };

  const VS = `#version 300 es
  uniform mat4 u_m;
  in vec3 a_pos; in vec2 a_uv; in vec4 a_mc; in vec3 a_day; in vec3 a_night; in vec2 a_x;
  uniform float u_night, u_grow;
  out vec2 v_uv; out float v_mat; out vec3 v_alb; out vec3 v_light; out vec2 v_x;
  void main() { gl_Position = u_m * vec4(a_pos.xy, a_pos.z * u_grow, 1.0); v_uv = a_uv; v_x = a_x; v_mat = a_mc.x; v_alb = a_mc.yzw / 255.0; vec3 l = mix(a_day, a_night, u_night) * 1.25;
    float g = dot(l, vec3(.333)); l = mix(vec3(g), l, mix(1.0, .5, u_night)) * mix(1.0, .72, u_night); v_light = l; }`;
  const FS = `#version 300 es
  precision highp float;
  uniform sampler2D u_atlas, u_emis, u_atlas2, u_emis2; uniform vec4 u_tiles[256]; uniform float u_night; uniform vec3 u_wash[8];
  in vec2 v_uv; in float v_mat; in vec3 v_alb; in vec3 v_light; in vec2 v_x;
  out vec4 o;
  void main() {
    int mi = int(v_mat + .5); vec4 t = u_tiles[mi];
    vec2 f = fract(v_uv), dx = dFdx(v_uv) * t.zw, dy = dFdy(v_uv) * t.zw, auv = t.xy + f * t.zw;
    vec3 base, em;
    if (mi >= 100) { base = textureGrad(u_atlas2, auv, dx, dy).rgb; em = textureGrad(u_emis2, auv, dx, dy).rgb; }      // a landmark's own tile (finer atlas)
    else { base = textureGrad(u_atlas, auv, dx, dy).rgb; em = textureGrad(u_emis, auv, dx, dy).rgb; }
    if (mi == 8) em = v_alb * .55;
    // a landmark's own colour of night light up its walls (v_x: how much, and which of the eight colours); nothing live, baked into the vertices
    int wi = int(v_x.y * 255.0 + .5); vec3 wc = u_wash[wi] * v_x.x * (.35 + .65 * dot(base, vec3(.333)));
    vec3 c = base * v_alb * v_light + u_night * (em + wc);
    o = vec4(c, 1.0);
  }`;

  // the eight colours a landmark's night wash can have (index 0 is none): violet, teal, amber, blue, rose, green, white
  const WASH = new Float32Array([0, 0, 0,  .46, .34, .95,  .16, .72, .72,  1.0, .62, .26,  .30, .45, 1.0,  .95, .36, .52,  .30, .80, .46,  1.0, .90, .74]);
  const mul = (a, b) => { const o = new Array(16).fill(0); for (let i = 0; i < 4; i++) for (let j = 0; j < 4; j++) { let s = 0; for (let k = 0; k < 4; k++) s += a[k * 4 + j] * b[i * 4 + k]; o[i * 4 + j] = s; } return o; };

  const layer = {
    id: ID, type: 'custom', renderingMode: '3d',
    onAdd(m, gl) {
      const sh = (t, s) => { const o = gl.createShader(t); gl.shaderSource(o, s); gl.compileShader(o); if (!gl.getShaderParameter(o, gl.COMPILE_STATUS)) throw new Error(gl.getShaderInfoLog(o)); return o; };
      const p = gl.createProgram(); gl.attachShader(p, sh(gl.VERTEX_SHADER, VS)); gl.attachShader(p, sh(gl.FRAGMENT_SHADER, FS)); gl.linkProgram(p); gl_.prog = p;
      const L = {}; ['u_m', 'u_night', 'u_grow', 'u_atlas', 'u_emis', 'u_atlas2', 'u_emis2', 'u_tiles', 'u_wash'].forEach(n => { L[n] = gl.getUniformLocation(p, n); });
      ['a_pos', 'a_uv', 'a_mc', 'a_day', 'a_night', 'a_x'].forEach(n => { L[n] = gl.getAttribLocation(p, n); }); gl_.loc = L;
      gl_.vbuf = gl.createBuffer(); gl.bindBuffer(gl.ARRAY_BUFFER, gl_.vbuf); gl.bufferData(gl.ARRAY_BUFFER, bin.subarray(0, data.indexOffsetBytes), gl.STATIC_DRAW);
      gl_.ibuf = gl.createBuffer(); gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, gl_.ibuf); gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, bin.subarray(data.indexOffsetBytes), gl.STATIC_DRAW);
      gl_.lbuf = gl.createBuffer(); gl.bindBuffer(gl.ARRAY_BUFFER, gl_.lbuf);
      const lb = lightBin && lightBin.length === data.vertices * 8 ? lightBin : (() => { const f = new Uint8Array(data.vertices * 8); for (let i = 0; i < f.length; i += 8) { f[i] = f[i + 1] = f[i + 2] = 215; f[i + 3] = f[i + 4] = f[i + 5] = 95; } return f; })();
      gl.bufferData(gl.ARRAY_BUFFER, lb, gl.STATIC_DRAW);
      const tex = (img, mip) => { const t = gl.createTexture(); gl.bindTexture(gl.TEXTURE_2D, t); gl.pixelStorei(gl.UNPACK_PREMULTIPLY_ALPHA_WEBGL, false); gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, img); gl.generateMipmap(gl.TEXTURE_2D);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR_MIPMAP_LINEAR); gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR); gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE); gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE); return t; };
      gl_.tex = tex(atlas); gl_.texE = tex(emis);
      const blank = (r) => { const c = document.createElement('canvas'); c.width = c.height = 4; const x = c.getContext('2d'); x.fillStyle = r; x.fillRect(0, 0, 4, 4); return c; };
      gl_.tex2 = tex(atlas2 || blank('#fff')); gl_.texE2 = tex(emis2 || blank('#000'));
      gl_.tiles = new Float32Array(1024); data.tiles.forEach((r, i) => { if (r) gl_.tiles.set(r, i * 4); });
      gl_.ready = true;
    },
    render(gl, args) {
      const g = grow; if (!gl_.ready || g <= .001) return;
      const main = (args && args.defaultProjectionData && args.defaultProjectionData.mainMatrix) || (args && args.mainMatrix) || args, L = gl_.loc;
      gl.useProgram(gl_.prog);
      gl.uniform1f(L.u_night, night ? 1 : 0); gl.uniform1f(L.u_grow, g); gl.uniform4fv(L.u_tiles, gl_.tiles); gl.uniform3fv(L.u_wash, WASH);
      gl.activeTexture(gl.TEXTURE0); gl.bindTexture(gl.TEXTURE_2D, gl_.tex); gl.uniform1i(L.u_atlas, 0);
      gl.activeTexture(gl.TEXTURE1); gl.bindTexture(gl.TEXTURE_2D, gl_.texE); gl.uniform1i(L.u_emis, 1);
      gl.activeTexture(gl.TEXTURE2); gl.bindTexture(gl.TEXTURE_2D, gl_.tex2); gl.uniform1i(L.u_atlas2, 2);
      gl.activeTexture(gl.TEXTURE3); gl.bindTexture(gl.TEXTURE_2D, gl_.texE2); gl.uniform1i(L.u_emis2, 3);
      gl.enable(gl.DEPTH_TEST); gl.depthFunc(gl.LEQUAL); gl.depthMask(true); gl.disable(gl.CULL_FACE); gl.disable(gl.BLEND);
      gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, gl_.ibuf);
      for (const md of data.models) {
        if (!shown(md)) continue;
        const mc = maplibregl.MercatorCoordinate.fromLngLat([md.lng, md.lat], 0), s = mc.meterInMercatorCoordinateUnits();
        // local (east, north, up in metres) -> mercator (east, south, up)
        const M = [s, 0, 0, 0, 0, -s, 0, 0, 0, 0, s, 0, mc.x, mc.y, 0, 1];
        gl.uniformMatrix4fv(L.u_m, false, new Float32Array(mul(Array.from(main), M)));
        gl.bindBuffer(gl.ARRAY_BUFFER, gl_.vbuf);
        const base = md.voff * 24;
        gl.enableVertexAttribArray(L.a_pos); gl.vertexAttribPointer(L.a_pos, 3, gl.FLOAT, false, 24, base);
        gl.enableVertexAttribArray(L.a_uv); gl.vertexAttribPointer(L.a_uv, 2, gl.FLOAT, false, 24, base + 12);
        gl.enableVertexAttribArray(L.a_mc); gl.vertexAttribPointer(L.a_mc, 4, gl.UNSIGNED_BYTE, false, 24, base + 20);
        gl.bindBuffer(gl.ARRAY_BUFFER, gl_.lbuf);
        gl.enableVertexAttribArray(L.a_day); gl.vertexAttribPointer(L.a_day, 3, gl.UNSIGNED_BYTE, true, 8, md.voff * 8);
        gl.enableVertexAttribArray(L.a_night); gl.vertexAttribPointer(L.a_night, 3, gl.UNSIGNED_BYTE, true, 8, md.voff * 8 + 3);
        gl.enableVertexAttribArray(L.a_x); gl.vertexAttribPointer(L.a_x, 2, gl.UNSIGNED_BYTE, true, 8, md.voff * 8 + 6);
        gl.drawElements(gl.TRIANGLES, md.i, gl.UNSIGNED_INT, md.ioff * 4);
      }
      ['a_pos', 'a_uv', 'a_mc', 'a_day', 'a_night', 'a_x'].forEach(n => gl.disableVertexAttribArray(L[n]));
    },
  };

  const img = src => new Promise(res => { const i = new Image(); i.onload = () => res(i); i.onerror = () => res(null); i.src = src + '?v=' + (window.SD_MAPV || ''); });
  // The landmark models are a flag, off by default: the City view is the plain coloured buildings of the open data (OpenStreetMap, Overture), by day and by night. The models, their
  // light and their pictures are not even downloaded until it is on: add ?models=1 to the page address, or set localStorage ss-models to 1.
  const ON = (() => { try { return !(/[?&]models=0\b/.test(location.search) || localStorage.getItem('ss-models') === '0'); } catch (e) { return true; } })();
  // a landmark drawn from a sheet is shown on the map only once it is approved (tools/viewer.py); ?models=all shows the drafts too
  const ALL = (() => { try { return window.SD_MODELS_ALL === true || /[?&]models=all\b/.test(location.search) || localStorage.getItem('ss-models') === 'all'; } catch (e) { return false; } })();
  const shown = md => ALL || !md.sheet || md.approved;
  const ready = (async () => {
    if (!ON) return false;
    try {
      data = await fetch('assets/map/landmarks3d.json').then(r => r.json());
      const unzip = r => new Response(r.body.pipeThrough(new DecompressionStream('gzip'))).arrayBuffer();   // the model files are zipped (5 times smaller to send)
      const [b, lb, a, e] = await Promise.all([fetch('assets/map/landmarks3d.bin.gz').then(unzip),
        fetch('assets/map/landmarks3d-light.bin.gz').then(r => r.ok ? unzip(r) : null).catch(() => null), img('assets/map/landmarks3d-atlas.png'), img('assets/map/landmarks3d-emis.png')]);
      [atlas2, emis2] = await Promise.all([img('assets/map/landmarks3d-atlas2.png'), img('assets/map/landmarks3d-emis2.png')]);
      bin = new Uint8Array(b); lightBin = lb ? new Uint8Array(lb) : null; atlas = a; emis = e;
      if (!atlas || !emis) throw new Error('atlas');
      return true;
    } catch (err) { data = null; return false; }
  })();

  window.sdModels = {
    ready,
    // for the design bench (docs/map-data/tools/bench): the shaders and the loaded data, so a landmark can be looked at on its own
    shaders: () => ({ VS, FS, WASH }),
    raw: () => ({ data, bin, lightBin, atlas, emis, atlas2, emis2 }),
    replaces: new Set(),
    names: () => (data ? data.models.map(m => m.name) : []),
    // add the layer under `before` (the first label); a no-op if the models did not load
    init(m, before) {
      map = m;
      if (!data) return false;
      data.models.forEach(md => { if (shown(md)) window.sdModels.replaces.add(md.replaces); });
      if (!m.getLayer(ID)) m.addLayer(layer, before);
      m.setLayoutProperty(ID, 'visibility', 'none');
      return true;
    },
    // how far the tilt has got (0 flat, 1 standing): the models grow out of the ground with it
    grow(k) { grow = k; if (map && map.getLayer(ID)) map.triggerRepaint(); },
    show(on, isNight) { night = !!isNight; if (map && map.getLayer(ID)) { map.setLayoutProperty(ID, 'visibility', on ? 'visible' : 'none'); map.triggerRepaint(); } },
  };
  // the buildings these models replace are known as soon as the data is: sd-city.js asks before it builds the plain ones
  ready.then(ok => { if (ok) data.models.forEach(md => { if (shown(md)) window.sdModels.replaces.add(md.replaces); }); });
})();
