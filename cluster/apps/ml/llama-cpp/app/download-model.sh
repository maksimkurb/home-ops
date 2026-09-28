#!/bin/sh
set -eu

download_if_missing() {
  model="$1"
  url="$2"
  if [ -s "$model" ]; then
    echo "Model already exists: $model"
    return
  fi
  curl --fail --location --retry 3 "$url" --output "$model.tmp"
  mv "$model.tmp" "$model"
}

download_if_missing /models/Qwen3.5-2B-Q4_K_M.gguf \
  https://huggingface.co/unsloth/Qwen3.5-2B-GGUF/resolve/main/Qwen3.5-2B-Q4_K_M.gguf
download_if_missing /models/Qwen3-Embedding-0.6B-Q8_0.gguf \
  https://huggingface.co/Qwen/Qwen3-Embedding-0.6B-GGUF/resolve/main/Qwen3-Embedding-0.6B-Q8_0.gguf
