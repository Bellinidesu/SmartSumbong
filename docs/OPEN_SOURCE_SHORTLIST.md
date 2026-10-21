# Open-source shortlist

Projects worth using, or learning from, for SmartSumbong's portal, SMART
engine and app. Found on 21 Oct 2026 by searching GitHub and GitLab across
16 feature areas (about 120 queries, 493 hits), then adding well-known
projects checked by name. What was actually used is in
[OPEN_SOURCE.md](OPEN_SOURCE.md); this page is the menu for what comes next.

**How it was filtered.** Licence read from the host's API and permissive
(MIT, BSD, Apache-2.0, ISC, CC0, MPL-2.0 for tools we only run); pushed
within two years; not archived; at least 40 stars (4 for Philippine-specific
searches). **How to read it.** *Use* = fits now and is cheap. *Try* = promising
but needs a test first. *Reference* = read the idea, write our own. Stars and
dates are as of 21 Oct 2026. **Not covered:** Codeberg (its search kept failing
from here), academic code, and the private BetterGov repo.

**Rule for the SMART engine:** nothing below decides a case. A model may
suggest; rules decide; a person approves anything new.

## SMART: reading Tagalog and Taglish

| Project | Licence | What it gives | Verdict |
|---|---|---|---|
| ljvmiranda921/calamanCy | MIT | Tagalog spaCy pipelines (tagging, NER) | Try, offline: measure its lemmas against `tools/reader_benchmark` |
| andrianllmm/taglid | MIT | Word-level Tagalog–English language ID | Try: Taglish detection for suggestions only |
| pemistahl/lingua-py | Apache-2.0 | Language detection, Tagalog included | Try, offline |
| explosion/spaCy | MIT | The base for calamanCy and negspacy | Reference |
| jenojp/negspacy | MIT | Negation detection ("no fire") | Reference: ours is rule-based and passes its cases |
| rapidfuzz/RapidFuzz | MIT | Fast fuzzy matching | Use offline: the benchmark baseline |
| seatgeek/thefuzz | MIT | Fuzzy matching | Reference |
| jamesturk/jellyfish | MIT | Phonetic and approximate matching (Soundex, Metaphone, Jaro-Winkler) | Try: a phonetic key for texting spellings |
| MaartenGr/PolyFuzz | MIT | Fuzzy grouping and evaluation | Reference |
| nol13/fuzzball.js | MIT | JS fuzzy matching | Reference |

*Measured:* SMART's rules recover 64 of 64 benchmark words; RapidFuzz alone 34 to
46 of 64 (PR #163). Fuzzy matching alone is not the answer for Tagalog
grammar.

## SMART: duplicates and search

| Project | Licence | What it gives | Verdict |
|---|---|---|---|
| ekzhu/datasketch | MIT | MinHash and LSH for near-duplicate text | Try, offline: compare with `pg_trgm` on real duplicates |
| quickwit-oss/tantivy | MIT | Rust full-text search | Reference |
| lucaong/minisearch | MIT | Tiny in-browser full-text search | Use: the portal's client-side search boxes |
| teamtnt/tntsearch | MIT | PHP full-text search | Reference |
| timescale/pg_textsearch | PostgreSQL | BM25 ranking inside Postgres | Try: better ranking than `ts_rank` |
| supabase/index_advisor | PostgreSQL | Suggests indexes | Use: run it against the query budget |
| supabase/pg_jsonschema | Apache-2.0 | JSON Schema checks in Postgres | Try: validate `smart_rules` JSON |
| pgvector/pgvector | NOASSERTION (PostgreSQL licence) | Vector similarity | Reference: meaning-based duplicates would need a model; rules first |

## SMART: forecasting and anomalies (offline checks only)

| Project | Licence | What it gives | Verdict |
|---|---|---|---|
| facebook/prophet | MIT | Seasonal forecasts | Try: back-test the weekly patterns |
| statsmodels/statsmodels | BSD-3-Clause | Classical time-series models | Try |
| deepcharles/ruptures | BSD-2-Clause | Change-point detection | Try: when a problem *starts*, not just spikes |
| yzhao062/pyod | BSD-2-Clause | Anomaly detection | Try |
| unit8co/darts | Apache-2.0 | Forecasting and anomalies | Reference |
| sktime/sktime | BSD-3-Clause | Time-series framework | Reference |
| facebookresearch/Kats | MIT | Time-series toolkit | Reference |
| google-research/timesfm, amazon-science/chronos-forecasting | Apache-2.0 | Pretrained forecasters | Reference: too heavy and opaque for 54 complaints |

## SMART: explaining and rules

| Project | Licence | What it gives | Verdict |
|---|---|---|---|
| interpretml/interpret | MIT | Glass-box models | Try: an explainable second opinion on triage scores |
| shap/shap | MIT | Explains any model's output | Reference |
| MAIF/shapash, TeamHG-Memex/eli5 | Apache-2.0, MIT | Model explanation | Reference |
| CacheControl/json-rules-engine | ISC | Rules as JSON | Reference |
| gorules/zen | MIT | Business-rules engine | Reference |
| microsoft/RulesEngine | MIT | Rules from JSON (.NET) | Reference |

## Maps and geography

| Project | Licence | What it gives | Verdict |
|---|---|---|---|
| uber/h3 + h3-js + h3-py | Apache-2.0 | Hexagonal cells | Use: hotspot cells for the heat view and `report_hotspots()` |
| postgis/h3-pg | Apache-2.0 | H3 inside Postgres | Try: only if Supabase offers the extension |
| maplibre/martin | Apache-2.0 | PostGIS tile server | Reference: we serve OpenFreeMap tiles |
| mapbox/supercluster | ISC | Fast point clustering | Reference: MapLibre already clusters |
| maplibre/maplibre-gl-geocoder | ISC | Address search box | Try: Spatial's search |
| visgl/deck.gl | MIT | Large-data map layers | Reference |
| go-spatial/tegola | MIT | Vector tile server | Reference |
| graphhopper/graphhopper | Apache-2.0 | Routing and isochrones on OSM | Try: tanod travel time that follows streets, not straight lines |
| routingpy/routingpy | Apache-2.0 | One client for routing services | Reference |
| nrenner/brouter-web | MIT | Routing client | Reference |
| placemark/placemark, mapbox/geojson.io | MIT, ISC | GeoJSON editing | Reference: boundary corrections |
| Leaflet/Leaflet | BSD-2-Clause | Maps library | Reference: we use MapLibre |
| maplibre/maplibre-gl-js | BSD-3-Clause (GitHub: NOASSERTION) | Our map library | In use |
| openvenues/libpostal | MIT | Address parsing, 60 countries | Try: tidy free-text places; heavy (2 GB data) |
| komoot/photon, pelias/pelias | Apache-2.0, MIT | Geocoders on OSM | Reference: we use Nominatim |
| geocoder-php/Geocoder, thephpleague/geotools | MIT | PHP geocoding and geo maths | Reference |

## Philippines data

| Project | Licence | What it gives | Verdict |
|---|---|---|---|
| altcoder/philippines-psgc-shapefiles | MIT (data CC BY-IGO) | PSGC boundaries | In use (boundary check) |
| bendlikeabamboo/barangay | MIT | 42,000 barangays with codes | In use (code check) |
| bendlikeabamboo/barangay-boundaries-repository | MIT | Barangay GeoJSON by class | Use: a lighter source than the 272 MB file |
| yajra/laravel-address | MIT | Address lookup | Reference |
| skyvstigreo/philippines-province-city-barangay-database | MIT | SQL lists | Reference |
| OSSPhilippines/awesome-pinoy-made | CC0 | Filipino open-source list | Reference: where to find more |
| ogbinar/DataEngineeringPilipinas | MIT | Community | Reference: a place to ask |
| phisix-org/phisix | Apache-2.0 | PSEi API | Not relevant |
| google-research/flood-forecasting | Apache-2.0 | Google's flood models | Reference |
| miniufo/besttracks | MIT | Tropical-cyclone best-track data | Reference: storm history |

## Disaster and civic reporting

| Project | Licence | What it gives | Verdict |
|---|---|---|---|
| Resgrid/Core | Apache-2.0 | Dispatch, personnel, shifts | Reference: dispatch ideas |
| nasa/CrisisMappingToolkit | Apache-2.0 | Flood mapping from satellite data | Reference |
| CityOfNewYork/NYCOpenRecords | Apache-2.0 | Public records requests | Reference: a records-request flow for the barangay |
| UnityFoundation-io/Libre311, bensheldon/open311status | Apache-2.0, MIT | Open311 service requests | Reference: shape of a public API |
| timwis/jkan | MIT | Open-data portal on static files | Try: publish anonymised statistics |
| ihsn/nada | MIT | Data catalogue | Reference |

## Portal: PHP and web

| Project | Licence | What it gives | Verdict |
|---|---|---|---|
| openspout/openspout | MIT | Streaming CSV/XLSX/ODS | Use: export without loading everything into memory |
| endroid/qr-code, Bacon/BaconQrCode | MIT, BSD-2-Clause | QR codes in PHP | Use: tracking-ID QR on printouts |
| chillerlan/php-qrcode | Apache-2.0 | QR generate and read | Reference |
| web-push-libs/web-push-php | MIT | Web Push from PHP | Try: portal notifications |
| symfony/intl, symfony/string | MIT | Locale data, UTF-8 strings | Reference |
| php-gettext/Gettext | MIT | .po/.mo handling | Reference: our `t()` works |
| parallax/jsPDF | MIT | PDF in the browser | Reference: the report PDF is already built |
| Hopding/pdf-lib | MIT | Edit PDFs in JS | Reference: certificate editor |
| mozilla/pdf.js | Apache-2.0 | PDF viewer | Use: view uploaded PDFs inside the portal |
| dompdf/dompdf, ezyang/htmlpurifier | LGPL-2.1 | HTML to PDF; HTML sanitising | Use as a library only (LGPL), never copy |
| mpdf/mpdf | GPL-2.0 | HTML to PDF | Do not use (copyleft) |
| cure53/DOMPurify | Apache-2.0 | Client-side HTML sanitiser | Use: any rich text shown in the portal |
| chartjs/Chart.js, leeoniya/uPlot | MIT | Charts | Try: uPlot is far smaller (the budget is 16 KB gzip a script) |
| flatpickr/flatpickr | MIT | Date picker | Reference: we have our own |
| alpinejs/alpine, bigskysoftware/htmx, lit/lit | MIT, 0BSD, BSD-3-Clause | Light interactivity | Reference |
| spatie/laravel-activitylog | MIT | Audit-log design | Reference: ours is hash-chained |

## Security, quality and operations

| Project | Licence | What it gives | Verdict |
|---|---|---|---|
| dequelabs/axe-core | MPL-2.0 | Accessibility checks | Use: a CI check of every page (needs a browser run) |
| GoogleChrome/lighthouse-ci | Apache-2.0 | Performance and a11y scores per push | Try |
| microsoft/playwright | Apache-2.0 | Browser tests | Use: replaces the hand-run screenshot harness |
| sitespeedio/sitespeed.io | MIT | Performance budgets | Reference |
| GitGuardian/ggshield | MIT | Secret scanning | Reference: CI already scans |
| OWASP/cve-lite-cli | MIT | JS dependency scan | Reference |
| aquasecurity/trivy | Apache-2.0 | Vulnerabilities, secrets, configs | Use: add to CI |
| louislam/uptime-kuma | MIT | Uptime monitor | Try: a status page for the portal |
| healthchecks/healthchecks | BSD-3-Clause | Cron monitoring | Try: watch the nightly backup |
| restic/restic | BSD-2-Clause | Encrypted backups | Reference: ours are age-encrypted |
| keycloak/keycloak | Apache-2.0 | Identity | Reference |
| apache/superset | Apache-2.0 | Dashboards | Reference |

## Database

| Project | Licence | What it gives | Verdict |
|---|---|---|---|
| amacneil/dbmate | MIT | Plain-SQL migrations | Reference: we already apply plain SQL |
| citusdata/postgresql-hll | Apache-2.0 | Approximate counts | Reference |
| apache/age | Apache-2.0 | Graph queries in Postgres | Reference |

## App (Flutter)

| Project | Licence | What it gives | Verdict |
|---|---|---|---|
| simolus3/drift | MIT | Reactive SQLite | Try: a real offline store for the outbox and saved screens |
| juliansteenbakker/flutter_secure_storage | BSD-3-Clause | Encrypted storage | Check: already in use? |
| transistorsoft/flutter_background_geolocation | Apache-2.0 | Background location | Not wanted: tanod location is at key moments only |
| rafaelsetragni/awesome_notifications | Apache-2.0 | Notifications | Reference: we use `flutter_local_notifications` |
| arrrrny/tesseract_ocr | BSD-3-Clause | Tesseract in Flutter | Reference: ID OCR is off |

## OCR and ID (switched off today)

| Project | Licence | What it gives | Verdict |
|---|---|---|---|
| tesseract-ocr/tesseract | Apache-2.0 | OCR | Reference |
| PaddlePaddle/PaddleOCR, mindee/doctr, JaidedAI/EasyOCR | Apache-2.0 | Modern OCR | Reference: if ID reading is ever switched on |
| opencv/opencv | Apache-2.0 | Image processing | Reference |
| zxing/zxing | Apache-2.0 | QR and barcodes | Reference |
| junhoyeo/BetterOCR | MIT | Combines OCR engines | Reference |

## SMS, email and notifications

| Project | Licence | What it gives | Verdict |
|---|---|---|---|
| textbee/textbee | MIT | An Android phone as an SMS gateway | Try: an SMS fallback with no credits (needs a phone and SIM left on) |
| notifo-io/notifo | MIT | Multi-channel notification service | Reference |
| nikoksr/notify, kha7iq/pingme | MIT | Send to many channels | Reference |

## Left out, and the open alternative

Checked 21 Oct 2026 by reading each project's own licence file where GitHub
could not name it.

| Left out | Why | Open alternative |
|---|---|---|
| Meilisearch | MIT core, but parts under the Business Source License | MiniSearch (MIT) in the browser; FlexSearch (Apache-2.0); Quickwit (Apache-2.0) or tantivy (MIT) for a server; PostgreSQL's own search (`pg_trgm`, pg_textsearch) |
| Typesense, Manticore | GPL-3.0 | as above |
| ParadeDB | AGPL-3.0 | pg_textsearch (PostgreSQL licence) |
| Metabase | AGPL-3.0 | Apache Superset (Apache-2.0), Redash (BSD-2-Clause), Evidence (MIT) |
| Grafana, OpenObserve | AGPL-3.0 | Superset or Redash for charts; Uptime Kuma (MIT) and Healthchecks (BSD-3) for monitoring |
| Sentry | Functional Source License | GlitchTip (MIT, on GitLab, speaks Sentry's protocol); our own error and uptime tables (0096–0098) |
| mPDF | GPL-2.0 | FPDF (setasign, permissive), pdf-lib or jsPDF (MIT) |
| TCPDF | its own licence, not checked line by line | FPDF |
| pa11y | LGPL-3.0 | axe-core (MPL-2.0), Lighthouse CI (Apache-2.0) |
| FixMyStreet, Ushahidi, Mark-a-Spot, uReport, Decidim, Polis | AGPL or GPL | Libre311 (Apache-2.0) and the Open311 API shape; ours stays our own |
| Zammad, FreeScout, osTicket, Frappe Helpdesk | AGPL or GPL | none permissive found; the case flow stays our own |
| Open-Meteo's server | AGPL-3.0 | its public API (we call it, not run it) |

Licences now confirmed from the files themselves: **htmx** Zero-Clause BSD,
**MapLibre GL JS** BSD-3-Clause, **pgBackRest** MIT, **pgvector** PostgreSQL
licence, **PMTiles** BSD-3-Clause (its specification public domain), **FPDF**
permissive. Bugsink and SigNoz were not taken further: neither is plainly
under one open licence.

Hits of no use from the broad queries (AI-agent tools, trading APIs, games)
are not listed.
