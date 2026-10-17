"""The legend: one table for what a kind of place looks like, by day and by night. The walls' tint, the sign boards and awnings, the portal's legend panel and the night glow of the models all read this,
so no colour can drift from another. Written to admin/assets/map/legend.json by tools/build_legend.py.
Fields: name, day (wall tint by day), night (wall tint by night), sign (sign board and awning), glow (which of sd-models.js's eight wash colours: 1 violet, 2 teal, 3 amber, 4 blue, 5 rose, 6 green, 7 white)."""
GROUPS = [
    ('f', 'Food', '#F4D9BC', '#7A6890', '#FF9A3D', 3),
    ('c', 'Cafe', '#E7CDB5', '#6F6385', '#B8794A', 3),
    ('s', 'Shop', '#EBD8AE', '#6B6489', '#4F8CFF', 4),
    ('h', 'Health', '#F6C9C6', '#8A5F86', '#F0524F', 5),
    ('e', 'Education', '#F7E3A3', '#8C86A0', '#9B6BFF', 7),
    ('l', 'Lodging', '#DCCBEA', '#7A62A0', '#D56FE0', 1),
    ('b', 'Bank', '#C6E4CF', '#4F7F8E', '#34B36B', 6),
    ('w', 'Worship', '#C5E6EC', '#4D86A3', '#22B8CF', 2),
    ('g', 'Government', '#C9D3F0', '#5D6EA8', '#6B7FD6', 4),
    ('v', 'Services', '#F0D2E2', '#8A6597', '#E4A8C8', 5),
    ('a', 'Auto and parking', '#D3D6DC', '#5F6788', '#8E97AB', 7),
]
LANDMARK_GLOW = 3                      # amber: the one shared rim of the landmark tier
LANDMARKS = r'Marriott|Ballroom|Newport Mall|Grand Wing|Shrine|Horizon|Belmont|Terminal 3|Aerospace Museum|Church of God'
BY_TEMPLATE = {'hotel': 'l', 'mall': 's', 'school': 'e', 'civic': 'g', 'church': 'w', 'gas': 'a', 'parking': 'a', 'office': 'v', 'generic': 's', 'toll': 'a'}   # a type model with no place in it takes its type's group
GLOW = {g[0]: g[5] for g in GROUPS}
