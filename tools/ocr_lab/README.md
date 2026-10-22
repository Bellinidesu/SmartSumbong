# OCR lab: can open-source OCR read Philippine IDs?

ID reading (on-device OCR, then the server's checks in 0126) has been off since
Rose's call on 27–30 Sep. It used Google's ML Kit, which is free but not open
source. This bench asks whether Tesseract (Apache-2.0) could take its place.

    py -3.12 -m pip install -r requirements.txt
    py -3.12 bench.py --tessdata <folder with eng.traineddata> [--n 12] [--save <folder>]

It draws **invented** cards (made-up names and numbers, a grey box where the
photo goes; no real card or person) in the four layouts the app recognises:
PhilSys, driver's licence, postal ID and barangay ID. It roughs each up like a
phone photo (tilt, perspective, blur, JPEG, glare, dim light) and reads it.
It scores what the app needs: the card's type, the name, and the ID number.

## Result (22 Oct 2026): Tesseract 5.5.3, tessdata_fast 4.1.0 (4 MB English model)

| Photo | Type | Name | Number | All three |
|---|---|---|---|---|
| Clean scan | 48/48 | 48/48 | 48/48 | 48/48 |
| Good phone photo | 46/48 | 43/48 | 48/48 | 42/48 (88%) |
| Poor phone photo | 30/48 | 29/48 | 36/48 | 17/48 (35%) |

- The larger `tessdata_best` models (15 MB) did no better.
- A home-made clean-up step (sharpen, flatten the lighting) made it much
  worse (3/48 on good photos), so Tesseract's own binarisation is left alone.
- These are plain invented cards. Real cards have guilloche patterns,
  holograms and laminate glare, so real accuracy will be lower than this.

## What it means

- Tesseract can be the reader for photos taken with care. It can't for hasty
  ones, which is where ML Kit tends to do better (it can't be benchmarked here:
  it only runs on the phone).
- Either way, reading stays advisory, as 0126 already treats it: "no reading"
  or a mismatch sends the account to a person, never refuses it, and **a
  reading never verifies anyone**.
- The app should guide the photo (a card-shaped frame, a "hold still" check,
  a retake button), because photo quality decides more than the engine does.

Decision for Ace: Tesseract (open, about 4 to 6 MB more in the APK, weaker on
poor photos) or ML Kit again (closed but free, better on poor photos). The
portal's ID-check queue works with either.
