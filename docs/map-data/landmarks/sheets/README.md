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
