#!/bin/sh
set -eu

DARTAI_VERSION="0.2.0"
DARTAI_DIR="/models/dartai-$DARTAI_VERSION"
DARTAI_ARCHIVE="/tmp/dartai-linux-x64-cuda12-$DARTAI_VERSION.tar.gz"
BONSAI_MODEL="/models/Ternary-Bonsai-1.7B-Q2_0.gguf"
EMBEDDING_MODEL="/models/Qwen3-Embedding-0.6B-Q8_0.gguf"

download_if_missing() {
  path="$1"
  url="$2"

  if [ -s "$path" ]; then
    echo "File already exists: $path"
    return
  fi

  wget -O "$path.tmp" "$url"
  mv "$path.tmp" "$path"
}

if [ ! -x "$DARTAI_DIR/llama-server" ]; then
  echo "Downloading DartAI Runtime $DARTAI_VERSION"
  wget -O "$DARTAI_ARCHIVE"     "https://github.com/ftoleedo/dartai/releases/download/v0.2.0/dartai-linux-x64-cuda12-0.2.0.tar.gz"

  echo "d868c105f50bc0d7abc5eecd96d9d8c38905cb64a400e02a8ebea48a4d7852c4  $DARTAI_ARCHIVE"     | sha256sum -c -

  mkdir -p "$DARTAI_DIR"
  tar -xzf "$DARTAI_ARCHIVE" -C "$DARTAI_DIR" --strip-components=1
  rm -f "$DARTAI_ARCHIVE"
fi

if [ ! -s "$BONSAI_MODEL" ]; then
  echo "Downloading Ternary Bonsai 1.7B"
  wget -O "$BONSAI_MODEL.tmp"     "https://huggingface.co/prism-ml/Ternary-Bonsai-1.7B-gguf/resolve/main/Ternary-Bonsai-1.7B-Q2_0.gguf"

  echo "d97d94eb564590c9f0300e54d3f87bbbb25a78693d0ade9f6e177973dcb8228a  $BONSAI_MODEL.tmp"     | sha256sum -c -

  mv "$BONSAI_MODEL.tmp" "$BONSAI_MODEL"
fi

download_if_missing "$EMBEDDING_MODEL"   "https://huggingface.co/Qwen/Qwen3-Embedding-0.6B-GGUF/resolve/main/Qwen3-Embedding-0.6B-Q8_0.gguf"

mkdir -p /models/dartai-home
