# Open source we use, learned from, and weighed

SmartSumbong is built on open data and open-source work, Filipino and
international. This page records what we took from each project, what we
only learned from, and what we weighed and left, with the licence that
decided it. It is also the "related work" list for the defense.

**Rules we keep.** We copy code or data only from MIT, BSD, Apache, ISC or
CC0/CC BY projects, and we credit them where they are used. GPL and AGPL
projects are references only: we read how they work and write our own. A
project with no licence is not copied at all. Nothing is installed from an
unvetted repository. The SMART engine stays rule-based: a model may suggest,
rules decide, and a person approves anything new.

## What changed on 21 Oct 2026

| Area | Project (licence) | What we did | Where |
|---|---|---|---|
| Barangay boundary | PSA/NAMRIA via OCHA HDX `cod-ab-phl` (CC BY-IGO), kept current by [altcoder/philippines-psgc-shapefiles](https://github.com/altcoder/philippines-psgc-shapefiles) (MIT); PSGC codes from [bendlikeabamboo/barangay](https://github.com/bendlikeabamboo/barangay) (MIT) | Compared the official line with our OpenStreetMap one; kept OSM, saved the official outline as a reference | [BOUNDARY.md](BOUNDARY.md), `tools/boundary_compare.py` |
| Typhoon signals | [edwardguevarra/bagyo-api](https://github.com/edwardguevarra/bagyo-api) (MIT) | Not adopted (a self-hosted Postgres, Redis and worker stack). Its idea, signals read per area, found our bug: the signal over Metro Manila was never read | `admin/includes/hazards.php` |
| Metro Manila advisories | [jakewarren/pagasa-feeds](https://github.com/jakewarren/pagasa-feeds) (MIT) | Its map of PAGASA's NCR desk page is used to read that page directly (fresher than the feed) | Flood watch; `hz_ncr()` |
| Earthquakes | [ravvdevv/phivocs-api](https://github.com/ravvdevv/phivocs-api), [arielbatoon09/betterquake](https://github.com/arielbatoon09/betterquake) (both MIT) | PHIVOLCS's public table read the same way; USGS fills in | Earthquakes widget; `ws_quake_phivolcs()` |
| SMART reading | [ljvmiranda921/calamanCy](https://github.com/ljvmiranda921/calamanCy) (MIT) and the Tagalog affix stemmers it builds on | The ideas only: the present tense, doubled words, stretched letters and English endings, as rules in SQL | Migration 0133, [SMART.md](SMART.md) |
| SMS codes | [pravennn08/semaphore-sdk](https://github.com/pravennn08/semaphore-sdk) (MIT) | Not added as a dependency. It showed Semaphore's OTP route and the sender name we were not sending | `supabase/functions/password-otp` |
| Holidays | [surelle-ha/PhilippineHolidayAPI](https://github.com/surelle-ha/PhilippineHolidayAPI) (MIT) | Not adopted: its public copy has no 2026 data, and its source (the Official Gazette) blocks automated reads. We stay on Nager.Date, which misses the holidays proclaimed each year (Eid'l Fitr, Eid'l Adha) | Calendar and Holidays widgets |

## Already in use

- **Maps.** OpenStreetMap data (ODbL), OpenFreeMap vector tiles, MapLibre GL
  (BSD-3), Project NOAH flood zones, Nominatim, Overpass.
- **Weather and hazards.** Open-Meteo (weather, air, marine), PAGASA, GDACS,
  USGS.
- **Database.** PostgreSQL, PostGIS, pg_trgm and fuzzystrmatch (SMART's
  duplicates and spellings), pg_cron.
- **App.** Flutter and the packages in `mobile/resident/pubspec.yaml`, each
  under its own licence.

## Kept for later

The wider menu, with about 150 projects by feature area, is
[OPEN_SOURCE_SHORTLIST.md](OPEN_SOURCE_SHORTLIST.md). In short:

These were checked for licence and fit and are not built in yet:

- **SMART, offline checks only** (never in the live path): RapidFuzz (MIT),
  lingua-py (Apache-2.0), negspacy (MIT), Prophet (MIT), statsmodels (BSD-3),
  PyOD (BSD-2), interpret and SHAP (MIT).
- **Maps.** Uber H3 (Apache-2.0) for hotspot cells; Turf (MIT) for geometry in
  the browser.
- **Tests and security.** axe-core (MPL-2.0) for accessibility checks; Trivy
  (Apache-2.0) for scanning.
- **App.** drift (MIT) for a fuller offline store.
- **Civic reporting, for the shape of a public API.** Open311 through
  Libre311 (Apache-2.0) and open311status (MIT); Resgrid (Apache-2.0) for
  dispatch.

## Read, not copied

- **Licence too strong to copy**: FixMyStreet (mySociety), Ushahidi,
  Mark-a-Spot (GPL-2.0), uReport and Decidim and Polis (AGPL-3.0),
  Open-Meteo's own server (AGPL-3.0; we only call its public API), the
  pagasa-parser projects (AGPL).
- **No licence**: pgTAP's GitHub copy, the zekejulia PHIVOLCS scraper,
  Flood-Watch-PH, AGAILA.
- **Licence to confirm first**: pgvector and PMTiles (GitHub shows
  NOASSERTION).

## Giving back

SmartSumbong is public. It is offered to the [BetterGov.ph](https://bettergov.ph)
community as a barangay complaint system: a 2026 BSIT capstone by Group 12,
Polytechnic University of the Philippines.
