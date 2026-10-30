# Feed rows

One look for "a line in a list of things that need you". Used by Notifications and the Inbox; Case Reports can adopt it
by adding the two attributes below to a row. The CSS is the block "The feed row" in `admin/assets/css/aesthetic.css`.

| | |
|---|---|
| Opt in | class `fr` on the row (a `div`, `a`, `summary` or `tr`), and `data-sev` = `high` \| `warn` \| `act` \| `info` |
| Edge | 3 px, coloured by severity: red act now, orange be careful, blue something to do, grey information |
| Unread | the row also has `.p-unread` or `.is-unread`: full strength and bold. Any other row goes quiet (80 %) |
| Hover | a soft background; the row's own buttons are its business |

Where the severity comes from:

- Notifications: `notif_look($kind, $message)` in `cases.php` (PHP) and `notifLook(n)` (JS, the live refresh). The kind gives a first answer
  and the message corrects it (an "is overdue" message is red; a system check or Typhoon Board notice is information).
- Inbox: a message that needs an answer is `high`, other unread mail is `act`, system and read mail are `info`.

Notifications about the same case fold into one row ("SS-2610-1003 · 2 updates on this case", `details.nf-case`) that opens to list them,
with Open the case and Mark all as read. The Inbox list shows the answer clock (`.ib-due`) on a message that waits for one, and
the open message shows its conversation (`.ib-thread`: the message it answers and the replies to it).
