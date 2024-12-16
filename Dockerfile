# syntax = docker/dockerfile:1.0-experimental

# the different stages of this Dockerfile are meant to be built into separate images
# https://docs.docker.com/develop/develop-images/multistage-build/#stop-at-a-specific-build-stage
# https://docs.docker.com/compose/compose-file/#target


# https://docs.docker.com/engine/reference/builder/#understand-how-arg-and-from-interact
ARG BASE_COMPOSER_IMAGE
ARG BASE_PHP_IMAGE


# "composer" container
# --------------------
# Since we can't use env vars within the --from flag of the COPY command we need to 'build' the composer image here
FROM ${BASE_COMPOSER_IMAGE} as api_platform_composer


# "php" container
# -------------
FROM ${BASE_PHP_IMAGE} AS api_platform_php

LABEL uk.co.goodcrm-owner="Good Technologies Ltd"
LABEL uk.co.goodcrm.platform="good-crm"
LABEL uk.co.goodcrm.platform-component="api"
LABEL uk.co.goodcrm.technology="php"

# Security patches
RUN apk upgrade --no-cache

# persistent / runtime deps
RUN apk add --no-cache \
		acl \
		fcgi \
		file \
		gettext \
		git \
		gnu-libiconv \
	;

# install gnu-libiconv and set LD_PRELOAD env to make iconv work fully on Alpine image.
# see https://github.com/docker-library/php/issues/240#issuecomment-763112749
ENV LD_PRELOAD /usr/lib/preloadable_libiconv.so

ARG APCU_VERSION=5.1.18
ARG MAILPARSE_VERSION=3.1.1
ARG MONGODB_VERSION=1.9.0

RUN set -eux; \
	apk add --no-cache --virtual .build-deps \
		$PHPIZE_DEPS \
		icu-dev \
		libzip-dev \
		zlib-dev \
		openssl-dev \
	; \
	\
	docker-php-ext-configure zip; \
	docker-php-ext-install -j$(nproc) \
		intl \
		pdo_mysql \
		zip \
	; \
	pecl install \
		apcu-${APCU_VERSION} \
		mailparse-${MAILPARSE_VERSION} \
		mongodb-${MONGODB_VERSION} \
	; \
	pecl clear-cache; \
	docker-php-ext-enable \
		apcu \
		mailparse \
		mongodb \
		opcache \
	; \
	\
	runDeps="$( \
		scanelf --needed --nobanner --format '%n#p' --recursive /usr/local/lib/php/extensions \
			| tr ',' '\n' \
			| sort -u \
			| awk 'system("[ -e /usr/local/lib/" $1 " ]") == 0 { next } { print "so:" $1 }' \
	)"; \
	apk add --no-cache --virtual .api-phpexts-rundeps $runDeps; \
	\
	apk del .build-deps