#!/usr/bin/env python3
"""Train a small MediaPipe-landmark ASL fingerspelling fallback.

Dataset: Kaggle ASL Alphabet by ameythakur20, CC BY 4.0.
Only static letters A-I and K-Y are learned; J and Z require motion and are
left to the in-app keyboard. The dataset is intentionally kept outside Git.

Example:
  python scripts/train_fingerspelling_model.py \
    --dataset "/path/to/asl-alphabet-train" \
    --hand-model "/path/to/hand_landmarker.task" \
    --model assets/ml/fingerspelling.tflite \
    --labels assets/ml/fingerspelling_labels.json
"""

from __future__ import annotations

import argparse
import json
import os
import random
from pathlib import Path

os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "2")

import mediapipe as mp
import numpy as np
import tensorflow as tf
from PIL import Image as PILImage
from sklearn.model_selection import train_test_split
from sklearn.metrics import accuracy_score, classification_report, confusion_matrix
from tensorflow import keras
from tensorflow.keras import layers

LETTERS = list("ABCDEFGHIKLMNOPQRSTUVWXY")  # J/Z are motion letters.
SEED = 1729


def normalize_landmarks(points: np.ndarray) -> np.ndarray:
    """Match runtime: wrist-relative coordinates normalized by palm length."""
    points = np.asarray(points, dtype=np.float32).reshape(21, 3).copy()
    points -= points[0]
    scale = float(np.linalg.norm(points[9, :2]))
    if scale < 1e-5:
        raise ValueError("Degenerate hand landmarks")
    points /= scale
    return points.reshape(63)


def read_dataset(root: Path, hand_model: Path) -> tuple[np.ndarray, np.ndarray, dict[str, int]]:
    # Kaggle extract layout is either <root>/<letter> or
    # <root>/asl-alphabet-train/<letter>.
    if not any((root / letter).is_dir() for letter in LETTERS):
        candidates = list(root.glob("**/A"))
        if not candidates:
            raise FileNotFoundError(f"Could not find class folders beneath {root}")
        root = candidates[0].parent

    if not hand_model.exists():
        raise FileNotFoundError(
            f"MediaPipe hand_landmarker.task not found: {hand_model}"
        )
    vision = mp.tasks.vision
    rows: list[np.ndarray] = []
    labels: list[int] = []
    counts: dict[str, int] = {}
    rng = random.Random(SEED)
    options = vision.HandLandmarkerOptions(
        base_options=mp.tasks.BaseOptions(model_asset_path=str(hand_model.resolve())),
        running_mode=vision.RunningMode.IMAGE,
        num_hands=1,
        min_hand_detection_confidence=0.4,
    )
    with vision.HandLandmarker.create_from_options(options) as detector:
        for label_id, letter in enumerate(LETTERS):
            files = sorted((root / letter).glob("*.jpg"))
            rng.shuffle(files)
            accepted = 0
            for image_path in files:
                # The holistic graph keeps a segmentation cache across images;
                # standardize frame size so static-image detection is stable.
                rgb = np.asarray(
                    PILImage.open(image_path).convert("RGB").resize((256, 256)),
                    dtype=np.uint8,
                )
                image = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)
                result = detector.detect(image)
                if not result.hand_landmarks:
                    continue
                points = np.array(
                    [[p.x, p.y, p.z] for p in result.hand_landmarks[0]],
                    dtype=np.float32,
                )
                try:
                    rows.append(normalize_landmarks(points))
                    labels.append(label_id)
                    accepted += 1
                except ValueError:
                    continue
            counts[letter] = accepted
            print(f"{letter}: {accepted}/{len(files)} images yielded landmarks", flush=True)

    if any(counts.get(letter, 0) < 8 for letter in LETTERS):
        raise RuntimeError("Each static letter needs at least 8 detected examples")
    return np.stack(rows), np.asarray(labels, dtype=np.int32), counts


def build_model(class_count: int) -> keras.Model:
    model = keras.Sequential(
        [
            keras.Input(shape=(63,), name="hand_landmarks"),
            layers.Dense(96, activation="relu", kernel_regularizer=keras.regularizers.l2(0.002)),
            layers.Dropout(0.35),
            layers.Dense(48, activation="relu", kernel_regularizer=keras.regularizers.l2(0.002)),
            layers.Dropout(0.25),
            layers.Dense(class_count, activation="softmax", name="letter_scores"),
        ],
        name="sign_bridge_static_fingerspelling",
    )
    model.compile(
        optimizer=keras.optimizers.Adam(learning_rate=0.001),
        loss="sparse_categorical_crossentropy",
        metrics=["accuracy"],
    )
    return model


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dataset", required=True, type=Path)
    parser.add_argument("--hand-model", required=True, type=Path)
    parser.add_argument("--model", type=Path, default=Path("assets/ml/fingerspelling.tflite"))
    parser.add_argument("--labels", type=Path, default=Path("assets/ml/fingerspelling_labels.json"))
    parser.add_argument("--report", type=Path, default=Path("docs/model/fingerspelling_baseline.json"))
    parser.add_argument("--epochs", type=int, default=80)
    args = parser.parse_args()

    random.seed(SEED)
    np.random.seed(SEED)
    tf.random.set_seed(SEED)
    tf.config.threading.set_intra_op_parallelism_threads(2)
    tf.config.threading.set_inter_op_parallelism_threads(2)

    x, y, counts = read_dataset(args.dataset, args.hand_model)
    x_train, x_holdout, y_train, y_holdout = train_test_split(
        x, y, test_size=0.30, random_state=SEED, stratify=y
    )
    x_val, x_test, y_val, y_test = train_test_split(
        x_holdout, y_holdout, test_size=0.50, random_state=SEED, stratify=y_holdout
    )

    # Landmark-space augmentation: small sensor jitter and horizontal mirror.
    rng = np.random.default_rng(SEED)
    jitter = x_train + rng.normal(0, 0.012, x_train.shape).astype(np.float32)
    mirror = x_train.copy().reshape(-1, 21, 3)
    mirror[:, :, 0] *= -1
    train_x = np.concatenate([x_train, jitter, mirror.reshape(-1, 63)])
    train_y = np.concatenate([y_train, y_train, y_train])

    model = build_model(len(LETTERS))
    history = model.fit(
        train_x,
        train_y,
        validation_data=(x_val, y_val),
        epochs=args.epochs,
        batch_size=32,
        callbacks=[
            keras.callbacks.EarlyStopping(
                monitor="val_loss", patience=10, restore_best_weights=True
            ),
            keras.callbacks.ReduceLROnPlateau(monitor="val_loss", patience=4, factor=0.5),
        ],
        verbose=2,
    )
    probabilities = model.predict(x_test, verbose=0)
    predicted = probabilities.argmax(axis=1)
    top_two = np.sort(probabilities, axis=1)[:, -2:]
    deployment_accept = (top_two[:, 1] >= 0.93) & (
        top_two[:, 1] - top_two[:, 0] >= 0.18
    )
    report = classification_report(
        y_test,
        predicted,
        labels=list(range(len(LETTERS))),
        target_names=LETTERS,
        output_dict=True,
        zero_division=0,
    )

    args.model.parent.mkdir(parents=True, exist_ok=True)
    converter = tf.lite.TFLiteConverter.from_keras_model(model)
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
    args.model.write_bytes(converter.convert())
    args.labels.parent.mkdir(parents=True, exist_ok=True)
    args.labels.write_text(json.dumps({"names": LETTERS}, indent=2) + "\n")

    args.report.parent.mkdir(parents=True, exist_ok=True)
    payload = {
        "model": "static ASL alphabet, MediaPipe Hands 21x3 wrist-relative/palm-scaled landmarks",
        "dataset": "Kaggle ameythakur20/asl-alphabet-train (CC BY 4.0)",
        "dataset_counts_with_landmarks": counts,
        "class_names": LETTERS,
        "excluded_motion_letters": ["J", "Z"],
        "split": "stratified image-level 70/15/15; signer-independent split unavailable",
        "seed": SEED,
        "samples": {"total": int(len(y)), "train": int(len(y_train)), "validation": int(len(y_val)), "test": int(len(y_test))},
        "test_accuracy": float(accuracy_score(y_test, predicted)),
        "test_macro_f1": float(report["macro avg"]["f1-score"]),
        "conservative_acceptance": {
            "score_threshold": 0.93,
            "top1_minus_top2_threshold": 0.18,
            "coverage": float(deployment_accept.mean()),
            "accuracy_when_accepted": float(
                accuracy_score(y_test[deployment_accept], predicted[deployment_accept])
            ) if deployment_accept.any() else None,
        },
        "classification_report": report,
        "confusion_matrix": confusion_matrix(y_test, predicted).tolist(),
        "best_validation_accuracy": float(max(history.history["val_accuracy"])),
        "tflite_bytes": args.model.stat().st_size,
        "threshold_note": "Softmax score is a ranking score, not a calibrated probability. Runtime uses temporal agreement and a conservative threshold.",
    }
    args.report.write_text(json.dumps(payload, indent=2) + "\n")
    print(json.dumps({k: payload[k] for k in ("samples", "test_accuracy", "test_macro_f1", "tflite_bytes")}, indent=2))


if __name__ == "__main__":
    main()
