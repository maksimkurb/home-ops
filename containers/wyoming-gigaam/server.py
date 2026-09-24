#!/usr/bin/env python3
import argparse
import asyncio
import logging
import os
import tempfile
import wave
from functools import partial

import gigaam
from wyoming.asr import Transcribe, Transcript
from wyoming.audio import AudioChunk, AudioStop
from wyoming.error import Error
from wyoming.event import Event
from wyoming.info import AsrModel, AsrProgram, Attribution, Describe, Info
from wyoming.server import AsyncEventHandler, AsyncServer

_LOGGER = logging.getLogger(__name__)


class GigaAMEventHandler(AsyncEventHandler):
    def __init__(self, info: Info, args, model, model_lock: asyncio.Lock, *handler_args, **kwargs):
        super().__init__(*handler_args, **kwargs)
        self.info_event = info.event()
        self.args = args
        self.model = model
        self.model_lock = model_lock
        self.audio_buffer: bytearray | None = None
        self.audio_format: tuple[int, int, int] | None = None

    async def handle_event(self, event: Event) -> bool:
        if AudioChunk.is_type(event.type):
            chunk = AudioChunk.from_event(event)
            chunk_format = (chunk.rate, chunk.width, chunk.channels)
            if self.audio_buffer is None:
                self.audio_buffer = bytearray()
                self.audio_format = chunk_format
            elif self.audio_format != chunk_format:
                raise ValueError(
                    f"Audio format changed within stream: {self.audio_format} -> {chunk_format}"
                )
            self.audio_buffer.extend(chunk.audio)
            return True

        if AudioStop.is_type(event.type):
            if self.audio_buffer is None or self.audio_format is None:
                _LOGGER.warning("Received AudioStop without audio")
                await self.write_event(Transcript(text="").event())
                return False

            audio = self.audio_buffer
            rate, width, channels = self.audio_format
            self.audio_buffer = None
            self.audio_format = None

            bytes_per_second = rate * width * channels
            duration = len(audio) / bytes_per_second if bytes_per_second else 0.0

            wav_path = None
            try:
                with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
                    wav_path = tmp.name
                with wave.open(wav_path, "wb") as wav_file:
                    wav_file.setnchannels(channels)
                    wav_file.setsampwidth(width)
                    wav_file.setframerate(rate)
                    wav_file.writeframes(audio)

                async with self.model_lock:
                    if duration >= self.args.longform_threshold_seconds:
                        _LOGGER.info(
                            "Longform transcription: %.2fs, batch_size=%d, workers=%d",
                            duration,
                            self.args.fr_batch_size,
                            self.args.fr_num_workers,
                        )
                        result = await asyncio.to_thread(
                            self.model.transcribe_longform,
                            wav_path,
                            False,
                            self.args.fr_batch_size,
                            self.args.fr_num_workers,
                        )
                    else:
                        result = await asyncio.to_thread(self.model.transcribe, wav_path)

                text = result.text if hasattr(result, "text") else str(result)
                _LOGGER.info("Transcription: %s", text)
                await self.write_event(Transcript(text=text).event())
            except Exception as err:
                _LOGGER.exception("Transcription failed")
                await self.write_event(Error(text=str(err), code="asr-error").event())
            finally:
                if wav_path:
                    try:
                        os.unlink(wav_path)
                    except FileNotFoundError:
                        pass
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
    parser.add_argument("--model-dir", default=os.getenv("MODEL_DIR", "/opt/models/gigaam"))
    parser.add_argument("--uri", default=os.getenv("URI", "tcp://0.0.0.0:10300"))
    parser.add_argument(
        "--fr-batch-size",
        type=int,
        default=int(os.getenv("FR_BATCH_SIZE", "1")),
    )
    parser.add_argument(
        "--fr-num-workers",
        type=int,
        default=int(os.getenv("FR_NUM_WORKERS", "0")),
    )
    parser.add_argument(
        "--longform-threshold-seconds",
        type=float,
        default=float(os.getenv("LONGFORM_THRESHOLD_SECONDS", "25")),
    )
    parser.add_argument("--debug", action="store_true")
    args = parser.parse_args()

    logging.basicConfig(level=logging.DEBUG if args.debug else logging.INFO)

    _LOGGER.info("Loading GigaAM model=%s device=%s", args.model, args.device)
    model = gigaam.load_model(
        model_name=args.model,
        device=args.device,
        download_root=args.model_dir,
        fp16_encoder=True,
        use_flash=False,
    )

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
    _LOGGER.info(
        "Ready on %s (longform >= %.1fs, batch_size=%d, workers=%d)",
        args.uri,
        args.longform_threshold_seconds,
        args.fr_batch_size,
        args.fr_num_workers,
    )
    await server.run(partial(GigaAMEventHandler, info, args, model, model_lock))


def main() -> None:
    asyncio.run(async_main())


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        pass
