# Wyoming GigaAM

Wyoming speech-to-text server backed by SaluteDevelopers GigaAM.

Default ASR model: `multilingual_ctc` (220M).

The image bakes both the GigaAM checkpoint and `pyannote/segmentation-3.0`
during the Docker build, so runtime transcription works offline.

Short audio uses `transcribe()`. Audio at or above the configured threshold
uses upstream `transcribe_longform()` with PyAnnote VAD.

Wyoming is exposed on TCP port `10300`.

## Runtime environment

- `MODEL` (default: `multilingual_ctc`)
- `DEVICE` (default: `cuda`)
- `MODEL_DIR` (default: `/opt/models/gigaam`)
- `URI` (default: `tcp://0.0.0.0:10300`)
- `FR_BATCH_SIZE` (default: `1`)
- `FR_NUM_WORKERS` (default: `0`)
- `LONGFORM_THRESHOLD_SECONDS` (default: `25`)

`FR_BATCH_SIZE=1` is only a conservative default for low-VRAM GPUs and may
be increased without rebuilding the image.

## Build

The build requires the GitHub Actions secret `HUGGING_FACE_TOKEN` with access
to the gated `pyannote/segmentation-3.0` repository. The workflow passes it
as a BuildKit secret; it is not persisted as an image ARG or ENV variable.

Third-party model attribution is documented in `THIRD_PARTY_NOTICES.md`.
