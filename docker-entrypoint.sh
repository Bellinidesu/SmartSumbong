#!/bin/sh
# Point Apache at whatever port the host assigned this container (Render
# sets $PORT; default to 10000 — Render's own default — if it's unset,
# e.g. when running this image locally with `docker run -p 8080:10000`).
set -e

PORT="${PORT:-10000}"

# Rewritten in place, not with sed -i: the container runs as www-data, which owns these two files but not
# /etc/apache2, where sed -i would make its temporary copy.
set_port() { sed -r "$1" "$2" > /tmp/port.conf && cat /tmp/port.conf > "$2" && rm -f /tmp/port.conf; }
set_port "s/^Listen .*/Listen ${PORT}/" /etc/apache2/ports.conf
set_port "s/:[0-9]+>/:${PORT}>/" /etc/apache2/sites-available/000-default.conf

exec "$@"
