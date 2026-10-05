#!/bin/sh
set -eu

DARTAI_VERSION="0.2.0"
DARTAI_DIR="/models/dartai-$DARTAI_VERSION"
DARTAI_ARCHIVE="/tmp/dartai-linux-x64-cuda12-$DARTAI_VERSION.tar.gz"
BONSAI_MODEL="/models/Ternary-Bonsai-1.7B-Q2_0.gguf"

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

mkdir -p /models/dartai-home
