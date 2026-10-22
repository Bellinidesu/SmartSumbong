# OCR lab: can open-source OCR read Philippine IDs?

ID reading (on-device OCR, then the server's checks in 0126) has been off since
Rose's call on 27–30 Sep. It used Google's ML Kit, which is free but not open
source. This bench asks which open-source reader could take its place:
Tesseract (Apache-2.0) or PaddleOCR's PP-OCR models (Apache-2.0), run through
RapidOCR (Apache-2.0) on ONNX Runtime (MIT), the same runtime a phone uses.

    py -3.12 -m pip install -r requirements.txt
    py -3.12 bench.py --engine paddle [--n 12] [--save <folder>]
    py -3.12 bench.py --engine tesseract --tessdata <folder with eng.traineddata> [--n 12]

RapidOCR ships its models inside the package (PP-OCRv6 small: detection
9.9 MB, recognition 21.2 MB, orientation 0.6 MB).

It draws **invented** cards (made-up names and numbers, a grey box where the
photo goes; no real card or person) in the four layouts the app recognises:
PhilSys, driver's licence, postal ID and barangay ID. It roughs each up like a
phone photo (tilt, perspective, blur, JPEG, glare, dim light) at four levels,
the last one blurred enough that a person squints, and reads it.
It scores what the app needs: the card's type, the name, and the ID number.

## Result (22 Oct 2026): all three right (type, name, ID number), 48 cards each

| Photo | Tesseract 5.5.3 (tessdata_fast) | PaddleOCR PP-OCRv6 small |
|---|---|---|
| Clean scan | 48/48 | 48/48 |
| Good phone photo | 42/48 (88%) | **48/48 (100%)** |
| Poor phone photo | 17/48 (35%) | **41/48 (85%)**: every name and number right, 7 card types missed |
| Bad phone photo (heavy blur) | 0/48 | **19/48 (40%)**: 40 names, 31 numbers |

- PaddleOCR took about 0.3 s a card on this PC (CPU, no GPU).
- Tesseract's larger `tessdata_best` models (15 MB) did no better, and a
  home-made clean-up step (sharpen, flatten the lighting) made it worse.
- These are plain invented cards. Real cards have guilloche patterns,
  holograms and laminate glare, so real accuracy will be lower than this.

## What it means

- PaddleOCR is the reader: open source, and it held up where Tesseract fell
  apart. No reader reads a photo a person can't, so the app still checks
  sharpness and light before upload and asks for a retake.
- Reading stays advisory, as 0126 already treats it: "no reading" or a
  mismatch sends the account to a person, never refuses it, and **a reading
  never verifies anyone**.
- Size: the models are about 31 MB and the APK is 55 MB of a 60 MB budget,
  so on the phone they are fetched once, at the ID step, from our own
  storage and checked by SHA-256, rather than shipped inside the APK.
