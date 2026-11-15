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
Text is cleaned before synthesis, because Silero only understands Cyrillic and drops digits:
- markdown, links and emoji are removed (`text_prep.py`);
- English words are transcribed to Cyrillic via the CMU dictionary;
- numbers are spelled out in Russian (`numbers_ru.py`): integers with gender and
  simple case agreement, decimals (`20.3` -> "двадцать целых три десятых"), times,
  dates, years, percents and degrees.

## License

The bundled Silero model is CC BY-NC-SA 4.0: attribution required, **non-commercial use only**.
See `THIRD_PARTY_NOTICES.md` and `SILERO_LICENSE`.
