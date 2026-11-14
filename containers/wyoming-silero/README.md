# Wyoming Silero

Wyoming text-to-speech server backed by Silero TTS (Russian, default `v5_6_ru`).
Runs on CPU. The model is baked into the image at build time.

Voices: `aidar`, `baya`, `kseniya`, `eugene`, `xenia`. Wyoming is exposed on TCP port `10200`.

## Runtime environment

- `SILERO_MODEL` (default: build arg `v5_6_ru`; used for display only)
- `MODEL_PATH` (default: `/opt/models/silero.pt`)
- `SAMPLE_RATE` (`8000`, `24000` or `48000`; default `24000`)
- `DEFAULT_SPEAKER` (default: `aidar`)
- `NUM_THREADS` (default: `4`)
- `URI` (default: `tcp://0.0.0.0:10200`)

## Build

```
docker build --build-arg SILERO_MODEL=v5_1_ru -t wyoming-silero containers/wyoming-silero
```

Available models are listed in `models.yml` of snakers4/silero-models.
Text is split into sentences before synthesis. Silero does not expand digits or
Latin text, so numbers should be written out in words.

## License

Silero models are CC BY-NC-SA 4.0 (non-commercial). See `THIRD_PARTY_NOTICES.md`.
