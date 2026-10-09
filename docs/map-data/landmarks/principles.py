"""
Design principles the interpretation step leans on when the data is silent, with where each came from, and a check that tells a sheet when it breaks them.

The rules are of two kinds. Facts of the building type that every source agrees on (a Catholic church is a cross on plan, its dome sits on a drum over the crossing; an airport
terminal separates departures and arrivals by level and puts its gates on the airside). And rules of thumb that the web search could not give numbers for: for those the numbers
here are taken from the buildings of this map (the satellite metre grid and the street views) and marked "measured on the map" so that nobody mistakes them for a standard.
Sources: Britannica "church architecture"; Wikipedia "Transept"; Buildings of Ireland survey records (Galway Cathedral, Carndonagh); O'Brien & Keane, Holy Name of Jesus Cathedral;
archgyan.com "How to design an airport"; Campbell Co. project page for NAIA Terminal 3; GMA News on the NAIA 3 curbside canopy (2026).
"""

CHURCH = dict(
    plan='A Catholic church is cruciform: a nave, a crossing where nave, chancel and transepts meet, a sanctuary (apse) opposite the entrance. (Britannica, Wikipedia "Transept")',
    crossing='Over the crossing stands a dome on a drum (or a tower or a spire). A drum is a short cylinder or an octagon with windows; the dome is taller than a hemisphere when it is the main feature. (O\'Brien & Keane; Buildings of Ireland)',
    front='The entrance front is a gable or an arch facing the street, often with the bell towers or small domes at its corners, set back from the facade. (Buildings of Ireland, Galway Cathedral)',
    dome_to_nave=(.75, 1.15, 'the main dome is about as wide as the nave (measured on the map: the Shrine of St. Therese 20 m dome over a 24 m nave)'),
    drum_to_dome=(.12, .35, 'drum height as a share of the dome diameter (measured on the map: .16 at the Shrine)'),
    small_dome_to_main=(.3, .55, 'the flanking domes are a third to half of the main dome (measured on the map: .4)'),
)

TERMINAL = dict(
    levels='Departures and arrivals are on different levels, with a kerb road for each (a viaduct for departures); processing sits in the middle, the gates on the airside. (archgyan; Campbell on NAIA 3)',
    form='NAIA Terminal 3 is a linear terminal: a main terminal building with a north and a south concourse, each concourse centred on a two-storey skylit atrium, gates along the airside. (Campbell)',
    roof='Large halls are covered by long vaults or a pitched roof that brings daylight to the middle; the landside has a canopy over the kerb (a new one was fitted in 2026). (archgyan; GMA)',
    gate_spacing=(35, 70, 'the distance between jet bridges along a concourse (measured on the map from the OpenStreetMap gate nodes: 40 to 55 m at NAIA 3)'),
    vault_width=(25, 40, 'the width of one roof vault (measured on the map: 35 m at NAIA 3)'),
)

KINDS = dict(church=CHURCH, terminal=TERMINAL)


def church_defaults(R):
    """Missing numbers of a dome of radius R: a drum a bit more than a seventh of the diameter... (principles marked 'measured on the map')."""
    return dict(drum=round(R * 2 * .16, 1), rise=round(R * .86, 1))


def check_church(sh):
    out = []
    doms = [f for f in sh.get('features', []) if f.get('type') == 'dome']
    if not doms:
        return out
    main = max(doms, key=lambda f: f['r'])
    for f in doms:
        if f is main:
            continue
        r = f['r'] / main['r']
        lo, hi, why = CHURCH['small_dome_to_main']
        if not lo <= r <= hi:
            out.append('a flanking dome is %.2f of the main dome (usually %.2f to %.2f: %s)' % (r, lo, hi, why))
    lo, hi, why = CHURCH['drum_to_dome']
    d = main.get('drum', 0) / (2 * main['r'])
    if not lo <= d <= hi:
        out.append('the main drum is %.2f of the dome diameter (usually %.2f to %.2f: %s)' % (d, lo, hi, why))
    return out


def check(sh):
    use = sh.get('use')
    return check_church(sh) if use in ('shrine', 'church', 'chapel') else []
