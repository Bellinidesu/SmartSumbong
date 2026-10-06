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
# mbstring — no database driver, no composer, no build step.

# PHP 8.5 (7 Oct 2026), the version the portal is developed on. It also
# keeps database connections open between page loads (supabase.php).
FROM php:8.5-apache

RUN apt-get update \
    && apt-get install -y --no-install-recommends libcurl4-openssl-dev libonig-dev \
    && docker-php-ext-install curl mbstring \
    && a2enmod rewrite expires headers deflate \
    && sed -i 's/AllowOverride None/AllowOverride All/' /etc/apache2/apache2.conf \
    && rm -rf /var/lib/apt/lists/*

# The image ships no php.ini, and PHP's built-in default prints errors
# into the page — a fatal on request-access.php showed visitors the
# server's file paths. The image's own production ini logs them instead.
RUN mv "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini"

# Speed (7 Oct 2026): OPcache (built into PHP 8.5) keeps compiled PHP in memory. The image never
# changes after it is built, so there is no need to re-check files on disk.
RUN { echo 'opcache.enable=1'; echo 'opcache.memory_consumption=64'; echo 'opcache.max_accelerated_files=4000';       echo 'opcache.validate_timestamps=0'; echo 'opcache.interned_strings_buffer=8'; } > "$PHP_INI_DIR/conf.d/zz-opcache.ini"

WORKDIR /var/www/html

COPY admin/ ./admin/
COPY index.php .htaccess ./

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# Render (and most Docker hosts) inject the real port to bind to as $PORT
# at container start — Apache's own config only knows the literal 80 baked
# in at build time, so the entrypoint rewrites both files before starting.
ENV PORT=10000
EXPOSE 10000

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["apache2-foreground"]
