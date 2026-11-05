# The press flow

What happens when someone presses something in the portal, the same on every page. Set up 7 Nov 2026.

## Why

An audit of every pressable element on every page, for each rung (super admin, Kagawad, staff), recorded what a press really
does from the listeners attached in the browser (`tests/browser/press-audit.spec.mjs`, run with `PA=1`). It found:

- **About 60 view changes that reload the whole page**: chooser tabs (Case Reports, Notifications, Residents, Personnel),
  pagers, Unread/All, sorts, the duty tiles, the Case Reports figures and filters, Report Summary's ranges, Workspace and
  Activity scopes, Inbox tabs and rows, the Dashboard month and category, the "Refresh to include it" banners.
- **About 150 forms that post and reload the whole page**, losing the scroll and the focus, with no sign that anything is
  happening, and only one (the command bar) guarding against a second press.
- **No dead presses.**

## How

[htmx](https://htmx.org) (0BSD, vendored in `admin/assets/vendor/htmx`, pinned and checked by `tools/vendor.py`). A press
fetches the page's own HTML and swaps only the part that changed. The server still renders every page and still decides who
may see what; there is no separate API. Without JavaScript every link and form works as before.

The portal's layer over it is `admin/assets/js/press.js`:

| Rule | Why |
| --- | --- |
| `allowEval: false`, `allowScriptTags: false` | The strict nonce CSP stays strict; swapped HTML never runs scripts. Widgets attach through `ssPress.ready(fn)` instead. |
| `historyCacheSize: 0`, `refreshOnHistoryMiss: true` | htmx would keep page HTML (names, numbers) in localStorage; Back fetches the page fresh instead. |
| `selfRequestsOnly: true` | A press only ever talks to the portal. |
| A thin progress bar after 120 ms | Every press answers; a fast one never flickers. |
| A failed GET opens the plain page; a failed POST says so | A press is never lost. |
| Focus stays on the pressed control, or moves to the region that changed; the change is announced | Keyboard and screen reader users are not dropped at the top of the page. |
| View transitions, unless reduced motion is asked for | A swap moves; it does not jump. |

## Rollout

1. **Foundation** (htmx, `press.js`, the widget registry, the test that proves a swap, the privacy and the fallback).
2. **Every save shows that it is working and cannot be sent twice**, site-wide.
3. **View changes swap in place**, page by page, choosers first, with the address kept so Back, Forward and refresh land on
   the same view.
4. **Frequent saves update in place**: mark as read, approve and decline, forward, toggles, Settings saves.

Each step is its own pull request, with the press audit run before and after.
