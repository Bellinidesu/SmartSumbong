# SmartSumbong — admin portal, containerized for Render's free Docker web
# service (or any other Docker host).
#
# Only admin/ (plus the root landing page) is ever served — mobile/,
# supabase/, docs/, and everything else in the repo stay out of the image
# (see .dockerignore). public/ (the transparency dashboard) was removed
# 15 Sep 2026 along with its own COPY step below — Ace: "completely remove
# the transparency page we dont need it" — see .htaccess and index.php for
# the rest of that removal. The portal talks to Supabase over HTTPS (cURL,
# PostgREST + GoTrue), so there is nothing to install beyond PHP + curl +
# mbstring — no database driver. Since 22 Oct 2026 one PHP library comes
# through Composer (OpenSpout, for the Report Summary spreadsheet), installed
# here at the versions in admin/composer.lock; docs/UPDATING.md.

# Composer only installs admin/composer.lock; it is not left in the image.
FROM composer:2.11.0 AS composer

# PHP 8.5 (7 Oct 2026), the version the portal is developed on. It also
# keeps database connections open between page loads (supabase.php).
# Pinned to the patch (22 Oct 2026): 8.5.12 fixes two critical remote code
# execution flaws (CVE-2026-109618, CVE-2026-109619; the first reachable on
# Apache's mod_php by any request, before the portal's code runs). The
# floating 8.5 tag let a rebuild reuse an older cached image; a pinned tag
# cannot, and Dependabot raises it with each new patch.
FROM php:8.5.12-apache

# apt-get upgrade (4 Nov 2026): Debian's security fixes that are newer than the PHP base image.
# No build tools in the running image (7 Nov 2026): the compilers and headers that building the zip extension needs (gcc, g++,
# the libc and kernel headers, the -dev packages; the base image keeps them as $PHPIZE_DEPS) were shipped to production and were
# most of the image scan's findings. The docker-library way: build, keep only the libraries PHP, its extensions and Apache link
# to (found with ldd), purge the rest, then prove the extensions still load and no compiler is left.
RUN set -eux; \
    apt-get update; \
    apt-get upgrade -y --no-install-recommends; \
    savedAptMark="$(apt-mark showmanual | grep -vxF "$(printf '%s\n' $PHPIZE_DEPS libc6-dev)" || true)"; \
    apt-get install -y --no-install-recommends libcurl4-openssl-dev libonig-dev libzip-dev; \
    docker-php-ext-install curl mbstring zip; \
    apt-mark auto '.*' > /dev/null; \
    [ -z "$savedAptMark" ] || apt-mark manual $savedAptMark > /dev/null; \
    find /usr/local /usr/lib/apache2/modules -type f \( -name '*.so' -o -perm -u+x \) -exec ldd '{}' ';' 2>/dev/null \
      | awk '/=>/ { so = $(NF-1); if (index(so, "/usr/local/") == 1) { next }; gsub("^/(usr/)?", "", so); printf "*%s\n", so }' \
      | sort -u | xargs -r dpkg-query --search 2>/dev/null \
      | awk -F': ' '/^diversion/ { next } { n = split($1, p, ", "); for (i = 1; i <= n; i++) print p[i] }' \
      | sort -u | xargs -r apt-mark manual > /dev/null; \
    apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
    for m in curl mbstring zip; do php -m | grep -qix "$m"; done; \
    if command -v gcc || command -v g++ || command -v make; then echo 'a build tool is still in the image' >&2; exit 1; fi; \
    a2enmod rewrite expires headers deflate; \
    sed -i 's/AllowOverride None/AllowOverride All/' /etc/apache2/apache2.conf; \
    rm -rf /var/lib/apt/lists/*

# The image ships no php.ini, and PHP's built-in default prints errors
# into the page — a fatal on request-access.php showed visitors the
# server's file paths. The image's own production ini logs them instead.
RUN mv "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini"

# Speed (7 Oct 2026): OPcache (built into PHP 8.5) keeps compiled PHP in memory. The image never
# changes after it is built, so there is no need to re-check files on disk.
RUN { echo 'opcache.enable=1'; echo 'opcache.memory_consumption=64'; echo 'opcache.max_accelerated_files=4000';       echo 'opcache.validate_timestamps=0'; echo 'opcache.interned_strings_buffer=8'; echo 'expose_php=Off'; } > "$PHP_INI_DIR/conf.d/zz-opcache.ini"

# Speed (7 Nov 2026): fewer, longer-lived PHP workers. Each Apache worker keeps its own open connection to Supabase (in Mumbai);
# Debian's defaults keep 5 to 10 idle workers and spread a few people's clicks across all of them, so a worker's connection had
# usually gone cold by its next turn and the page paid a fresh TCP and TLS handshake (two or three round trips) before its one
# database wait. Two to start and one to three spare keep the same workers busy and their connections open; Apache still adds
# workers under load, up to twelve (about 35 MB each, within the 512 MB of a small instance; Debian's 150 could never fit).
# Server-Timing's "conn" says how many new connections a page had to open.
RUN printf '%s\n' '<IfModule mpm_prefork_module>' '    StartServers 2' '    MinSpareServers 1' '    MaxSpareServers 3' \
      '    MaxRequestWorkers 12' '    MaxConnectionsPerChild 0' '</IfModule>' > /etc/apache2/conf-available/zz-workers.conf \
    && a2enconf zz-workers

WORKDIR /var/www/html

COPY admin/ ./admin/
# The locked library versions, into admin/includes/vendor (forbidden to the web by .htaccess); nothing for development.
COPY --from=composer /usr/bin/composer /tmp/composer
RUN COMPOSER_ALLOW_SUPERUSER=1 /tmp/composer install --working-dir=admin --no-dev --no-interaction --no-progress --classmap-authoritative \
    && rm /tmp/composer
COPY index.php .htaccess ./

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# Not root (22 Oct 2026, Trivy DS-0002). Apache runs as www-data from the start: the port is above 1024 so
# it needs no root to bind, the base image already gives www-data Apache's run, lock and log folders, and the
# entrypoint rewrites the two files that hold the port, so www-data owns those. The code stays root-owned
# and read-only to it.
RUN chown www-data:www-data /etc/apache2/ports.conf /etc/apache2/sites-available/000-default.conf
USER www-data

# Render (and most Docker hosts) inject the real port to bind to as $PORT
# at container start — Apache's own config only knows the literal 80 baked
# in at build time, so the entrypoint rewrites both files before starting.
ENV PORT=10000
EXPOSE 10000

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["apache2-foreground"]
