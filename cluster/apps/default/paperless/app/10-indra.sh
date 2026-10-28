#!/bin/bash
# Installs the Indra OCR plugin into the stock paperless-ngx image at container start.
# Mount this folder at /custom-cont-init.d (see README).
#
# Offline-friendly:
#   1. already installed at the pinned version  -> nothing to do (no network)
#   2. otherwise try uv's cache only (--offline) -> works after the first online start
#      if the cache folder is a volume
#   3. otherwise download                        -> needs network
set -eu

VERSION="${INDRA_PLUGIN_VERSION:-0.1.0}"
# Override INDRA_PLUGIN_SPEC with a local wheel (e.g. /wheels/ocrmypdf_indra-0.1.0-py3-none-any.whl)
# to avoid the network completely.
SPEC="${INDRA_PLUGIN_SPEC:-https://github.com/maksimkurb/paperless-ngx-indra/releases/download/v${VERSION}/ocrmypdf_indra-${VERSION}-py3-none-any.whl}"
# Paperless installs its packages into the system Python with uv.
UV_ARGS="${INDRA_UV_ARGS:---system --no-python-downloads --python-preference system}"
export UV_CACHE_DIR="${INDRA_CACHE_DIR:-/usr/src/paperless/indra/uv}"
mkdir -p "$UV_CACHE_DIR"

installed() {
    python3 -c "import importlib.metadata as m, sys; sys.exit(m.version('ocrmypdf-indra') != '$VERSION')" 2>/dev/null
}

if installed; then
    echo "indra: ocrmypdf-indra $VERSION already installed"
    exit 0
fi

# shellcheck disable=SC2086  # UV_ARGS is a list of flags
if uv pip install $UV_ARGS --offline "$SPEC" >/dev/null 2>&1; then
    echo "indra: installed ocrmypdf-indra $VERSION from the local cache"
elif uv pip install $UV_ARGS "$SPEC"; then
    echo "indra: installed ocrmypdf-indra $VERSION"
else
    echo "indra: could not install ocrmypdf-indra $VERSION: no network and nothing cached." >&2
    echo "indra: start once with network access, mount a cache volume at $UV_CACHE_DIR," >&2
    echo "indra: or set INDRA_PLUGIN_SPEC to a local wheel." >&2
    exit 1
fi
