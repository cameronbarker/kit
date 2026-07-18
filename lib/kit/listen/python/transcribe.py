#!/usr/bin/env python3
"""Local WhisperX + pyannote transcription worker.

Ruby owns orchestration. This script only:
  - loads audio
  - runs WhisperX transcription + alignment
  - runs pyannote diarization
  - writes stable raw JSON segments

HF_TOKEN is read from the environment (never from argv).
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path
from typing import Any


MOCK_SEGMENTS = [
    {
        "speaker": "SPEAKER_00",
        "start": 72.0,
        "end": 78.0,
        "text": "I'll follow up with DevOps and confirm the migration window.",
    },
    {
        "speaker": "SPEAKER_01",
        "start": 78.0,
        "end": 84.0,
        "text": "Great, I'll update the rollout plan once you confirm.",
    },
]


def fail(message: str, code: int = 1) -> None:
    print(message, file=sys.stderr)
    raise SystemExit(code)


def configure_model_cache(*, offline: bool | None = None) -> Path:
    """Keep model downloads inside the repo so the project stays self-contained.

    Defaults Hugging Face and torch caches to <repo>/.cache/ unless the caller
    already set them. Offline is the default: transcription never touches the
    network and reads models from the warmed cache. Opt back into network access
    with LISTEN_OFFLINE=0 (needed only to download new models). Pass offline=False
    to force network access regardless of the env var (used by prefetch).

    Must run before any torch / whisperx / huggingface import so the env vars
    take effect.
    """
    root = Path(__file__).resolve().parents[4]
    cache_root = Path(os.environ.get("LISTEN_CACHE_DIR", root / ".cache"))

    os.environ.setdefault("HF_HOME", str(cache_root / "huggingface"))
    os.environ.setdefault("TORCH_HOME", str(cache_root / "torch"))

    if offline is None:
        offline = os.environ.get("LISTEN_OFFLINE", "1") != "0"

    value = "1" if offline else "0"
    os.environ["HF_HUB_OFFLINE"] = value
    os.environ["TRANSFORMERS_OFFLINE"] = value

    return cache_root


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Local WhisperX + pyannote transcription worker"
    )
    parser.add_argument("--input", required=True, help="Path to audio/video file")
    parser.add_argument("--output", required=True, help="Path to write raw JSON")
    parser.add_argument(
        "--mock",
        action="store_true",
        help="Emit deterministic mock segments (no ML imports)",
    )
    parser.add_argument(
        "--model",
        default=os.environ.get("WHISPERX_MODEL", "small"),
        help="WhisperX model name (default: small, or WHISPERX_MODEL)",
    )
    parser.add_argument(
        "--language",
        default=os.environ.get("WHISPERX_LANGUAGE", "en"),
        help="Language code (default: en)",
    )
    parser.add_argument(
        "--device",
        default=os.environ.get("WHISPERX_DEVICE", "auto"),
        help="Device: auto, cpu, or cuda (default: auto)",
    )
    parser.add_argument(
        "--compute-type",
        default=os.environ.get("WHISPERX_COMPUTE_TYPE", "default"),
        help="CTranslate2 compute type (default: int8 on cpu, float16 on cuda)",
    )
    return parser.parse_args(argv)


def resolve_device(requested: str) -> str:
    if requested != "auto":
        return requested
    try:
        import torch

        return "cuda" if torch.cuda.is_available() else "cpu"
    except Exception:
        return "cpu"


def resolve_compute_type(requested: str, device: str) -> str:
    if requested != "default":
        return requested
    return "float16" if device == "cuda" else "int8"


def write_raw_json(output_path: Path, payload: dict[str, Any]) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with output_path.open("w", encoding="utf-8") as handle:
        json.dump(payload, handle, indent=2, ensure_ascii=False)
        handle.write("\n")


def mock_payload(input_path: Path) -> dict[str, Any]:
    return {
        "source_file": str(input_path),
        "mock": True,
        "segments": MOCK_SEGMENTS,
    }


def normalize_segments(segments: list[dict[str, Any]]) -> list[dict[str, Any]]:
    normalized: list[dict[str, Any]] = []
    for segment in segments:
        text = str(segment.get("text", "")).strip()
        if not text:
            continue
        speaker = segment.get("speaker") or "UNKNOWN"
        start = float(segment.get("start", 0.0))
        end = float(segment.get("end", start))
        normalized.append(
            {
                "speaker": str(speaker),
                "start": start,
                "end": end,
                "text": text,
            }
        )
    return normalized


def run_whisperx(
    input_path: Path,
    *,
    model_name: str,
    language: str,
    device: str,
    compute_type: str,
) -> dict[str, Any]:
    hf_token = os.environ.get("HF_TOKEN")
    if not hf_token:
        fail(
            "HF_TOKEN is missing. Export a Hugging Face token before running "
            "diarization (never pass it on the command line):\n"
            "  export HF_TOKEN=hf_...\n"
            "Also accept the pyannote model terms on Hugging Face."
        )

    try:
        import whisperx
    except ImportError as exc:
        fail(
            "WhisperX is not installed. Create a Python 3.11/3.12 venv and install "
            "python/requirements.txt, or use --mock for pipeline smoke tests.\n"
            f"Import error: {exc}"
        )

    device = resolve_device(device)
    compute_type = resolve_compute_type(compute_type, device)

    try:
        audio = whisperx.load_audio(str(input_path))
        model = whisperx.load_model(
            model_name, device, compute_type=compute_type, language=language
        )
        result = model.transcribe(audio, batch_size=8)

        align_model, metadata = whisperx.load_align_model(
            language_code=result.get("language", language), device=device
        )
        result = whisperx.align(
            result["segments"],
            align_model,
            metadata,
            audio,
            device,
            return_char_alignments=False,
        )

        # WhisperX API has shifted across versions; try common diarization entry points.
        diarize_segments = None
        if hasattr(whisperx, "DiarizationPipeline"):
            diarize_model = whisperx.DiarizationPipeline(
                use_auth_token=hf_token, device=device
            )
            diarize_segments = diarize_model(audio)
        elif hasattr(whisperx, "diarize"):
            diarize_model = whisperx.diarize.DiarizationPipeline(
                use_auth_token=hf_token, device=device
            )
            diarize_segments = diarize_model(audio)
        else:
            fail(
                "Installed WhisperX does not expose DiarizationPipeline. "
                "Check your WhisperX version against python/requirements.txt."
            )

        result = whisperx.assign_word_speakers(diarize_segments, result)
    except Exception as exc:  # noqa: BLE001 - surface ML failures clearly to Ruby
        fail(f"Transcription/diarization failed: {exc}")

    segments = normalize_segments(list(result.get("segments") or []))
    if not segments:
        fail("No speech segments produced from input audio.")

    return {
        "source_file": str(input_path),
        "mock": False,
        "model": model_name,
        "language": language,
        "device": device,
        "segments": segments,
    }


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    input_path = Path(args.input).expanduser().resolve()
    output_path = Path(args.output).expanduser().resolve()

    if not input_path.is_file():
        fail(f"Input file not found: {input_path}")

    if args.mock:
        payload = mock_payload(input_path)
    else:
        configure_model_cache()
        payload = run_whisperx(
            input_path,
            model_name=args.model,
            language=args.language,
            device=args.device,
            compute_type=args.compute_type,
        )

    write_raw_json(output_path, payload)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
