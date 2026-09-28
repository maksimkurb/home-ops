# Wyoming GigaAM

Wyoming speech-to-text server backed by the ONNX export of SaluteDevelopers GigaAM.

Default ASR model: `gigaam-multilingual-ctc` (220M).

The image bakes the PyAnnote ONNX VAD. The selected ASR model downloads on
first start into `/models` and is reused on later starts. Mount `/models`
on a persistent volume.

Short audio uses `onnx-asr` recognition. Audio at or above the configured
threshold uses its PyAnnote ONNX VAD for segmentation.

Wyoming is exposed on TCP port `10300`.

## Runtime environment

- `MODEL` (default: `gigaam-multilingual-ctc`; accepts any onnx-asr model name or compatible Hugging Face repository)
- `DEVICE` (default: `cuda`)
- `MODEL_CACHE_DIR` (default: `/models`)
- `MODEL_CACHE_KEY` (default: `default`; change it to download the latest files again)
- `MODEL_REVISION` (optional Hugging Face branch, tag, or commit)
- `VAD_DIR` (default: `/opt/models/vad`)
- `URI` (default: `tcp://0.0.0.0:10300`)
- `FR_BATCH_SIZE` (default: `1`)
- `LONGFORM_THRESHOLD_SECONDS` (default: `25`)

The previous `MODEL=multilingual_ctc` value remains accepted for existing deployments.
Changing `MODEL` keeps each model in a separate cache directory. Previous
copies remain on the volume until removed manually.

`FR_BATCH_SIZE=1` is a conservative default for low-VRAM GPUs and may be
increased without rebuilding the image.

## Build

The build downloads the public ONNX VAD model from Hugging Face. The runtime
needs Hugging Face access on first start for each ASR model or cache key.

Third-party model attribution is documented in `THIRD_PARTY_NOTICES.md`.
