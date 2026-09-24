#!/usr/bin/env python3
import argparse
import asyncio
import logging
import os
import types
from functools import partial

import gigaam
import torch
from wyoming.asr import Transcribe, Transcript
from wyoming.audio import AudioChunk, AudioStop
from wyoming.event import Event
from wyoming.info import AsrModel, AsrProgram, Attribution, Describe, Info
from wyoming.server import AsyncEventHandler, AsyncServer

_LOGGER = logging.getLogger(__name__)


def prepare_wav_from_pcm(self, buffer: bytearray):
    wav = torch.frombuffer(buffer, dtype=torch.int16).float() / 32768.0
    wav = wav.to(self._device).to(self._dtype).unsqueeze(0)
    length = torch.full([1], wav.shape[-1], device=self._device)
    return wav, length


class GigaAMEventHandler(AsyncEventHandler):
    def __init__(self, info: Info, model, model_lock: asyncio.Lock, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.info_event = info.event()
        self.model = model
        self.model_lock = model_lock
        self.audio_buffer: bytearray | None = None

    async def handle_event(self, event: Event) -> bool:
        if AudioChunk.is_type(event.type):
            chunk = AudioChunk.from_event(event)
            if self.audio_buffer is None:
                self.audio_buffer = bytearray()
            self.audio_buffer.extend(chunk.audio)
            return True

        if AudioStop.is_type(event.type):
            if self.audio_buffer is None:
                _LOGGER.warning("Received AudioStop without audio")
                await self.write_event(Transcript(text="").event())
                return False

            async with self.model_lock:
                result = await asyncio.to_thread(self.model.transcribe, self.audio_buffer)

            self.audio_buffer = None
            text = result.text if hasattr(result, "text") else str(result)
            _LOGGER.info("Transcription: %s", text)
            await self.write_event(Transcript(text=text).event())
            return False

        if Transcribe.is_type(event.type):
            Transcribe.from_event(event)
            return True

        if Describe.is_type(event.type):
            await self.write_event(self.info_event)
            return True

        return True


async def async_main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", default=os.getenv("MODEL", "multilingual_ctc"))
    parser.add_argument("--device", default=os.getenv("DEVICE", "cuda"))
    parser.add_argument("--data-dir", default=os.getenv("DATA_DIR", "/data"))
    parser.add_argument("--uri", default=os.getenv("URI", "tcp://0.0.0.0:10300"))
    parser.add_argument("--debug", action="store_true")
    args = parser.parse_args()

    logging.basicConfig(level=logging.DEBUG if args.debug else logging.INFO)

    _LOGGER.info("Loading GigaAM model=%s device=%s", args.model, args.device)
    model = gigaam.load_model(
        model_name=args.model,
        device=args.device,
        download_root=args.data_dir,
        fp16_encoder=True,
        use_flash=False,
    )

    # Wyoming sends signed 16-bit PCM, so bypass file/ffmpeg loading.
    model.prepare_wav = types.MethodType(prepare_wav_from_pcm, model)

    info = Info(
        asr=[
            AsrProgram(
                name="GigaAM",
                description="GigaAM Wyoming ASR server",
                attribution=Attribution(
                    name="SaluteDevelopers",
                    url="https://github.com/salute-developers/GigaAM",
                ),
                installed=True,
                version="1",
                models=[
                    AsrModel(
                        name="GigaAM Multilingual CTC 220M",
                        description="GigaAM multilingual 220M CTC model",
                        attribution=Attribution(
                            name="SaluteDevelopers",
                            url="https://github.com/salute-developers/GigaAM",
                        ),
                        installed=args.model == "multilingual_ctc",
                        languages=["ru", "en", "kk", "ky", "uz"],
                        version="1",
                    )
                ],
            )
        ]
    )

    server = AsyncServer.from_uri(args.uri)
    model_lock = asyncio.Lock()
    _LOGGER.info("Ready on %s", args.uri)
    await server.run(partial(GigaAMEventHandler, info, model, model_lock))


def main() -> None:
    asyncio.run(async_main())


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        pass
