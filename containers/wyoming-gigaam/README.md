# Wyoming GigaAM

Wyoming speech-to-text server backed by SaluteDevelopers GigaAM.

Default model: `multilingual_ctc` (220M).

The container exposes Wyoming on TCP port `10300` and stores downloaded
model files in `/data`.

## Environment

- `MODEL` (default: `multilingual_ctc`)
- `DEVICE` (default: `cuda`)
- `DATA_DIR` (default: `/data`)
- `URI` (default: `tcp://0.0.0.0:10300`)
