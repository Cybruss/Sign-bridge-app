#!/usr/bin/env python3
"""Generate the private Kaggle notebook that extracts and trains on WLASL videos."""

from __future__ import annotations

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
KAGGLE_DIR = ROOT / "kaggle" / "sign_bridge_wlasl_video_pipeline"
TRAINER = ROOT / "scripts" / "train_sign_bridge_wlasl_video.py"
NOTEBOOK = KAGGLE_DIR / "sign_bridge_wlasl_video_pipeline.ipynb"


def source_cell(source: str) -> dict:
    return {
        "cell_type": "code",
        "id": "video-pipeline",
        "execution_count": None,
        "metadata": {},
        "outputs": [],
        "source": source.splitlines(keepends=True),
    }


def markdown_cell(source: str) -> dict:
    return {"cell_type": "markdown", "id": "pipeline-notes", "metadata": {}, "source": source.splitlines(keepends=True)}


def main() -> None:
    KAGGLE_DIR.mkdir(parents=True, exist_ok=True)
    trainer_source = TRAINER.read_text(encoding="utf-8")
    cell = """from pathlib import Path
import importlib.util
import json
import subprocess
import sys

# Full run on all eligible WLASL-2000 examples.
RUN_MODE = "full"

if importlib.util.find_spec("mediapipe") is None:
    # Kaggle's Python 3.13 runtime publishes MediaPipe 0.10.35+ wheels.
    subprocess.check_call([sys.executable, "-m", "pip", "install", "mediapipe==0.10.35"])

import mediapipe as mp
print("MediaPipe", mp.__version__)
TRAINER_SOURCE = """ + json.dumps(trainer_source) + """
trainer_path = Path("/kaggle/working/train_sign_bridge_wlasl_video.py")
trainer_path.parent.mkdir(parents=True, exist_ok=True)
trainer_path.write_text(TRAINER_SOURCE, encoding="utf-8")
subprocess.run(
    [sys.executable, "-u", str(trainer_path), "--mode", RUN_MODE],
    check=True,
)
"""
    notebook = {
        "cells": [
            markdown_cell("""# Sign Bridge · WLASL video training

This private Kaggle notebook runs the video-to-landmark-to-model pipeline on the attached WLASL-processed dataset. It samples each usable clip at 64 frames, runs the same MediaPipe Holistic task asset bundled with Sign Bridge, selects the app's 180 landmark features, and trains a softmax classifier from raw videos.

The manifest keeps the WLASL official split and signer IDs. Only glosses with available examples in train, validation, and test can be evaluated; the 2,000-class annotations do **not** imply 2,000 usable classes in the local video copy. This produces a new classifier output contract `[1,64,180,3] → [1,N]`, so the mobile inference decoder will need an update before this model is installed in the app.

WLASL videos and derived features are academic/computational research data. Follow the WLASL C-UDA and cite Li et al., WACV 2020. This kernel is private; it does not upload the raw videos anywhere.

## Resume notes

Feature extraction writes each completed chunk atomically under `/kaggle/working/sign_bridge_wlasl_run/features/`; it skips valid chunks on a rerun. Training saves a TensorFlow model+optimizer checkpoint after every epoch. If the Kaggle session retains or reattaches `/kaggle/working`, the next run resumes from those checkpoints. A completed Kaggle notebook version saves its output files and they can be attached to a later version. Kaggle background `Save & Run All` sessions use a fresh environment; a forcibly cancelled background run is not guaranteed to preserve unsaved working files. For a durable restart, save/attach the latest completed output version before restarting. Do not delete the checkpoint files.

The six-gloss GPU preflight passed, including video decode, landmark extraction, one training epoch, and TFLite export. This version runs the full eligible WLASL-2000 dataset and logs progress at each extraction chunk and epoch.
"""),
            source_cell(cell),
        ],
        "metadata": {
            "kernelspec": {"display_name": "Python 3", "language": "python", "name": "python3"},
            "language_info": {"name": "python", "version": "3.10.13"},
        },
        "nbformat": 4,
        "nbformat_minor": 5,
    }
    NOTEBOOK.write_text(json.dumps(notebook, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"Wrote {NOTEBOOK}")


if __name__ == "__main__":
    main()
