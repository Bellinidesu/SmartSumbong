# The engine

Work the database hands out, run on the server instead of the phone or the portal (Ace, 22 Oct 2026: the
portal's features and labs run as engine functions). Its own small service, apart from the portal, because
the work needs memory the portal's instance does not have.

| Job | What | Since |
|---|---|---|
| Reading ID photos | The card's type, name and number, with PaddleOCR (tools/ocr_lab), judged by `_smart_verify` (0126) | 0137 |

How a job flows: `engine-tick` (pg_cron, every minute) queues what needs doing, signs one Cloudinary link per
photo, and posts it to `/read` with the shared secret; the next tick files the answer. The engine has no
database or Cloudinary key and keeps nothing; its log has times and sizes, never names or numbers.

    python -m unittest -v test_reader                 # the reader, no model needed
    docker build -t engine . && docker run --rm engine python selftest.py   # a real reading in the image

Setting it up on Render: DEPLOY.md, "The engine".
