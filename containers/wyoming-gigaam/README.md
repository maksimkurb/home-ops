# Wyoming GigaAM

Wyoming speech-to-text server backed by the ONNX export of SaluteDevelopers GigaAM.

Default ASR model: `gigaam-multilingual-ctc` (220M).

The image bakes both the multilingual CTC ONNX model and the PyAnnote ONNX
VAD during the Docker build, so runtime transcription works offline.

Short audio uses `onnx-asr` recognition. Audio at or above the configured
threshold uses its PyAnnote ONNX VAD for segmentation.

Wyoming is exposed on TCP port `10300`.

## Runtime environment

- `MODEL` (default: `gigaam-multilingual-ctc`)
- `DEVICE` (default: `cuda`)
- `MODEL_DIR` (default: `/opt/models/gigaam`)
- `VAD_DIR` (default: `/opt/models/vad`)
- `URI` (default: `tcp://0.0.0.0:10300`)
- `FR_BATCH_SIZE` (default: `1`)
- `LONGFORM_THRESHOLD_SECONDS` (default: `25`)

The previous `MODEL=multilingual_ctc` value remains accepted for existing deployments.

`FR_BATCH_SIZE=1` is a conservative default for low-VRAM GPUs and may be
increased without rebuilding the image.

## Build

The build downloads the public ONNX ASR and VAD models from Hugging Face.

Third-party model attribution is documented in `THIRD_PARTY_NOTICES.md`.
