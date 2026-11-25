# Live updates

Ace, 25 Nov 2026 (approved by Rose, who owns the looks): *"all pages and everything that appears and pops up in any press must
update itself without needing constant reloads."* This is how the portal does it, how to give a page its live parts, how to turn
it off, and what is still to do (the portal's remaining pages and the app).

## How it works

```
a change in the database ──▶ Supabase Realtime ──▶ live.js (the page's one connection)
                                   (or, while Realtime is down: every 25 s, tab visible)
                                                  │  wait 500 ms (bursts become one), at most one refetch every 3 s
                                                  ▼
                       GET <the same address>   X-Live: 1, same origin, the person's own session
                                                  │
                                                  ▼
          for each data-live part whose HTML changed:  free? ──yes──▶ morph it in place, tint what changed
                                                         │
                                                         no (typing, a dialog, a menu, an opened <details>, a press)
                                                         ▼
                                         wait; apply when they are done; after 10 s a chip offers it
```

- **The server still draws everything** and still decides who may see what. Realtime is only the signal that something changed;
  its payload is never trusted or patched in (row level security also filters which signals reach whom).
- **One shared layer**: `admin/assets/js/live.js` (external, nonce-loaded, no inline handlers) and `admin/assets/css/live.css`,
  written into the page by `live_head()` (`admin/includes/live.php`, called from `layout_head()`) only when the page opted in and the
  switch is on.
- **The page's one connection**: live.js opens its channel on `window.ssSupabase` (the client presence.js already shares), so a tab
  holds one websocket. It removes its channel on `pagehide` and joins again when the page comes back from the back-forward cache.
- **The morph** keeps each element that is still there (matched by `id`, then by `data-live-key`, then by position and tag), so a
  button keeps its listeners, a field keeps what was typed, a scrolled box its scroll, a `<details>` its open state, a tab its
  selection. Only attributes, text and children that differ change. A script in a refetched page never runs.
- **What holds a part** (it waits, the rest of the page still updates): the focus in a field being typed in or chosen from; a field
  changed and not saved; an open `<dialog>` or `role="dialog"` panel in or around it; an open menu (`aria-haspopup` with
  `aria-expanded="true"`, a popover); a `<details>` the person opened by hand; a text selection in it; any press on its way (htmx);
  one of the portal's dropdowns, calendars or modals open; a page's own rule (`window.ssLiveBusy(el)`, Case Reports: ticked rows or
  the forward dialog). A field that only had the focus applies once the focus leaves; a field with typed text waits until it is
  saved or emptied, or until the person presses the chip (**Show the update**), which applies it and keeps what was typed in every
  field that is still there.
- **A press is newer than a refetch**: when someone presses something in place (htmx), anything already fetched is dropped and the
  page is asked for again after the press settles, so the rest of the page follows the press and never goes back to before it.
- **The badge** (`#live-badge`): **Live** while the channel is joined, **Polling** (amber) while Realtime is down or the join was
  refused, **Offline** when the browser is offline. English and Tagalog come from the server (`t()`), so the wording catalogue has them.
- **A page that is no longer this person's** (a redirect, 401, 403, 404, or none of its parts in the answer: the case moved to a
  committee they cannot read, their rung changed, they were signed out) gets a calm line at the top with **Open it again**; live
  updates stop on that page.
- **Background refetches are not use**: a page refetching itself does not keep the session alive (the two-hour idle sign-out still
  applies), and it never takes away a one-time message (a save's green or red line) meant for the next page. The sidebar's counts are
  kept 5 s for a live refetch (a minute otherwise), so a count follows the change it was refetched for.

## Pages

| Page | Live parts | Tables (filter) | Notes |
| --- | --- | --- | --- |
| Case page `case.php` | `case-flags` (status pill, badges), `case-sla` (countdown), `case-tabs` (timeline count), `case-body` (report, field report, concerns, Why this level, timeline, feedback, the map's side panel), `case-controls` (where the case is, owner, handler, committee, dispatch, Next step, the tiles that lock and unlock), `case-ver` | reports (`id`), status_logs, dispatches, escalation_requests, case_handler_log, report_messages (`report_id`), dispatch_updates (`dispatch_id=in.(…)`) | Feedback, field photos, concerns and forwards are in no publication: the page's 25 s light poll (feedback, proof photos) and the 2-minute safety check bring them. Forms brought up to date carry the new case version; forms that waited keep theirs (the stale-case guard). The chat head still refreshes itself on a message. |
| Case Reports `cases.php` | `cases-list` (figures, filters, list, pager) | reports (all the person may read), notifications (`user_id`) | The address is the view (filters, page, search, sort), so a refetch shows the same view. Ticked rows or the forward dialog hold the list. |
| Notifications `notifications.php` | `notes` (the list and the rail: waiting on you, right now) | notifications (`user_id`) | A folded group opened by hand holds the list. |
| Dashboard `dashboard.php` (this month only) | `dash-brain`, `dash-peek`, `dash-panel` (the engine's window) | reports | The charts redraw themselves from `dashboard_metrics` (since Sep); the page is heavy, so at most one refetch every 15 s. A past month does not change and does not listen. |
| Every live page | `side-nav` (the sidebar's counts) | | The Inbox's chats bubble is left to chat-head.js. |

Still to do (each keeps what it had; none is broken by this):

| Page | What it has today | Next step |
| --- | --- | --- |
| Inbox `inbox.php` | the chat head polls every 15 s, the sidebar pill every 60 s | mark the conversation list `data-live`, tables report_messages and dispatch_updates for the person's cases |
| Residents, Personnel `residents.php`, `personnel.php` | their own Realtime (verification queue) and the press flow's quiet refresh (`ssPress.refresh('#people-list')`) | `users` is not published (0046, privacy): polling only; mark `people-list` and move its refresh to the layer |
| Report Summary `summary.php` | its own Realtime for an open period | mark the period's parts |
| Spatial Distribution `spatial.php` | its own Realtime on reports (the map redraws its pins) | leave the map to itself; the panels could be marked |
| Activity `activity.php` | its own Realtime and `ssPress.refresh('#act-list')` | move to the layer (one line each) |
| Retirement requests, Administrative services | own Realtime on retirement_requests | mark the queue |
| Settings, Profile, Control Room, the committee editor | none (forms people fill) | leave as they are: nothing there changes under a person but their own saves |
| Workspace, command center, hall display | switched off until after the defense | |
| Complaint print, Complaint summary, Certificate | documents to print | none needed |
| The sign-in pages' At a glance panel (glance.js) | public weather and advisories every 5 minutes | fine as it is: not case data |

## Giving a page its live parts

1. Before `layout_head()`, opt in with the tables whose changes concern the page and, where the page is about one thing, a filter:

   ```php
   live_page('case', ['reports' => 'id=eq.' . $id, 'status_logs' => 'report_id=eq.' . $id], ['gap' => 3]);
   ```

   Only the tables in the `supabase_realtime` publication are kept (`LIVE_PUBLISHED` in `includes/live.php`: case_handler_log,
   detail_requests, dispatch_updates, dispatches, escalation_requests, notifications, report_messages, reports, retirement_requests,
   status_logs). Options: `poll` (seconds between checks while Realtime is down, default 25, at least 15), `safety` (between checks
   while it is up, for what no table pushes, default 120), `gap` (the least seconds between two refetches, default 3; heavy pages more).
   Opt in only when the page can be drawn (not on its error page): an answer without the page's parts is read as "no longer yours".
2. Put `data-live="name"` on **stable wrappers**: an element that is on the page whatever the data (or a placeholder where it may
   appear later: `<template data-live="case-sla"></template>`; a part whose tag changes is replaced whole). Names are unique on the
   page. Do not nest live parts. Do not put scripts inside one.
3. Give list rows a key: `data-live-key="<id>"` (rows, timeline entries, notifications), so an insert at the top moves the others
   instead of rewriting every row.
4. Mark what a script owns:
   - `data-live-skip`: the morph leaves the element alone (a map container, a street-view picture, presence's "Also here now", a
     countdown's text, the chats bubble).
   - `data-live-keep="hidden required"`: attributes a script sets that the morph keeps (the deny panel's `hidden`, the reason's
     `required`). `open`, `aria-expanded`, `aria-selected` and `tabindex` are always kept on elements that stay.
   - `data-live-own` on an element a script added (the case forms' version input): the morph steps over it and never removes it.
   - `data-live-quiet`: changes inside are applied but never tinted (a "Today · 3:40 PM" line). `.p-when` (relative times) is quiet too.
5. Bind presses from the document (`document.addEventListener('click', e => e.target.closest('#deny-toggle') …)`), not to a button an
   update could replace. A widget that draws into a part sets itself up again from `ssPress.ready()` (the portal's dropdowns and
   choosers already do; live.js calls `ssPress.init(part)` and `htmx.process(part)` after each update) or listens for:
   - `ss:live` on `document` after parts were updated: `e.detail.regions` (names), `e.detail.els` (elements);
   - `ss:live-event` on `document` for each Realtime signal: `e.detail.table`, `e.detail.type` (the chat head and the Dashboard's
     charts use it).
6. While live updates are on, a page's own old channel steps aside (`if (window.ssLiveLayer && window.ssLiveLayer.active) …`), so the
   page still has one channel; with them off, the old code runs unchanged.
7. Add the page to the table above and to a test in `tests/browser/live.spec.mjs`.

Looking into it in a browser's console: `ssLiveLayer.mode` (live, poll, off), `ssLiveLayer.stats` (fetches, parts applied, parts
waiting), `ssLiveLayer.waiting()` (what holds each waiting part), `ssLiveLayer.kick()` (check now), `ssLiveLayer.applyNow()`.

## The kill switch

Any one of these turns live updates off; off, every page behaves exactly as before (case.php's "Refresh to see it" banner, Case
Reports' and the Dashboard's own channels).

| Where | How | Takes effect |
| --- | --- | --- |
| Settings > Parts of the system | a switch row `live_updates`; turn it off there | at once for new pages; an open page stops at its next refetch. **No redeploy.** |
| Render > smartsumbong-ph > Environment | `LIVE_UPDATES=off` | Render restarts the service when it is saved (about a minute) |
| One browser | `localStorage.setItem('ss-live', 'off')` in the console (or `window.SS_LIVE_OFF = true` before the page loads); `removeItem('ss-live')` to undo | that browser's next page |

The switch row does not exist until it is added once (the backend is frozen: no migration; a missing row means **on**). In the
Supabase SQL editor, as a data change:

```sql
insert into public.feature_switches (key, label_en, label_fil, enabled, note)
values ('live_updates', 'Live updates', 'Live na update', true, 'Pages update themselves (25 Nov 2026). Off: every page as before.')
on conflict (key) do nothing;
```

From then on it is a toggle in Settings > Parts of the system (`feature_set()`, which keeps the change in SMART's events). With the
feature cache (`FEATURE_CACHE_TTL`, 300 s on Render) a flip reaches every page within five minutes, at once for the person who flipped it.

## Realtime on the free plan

As published by Supabase for the Free plan (check https://supabase.com/docs/guides/realtime/limits before relying on a number):
about **200 concurrent connections**, **100 messages per second**, **100 channel joins per second**, **100 channels per
connection**, **2 million messages a month**. A tab holds one connection (presence and the page's live channel share it, since 7 Nov),
so 200 is about 200 open portal tabs and phones together. Postgres Changes checks every change against every subscriber's row level
security on one thread, so at the barangay's volume (a few changes a minute) it is far inside the limits; a city-wide deployment
would move the case signals to Broadcast from a trigger. When the connection is refused or drops, pages fall back to polling every
25 s (one page request per open, visible tab), so the plan's limits slow the updates down, never stop them.

## What the tests cover, and what they do not

`tests/browser/live.spec.mjs` runs against the fake Supabase, which since 25 Nov has a small Realtime socket (Phoenix serializer
2.0.0 and 1.0.0) answered only for a browser carrying its test's `ss_rt` cookie, so the other specs still see no socket. It covers:
a push updates the case in place and keeps the elements; typed text is never clobbered and the chip applies it; a focused field, an
open dialog and an opened `<details>` hold their part and release it; the tab and the scroll stay; polling when the socket is down
and when a join is refused; both kill switches; switched off while a page is open; the "no longer yours" notice (a staff member who
cannot read the case); Case Reports with a ticked row; a new notification and the sidebar's count; the Dashboard's one connection;
nothing while the tab is hidden; no console errors; axe on the updated case page and on the Polling badge.

Not proven by the fake (to watch on the live portal): the real Realtime server's join replies and row level security filtering per
rung (a Kagawad, staff); reconnects after a laptop sleeps or the network changes; token renewal on a page left open for hours (the
existing `ssAccessToken` path); the free plan's connection limit under many tabs; the feel of the tint and the chip on Ace's 24"
screen and on a phone; Render's own timing for a full case page refetch (each refetch is one page render: about the same as opening it).

## The app (audit, 25 Nov 2026; no change made: the app is with the testers)

What each screen of `mobile/resident/lib` listens to, and where it goes stale after a status change made on the portal:

| Screen | Listens | Stale after |
| --- | --- | --- |
| Resident Home `screens/home_screen.dart` | notifications (`user_id`), reloads on resume, flood reading every 10 min | a case's status on its cards updates only through a notification row |
| Notifications `screens/notifications_screen.dart` | notifications (`user_id`) | fine |
| My reports `screens/reports_screen.dart` | reports (`resident_id`) | concerns resolved (report_concerns is not published) until the report row itself changes |
| View report `screens/report_view_screen.dart` | reports UPDATE (`id`), status_logs INSERT (`report_id`) | a tanod assigned or accepting (dispatches), proof photos (dispatch_media), barangay photos (report_evidence), a concern resolved (report_concerns), a detail request (detail_requests is published but not listened to here), the resolution check: all until the next report update or reopening the screen |
| Ask the barangay `screens/report_messages_screen.dart` | report_messages INSERT (`report_id`) | fine |
| Map `screens/map_screen.dart` | none (reads once) | published incidents and own pins until reopened |
| Account status, Verification pending | none; Verification pending reloads on resume and a 30 s cooldown on its refresh button | approval of the account (users is not published, 0046) until resume or refresh |
| Emergency, Settings, report form screens | none | fine (no case data) |
| Tanod Home `tanod/screens/tanod_home_screen.dart` | dispatches (`tanod_id`), reloads on resume | the case's own status or escalation by the portal without a dispatch change |
| Tanod reports `tanod/screens/tanod_reports_screen.dart`, History `history_screen.dart` | dispatches (`tanod_id`) | same as above |
| Dispatch window `tanod/screens/dispatch_window.dart` | dispatch_updates INSERT (`dispatch_id`), dispatches UPDATE (`id`), detail_requests (`report_id`) | the case resolved, escalated or handed to another committee on the portal while the dispatch row stays the same; concerns resolved on the portal |
| Retirement, Extra admin services `tanod/screens/retirement_screen.dart`, `extra_admin_services_screen.dart` | none (reads `my_retirement_status` once) | a decision on the request (retirement_requests is published) until reopened |

For later, in order: View report listens to dispatches (`report_id`) and detail_requests; the dispatch window to reports (`id`) for
status and escalation; the retirement screens to retirement_requests (`requested_by`); report_concerns either joins the publication
(a migration, after the defense) or the screens re-read concerns on any reports or status_logs signal.
