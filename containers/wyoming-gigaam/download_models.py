#!/usr/bin/env python3
import argparse
from pathlib import Path

import gigaam
from huggingface_hub import snapshot_download


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--hf-token-file", required=True)
    parser.add_argument("--gigaam-dir", default="/opt/models/gigaam")
    parser.add_argument("--hf-home", default="/opt/models/huggingface")
    args = parser.parse_args()

    token = Path(args.hf_token_file).read_text(encoding="utf-8").strip()
    if not token:
        raise RuntimeError("Hugging Face token secret is empty")

    Path(args.gigaam_dir).mkdir(parents=True, exist_ok=True)
    Path(args.hf_home).mkdir(parents=True, exist_ok=True)

    # Download and verify the GigaAM checkpoint at build time.
    gigaam.load_model(
        "multilingual_ctc",
        device="cpu",
        fp16_encoder=False,
        use_flash=False,
        download_root=args.gigaam_dir,
    )

    # Pre-populate the Hugging Face cache used by GigaAM longform VAD.
    snapshot_download(
        repo_id="pyannote/segmentation-3.0",
        token=token,
        cache_dir=args.hf_home,
    )


if __name__ == "__main__":
    main()
