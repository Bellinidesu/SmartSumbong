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

FROM php:8.3-apache

RUN apt-get update \
    && apt-get install -y --no-install-recommends libcurl4-openssl-dev libonig-dev \
    && docker-php-ext-install curl mbstring \
    && a2enmod rewrite \
    && sed -i 's/AllowOverride None/AllowOverride All/' /etc/apache2/apache2.conf \
    && rm -rf /var/lib/apt/lists/*

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
