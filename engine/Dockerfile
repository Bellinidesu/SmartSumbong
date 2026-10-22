# SmartSumbong engine (0137): the work the database hands out, starting with reading ID photos.
# Build context: engine/ (Render: Root Directory "engine"). Its own image, apart from the portal's.
# 3.12.15: newer than two weeks, taken for its security fixes (Debian's libpcre2 and perl among them)
FROM python:3.12.15-slim-bookworm

ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 OMP_NUM_THREADS=1 PIP_NO_CACHE_DIR=1 PIP_DISABLE_PIP_VERSION_CHECK=1

# Debian's security updates since the base image was built
RUN apt-get update && apt-get upgrade -y --no-install-recommends && rm -rf /var/lib/apt/lists/*

WORKDIR /engine
COPY requirements.txt models.sha256 ./
RUN pip install --no-cache-dir -r requirements.txt \
    # the models come inside the rapidocr package: check they are the ones measured in tools/ocr_lab
    && cd "$(python -c 'import os, rapidocr; print(os.path.dirname(rapidocr.__file__))')/models" \
    && sha256sum -c /engine/models.sha256

COPY reader.py server.py selftest.py ./

# Not root. Nothing on disk is written at run time.
RUN useradd --system --no-create-home --shell /usr/sbin/nologin engine
USER engine

EXPOSE 8080
CMD ["python", "server.py"]
