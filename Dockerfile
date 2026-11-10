# syntax=docker/dockerfile:1.28
# =============================================================================
# Base images for Mage-OS on FrankenPHP. Two targets:
#
#   runtime  FrankenPHP, supervisor, logrotate and the PHP extensions Mage-OS needs.
#            Every staging and production image is built on it.
#   build    runtime plus git, unzip, Node, Composer, and Xdebug installed but not
#            enabled. CI builds the site on it; the dev image is it with Xdebug on.
#
# Nothing here belongs to one project: no config files, no entrypoint. The images
# built on these add them.
#
# The FrankenPHP base isn't named in this file. Each php8.x branch names it in its own
# base.Dockerfile, and the build passes it in as the `upstream` context:
#
#   docker buildx build --target runtime \
#       --build-context upstream=docker-image://$(sed -n 's/^FROM //p' base.Dockerfile) .
#
# Without that context the build fails, so it can't quietly use another base.
# =============================================================================

FROM upstream AS runtime

# The base image's own labels carry over unless replaced here, so every one it sets
# (title, description, url, source, licenses, vendor) is set again, to describe this image.
# The build target inherits them.
LABEL org.opencontainers.image.title="FrankenPHP For MageOS" \
      org.opencontainers.image.vendor="Mark Rees" \
      org.opencontainers.image.url="https://github.com/Sental/mageos-frankenphp-docker" \
      org.opencontainers.image.source="https://github.com/Sental/mageos-frankenphp-docker" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.description="Mage-OS on FrankenPHP: base images for staging, production and dev builds"

# supervisor runs the queue consumers; logrotate keeps var/log bounded.
RUN apt-get update \
    && apt-get install -y --no-install-recommends supervisor logrotate \
    && rm -rf /var/lib/apt/lists/*

# install-php-extensions resolves each extension's system libraries and skips anything
# the base already provides. igbinary, redis and imagick come from PECL, so they're
# pinned, and Renovate bumps them on main; the others are part of PHP itself. Sodium,
# which encrypts the SMTP password in env.php, is in PHP core.
#
# igbinary is 3.2.17RC1 because PECL publishes it as igbinary's stable release, and it's
# what an unpinned install gets. 3.2.16 doesn't build on PHP 8.5: it includes
# ext/standard/php_smart_string.h, which 8.5 no longer ships.
RUN install-php-extensions \
    bcmath gd intl pdo_mysql soap sockets xsl zip opcache \
    igbinary-3.2.17RC1 redis-6.3.0 imagick-3.8.1 pcntl ftp mbstring

# What this image holds, so two of them can be compared without running anything.
RUN mkdir -p /usr/local/share/mageos-frankenphp \
    && { \
        frankenphp version; \
        php -r 'printf("php %s\n", PHP_VERSION);'; \
        php -r 'foreach (get_loaded_extensions() as $e) { printf("ext %s %s\n", $e, phpversion($e) ?: "-"); }' | sort; \
    } > /usr/local/share/mageos-frankenphp/versions.txt

# -----------------------------------------------------------------------------
FROM runtime AS build

RUN apt-get update \
    && apt-get install -y --no-install-recommends git unzip nodejs npm \
    && rm -rf /var/lib/apt/lists/*

# Xdebug is installed but not enabled (IPE_DONT_ENABLE): CI builds never load it, and
# the dev image enables it with its own xdebug.ini. Composer is pinned like the PECL
# extensions.
RUN IPE_DONT_ENABLE=1 install-php-extensions xdebug-3.5.3 \
    && install-php-extensions @composer-2.11.2

RUN { \
        printf 'composer %s\n' "$(COMPOSER_ALLOW_SUPERUSER=1 composer --version --no-ansi 2>/dev/null)"; \
        printf 'node %s\n' "$(node --version)"; \
        printf 'npm %s\n' "$(npm --version)"; \
        printf 'git %s\n' "$(git --version)"; \
        php -d zend_extension=xdebug -r 'printf("xdebug %s (installed, not enabled)\n", phpversion("xdebug"));'; \
    } >> /usr/local/share/mageos-frankenphp/versions.txt
