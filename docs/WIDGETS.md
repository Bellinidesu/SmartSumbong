# Workspace widgets: the backend

Ace approved all 120 widgets on 17 Oct 2026 (aesthetics page, sections 33 and 34). This is what the portal serves
them (migration 0132, PR #131). The screen is built on top of it (#132–#136): the slim rail on the Workspace
(`admin/includes/widget_panel.php`), the library with a live preview behind each widget's eye button
(`admin/widget-view.php?w=id`, which saves nothing), the engine `assets/js/widgets-core.js` and eight lazy modules
(`widgets-{live,cases,team,tools,apps,rss,games,me}.js`). Twelve are on by default (`WS_DEFAULT_TABS` in
`admin/includes/widgets.php`).

## Doors

| Door | Method | What |
|---|---|---|
| `admin/widgets.php?catalogue=1` | GET | every widget: library group, `ready` or `new`, the data groups it reads; the built-in feeds; the games; the default tabs |
| `admin/widgets.php?w=id,id&g=alarm,prefs` | GET | the data groups those widgets read, plus named groups. Each group is `{ok, stale, at, data}` |
| `admin/widgets.php?find=text` | GET | Find a case: up to 8 by tracking number, subject or place (matched literally) |
| `admin/workspace-act.php` | POST + `csrf` | every write; `action=` as listed at the top of the file |

All three are administrators only, answer JSON, and never redirect: signed out is `401 {"error":"signed_out"}`. A
background call does not keep the session alive (the two-hour idle sign-out still applies). The browser never calls
an outside host for data, with one exception: when the portal's own request to a free weather source is refused
(shared hosting addresses sometimes are), the weather, air, sea and quake widgets ask the same public API from the
browser (`WS.fallback` in `widgets-live.js`), and the content-security policy allows exactly those hosts
(api, air-quality-api and marine-api.open-meteo.com, earthquake.usgs.gov). The answer is marked `direct`.

A failed group is `ok: false, data: null` and never takes another group down. An outside source that fails serves its
last good copy with `stale: true`.

## Data groups

| Group | From | Used by |
|---|---|---|
| `brief` | smart_summary, counts | Briefing |
| `hazards` | PAGASA, GDACS (includes/hazards.php, 10 min) | Flood watch, Typhoon watch, the alarm |
| `wx` | Open-Meteo forecast (10 min): now, 24 hours, 7 days, heat index now and the day's peak with PAGASA's band, pressure change over 3 h, moon, daylight left | Weather, Heat index, Sun and moon, UV, Wind, Next 24 hours, 7-day outlook, Barometer, Flood watch, Drink water |
| `air` | Open-Meteo air quality (30 min), US AQI band | Air quality |
| `marine` | Open-Meteo Marine for Manila Bay (30 min): sea level, next highs and lows, waves. A global tide model, not an official tide table (`model: true`) | Tide, Sea and waves |
| `quake` | USGS, magnitude 3+, the Philippines, 7 days (10 min), distance and direction from the hall | Earthquakes |
| `holidays` | Nager.Date, this year and next (1 day) | Holidays, This week |
| `evac` | `admin/assets/data/safe-b183.json` (tools/build_safe.php), live Overpass as fallback, plus `safe_point_notes` | Evacuation centres |
| `rss:<key>` | the built-in feeds (10 min): philstar, rappler, gma, inquirer, gdacs, who, usgs, and news searches pna, doh, water (Maynilad), power (Meralco), fuel | Headlines, Fuel prices, each RSS widget |
| `rssmine` | the person's own feeds + the built-in feeds whose widgets they have on, one stream newest first, watch words marked | My own feed, All my feeds, Keyword watch |
| `numbers` | workspace_numbers(): status bar, by category, per day (30), per hour (90 days), first-response pace (7 days), this month vs last, resolved today, busiest streets, escalations | Cases by category, Response time, Busiest streets, This month, Cases per day, Busiest hours, Open and closed, On time, Escalations, Resolved today |
| `team` | workspace_team(): tanods (duty, jobs, first on duty today, late against the roster, hours this week), roster 7 days, shift start hours, leave, credentials, birthdays 14 days, directory, waiting for approval | Tanod on duty, Waiting for approval, Who to call, Attendance, Birthdays, Roster, Who is off, Trainings and IDs, Pick a name, Patrol checkpoints, This week |
| `risk` | workspace_risk(): open cases in a NOAH flood or surge zone | Cases at risk |
| `queue` | smart_queue, stages review and dispatch, top 10 | Needs a tanod |
| `due` | open cases due within 8 days or overdue, with the handler | Deadlines, This week |
| `recur` | smart_patterns | Recurring problems |
| `sla` | smart_sla_scorecard | On time, This month |
| `map` | open cases with place and level | Mini map |
| `activity` | workspace_activity() | Latest activity |
| `photos` | workspace_photos(): images only, never from a sensitive case | Latest photos |
| `hotlines` | hotline_groups and numbers | Hotlines |
| `posts` | team_posts with who has seen each, staff count, whether I may post a notice | Chairman's notice, Shift handover, Team board, Announcements |
| `polls` | polls with counts and my vote | Quick poll |
| `checkpoints` | patrol_checkpoints and today's last scan of each | Patrol checkpoints |
| `relief` | relief_tally by event and street, 60 days | Relief tally |
| `mood` | my check-in today, and the totals for the lead (hidden under three answers) | How is the shift? |
| `settings` | workspace_settings + whether I am the lead | Test the alarm, Big clock, Fare calculator, the Settings page |
| `prefs` | my workspace_prefs (or the defaults) | the rail, every "just for me" widget |
| `mine` | my cases closed this week, my open cases | Goal of the week |
| `games` | whether games are on, top 5 per game, my bests | the 14 minigames |
| `alarm` | the rules that are on and those firing now: red (Red warning naming Metro Manila), sig3 (Signal 3+), urgent2h, deadline, each with the tab to open | the alarm takeover |
| `meta` | the hall's place, phone and hours, the resident app link (`RESIDENT_APP_URL`), the time | Report QR, Compass |

Widgets with no groups run in the page alone: Find a case (uses `?find=`), Quick links, Patrol timer, Quick reference,
Quick SMS, Print shortcuts, Open in Maps, and the little apps (calculator, torch, converter, dice, coin, CPR beat,
battery, word of the day, phrasebook, radio codes, first aid, stopwatch, world clock, random number, password maker,
8-ball, joke, fact, tip calculator, quote for the shift).

## Who may do what (0132)

- Everyone on staff: their own Workspace and notes, board lines and handovers, polls and votes, birthdays, leave,
  credentials, the roster, checkpoints and scans, relief packs, their own check-in, their own game scores.
- The Chairman or the Secretary (any administrator while no Chairman account exists): notices and announcements,
  removing anyone's post, closing anyone's poll, the barangay settings (alarm rules, minigames on or off, shift
  start hours, fares), safe-point capacity and status, and the check-in totals.
- A tanod: may record their own checkpoint scan (for the app later). Residents: nothing.
- Minigame scores are refused while minigames are off (they start off).
- Own RSS feeds: https only, port 443, public addresses only (every address the host resolves to is checked, the
  connection is pinned to it, each redirect is checked again), 2 MB at most, documents that declare entities refused.

## Limits worth knowing

- PAGASA and the news searches have no documented API; readings are tolerant and the last good copy is kept.
- News searches (PNA, DOH, Maynilad, Meralco, oil prices) are news stories, never official notices; each item names
  its publisher. Each search carries a window (2 to 30 days) so an old notice never reads as today's.
- The DOH site sits behind a bot check and PNA publishes no feed; both come through a news search.
- The tide is a model (Open-Meteo Marine), not the NAMRIA tide table.
- Fares start empty: the barangay sets them in Settings.

## The Workspace screen (17 Oct 2026)

The sky bar on top keeps the sky, the clock, the date and the Morning / Afternoon / Night switch. Its brain became the
weather tile: the engine's glow (navy, a blue and orange spark sweeping round it, the symbol glowing yellow), the
temperature riding on it, the details in a tooltip. The arrow folds the widgets away and back.

Under it is the widget panel (`includes/widget_panel.php`, `assets/js/widgets-core.js`, `assets/css/widgets.css`):
a slim rail of the widgets the person chose (layout B, locked), the pane of the one open, and the library
(the + at the foot of the rail) to add, remove and reorder from all 120, search, and the barangay's switches. A new
person starts with twelve: Briefing, Needs a tanod, Deadlines, Cases at risk, Tanod on duty, Waiting for approval,
Flood watch, Typhoon watch, Weather, Chairman's notice, Latest activity, This month (`WS_DEFAULT_TABS`).

The widgets themselves are in eight scripts loaded the first time one of their kind opens (live, cases, team, tools,
apps, rss, games, me), each under the 14 KB budget; `assets/css/widgets-x.css` holds their shapes. The alarm is its own
takeover above the panel: it rings by itself for the rules the Chairman or the Secretary turned on, or when tested.
Everything a widget needs is one `widgets.php` call; every save is `workspace-act.php`.
