#!/usr/bin/env python3
"""Download every model Listen needs into the repo-local cache.

Run this once while online. Afterwards the project is self-contained:
transcription defaults to offline and reads models from <repo>/.cache/ without
network access. (Set LISTEN_OFFLINE=0 only when you need to fetch new models.)

Mirrors the models loaded by transcribe.py:
  - WhisperX ASR model (default: small)
  - wav2vec2 alignment model (default language: en)
  - pyannote diarization pipeline (requires HF_TOKEN + accepted model terms)
"""

from __future__ import annotations

import os
import sys

# transcribe.py lives beside this script; reuse its cache configuration so both
# paths agree on where models are stored.
from transcribe import configure_model_cache

GATED_MODELS = (
    "https://huggingface.co/pyannote/speaker-diarization-3.1",
    "https://huggingface.co/pyannote/segmentation-3.0",
    "https://huggingface.co/pyannote/wespeaker-voxceleb-resnet34-LM",
)


def main() -> int:
    # Downloading requires the network, so force online even though transcription
    # defaults to offline.
    cache_root = configure_model_cache(offline=False)

    model_name = os.environ.get("WHISPERX_MODEL", "small")
    language = os.environ.get("WHISPERX_LANGUAGE", "en")
    device = "cpu"
    compute_type = "int8"

    hf_token = os.environ.get("HF_TOKEN")

    try:
        import whisperx
    except ImportError as exc:
        print(
            "WhisperX is not installed. Install lib/kit/listen/python/requirements.txt first.\n"
            f"Import error: {exc}",
            file=sys.stderr,
        )
        return 1

    print(f"Cache directory: {cache_root}")

    print(f"Downloading WhisperX ASR model: {model_name} ...")
    whisperx.load_model(
        model_name, device, compute_type=compute_type, language=language
    )

    print(f"Downloading alignment model for language: {language} ...")
    whisperx.load_align_model(language_code=language, device=device)

    if not hf_token:
        print(
            "\nHF_TOKEN not set: skipped pyannote diarization models.\n"
            "Export HF_TOKEN and accept the model terms, then re-run to finish:\n"
            + "\n".join(f"  {url}" for url in GATED_MODELS),
            file=sys.stderr,
        )
        return 2

    print("Downloading pyannote diarization models ...")
    try:
        if hasattr(whisperx, "DiarizationPipeline"):
            whisperx.DiarizationPipeline(use_auth_token=hf_token, device=device)
        elif hasattr(whisperx, "diarize"):
            whisperx.diarize.DiarizationPipeline(
                use_auth_token=hf_token, device=device
            )
        else:
            print(
                "Installed WhisperX does not expose DiarizationPipeline. "
                "Check your WhisperX version against python/requirements.txt.",
                file=sys.stderr,
            )
            return 1
    except Exception as exc:  # noqa: BLE001 - surface gated/term errors clearly
        print(
            f"Failed to download pyannote models: {exc}\n"
            "Confirm HF_TOKEN is valid and you accepted the terms for:\n"
            + "\n".join(f"  {url}" for url in GATED_MODELS),
            file=sys.stderr,
        )
        return 1

    print(
        f"\nDone. All models cached under {cache_root}.\n"
        "Transcription runs offline by default now (no further env vars needed)."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
