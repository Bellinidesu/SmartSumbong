# Roles and pages (ready for Barangay 183)

What each person in the barangay sees and does in the portal, page by page,
as decided with Ace between 29 and 30 October 2026 after Sir Kiko's notes
(the barangay's IT administrator and the team's adviser). This is the plan
the build follows; each step below links to the change that delivered it.
Decisions marked *open* wait on Sir Kiko (meeting of Monday 2 November).

The system stays general: nothing here is written for Barangay 183 alone.
Committees, categories, colours, rules and wording are all set by a super
admin, so another barangay sets up its own.

## 1. The ladder

| Rung | Role in the portal | Default access |
|---|---|---|
| Chairman (Punong Barangay) | Super admin, automatically | Everything |
| Kagawad | Admin of a committee | Their committee's categories and cases |
| Staff (the secretary and others) | Moderator, assigned to a committee | Their committee's cases, without the decisions that change who is accountable |
| Tanod | User | The app only, no portal |

A super admin can raise someone above their rung: Sir Kiko is staff by rank
and super admin by choice. **DEV** marks the development team (the
debugger); for now it is a title only. A view-only **captain** tier exists
for barangays that want one; Barangay 183 does not use it.

Built so far (0151): a staff member (the *moderator* tier) is assigned to a
committee by a super admin and sees and works that committee's cases like
its Kagawad, but cannot approve or deny an escalation, escalate up the
ladder, hand a case to a higher official or refer it outside. Setting a
position sets the tier that goes with it (Chairman super admin, Kagawad
committee admin, secretary moderator); someone a super admin has raised to
super admin stays one.

*Open:* the moderator's exact powers (Sir Kiko).

**Seeing every rung (0162).** A member of the development team (DEV) has a real test account for each rung: super admin, captain, Kagawad and staff (the Kagawad and staff in a committee they pick). The DEV switcher in the sidebar signs into one with no password and back; a striped band says whose eyes these are. Because it is a real account of that rung, the database shows exactly what that rung may see and do. Test accounts are marked TEST and are never the Kagawad the system asks to pick a tanod; every switch is recorded.

## 2. Committees and colour (locked)

- Barangay 183 keeps three committees: Peace and Order (with Human Rights,
  Transportation and Communication), Environmental Protection and Disaster
  Risk Reduction, and Health and Sanitation. The others on the Kagawad list,
  BADAC included, are not created.
- A super admin makes and edits committees in **Administrative Services**:
  names in English and Tagalog, the categories it sees, on or off, and its
  **colour**, chosen from a palette or any colour.
- **One super admin colour** for every super admin, branding blue by default.
  No committee can use it or anything close to it ("too close" is taken, so a
  screenshot is never ambiguous). If the super admins change their colour,
  branding blue becomes free for committees.
- A committee admin's **sidebar wears the committee's colour**, with a banner
  naming the committee, so a screenshot says which committee it came from.
  Super admins keep the super admin colour.
- **The ladder colours** are vivid and locked: Staff cyan (#00A3C4 light,
  #00E5FF dark), Tanod green (#00A651 / #1DF08A), Kagawad violet
  (#8A2BE2 / #B66CFF), Chairman red (#FF1744 / #FF3D6E) with a gold ring
  (#FFB000 / #FFD400). They show as pills with a glowing dot and on avatar
  rings.

## 3. The pages

| Page | Super admin | Kagawad | Staff |
|---|---|---|---|
| Dashboard | Yes | No | No |
| Report Summary | Overall, plus a Committee filter and a By committee tab | Their committee's version | Their committee's version |
| Spatial Distribution | Yes (plan *open*, discussed later) | Yes | Yes |
| Case Reports | All, committee chips, forwarding | Their committee's, forwarding | Their committee's, can flag for forwarding |
| Notifications | All, system alerts included | Their committee's; forwarded and flagged cases pinned on top | Their committee's |
| Inbox (new) | Yes | Yes | Yes |
| Residents | Yes | No | No |
| Personnel | Everyone, by committee | Their staff and their tanods | Their committee's |
| Administrative Services (renamed) | Committees, administrators, retirement requests, tanod-to-committee approvals, Planning | Retirement requests: view and review; can endorse a staff member's | No |
| Control Room (new) | Complaint types, rules, hotlines, wording, the barangay's name and seal, parts of the system | No | No |
| Settings | System status, plan and usage, SMART, appearance | No | No |
| Edit Profile | Their own | Their own | Their own |

### Dashboard (super admins)

- *Needs me today* (waiting for a super admin decision, overdue, not taken
  by any committee, open now) is one summary band across the top, and *The
  committees* (open, overdue for each, who leads it, plus "No committee yet")
  is a card of rows: a committee's name is a name, not a pill. (1 Nov: the
  band replaced the four tiles under the donut.)
- The engine is **one brain button** in the Dashboard's header, with a count
  of what needs attention; it opens the engine's **window** from the right
  ("What the engine sees": the urgent and at-risk cases, recurring problems,
  quiet cases, spikes, when complaints come in, on time by kind) and, under
  "About the charts", explains *Total reports received* and *Resolution
  efficiency*. (1 Nov: this replaced the engine bar and the brain buttons on
  those two charts.)
- Pressing a donut segment or its name opens a **big box beside the donut**
  with that status's or category's cases and an *Open in Case Reports*
  button.
- *Built (0156):* `dashboard_committees`, `dashboard_slice` (the box, the
  donut's own buckets) and `smart_chart_notes` (facts the page words in
  English or Tagalog).

### Report Summary

- Super admins get the overall report, a **Committee filter** beside the
  category filter (the orange bar takes the committee's colour), a scope
  pill beside the title, a Committee column in the Ledger and Escalations
  (overall only), and a fifth tab, **By committee** (logged, resolved,
  overdue and average resolution time for each committee).
- *Built (0156):* the filter (`?com=`), the pill, the column, the tab and the
  committee form (`complaint-summary.php?com=`) are in the portal; the
  committee of each case is the `case_committee` column (0152).
- A committee's version: its ledger, escalations and timelines only; tanod
  attendance only for tanods who worked its cases. Its PDF names the
  committee, the Kagawad signs as head and the Chairperson notes it.

### Case Reports: forwarding

- **Committee chips** above the table, each in its colour with a count
  (All, each committee, red *No committee yet*; a Kagawad also gets
  *Forwarded to me* and *Flagged to forward*).
- **Forward to committee**, beside Review, and in bulk with row checkboxes.
  Who forwards: a super admin and a Kagawad (super admin to Kagawad, Kagawad
  to super admin, Kagawad to Kagawad). Forwarding to a super admin is not an
  escalation: escalation asks the Chairman to decide; forwarding hands the
  case over to be placed.
- **Staff flag a case for forwarding** with a message saying why; their
  Kagawad decides.
- Every forward and flag is written to the case's history, which cannot be
  edited. A forwarded case carries a "Forwarded from …" tag.
- This needs a per-case committee: today a case's committee comes only from
  its category.
- *Built (0152):* `reports.committee` is set only by forwarding (null: the
  category's committee, as before); `reports.awaiting_placement` marks a case
  a Kagawad handed to the super admins, which no committee sees until it is
  placed. The functions are `forward_case`, `flag_case_for_forward` and
  `dismiss_forward_flag`; the log is `case_forwards` and the open flags are the
  view `case_forward_flags`. The portal side is `admin/includes/forwarding.php`.

### Notifications

- Forwarded and flagged cases are **pinned at the top** for the Kagawad.
- Repeated engine warnings ("waited N min without a tanod") collapse into
  one row that opens to show the cases.
- Committee chips; a committee dot on every case notification; system alerts
  for super admins only; the *Right now* strip follows the version.
- *Built (0152, 0155, 0156):* the pins, the chips (`?ncom=`, filtered by the
  `notification_committee` column), the dot, the grouped warnings (one page at
  a time), and `_notifications_scope` keeping system alerts from a
  committee's admins.

### Inbox (new)

An intranet mail inside the portal. System messages (reroute questions,
flags, forwards) arrive there and can be answered; admins can also write to
each other, each message able to carry a case. Mail runs **along the
ladder**: staff to their own Kagawad; a Kagawad to their staff, other
Kagawads and super admins; super admins to anyone.

*Built (0155):* `admin/inbox.php` (Inbox, Sent, Write, one message); the
tables `inbox_messages` (one row per recipient) and `reroute_questions`;
`send_mail` checks the ladder, `mail_recipients` lists who one may write to.
A captain writes to the super admins. On a reroute, `auto_dispatch` tries the
case's committee's tanods only (`_reroute_ok`); none free, `_reroute_ask`
asks the Kagawad; `answer_reroute_question` and the every-minute
`sweep_reroute_questions` finish it. The waits are
`operational_settings.reroute_ask_urgent_minutes` and `reroute_ask_minutes`.

### Personnel

- **Tanods are assigned to committees** by knowledge and collaboration: a
  committee proposes, a super admin approves. A tanod can belong to several
  committees (a pill for each); one who fits only one committee appears only
  there. A tanod with no committee is seen by super admins only.
- Tanods keep their four statuses (On Duty, Lunch, Break, Offline).
- Kagawads and staff get an **automatic punch card**: when they signed in
  and out and the cases they touched, built from the sign-ins and the case
  history. Super admins see every card; a Kagawad sees their staff's.
- When a tanod is on a case, other committees see only that committee's pill,
  never the case.
- **Automatic reroute** (a tanod did not accept in time) picks from the
  case's committee's tanods first. If none is free, it **asks the Kagawad**
  (pinned notification, web push, Inbox) with a countdown; if nobody answers
  it sends the nearest tanod from any committee and says so. The wait is
  5 minutes for urgent cases and 15 for the rest, set in the Control Room.
- *Built (0153), except the reroute (step 5):* `tanod_committees` (proposed
  or approved, with the committee's role) and its log; `propose_tanod_committee`,
  `decide_tanod_committee`, `remove_tanod_committee`, `tanod_pick_list` (names
  only, so a Kagawad can propose a tanod they cannot otherwise see) and
  `personnel_committees`. `account_directory` shows a committee's admins only
  their tanods. The punch card is `admin_punches` (written by the portal at
  sign-in and sign-out, Kagawads and staff only) and `punch_cards`. The portal
  side is `admin/includes/personnel_committees.php`.

### Administrative Services and the Control Room

- *Administrative Services* (renamed from Extra Administrative Services):
  committees and who sees what, administrator accounts, retirement requests,
  tanod-to-committee approvals, Planning. A Kagawad views and reviews
  retirement requests and can endorse a staff member's to a super admin.
- *Control Room* (new): complaint types and options, urgency levels,
  deadlines and limits, hotlines, wording, the barangay's name, place and
  seal, and the parts of the system that can be switched off.
- *Settings* keeps System status (technical cards for every super admin),
  Plan and usage, SMART and Appearance.

### Edit Profile

A banner of the person's own picture (separate from the avatar, draggable)
or a preset (the barangay's contour pattern, a solid colour, the committee's
colour); the default is the person's sidebar colour. It shows the rung pill,
the tier and the committee; a punch card summary of today; alert switches
for forwards, flags, reroute questions and Inbox messages.

*Built (0157):* `users.banner_preset`, `banner_colour`, `banner_url`,
`banner_y`, set through `set_my_banner`; the alert kind `inbox_mail`, raised by
a trigger on `inbox_messages`. The Kagawad's endorsement is
`retirement_requests.endorsed_*` and `endorse_retirement`, read through
`retirement_requests_queue` (Personnel > Retirement requests for a Kagawad).

## 4. Build order

| Step | What | Status |
|---|---|---|
| 1a | Pages: Administrative Services and the Control Room take their tabs from Settings | Built (this PR) |
| 1b | Committee colours and creator, the super admin colour, committee sidebars, vivid ladder | Built (0150) |
| 2 | Roles: moderator tier, staff assigned to a committee, the Chairman as super admin, each rung's pages | Built (0151) |
| 3 | Forwarding: per-case committee, forward and flag, history, pinned notifications, Case Reports chips | Built (0152) |
| 4 | Personnel: tanods to committees with approval, each version's view, the punch card | Built (0153) |
| 5 | Inbox and the reroute question | Built (0155) |
| 6 | Dashboard, Report Summary and Notifications changes | Built (0156) |
| 7 | Edit Profile banner, retirement endorsement | Built (0157) |

Spatial Distribution is discussed later.
