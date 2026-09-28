#!/usr/bin/env python3
from huggingface_hub import snapshot_download


snapshot_download(
    "onnx-community/pyannote-segmentation-3.0",
    revision="733a93b6473d019a773298e08cefa686894b1854",
    local_dir="/opt/models/vad",
    allow_patterns=["README.md", "config.json", "onnx/model.onnx"],
)
