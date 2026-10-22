"""Inside the built image: draw an invented card, read it with the real models, check the reading.
docker run --rm <image> python selftest.py   (CI does this; no network, no secret)"""
from PIL import Image, ImageDraw, ImageFont
import numpy as np
from server import ocr
from reader import read_card, top_down

im = Image.new('RGB', (900, 560), 'white')
d = ImageDraw.Draw(im)
font = ImageFont.load_default(size=34)
for y, text in [(40, 'PAMBANSANG PAGKAKAKILANLAN'), (110, '1234-5678-9012-3456'), (190, 'Apelyido / Last Name'),
                (240, 'DELA CRUZ'), (310, 'Mga Pangalan / Given Names'), (360, 'JUAN')]:
    d.text((40, y), text, fill='black', font=font)
out = ocr()(np.array(im))
card = read_card(top_down(out.txts, out.boxes))
assert card['type'] == 'philsys', card
assert card['number'] == '1234-5678-9012-3456', card
assert 'DELA CRUZ' in (card['name'] or '') and 'JUAN' in card['name'], card
print('selftest ok:', card)
