#!/usr/bin/env python3
"""Smoke-test the bundled recognizer and optionally compare a Keras checkpoint.

Run with the supplied environment:
    source ~/Desktop/pyvenv/bin/activate
    python3 scripts/verify_tflite_model.py

For a local checkpoint available to you:
    python3 scripts/verify_tflite_model.py --checkpoint /path/to/best_signbridge.weights.h5

The deterministic synthetic input checks only the runtime tensor contract and
export behavior. It is not an accuracy evaluation.
"""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path

os.environ.setdefault("CUDA_VISIBLE_DEVICES", "")
os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "2")

import numpy as np
import tensorflow as tf


FRAMES = 64
LANDMARKS = 180
COORDS = 3
EMBEDDING_DIM = 300


def build_gru_model() -> tf.keras.Model:
    inputs = tf.keras.Input(
        shape=(FRAMES, LANDMARKS, COORDS), name="landmarks"
    )
    x = tf.keras.layers.Reshape(
        (FRAMES, LANDMARKS * COORDS), name="reshape"
    )(inputs)
    x = tf.keras.layers.TimeDistributed(
        tf.keras.layers.Dense(256, activation="relu"), name="frame_proj"
    )(x)
    x = tf.keras.layers.TimeDistributed(
        tf.keras.layers.LayerNormalization(), name="frame_norm"
    )(x)
    x = tf.keras.layers.Dropout(0.2, name="frame_drop")(x)
    x = tf.keras.layers.Bidirectional(
        tf.keras.layers.GRU(256, return_sequences=True, unroll=True),
        name="bigru_1",
    )(x)
    x = tf.keras.layers.LayerNormalization(name="ln_1")(x)
    x = tf.keras.layers.Bidirectional(
        tf.keras.layers.GRU(128, return_sequences=True, unroll=True),
        name="bigru_2",
    )(x)
    x = tf.keras.layers.LayerNormalization(name="ln_2")(x)
    scores = tf.keras.layers.TimeDistributed(
        tf.keras.layers.Dense(1), name="attn_score"
    )(x)
    weights = tf.keras.layers.Softmax(axis=1, name="attn_weights")(scores)
    x = tf.keras.layers.Multiply(name="attn_apply")([x, weights])
    x = tf.keras.layers.Lambda(
        lambda tensor: tf.reduce_sum(tensor, axis=1), name="attn_pool"
    )(x)
    x = tf.keras.layers.Dense(512, activation="relu", name="head_1")(x)
    x = tf.keras.layers.Dropout(0.4, name="drop_1")(x)
    x = tf.keras.layers.Dense(256, activation="relu", name="head_2")(x)
    x = tf.keras.layers.Dropout(0.3, name="drop_2")(x)
    x = tf.keras.layers.Dense(EMBEDDING_DIM, name="output_vec")(x)
    outputs = tf.keras.layers.Lambda(
        lambda tensor: tf.math.l2_normalize(tensor, axis=-1), name="l2_norm"
    )(x)
    return tf.keras.Model(inputs, outputs, name="SignBridge_GRU")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--model", type=Path, default=Path("assets/ml/sign_bridge.tflite")
    )
    parser.add_argument(
        "--labels", type=Path, default=Path("assets/ml/labels.json")
    )
    parser.add_argument(
        "--checkpoint",
        type=Path,
        help="Optional weights-only checkpoint for synthetic Keras/TFLite parity.",
    )
    parser.add_argument("--seed", type=int, default=1729)
    parser.add_argument("--samples", type=int, default=3)
    args = parser.parse_args()

    with args.labels.open(encoding="utf-8") as file:
        labels = json.load(file)
    names = labels.get("names")
    vectors = np.asarray(labels.get("vectors"), dtype=np.float32)
    if (
        not isinstance(names, list)
        or not names
        or len(set(names)) != len(names)
        or vectors.shape != (len(names), EMBEDDING_DIM)
        or not np.isfinite(vectors).all()
    ):
        raise ValueError("Label names/vectors do not match the 300-D model output.")

    interpreter = tf.lite.Interpreter(model_path=str(args.model), num_threads=2)
    interpreter.allocate_tensors()
    input_detail = interpreter.get_input_details()[0]
    output_detail = interpreter.get_output_details()[0]
    expected_input = [1, FRAMES, LANDMARKS, COORDS]
    expected_output = [1, EMBEDDING_DIM]
    if input_detail["shape"].tolist() != expected_input:
        raise ValueError(f"Unexpected model input shape: {input_detail['shape']}")
    if output_detail["shape"].tolist() != expected_output:
        raise ValueError(f"Unexpected model output shape: {output_detail['shape']}")

    rng = np.random.default_rng(args.seed)
    keras_model = None
    if args.checkpoint:
        keras_model = build_gru_model()
        keras_model.load_weights(args.checkpoint)

    max_errors: list[float] = []
    mean_errors: list[float] = []
    top1_matches = 0
    top5_overlap = 0
    for sample_idx in range(args.samples):
        sample = rng.normal(0.0, 0.2, size=(1, FRAMES, LANDMARKS, COORDS))
        sample = np.clip(sample, -1.0, 1.0).astype(np.float32)
        interpreter.set_tensor(input_detail["index"], sample)
        interpreter.invoke()
        tflite_output = interpreter.get_tensor(output_detail["index"])
        if not np.isfinite(tflite_output).all():
            raise ValueError("TFLite output contains NaN or infinity.")
        norm = float(np.linalg.norm(tflite_output[0]))
        if not 0.98 <= norm <= 1.02:
            raise ValueError(f"TFLite output is not unit-normalized (norm={norm:.5f}).")
        print(f"sample {sample_idx + 1}: TFLite embedding norm={norm:.6f}")

        if keras_model is not None:
            keras_output = keras_model(sample, training=False).numpy()
            max_errors.append(float(np.max(np.abs(keras_output - tflite_output))))
            mean_errors.append(float(np.mean(np.abs(keras_output - tflite_output))))
            keras_scores = keras_output[0] @ vectors.T
            tflite_scores = tflite_output[0] @ vectors.T
            keras_top = np.argsort(keras_scores)[::-1]
            tflite_top = np.argsort(tflite_scores)[::-1]
            top1_matches += int(keras_top[0] == tflite_top[0])
            top5_overlap += len(set(keras_top[:5]) & set(tflite_top[:5]))

    print(f"Model input: {expected_input}; output: {expected_output}")
    print(f"Vocabulary: {len(names)} labels; embeddings: {vectors.shape}")
    if keras_model is not None:
        print(
            "Synthetic checkpoint parity: "
            f"max_abs_error={max(max_errors):.6f}, "
            f"mean_abs_error={np.mean(mean_errors):.6f}, "
            f"top1_agreement={top1_matches}/{args.samples}, "
            f"mean_top5_overlap={top5_overlap / args.samples:.2f}/5"
        )
    print("PASS: TFLite model accepted deterministic synthetic inputs.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
