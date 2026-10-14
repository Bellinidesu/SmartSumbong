# MapLibre GL JS 6.13.0

MapLibre 6 ships only as an ES module. The portal pages load it as a classic
script and use the global `maplibregl`, so `maplibre-gl.js` here is the
published `dist/maplibre-gl.mjs` compiled to that form; nothing else in it
changed. `maplibre-gl-worker.mjs` and `maplibre-gl.css` are copied as
published. The worker is found next to `maplibre-gl.js` (the script's own
URL) and is same-origin, so the CSP's `worker-src 'self'` covers it;
`.htaccess` serves `.mjs` as JavaScript.

To upgrade, with the new version's npm package unpacked in `package/`:

```sh
npx esbuild@0.25.10 package/dist/maplibre-gl.mjs --bundle --minify \
  --format=iife --global-name=maplibregl --legal-comments=inline \
  --define:import.meta.url=__maplibreScriptUrl \
  --banner:js='var __maplibreScriptUrl=document.currentScript&&document.currentScript.src||"";' \
  --outfile=maplibre-gl.js
cp package/dist/maplibre-gl-worker.mjs package/dist/maplibre-gl.css package/LICENSE.txt .
```

Then open a map page (case, print, spatial) and check the browser console.
