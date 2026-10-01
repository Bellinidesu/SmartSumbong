# Portal v1 — the design before the preview port (kept for later)

The admin portal's look as it was on 1 Oct 2026 (commit f4db08d): the
Figma-derived pages, `app.css`, and the `refined.css` overlay that was tried
on top of it. Ace replaced it with the approved preview design ("Portal
Preview" artifact), built fresh, and asked that the old design code be kept
here, the same way shelved features stay in the repo behind flags.

Nothing here is served. The Docker image copies only `admin/` (see the
root `Dockerfile`), so these files are reference only. The data and the
actions they call are unchanged in the live pages; only the markup and
styles moved on.

To compare or restore a page: `git log -- admin/<page>.php`, or copy the
file back over its `admin/` counterpart (its includes are under
`includes/` here).
