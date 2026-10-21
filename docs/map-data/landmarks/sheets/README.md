# Landmark sheets

One JSON file per landmark. `sheet.py` reads it, finds the building by name (or by index in `buildings.json`) and builds the model on the building's real footprint.
Everything it draws is geometry or a tile; nothing is live, nothing moves.

```
{
  "name": "Plaza 66",
  "match": { "name": "Plaza 66" },            // or { "index": 2032 }
  "palette": { "wall": "EADFC6", "trim": "F4F1EA", "accent": "3F67B0", "podium": "E3D6B8" },
  "use": "commercial-residential",             // hotel, residential, mall, office, terminal, shrine, hospital, school: sets how many windows are lit
  "tiles": { "loggia": { "kind": "loggia", "m": [6.4, 3.4], "fit": true, "seed": 3 }, ... },
  "body":  { "podium": 6.0, "podium_mat": "shops", "floors_mat": "loggia", "band": 3.4, "band_mat": "band", "band_colour": "accent" },
  "features": [ { "type": "corner_tower", ... }, { "type": "canopy", ... }, { "type": "roof_sign", "text": "PLAZA 66", "neon": "blue" }, { "type": "flag" } ],
  "facade": { "awnings": true },               // flags for facade.py (false turns the whole pass off)
  "night": { "wash": { "color": "blue", "height": 24, "strength": 0.55 }, "lit": 0.45 },
  "ref": ["mapillary:<image id>"]
}
```

## Tiles (`tiles_lib.py`)

`kind`: `loggia` (recessed balconies between pilasters), `curtain` (mullions, vision glass, spandrels), `band` (a plain band with small windows), `stucco`, `board`
(board-marked concrete), `terrazzo`, `stone`, `timber` (louvres), `shopfront`. `m` is the metres one tile covers (across, up); `fit` cuts a wall to whole bays and
storeys; `graded` lets the glass take the sky gradient. Other keys go to the kind: `seed`, `p` (share of windows lit), `lc` (`warm`, `bright`, `cool`), `wear` (0 to 1,
how weathered), `bays`. A sheet may own at most 8 tiles; they are numbered from 100 in the atlas.

## Features

`corner_tower` (`end`: start or end of the front, `size`, `proud`, `extra`, `mat`), `canopy` (`at`, `width`, `colour`), `roof_sign` (`text`, `width`, `neon`:
violet, teal, amber or blue), `flag`.

## The one accent

Each landmark has one accent colour. It may be used on trim, signs, the band and the night wash, and nowhere else; the rest stays in the pastel family so the map
keeps one voice. `sheet.lint` warns when a sheet is over its budget (24,000 vertices, 14,000 triangles, 8 tiles) or has no accent.

## Working on a sheet

```
python docs/map-data/tools/bench.py "Plaza 66" --watch      rebuild and photograph (four sides, day and night, next to the street view) on every save
python docs/map-data/tools/silhouettes.py                    the skyline test: landmarks must not share an outline
python docs/map-data/tools/make_city.py --only models,light,wash      the full build for the map
```

## The engine (`docs/map-data/tools/engine.py`)

```
engine.py find "newprt mal"       fuzzy search over every named building, sheet, model and reference (shows what each already has)
engine.py status                  the landmarks with a sheet: built, size, references, wall colour against the street's (dE)
engine.py refs "Newport Mall"     reference search: Openverse, Wikimedia Commons, Mapillary street views, Sketchfab models (proportion only); one board
engine.py refs "Newport Mall" --pick commons:Newport_city_tmall.JPG     mark a reference as used: it is credited in landmarks/REFS.md
engine.py suggest "Plaza 66"      colours, floor height, bay width and glass share read off the street view
engine.py draft "Plaza 66"        a first sheet from those numbers
engine.py bench "Plaza 66"        four sides, day and night, with the street view, the references and the colour distance
engine.py new "Newport Mall"      refs + suggest + draft + build + bench in one go
```

Search keeps a picture only when it says it was taken here (Commons categories, Openverse tags, or a street-level frame, which is here by construction) and is
about the building; `--loose` keeps pictures that do not say where. Keys are read from `.env` (OPENVERSE_CLIENT_ID/SECRET, SKETCHFAB_TOKEN, MAPILLARY_TOKEN);
`refsearch.py --index-mapillary` builds the street-view index of the zone once.

## Reading a facade from photographs (the overdrive pass)

```
engine.py ... / measure.py "Horizon Centre" --floor 3.8     the unwrapped street-view faces with a ruler (a line every floor, a tick every metre) and the real colours: read bay, floor, window, spandrel by eye
sat.py "Plaza 66" --apply                                     the satellite view (open tiles, no key): roof colour, roof plant, and roof zones (tile hips, solar, planting) written into the sheet
```

Tile kind `photo` draws a facade from measured numbers: `bays` x `floors` cells in a tile, `bay_w`, `floor_h`, `win` [x0, x1, y0, y1] (the window inside its cell), `glass`, `glass_hi`,
`spandrel`, `pier`, `mull`, `mull_x`, `mull_y`, `sky`, `jit`, `p` (share of lit windows), `blinds`. Colours are absolute hex; the sheet's `palette.wall` is the lightest of them.
The landmarks' own tiles are in a finer atlas (256 px a cell). A sheet may set `height` (measured: the eaves) and the feature `piers` (real fins or piers: `bay`, `width`, `depth`, `colour`).
