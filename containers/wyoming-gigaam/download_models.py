#!/usr/bin/env python3
import argparse
import shutil
from pathlib import Path

import gigaam
from huggingface_hub import snapshot_download


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--hf-token-file", required=True)
    parser.add_argument("--gigaam-dir", default="/opt/models/gigaam")
    parser.add_argument("--hf-cache", default="/opt/models/huggingface")
    parser.add_argument(
        "--pyannote-notice-dir",
        default="/usr/share/licenses/pyannote-segmentation-3.0",
    )
    args = parser.parse_args()

    token = Path(args.hf_token_file).read_text(encoding="utf-8").strip()
    if not token:
        raise RuntimeError("Hugging Face token secret is empty")

    Path(args.gigaam_dir).mkdir(parents=True, exist_ok=True)
    Path(args.hf_cache).mkdir(parents=True, exist_ok=True)

    # Download and checksum-verify the GigaAM checkpoint at build time.
    gigaam.load_model(
        "multilingual_ctc",
        device="cpu",
        fp16_encoder=False,
        use_flash=False,
        download_root=args.gigaam_dir,
    )

    # Pre-populate the exact cache used by runtime local_files_only lookup.
    snapshot_path = Path(
        snapshot_download(
            repo_id="pyannote/segmentation-3.0",
            token=token,
            cache_dir=args.hf_cache,
        )
    )

    notice_dir = Path(args.pyannote_notice_dir)
    notice_dir.mkdir(parents=True, exist_ok=True)
    for name in ("LICENSE", "LICENSE.md", "README.md"):
        source = snapshot_path / name
        if source.is_file():
            shutil.copy2(source, notice_dir / name)


if __name__ == "__main__":
    main()
