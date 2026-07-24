#!/usr/bin/env python3
"""Local WhisperX + pyannote transcription worker.

Ruby owns orchestration. This script only:
  - loads audio
  - runs WhisperX transcription + alignment
  - runs pyannote diarization
  - writes stable raw JSON segments
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path
from typing import Any


DEFAULT_MODEL_NAME = "small"
MODEL_DIR_ENV = "KIT_LISTEN_MODEL_DIR"
MODEL_LABELS = {
    "asr": "speech-transcription",
    "alignment": "word-alignment",
    "diarization": "speaker-diarization",
}
FLAT_MODEL_FILES = {
    "speech-transcription": (
        "config.json",
        "model.bin",
        "tokenizer.json",
        "vocabulary.txt",
    ),
    "word-alignment": ("wav2vec2_fairseq_base_ls960_asr_ls960.pth",),
    "speaker-diarization": ("speaker-diarization.yml",),
}

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


def progress(message: str) -> None:
    # Prefixed so Ruby can relay stages without Lightning/pyannote warning noise.
    print(f"kit-listen:{message}", file=sys.stderr, flush=True)


def configure_runtime_defaults() -> None:
    """Apply process defaults so transcription works without a scavenger hunt of env vars.

    x86 torch under Rosetta on Apple Silicon commonly deadlocks with OpenMP /
    MPS thread pools. Cap BLAS/OpenMP threads unless the caller already set them.
    """
    for key in (
        "OMP_NUM_THREADS",
        "MKL_NUM_THREADS",
        "VECLIB_MAXIMUM_THREADS",
        "OPENBLAS_NUM_THREADS",
    ):
        os.environ.setdefault(key, "1")


def configure_model_storage() -> Path:
    """Point every model lookup at the packaged flat model directory.

    Must run before any torch / whisperx import so the env vars take effect.
    """
    configure_runtime_defaults()

    root = Path(__file__).resolve().parents[4]
    model_root = Path(os.environ.get(MODEL_DIR_ENV, root / "model"))

    os.environ["TORCH_HOME"] = str(model_root)
    os.environ["TRANSFORMERS_OFFLINE"] = "1"

    return model_root


def require_packaged_models(model_root: Path) -> None:
    missing = []
    for label, filenames in FLAT_MODEL_FILES.items():
        for filename in filenames:
            path = model_root / filename
            if not path.is_file():
                missing.append(f"{label}: {path}")

    if missing:
        fail(
            "Packaged Listen model files are missing. Expected flat files under "
            f"{model_root}:\n  " + "\n  ".join(missing)
        )


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
        default=os.environ.get("WHISPERX_MODEL", DEFAULT_MODEL_NAME),
        help="Packaged speech transcription variant label (default: small)",
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
    # WhisperX/pyannote + Rosetta x86 torch on Apple Silicon deadlocks on MPS.
    # Prefer CPU on macOS unless the caller explicitly set --device / WHISPERX_DEVICE.
    if sys.platform == "darwin":
        return "cpu"
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
    model_root: Path,
    model_name: str,
    language: str,
    device: str,
    compute_type: str,
) -> dict[str, Any]:
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
        progress("Loading audio")
        audio = whisperx.load_audio(str(input_path))
        progress(f"Loading {MODEL_LABELS['asr']} model")
        model = whisperx.load_model(
            str(model_root),
            device,
            compute_type=compute_type,
            language=language,
            local_files_only=True,
        )
        progress("Transcribing")
        result = model.transcribe(audio, batch_size=8)

        progress(f"Loading {MODEL_LABELS['alignment']} model")
        align_model, metadata = whisperx.load_align_model(
            language_code=result.get("language", language),
            device=device,
            model_dir=str(model_root),
        )
        progress("Aligning")
        result = whisperx.align(
            result["segments"],
            align_model,
            metadata,
            audio,
            device,
            return_char_alignments=False,
        )

        # WhisperX API has shifted across versions; try common diarization entry points.
        progress(f"Loading {MODEL_LABELS['diarization']} model")
        diarize_segments = None
        diarization_config = str(model_root / "speaker-diarization.yml")
        if hasattr(whisperx, "DiarizationPipeline"):
            diarize_model = whisperx.DiarizationPipeline(
                model_name=diarization_config, device=device
            )
            diarize_segments = diarize_model(audio)
        elif hasattr(whisperx, "diarize"):
            diarize_model = whisperx.diarize.DiarizationPipeline(
                model_name=diarization_config, device=device
            )
            diarize_segments = diarize_model(audio)
        else:
            fail(
                "Installed WhisperX does not expose DiarizationPipeline. "
                "Check your WhisperX version against python/requirements.txt."
            )

        progress("Diarizing")
        result = whisperx.assign_word_speakers(diarize_segments, result)
    except Exception as exc:  # noqa: BLE001 - surface ML failures clearly to Ruby
        fail(f"Transcription/diarization failed: {exc}")

    segments = normalize_segments(list(result.get("segments") or []))
    if not segments:
        fail("No speech segments produced from input audio.")

    return {
        "source_file": str(input_path),
        "mock": False,
        "model": {
            "name": MODEL_LABELS["asr"],
            "source": "whisperx",
            "variant": model_name,
        },
        "models": {
            MODEL_LABELS["asr"]: {
                "source": "whisperx",
                "variant": model_name,
                "path": str(model_root),
            },
            MODEL_LABELS["alignment"]: {
                "source": "whisperx",
                "language": language,
                "path": str(model_root / "wav2vec2_fairseq_base_ls960_asr_ls960.pth"),
            },
            MODEL_LABELS["diarization"]: {
                "source": "pyannote",
                "path": str(model_root / "speaker-diarization.yml"),
            },
        },
        "language": language,
        "device": device,
        "segments": segments,
    }


def main(argv: list[str] | None = None) -> int:
    configure_runtime_defaults()
    args = parse_args(argv)
    input_path = Path(args.input).expanduser().resolve()
    output_path = Path(args.output).expanduser().resolve()

    if not input_path.is_file():
        fail(f"Input file not found: {input_path}")

    if args.mock:
        progress("Mock transcription")
        payload = mock_payload(input_path)
    else:
        model_root = configure_model_storage()
        require_packaged_models(model_root)
        payload = run_whisperx(
            input_path,
            model_root=model_root,
            model_name=args.model,
            language=args.language,
            device=args.device,
            compute_type=args.compute_type,
        )

    write_raw_json(output_path, payload)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
