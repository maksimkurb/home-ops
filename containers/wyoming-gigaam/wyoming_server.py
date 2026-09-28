#!/usr/bin/env python3
import argparse
import asyncio
import ctypes
import logging
import os
import tempfile
import wave
from functools import partial

import onnx_asr
import onnxruntime as ort
from wyoming.asr import Transcribe, Transcript
from wyoming.audio import AudioChunk, AudioStop
from wyoming.error import Error
from wyoming.event import Event
from wyoming.info import AsrModel, AsrProgram, Attribution, Describe, Info
from wyoming.server import AsyncEventHandler, AsyncServer

_LOGGER = logging.getLogger(__name__)
_malloc_trim = ctypes.CDLL("libc.so.6").malloc_trim


class GigaAMEventHandler(AsyncEventHandler):
    def __init__(self, info: Info, args, model, longform_model, model_lock: asyncio.Lock, *handler_args, **kwargs):
        super().__init__(*handler_args, **kwargs)
        self.info_event = info.event()
        self.args = args
        self.model = model
        self.longform_model = longform_model
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
                            "Longform transcription: %.2fs, batch_size=%d",
                            duration,
                            self.args.fr_batch_size,
                        )
                        segments = await asyncio.to_thread(self.longform_model.recognize, wav_path)
                        text = " ".join(segment.text for segment in segments)
                    else:
                        text = await asyncio.to_thread(self.model.recognize, wav_path)

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
                _malloc_trim(0)
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
    parser.add_argument("--model", default=os.getenv("MODEL", "gigaam-multilingual-ctc"))
    parser.add_argument("--device", choices=("cpu", "cuda"), default=os.getenv("DEVICE", "cuda"))
    parser.add_argument("--model-dir", default=os.getenv("MODEL_DIR", "/opt/models/gigaam"))
    parser.add_argument("--vad-dir", default=os.getenv("VAD_DIR", "/opt/models/vad"))
    parser.add_argument("--uri", default=os.getenv("URI", "tcp://0.0.0.0:10300"))
    parser.add_argument(
        "--fr-batch-size",
        type=int,
        default=int(os.getenv("FR_BATCH_SIZE", "1")),
    )
    parser.add_argument(
        "--longform-threshold-seconds",
        type=float,
        default=float(os.getenv("LONGFORM_THRESHOLD_SECONDS", "25")),
    )
    parser.add_argument("--debug", action="store_true")
    args = parser.parse_args()
    if args.model == "multilingual_ctc":
        args.model = "gigaam-multilingual-ctc"

    logging.basicConfig(level=logging.DEBUG if args.debug else logging.INFO)

    providers = ["CUDAExecutionProvider", "CPUExecutionProvider"] if args.device == "cuda" else ["CPUExecutionProvider"]
    if args.device == "cuda" and "CUDAExecutionProvider" not in ort.get_available_providers():
        raise RuntimeError("ONNX Runtime CUDA provider is unavailable")
    _LOGGER.info("Loading GigaAM ONNX model=%s device=%s", args.model, args.device)
    model = onnx_asr.load_model(args.model, args.model_dir, providers=providers)
    if args.device == "cuda" and "CUDAExecutionProvider" not in model.asr._model.get_providers():
        raise RuntimeError("GigaAM ONNX model did not initialize on CUDA")
    vad = onnx_asr.load_vad("pyannote", args.vad_dir, providers=["CPUExecutionProvider"])
    longform_model = model.with_vad(vad, batch_size=args.fr_batch_size)
    _malloc_trim(0)

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
                        installed=args.model == "gigaam-multilingual-ctc",
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
        "Ready on %s (longform >= %.1fs, batch_size=%d)",
        args.uri,
        args.longform_threshold_seconds,
        args.fr_batch_size,
    )
    await server.run(partial(GigaAMEventHandler, info, args, model, longform_model, model_lock))


def main() -> None:
    asyncio.run(async_main())


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        pass
