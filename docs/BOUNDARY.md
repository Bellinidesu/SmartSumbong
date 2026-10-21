# The barangay boundary

SmartSumbong decides "inside Barangay 183 or not" with one polygon: the row in
`barangay_boundary` (migration 0005), copied from OpenStreetMap relation
[2988704](https://www.openstreetmap.org/relation/2988704). This page compares
it with the official line from the Philippine Statistics Authority (PSA) and
NAMRIA, and records what we decided.

Checked 21 Oct 2026 with `python tools/boundary_compare.py` (standard library
only; it fetches just Barangay 183's record from the 272 MB national file).

## What the two sources say

| | OpenStreetMap (ours) | PSA / NAMRIA (official) |
|---|---|---|
| Area | 6.26 km² | 3.88 km² |
| PSGC code | `1381100183` (current 10-digit code) | `PH1307605183` (the 2023 9-digit code; OSM keeps it as `old_ref`) |
| Valid on | relation version 20, 3 Nov 2025 | 6 Nov 2023 (HDX's May 2026 release has the same shape, `v03`) |
| Population tag | 41,113 (1 Jul 2024) | — |

- The official outline lies **inside** ours: they share 3.88 km², and only
  0.003 km² of it falls outside our line. Where both draw an edge, they agree to
  within 4 m at the median.
- Ours runs about **1.1 km further west**: 2.39 km² that the official line
  leaves out. That strip is NAIA airside: the Terminal 3 apron, Andrews Avenue,
  the weather radar. No one lives there.
- **No complaint has been filed in the strip.** Of the 54 complaints on record,
  the same 43 are inside both lines (read-only check against the live database,
  21 Oct 2026).
- OpenStreetMap's neighbouring barangays (191, 197, 201, 184) tile cleanly
  against ours, with no overlap.
- Our PSGC code is right: `1381100183` is the current code in the PSA's July
  2026 list (via the `barangay` package), under Pasay `1381100000`.

## What we decided

**We keep OpenStreetMap's line for jurisdiction.** The two lines agree on every
place a resident lives and every complaint filed so far. The difference is
airport land, which the portal's map already leaves out: it is pinned to the
residential grid (see the note above `RESIDENTIAL_CENTRE` in
`admin/spatial.php`). The official line is a reference, not a correction.
NAMRIA's boundaries are themselves drawn for statistics and are not a legal
survey.

**The barangay decides.** If the barangay hall says the airport strip is not
theirs, swap the row. The table holds the shape, not the code, so no migration
is needed:

```sql
update public.barangay_boundary
   set geom = st_multi(st_geomfromgeojson('<geometry from docs/data/brgy183-psa-namria.geojson>'))::geography,
       source = 'PSA/NAMRIA 2023-11-06 (HDX cod-ab-phl, CC BY-IGO)', updated_at = now()
 where id = 1;
```

Run the check again when either source changes: a new OSM version of the
relation, or a new HDX release.

## Sources and licences

- Official outline: [OCHA HDX `cod-ab-phl`](https://data.humdata.org/dataset/cod-ab-phl),
  NAMRIA and PSA, **CC BY-IGO**; read from
  [altcoder/philippines-psgc-shapefiles](https://github.com/altcoder/philippines-psgc-shapefiles)
  (MIT), which keeps it matched to current PSGC names. Saved as
  `docs/data/brgy183-psa-namria.geojson` with that credit inside it.
- Our outline: © OpenStreetMap contributors, **ODbL**.
- The PSGC code list: [bendlikeabamboo/barangay](https://github.com/bendlikeabamboo/barangay) (MIT).
