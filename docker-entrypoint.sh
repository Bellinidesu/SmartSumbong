#!/bin/sh
# Point Apache at whatever port the host assigned this container (Render
# sets $PORT; default to 10000 — Render's own default — if it's unset,
# e.g. when running this image locally with `docker run -p 8080:10000`).
set -e

PORT="${PORT:-10000}"

sed -ri "s/^Listen .*/Listen ${PORT}/" /etc/apache2/ports.conf
sed -ri "s/:80>/:${PORT}>/" /etc/apache2/sites-available/000-default.conf

exec "$@"
