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

VERSION="${INDRA_PLUGIN_VERSION:-0.1.2}"
# Override INDRA_PLUGIN_SPEC with a local wheel (e.g. /wheels/ocrmypdf_indra-0.1.2-py3-none-any.whl)
# to avoid the network completely.
SPEC="${INDRA_PLUGIN_SPEC:-https://github.com/maksimkurb/paperless-ngx-indra/releases/download/v${VERSION}/ocrmypdf_indra-${VERSION}-py3-none-any.whl}"
# Paperless installs its packages into the system Python with uv.
UV_ARGS="${INDRA_UV_ARGS:---system --no-python-downloads --python-preference system}"
export UV_CACHE_DIR="${INDRA_CACHE_DIR:-/usr/src/paperless/indra/uv}"
mkdir -p "$UV_CACHE_DIR"

installed() {
    python3 -c "import importlib.metadata as m, sys; sys.exit(m.version('ocrmypdf-indra') != '$VERSION')" 2>/dev/null
}

install_plugin() {
    if installed; then
        echo "indra: ocrmypdf-indra $VERSION already installed"
        return 0
    fi

    echo "indra: installing $SPEC"
    # shellcheck disable=SC2086  # UV_ARGS is a list of flags
    if uv pip install $UV_ARGS --offline "$SPEC" >/dev/null 2>&1; then
        echo "indra: installed ocrmypdf-indra $VERSION from the local cache"
    elif uv pip install $UV_ARGS "$SPEC"; then
        echo "indra: installed ocrmypdf-indra $VERSION"
    else
        echo "indra: could not install ocrmypdf-indra $VERSION from: $SPEC" >&2
        echo "indra: check the error above (a bad INDRA_PLUGIN_SPEC, e.g. an empty \${...} expanded by" >&2
        echo "indra: compose, or no network and an empty cache). Either start once with network access" >&2
        echo "indra: and a cache volume at $UV_CACHE_DIR, or set INDRA_PLUGIN_SPEC to a local wheel," >&2
        echo "indra: or unset INDRA_PLUGIN_SPEC to use the default release URL." >&2
        exit 1
    fi
}

# Download the model once here, instead of in every Celery worker on its first OCR task.
# Not fatal: without network and without a cached model, OCR fails later with a clear message.
preload_model() {
    if [ -n "${INDRA_OCR_MODEL_DIR:-}" ]; then
        return 0 # a local folder is used as is, nothing to download
    fi
    export HF_HOME="${HF_HOME:-/usr/src/paperless/indra/hf}"
    mkdir -p "$HF_HOME"
    case "${INDRA_OCR_MATH:-}" in 1 | true | yes | on) math=True ;; *) math=False ;; esac
    if python3 -c "import indra_ocr; indra_ocr.model_dir(None, math=$math)" >/dev/null 2>&1; then
        echo "indra: model ready in $HF_HOME"
    else
        echo "indra: WARNING could not fetch the Indra model into $HF_HOME (no network?)." >&2
        echo "indra: OCR will fail until the model is cached; start once with network access." >&2
    fi
    # the paperless user (Celery workers) must be able to read, and lock, the cache
    chown -R paperless:paperless "$HF_HOME" 2>/dev/null || true
}

install_plugin
preload_model
