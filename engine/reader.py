"""What an ID card says, from the lines an OCR model read off it.

The same reading the app did on the phone until 22 Oct 2026 (mobile/core/lib/src/id_ocr.dart), moved to the
engine: which kind of card it is, the name, and the ID number. Nothing here decides anything; the database
compares the reading with what the resident registered (_smart_verify, 0126) and an administrator decides.
Pure Python, no OCR model, so the tests run anywhere.
"""
import re

# Header phrases printed on each kind of card (the id_document_type values). Several per kind: a cropped or
# glare-washed photo can still give back part of one. REPUBLIKA NG PILIPINAS is on nearly every card, so not here.
HEADER_HINTS = {
    'drivers_license': ["DRIVER'S LICENSE", 'DRIVERS LICENSE', 'LAND TRANSPORTATION OFFICE', 'NON-PROFESSIONAL', 'PROFESSIONAL DRIVER'],
    'passport': ['PASSPORT', 'PASAPORTE', 'DEPARTMENT OF FOREIGN AFFAIRS'],
    'philsys': ['PHILIPPINE IDENTIFICATION CARD', 'PAMBANSANG PAGKAKAKILANLAN'],
    'postal_id': ['POSTAL ID', 'PHLPOST', 'PHILIPPINE POSTAL'],
    'barangay_id': ['BARANGAY ID', 'BARANGAY IDENTIFICATION'],
    'barangay_appointment': ['APPOINTMENT', 'DESIGNATION', 'TANOD'],
}

# A label, then the value on the next line (PhilSys and the driver's licence print them this way).
NAME_LABELS = {
    'last': ['APELYIDO', 'LAST NAME', 'SURNAME', 'SUMAME'],   # rn read as m
    'given': ['MGA PANGALAN', 'GIVEN NAME', 'GIVEN NAMES', 'PANGALAN'],
    'middle': ['GITNANG APELYIDO', 'MIDDLE NAME'],
    'full': ['NAME'],
}

LTO_NUMBER = re.compile(r'\b[A-Z]\d{2}-\d{2}-\d{6}\b')       # a driver's licence: N01-23-456789
ANY_NUMBER = re.compile(r'\b\d[\d\- ]{4,}\d\b')


def levenshtein(a, b):
    if a == b:
        return 0
    prev = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        cur = [i]
        for j, cb in enumerate(b, 1):
            cur.append(min(cur[j - 1] + 1, prev[j] + 1, prev[j - 1] + (ca != cb)))
        prev = cur
    return prev[-1]


def fuzzy_contains(hay, needle, rate=0.22):
    """The phrase is in the text, allowing about one slip in five letters (phrases of six letters or more)."""
    if not needle:
        return False
    if needle in hay:
        return True
    if len(needle) < 6:
        return False
    errors = int(len(needle) * rate)
    if errors == 0:
        return False
    lo, hi = max(1, len(needle) - errors), min(len(hay), len(needle) + errors)
    for start in range(0, len(hay) - lo + 1):
        for n in range(lo, hi + 1):
            if start + n > len(hay):
                break
            if levenshtein(hay[start:start + n], needle) <= errors:
                return True
    return False


def _name_like(value, lo, hi):
    """Capitals, mostly letters, of a sensible length: how a name is printed on a card."""
    if not (lo <= len(value) <= hi) or value != value.upper():
        return False
    bare = value.replace(' ', '')
    letters = re.sub(r'[^A-Za-z]', '', bare)
    return bool(bare) and len(letters) >= len(bare) * 0.7


def name_by_label(lines):
    parts, used = {}, set()
    for i in range(len(lines) - 1):
        line = lines[i].upper()
        for key, hints in NAME_LABELS.items():
            # one value line answers one label: "Last Name, First Name, Middle Name" is one label over one line
            if key in parts or i + 1 in used or not any(fuzzy_contains(line, h) for h in hints):
                continue
            value = lines[i + 1].strip()
            if _name_like(value, 2, 40):
                parts[key] = value
                used.add(i + 1)
    joined = ' '.join(parts[k] for k in ('last', 'given', 'middle') if k in parts).strip()
    return (joined or parts.get('full') or '').replace(',', ' ').replace('  ', ' ').strip() or None


# Words on the card that are never part of a person's name: mastheads, offices, labels, months.
NOT_NAME = set("""REPUBLIKA REPUBLIC PILIPINAS PHILIPPINES PHILIPPINE PAMBANSANG PAGKAKAKILANLAN DEPARTMENT OFFICE
CORPORATION AUTHORITY NATIONAL LUNGSOD CITY BARANGAY ZONE PASAY CARD IDENTIFICATION IDENTITY LICENSE DRIVER DRIVERS
POSTAL PHLPOST TRANSPORTATION FOREIGN AFFAIRS PASSPORT PASAPORTE SIGNATURE ADDRESS NATIONALITY SEX DATE BIRTH
EXPIRATION VALID UNTIL PRN BLOOD TYPE APPOINTMENT DESIGNATION TANOD OF THE NG SA AND JANUARY FEBRUARY MARCH APRIL MAY
JUNE JULY AUGUST SEPTEMBER OCTOBER NOVEMBER DECEMBER""".split())


def _plain_name(line):
    words = re.findall(r"[A-Z][A-Z'.-]*", line.upper())
    return _name_like(line, 2, 60) and words and not any(w.strip('.') in NOT_NAME for w in words)


def name_lines(lines):
    """The name when no label survived: a "SURNAME, GIVEN" line, or else the longest run of name-like lines
    in a row (PhilSys prints surname, given names and middle name one under another), up to three."""
    cands = [l.strip() for l in lines]
    for l in cands:
        if ',' in l and _plain_name(l):
            return l.replace(',', ' ').replace('  ', ' ').strip()
    best, run = [], []
    for l in cands + ['']:
        if l and _plain_name(l) and len(run) < 3:
            run.append(l)
            continue
        if sum(map(len, run)) > sum(map(len, best)):
            best = run
        run = [l] if l and _plain_name(l) else []
    return ' '.join(best) or None


def id_number(text):
    m = LTO_NUMBER.search(text.upper())
    if m:
        return m.group(0)
    m = ANY_NUMBER.search(text)
    if not m or len(re.sub(r'\D', '', m.group(0))) < 6:
        return None
    return m.group(0).strip()


def read_card(lines):
    """lines: the text lines, top of the card first. Returns type, name and number; all None when unreadable."""
    lines = [l.strip() for l in lines if l and l.strip()]
    text = '\n'.join(lines)
    up = text.upper()
    if len(re.findall(r'[A-Z0-9]', up)) < 12:
        return {'type': None, 'name': None, 'number': None}
    kind = next((k for k, hints in HEADER_HINTS.items() if any(fuzzy_contains(up, h) for h in hints)), None)
    # by label, or by the run of name lines, whichever found more of the name (a label can be lost to glare)
    found = [n for n in (name_by_label(lines), name_lines(lines)) if n]
    name = max(found, key=lambda n: len(n.split())) if found else None
    return {'type': kind, 'name': name[:120] if name else None, 'number': (id_number(text) or None)}


def top_down(texts, boxes):
    """RapidOCR's lines sorted by where they sit on the card, top first."""
    pairs = list(zip(texts or (), boxes if boxes is not None else ()))
    pairs.sort(key=lambda p: min(pt[1] for pt in p[1]))
    return [t for t, _ in pairs]
