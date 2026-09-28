#!/usr/bin/env python3
from huggingface_hub import snapshot_download


snapshot_download(
    "istupakov/gigaam-multilingual-ctc-onnx",
    revision="458860e1983aef670dd9795fb6af603c82767d5d",
    local_dir="/opt/models/gigaam",
    allow_patterns=["README.md", "config.json", "multilingual_ctc.onnx", "multilingual_vocab.txt"],
)
snapshot_download(
    "onnx-community/pyannote-segmentation-3.0",
    revision="733a93b6473d019a773298e08cefa686894b1854",
    local_dir="/opt/models/vad",
    allow_patterns=["README.md", "config.json", "onnx/model.onnx"],
)
