#!/usr/bin/env python3
import argparse
import asyncio
import logging
import os
import re
from functools import partial

import numpy as np
import torch
from wyoming.audio import AudioChunk, AudioStart, AudioStop
from wyoming.error import Error
from wyoming.event import Event
from wyoming.info import Attribution, Describe, Info, TtsProgram, TtsVoice
from wyoming.server import AsyncEventHandler, AsyncServer
from wyoming.tts import Synthesize

_LOGGER = logging.getLogger(__name__)
_SENTENCE_RE = re.compile(r"(?<=[.!?…])\s+|\n+")
_MAX_CHARS = 700
_CHUNK_SAMPLES = 2048
_ATTRIBUTION = Attribution(name="Silero", url="https://github.com/snakers4/silero-models")


def split_text(text: str) -> list[str]:
    parts: list[str] = []
    for sentence in _SENTENCE_RE.split(text):
        sentence = sentence.strip()
        while len(sentence) > _MAX_CHARS:
            cut = sentence.rfind(" ", 0, _MAX_CHARS)
            cut = cut if cut > 0 else _MAX_CHARS
            parts.append(sentence[:cut].strip())
            sentence = sentence[cut:].strip()
        if sentence:
            parts.append(sentence)
    return parts


class SileroEventHandler(AsyncEventHandler):
    def __init__(self, info: Info, args, model, lock: asyncio.Lock, *handler_args, **kwargs):
        super().__init__(*handler_args, **kwargs)
        self.info_event = info.event()
        self.args = args
        self.model = model
        self.lock = lock

    def _synthesize(self, text: str, speaker: str) -> np.ndarray:
        audio = self.model.apply_tts(text=text, speaker=speaker, sample_rate=self.args.sample_rate)
        return (audio.clamp(-1, 1).numpy() * 32767).astype(np.int16)

    async def handle_event(self, event: Event) -> bool:
        if Describe.is_type(event.type):
            await self.write_event(self.info_event)
            return True

        if not Synthesize.is_type(event.type):
            return True

        synthesize = Synthesize.from_event(event)
        speaker = synthesize.voice.name if synthesize.voice and synthesize.voice.name else self.args.default_speaker
        if speaker not in self.model.speakers:
            _LOGGER.warning("Unknown voice %r, using %s", speaker, self.args.default_speaker)
            speaker = self.args.default_speaker

        sentences = split_text(synthesize.text)
        _LOGGER.info("Synthesizing %d chars (%d parts) speaker=%s", len(synthesize.text), len(sentences), speaker)
        rate, width, channels = self.args.sample_rate, 2, 1
        await self.write_event(AudioStart(rate=rate, width=width, channels=channels).event())
        produced = False
        try:
            for sentence in sentences:
                try:
                    async with self.lock:
                        pcm = await asyncio.to_thread(self._synthesize, sentence, speaker)
                except Exception:
                    _LOGGER.exception("Failed to synthesize part: %r", sentence[:80])
                    continue
                produced = True
                for start in range(0, len(pcm), _CHUNK_SAMPLES):
                    chunk = pcm[start : start + _CHUNK_SAMPLES]
                    await self.write_event(
                        AudioChunk(rate=rate, width=width, channels=channels, audio=chunk.tobytes()).event()
                    )
        finally:
            await self.write_event(AudioStop().event())
        if sentences and not produced:
            await self.write_event(Error(text="Silero could not synthesize the text", code="tts-error").event())
        return True


async def async_main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model-path", default=os.getenv("MODEL_PATH", "/opt/models/silero.pt"))
    parser.add_argument("--model-name", default=os.getenv("SILERO_MODEL", "v5_6_ru"))
    parser.add_argument("--sample-rate", type=int, choices=(8000, 24000, 48000), default=int(os.getenv("SAMPLE_RATE", "24000")))
    parser.add_argument("--default-speaker", default=os.getenv("DEFAULT_SPEAKER", "aidar"))
    parser.add_argument("--num-threads", type=int, default=int(os.getenv("NUM_THREADS", "4")))
    parser.add_argument("--uri", default=os.getenv("URI", "tcp://0.0.0.0:10200"))
    parser.add_argument("--debug", action="store_true")
    args = parser.parse_args()
    logging.basicConfig(level=logging.DEBUG if args.debug else logging.INFO)

    torch.set_num_threads(args.num_threads)
    _LOGGER.info("Loading Silero %s from %s", args.model_name, args.model_path)
    model = torch.package.PackageImporter(args.model_path).load_pickle("tts_models", "model")
    if args.default_speaker not in model.speakers:
        raise ValueError(f"DEFAULT_SPEAKER {args.default_speaker!r} not in {model.speakers}")
    model.apply_tts(text="Проверка.", speaker=args.default_speaker, sample_rate=args.sample_rate)  # warm-up

    info = Info(
        tts=[
            TtsProgram(
                name="Silero",
                description="Silero TTS Wyoming server",
                attribution=_ATTRIBUTION,
                installed=True,
                version=args.model_name,
                voices=[
                    TtsVoice(
                        name=speaker,
                        description=f"Silero {args.model_name} {speaker}",
                        attribution=_ATTRIBUTION,
                        installed=True,
                        languages=["ru"],
                        version=args.model_name,
                    )
                    for speaker in model.speakers
                ],
            )
        ]
    )

    server = AsyncServer.from_uri(args.uri)
    _LOGGER.info("Ready on %s (voices: %s, %d Hz)", args.uri, ", ".join(model.speakers), args.sample_rate)
    await server.run(partial(SileroEventHandler, info, args, model, asyncio.Lock()))


if __name__ == "__main__":
    try:
        asyncio.run(async_main())
    except KeyboardInterrupt:
        pass
