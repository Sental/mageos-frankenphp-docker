#!/usr/bin/env bash
# check.sh RUNTIME_IMAGE BUILD_IMAGE: checks two freshly built images before anything is
# published. Every failure is named, and the first one stops the check.
#
#   both     every extension Mage-OS needs is loaded, and versions.txt is there
#   build    composer, node, npm, git and unzip are on the PATH, and Xdebug is
#            installed (xdebug.so loads on request) but not enabled
#
# shellcheck disable=SC2016 # the $ in the PHP and sh snippets belongs to the container
set -euo pipefail

runtime=${1:?usage: check.sh <runtime image> <build image>}
build=${2:?usage: check.sh <runtime image> <build image>}

# The names extension_loaded() knows them by. OPcache is "Zend OPcache".
extensions=(bcmath gd intl pdo_mysql soap sockets xsl zip "Zend OPcache" igbinary redis imagick pcntl ftp mbstring sodium)

check_common() {
    local image=$1
    echo "== $image"
    docker run --rm --entrypoint php "$image" -r '
        $missing = array_values(array_filter(array_slice($argv, 1), fn ($e) => !extension_loaded($e)));
        if ($missing) {
            fwrite(STDERR, "missing extensions: " . implode(", ", $missing) . "\n");
            exit(1);
        }
        echo "extensions: all loaded\n";
    ' "${extensions[@]}"
    docker run --rm --entrypoint sh "$image" -c '
        test -s /usr/local/share/mageos-frankenphp/versions.txt \
            || { echo "versions.txt is missing or empty" >&2; exit 1; }
        cat /usr/local/share/mageos-frankenphp/versions.txt
    '
}

check_common "$runtime"
check_common "$build"

docker run --rm --entrypoint sh "$build" -c '
    set -e
    for tool in composer node npm git unzip; do
        command -v "$tool" >/dev/null || { echo "build image: $tool is missing" >&2; exit 1; }
    done
    dir=$(php -r "echo ini_get(\"extension_dir\");")
    [ -f "$dir/xdebug.so" ] || { echo "build image: xdebug.so is not in $dir" >&2; exit 1; }
    if php -m | grep -qix xdebug; then
        echo "build image: Xdebug is enabled; it must only be installed" >&2
        exit 1
    fi
    php -d zend_extension=xdebug -r "exit(extension_loaded(\"xdebug\") ? 0 : 1);" \
        || { echo "build image: xdebug.so does not load" >&2; exit 1; }
    echo "build image: tools present; Xdebug installed, not enabled"
'
