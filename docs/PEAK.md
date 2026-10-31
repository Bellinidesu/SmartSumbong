# The peak standard

What "peak" means for a screen in SmartSumbong, from the super admin to the staff. Set by Ace on 1 Nov 2026: *peak means
industry standard and the best experience of use for the person at that screen, and the peak is always the peak: the
same for every rung of the ladder.* A page is not finished until it meets every line; a role's version is the super admin's
version with less in it, never a lesser version.

Orange is the identity (the Figma band, headers, the active tab, the stylised buttons the barangay chose). The Damascus
contour lines stay in the background. A screen follows the Figma skeleton and these rules; where they conflict, the rules
about the person's work win and the look is adapted.

## 1. It answers a question before it shows a list
- Every page opens with what the person came to learn: figures that say *how they moved* against the period before and show
  *their shape*, and, where a sentence would save reading, one sentence computed from the same rows.
- A small base is not a trend: below ten, say the numbers ("from 8 before"), not a percentage.
- What needs the person (overdue, unplaced, waiting for a decision) is marked where it appears: a bar and a tint on the row.

## 2. One grammar
- A **status** is a dot and a word. A **tag** is outlined. Only what needs the eye (Overdue, Urgent, Suspended, Rejected)
  keeps a fill. A **committee** is a colour bar and its name, never a pill. A name that titles a row is never a pill.
- One table header colour on every tab and page. Orange is the main action and the identity; the red row action is locked.
- The main action is the one loud thing on the screen; the second action is outlined.

## 3. Measured, not eyeballed (docs of the rule: aesthetic symmetry)
- The audit (`tests/browser/rules-audit.spec.mjs`, `RA=1`) is clean at 2048 light and dark and at 1440 (1024 where the page
  is meant for it): nothing cut without a tooltip, no sideways scroll, rows of one height, headers over their cells, pills
  centred, no lone item on a wrapped row, every control named, no "1 numbers".
- The design width is 2048 (Ace's screen); then 1440, 1280 and the phone.

## 4. Honest data
- A figure and the list beside it count the same things (the average resolution time counts what the Resolved figure counts).
- An empty cell says something (open 12 d, or a dash for rejected), never a column of dashes.
- Real data is longer than the test data: names and addresses wrap or carry their whole text on hover.

## 5. Every state is designed
- Empty, loading, error and "nothing yet" read as sentences with a next step; popups carry the same grammar as pages.
- The live refresh draws what a reload draws, and a test compares them where a page polls.

## 6. For everyone
- Keyboard: every control reachable, focus visible, Escape closes a window and returns focus to what opened it.
- The accessibility check (axe, serious and critical) passes on every page, and with every window open.
- English and Tagalog: every string has both; the wording catalogue is current.

## 7. The ladder
- The same page for a Kagawad or staff member is the super admin's page scoped by what they may see: their committee's
  colour is the accent, the figures and the sentence speak about their committee, and nothing they may not see is drawn
  and greyed. A page is checked as each rung before it is called done (a "view as" is how the super admin does it).

## How a page is judged
Run the page tests, the rules audit and the wording and i18n checks; look at it in light and dark at 2048 and 1440; read
this list. The pull request says what was measured.
