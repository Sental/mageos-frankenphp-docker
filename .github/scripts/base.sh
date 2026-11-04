#!/usr/bin/env bash
# base.sh PHP_VERSION: prints the base image named in base.Dockerfile, after checking
# that it's for PHP_VERSION. Each php8.x branch names its base there, and nowhere else.
#
# Fails, naming the problem, if the file is missing, has more or fewer than one FROM
# line, or names another PHP version: the environment's php_string and the base must
# never disagree.
set -euo pipefail

php=${1:?usage: base.sh <php version, e.g. 8.3>}

if [ ! -f base.Dockerfile ]; then
    echo "base.Dockerfile is missing. Each php8.x branch names its FrankenPHP base there (see README.md)." >&2
    exit 1
fi

mapfile -t refs < <(sed -n 's/^FROM[[:space:]]\{1,\}\([^[:space:]]\{1,\}\).*/\1/p' base.Dockerfile)
if [ "${#refs[@]}" -ne 1 ]; then
    echo "base.Dockerfile must have exactly one FROM line; it has ${#refs[@]}." >&2
    exit 1
fi

case "${refs[0]}" in
    *-php"$php"-*) ;;
    *)
        echo "base.Dockerfile names ${refs[0]}, which isn't PHP $php." >&2
        exit 1
        ;;
esac

printf '%s\n' "${refs[0]}"
