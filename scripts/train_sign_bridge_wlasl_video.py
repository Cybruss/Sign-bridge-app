#!/usr/bin/env python3
"""Extract Android-compatible Holistic sequences from WLASL MP4s and train a classifier.

The WLASL source videos are inputs only. Per-video feature chunks and training
checkpoints are written under /kaggle/working so completed chunks/epochs can be
reused when Kaggle preserves or reattaches the prior run's outputs.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import os
import shutil
import time
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any

import cv2
import mediapipe as mp
import numpy as np

FRAMES = 64
LANDMARKS = 180
COORDS = 3
NSLT_SUBSET = 2000
MIN_TRAIN_PER_CLASS = 1
TASK_FILENAME = "holistic_landmarker.task"
FACE_INDICES = [
    0, 4, 7, 8, 10, 13, 14, 17, 21, 33, 37, 39, 40, 46, 52, 53, 54, 55,
    58, 61, 63, 65, 66, 67, 70, 78, 80, 81, 82, 84, 87, 88, 91, 93, 95,
    103, 105, 107, 109, 127, 132, 133, 136, 144, 145, 146, 148, 149, 150,
    152, 153, 154, 155, 157, 158, 159, 160, 161, 162, 163, 172, 173, 176,
    178, 181, 185, 191, 234, 246, 249, 251, 263, 267, 269, 270, 276, 282,
    283, 284, 285, 288, 291, 293, 295, 296, 297, 300, 308, 310, 311, 312,
    314, 317, 318, 321, 323, 324, 332, 334, 336, 338, 356, 361, 362, 365,
    373, 374, 375, 377, 378, 379, 380, 381, 382, 384, 385, 386, 387, 388,
    389, 390, 397, 398, 400, 402, 405, 409, 415, 454, 466, 468, 473,
]
POSE_INDICES = [11, 12, 13, 14, 15, 16]


def args_parser() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--mode", choices=("preflight", "full"), default="full")
    parser.add_argument("--data-root", type=Path, default=Path("/kaggle/input/wlasl-processed"))
    parser.add_argument("--task-model", type=Path, default=Path("/kaggle/input/sign-bridge-holistic-task-model/holistic_landmarker.task"))
    parser.add_argument("--work-dir", type=Path, default=Path("/kaggle/working/sign_bridge_wlasl_run"))
    parser.add_argument("--epochs", type=int, default=60)
    parser.add_argument("--batch-size", type=int, default=32)
    parser.add_argument("--extract-chunk-size", type=int, default=64)
    return parser.parse_args()


def read_records(root: Path) -> tuple[list[dict[str, Any]], list[str], dict[str, Any]]:
    classes = {}
    for line in (root / "wlasl_class_list.txt").read_text(encoding="utf-8").splitlines():
        class_id, gloss = line.strip().split(maxsplit=1)
        classes[int(class_id)] = gloss

    with (root / f"nslt_{NSLT_SUBSET}.json").open(encoding="utf-8") as source:
        nslt = json.load(source)
    with (root / "WLASL_v0.3.json").open(encoding="utf-8") as source:
        wlasl = json.load(source)

    annotations: dict[str, dict[str, Any]] = {}
    for word in wlasl:
        for instance in word.get("instances", []):
            video_id = str(instance.get("video_id", ""))
            if video_id:
                annotations[video_id] = {**instance, "gloss": str(word.get("gloss", ""))}

    video_root = root / "videos"
    split_counts: dict[str, Counter[str]] = {s: Counter() for s in ("train", "val", "test")}
    rows: list[dict[str, Any]] = []
    missing_video = 0
    missing_metadata = 0
    for video_id, item in nslt.items():
        video_id = str(video_id)
        action = item.get("action", [])
        split = str(item.get("subset", "")).lower()
        if len(action) < 1 or split not in split_counts or action[0] not in classes:
            continue
        gloss = classes[action[0]]
        if not (video_root / f"{video_id}.mp4").is_file():
            missing_video += 1
            continue
        annotation = annotations.get(video_id)
        if annotation is None or annotation.get("gloss") != gloss:
            missing_metadata += 1
            continue
        start = int(annotation.get("frame_start", 1) or 1)
        end = int(annotation.get("frame_end", -1) or -1)
        rows.append({
            "video_id": video_id,
            "gloss": gloss,
            "split": split,
            "signer_id": str(annotation.get("signer_id", "")),
            "frame_start": start,
            "frame_end": end,
            "fps": float(annotation.get("fps", 25) or 25),
            "path": str(video_root / f"{video_id}.mp4"),
        })
        split_counts[split][gloss] += 1

    common = set.intersection(*(set(split_counts[s]) for s in ("train", "val", "test")))
    eligible = {
        gloss for gloss in common
        if split_counts["train"][gloss] >= MIN_TRAIN_PER_CLASS
    }
    rows = [row for row in rows if row["gloss"] in eligible]
    rows.sort(key=lambda row: (row["split"], row["gloss"], row["video_id"]))
    class_names = sorted(eligible)
    summary = {
        "subset": f"WLASL{NSLT_SUBSET}",
        "source_video_count": len({row["video_id"] for row in rows}),
        "usable_class_count": len(class_names),
        "class_names": class_names,
        "eligible_examples_by_split": dict(Counter(row["split"] for row in rows)),
        "source_videos_missing_locally": missing_video,
        "annotation_join_mismatches": missing_metadata,
        "eligibility": f"At least {MIN_TRAIN_PER_CLASS} available train clip and at least one available val and test clip per class.",
        "split_policy": "Official NSLT train/val/test split; signer IDs are preserved and overlap must be audited.",
    }
    return rows, class_names, summary


def make_preflight_rows(rows: list[dict[str, Any]], class_names: list[str]) -> tuple[list[dict[str, Any]], list[str]]:
    # A deterministic small sample with all three splits for a few glosses.
    selected_names = class_names[:6]
    chosen = []
    for gloss in selected_names:
        for split in ("train", "val", "test"):
            candidates = [row for row in rows if row["gloss"] == gloss and row["split"] == split]
            chosen.extend(candidates[:2 if split != "train" else 3])
    return chosen, selected_names


def extract_one(row: dict[str, Any], landmarker: Any) -> tuple[np.ndarray, float]:
    cap = cv2.VideoCapture(row["path"])
    if not cap.isOpened():
        raise ValueError("video_open_failed")
    fps = cap.get(cv2.CAP_PROP_FPS)
    if not np.isfinite(fps) or fps < 1:
        fps = 25.0
    total = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    if total < 1:
        cap.release()
        raise ValueError("video_has_no_frames")
    # WLASL boundaries are indexed at 25 fps; convert to the decoded file FPS.
    start = max(0, int(round((row["frame_start"] - 1) * fps / max(row["fps"], 1.0))))
    end = total - 1 if row["frame_end"] < 0 else int(round((row["frame_end"] - 1) * fps / max(row["fps"], 1.0)))
    start = min(start, total - 1)
    end = min(max(end, start), total - 1)
    targets = np.rint(np.linspace(start, end, FRAMES)).astype(np.int64)
    target_slots: dict[int, list[int]] = defaultdict(list)
    for slot, frame_index in enumerate(targets):
        target_slots[int(frame_index)].append(slot)

    sequence = np.zeros((FRAMES, LANDMARKS, COORDS), dtype=np.float32)
    seen_hands = 0
    cap.set(cv2.CAP_PROP_POS_FRAMES, start)
    current_index = start
    while current_index <= end:
        ok, bgr = cap.read()
        if not ok:
            break
        slots = target_slots.get(current_index)
        if slots:
            rgb = cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB)
            # Holistic's temporal smoothing graph expects a stable image size
            # across calls made by the same landmarker instance.
            rgb = cv2.resize(rgb, (256, 256), interpolation=cv2.INTER_AREA)
            result = landmarker.detect(mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb))
            right = result.right_hand_landmarks or []
            left = result.left_hand_landmarks or []
            pose = result.pose_landmarks or []
            face = result.face_landmarks or []
            if right or left:
                seen_hands += len(slots)
            feature = np.zeros((LANDMARKS, COORDS), dtype=np.float32)
            offset = 0
            for group, indices in ((right, range(21)), (left, range(21)), (pose, POSE_INDICES), (face, FACE_INDICES)):
                for index in indices:
                    if group and index < len(group):
                        lm = group[index]
                        feature[offset] = (lm.x, lm.y, lm.z)
                    offset += 1
            for slot in slots:
                sequence[slot] = feature
        current_index += 1
    cap.release()
    if not np.any(sequence):
        raise ValueError("no_landmarks_detected")
    return normalize_sequence(sequence), float(seen_hands / FRAMES)


def normalize_sequence(sequence: np.ndarray) -> np.ndarray:
    seq = np.asarray(sequence, dtype=np.float32).copy()
    if seq.shape != (FRAMES, LANDMARKS, COORDS) or not np.isfinite(seq).all():
        raise ValueError(f"invalid_sequence_shape_or_values: {seq.shape}")
    for frame in seq:
        for start, end in ((0, 21), (21, 42)):
            hand = frame[start:end]
            if np.any(hand != 0):
                hand -= hand[0].copy()
                hand /= max(float(np.max(np.abs(hand))), 1e-6)
    return seq


def locate_completed_chunks(work: Path, split: str) -> set[int]:
    directory = work / "features" / split
    return {int(path.stem.split("_")[-1]) for path in directory.glob("chunk_*.npz")}


def extract_chunks(rows: list[dict[str, Any]], class_names: list[str], task_model: Path,
                   work: Path, chunk_size: int, mode: str) -> None:
    class_to_id = {name: index for index, name in enumerate(class_names)}
    task = mp.tasks.vision
    landmarker = None
    for delegate in (mp.tasks.BaseOptions.Delegate.GPU, mp.tasks.BaseOptions.Delegate.CPU):
        options = task.HolisticLandmarkerOptions(
            base_options=mp.tasks.BaseOptions(model_asset_path=str(task_model), delegate=delegate),
            running_mode=task.RunningMode.IMAGE,
            min_face_detection_confidence=0.5,
            min_pose_detection_confidence=0.5,
            min_hand_landmarks_confidence=0.5,
        )
        try:
            landmarker = task.HolisticLandmarker.create_from_options(options)
            print(f"[extract] MediaPipe delegate: {delegate.name}", flush=True)
            break
        except Exception as error:
            print(f"[extract] {delegate.name} delegate unavailable: {error}; trying fallback", flush=True)
    if landmarker is None:
        raise RuntimeError("Could not initialize MediaPipe Holistic with GPU or CPU delegate")
    failures_path = work / "extraction_failures.csv"
    progress_path = work / "extraction_progress.json"
    chunk_total = 0
    failure_counts: Counter[str] = Counter()
    with landmarker:
        for split in ("train", "val", "test"):
            subset = [row for row in rows if row["split"] == split]
            if mode == "preflight":
                subset = subset[:96]
            out_dir = work / "features" / split
            out_dir.mkdir(parents=True, exist_ok=True)
            chunk_count = (len(subset) + chunk_size - 1) // chunk_size
            for chunk_index in range(chunk_count):
                target = out_dir / f"chunk_{chunk_index:05d}.npz"
                start = chunk_index * chunk_size
                chunk_rows = subset[start:start + chunk_size]
                expected_ids = [row["video_id"] for row in chunk_rows]
                if target.is_file():
                    try:
                        with np.load(target, allow_pickle=False) as saved:
                            if saved["video_ids"].astype(str).tolist() == expected_ids:
                                chunk_total += 1
                                continue
                    except Exception:
                        target.unlink(missing_ok=True)
                xs: list[np.ndarray] = []
                ys: list[int] = []
                ids: list[str] = []
                ratios: list[float] = []
                reasons: list[str] = []
                for row in chunk_rows:
                    try:
                        x, hand_ratio = extract_one(row, landmarker)
                        xs.append(x)
                        ys.append(class_to_id[row["gloss"]])
                        ids.append(row["video_id"])
                        ratios.append(hand_ratio)
                    except Exception as error:
                        reasons.append(f"{row['video_id']},{row['gloss']},{split},{type(error).__name__}:{error}")
                        failure_counts[type(error).__name__] += 1
                temp = target.with_suffix(".tmp.npz")
                np.savez_compressed(
                    temp,
                    x=np.stack(xs) if xs else np.zeros((0, FRAMES, LANDMARKS, COORDS), dtype=np.float32),
                    y=np.asarray(ys, dtype=np.int32),
                    video_ids=np.asarray(ids, dtype=str),
                    hand_frame_ratio=np.asarray(ratios, dtype=np.float32),
                )
                os.replace(temp, target)
                if reasons:
                    with failures_path.open("a", encoding="utf-8") as failures:
                        if failures.tell() == 0:
                            failures.write("video_id,gloss,split,reason\n")
                        failures.write("\n".join(reasons) + "\n")
                chunk_total += 1
                if chunk_total % 5 == 0 or chunk_total == 1:
                    progress_path.write_text(json.dumps({
                        "completed_chunks": chunk_total,
                        "split": split,
                        "chunk": chunk_index,
                        "failures_by_exception": dict(failure_counts),
                        "updated_unix": time.time(),
                    }, indent=2))
                    print(f"[extract] {split}: chunk {chunk_index + 1}/{chunk_count}; completed chunks={chunk_total}; failures={sum(failure_counts.values())}", flush=True)


def load_split(work: Path, split: str) -> tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
    paths = sorted((work / "features" / split).glob("chunk_*.npz"))
    if not paths:
        raise RuntimeError(f"No extracted chunks for {split}")
    xs, ys, ids, hand_ratios = [], [], [], []
    for path in paths:
        with np.load(path, allow_pickle=False) as data:
            if len(data["x"]):
                xs.append(data["x"])
                ys.append(data["y"])
                ids.append(data["video_ids"])
                hand_ratios.append(data["hand_frame_ratio"])
    if not xs:
        raise RuntimeError(f"All videos failed extraction for {split}")
    return np.concatenate(xs), np.concatenate(ys), np.concatenate(ids), np.concatenate(hand_ratios)


def build_classifier(tf: Any, classes: int, unroll: bool = False) -> Any:
    inputs = tf.keras.Input((FRAMES, LANDMARKS, COORDS), name="landmarks")
    x = tf.keras.layers.Reshape((FRAMES, LANDMARKS * COORDS), name="flatten_frame")(inputs)
    x = tf.keras.layers.TimeDistributed(tf.keras.layers.Dense(128, activation="relu"), name="frame_projection")(x)
    x = tf.keras.layers.TimeDistributed(tf.keras.layers.LayerNormalization(), name="frame_normalization")(x)
    x = tf.keras.layers.Dropout(0.15)(x)
    x = tf.keras.layers.Bidirectional(tf.keras.layers.GRU(128, return_sequences=True, unroll=unroll), name="bigru")(x)
    x = tf.keras.layers.LayerNormalization()(x)
    scores = tf.keras.layers.TimeDistributed(tf.keras.layers.Dense(1), name="temporal_attention_scores")(x)
    weights = tf.keras.layers.Softmax(axis=1, name="temporal_attention_weights")(scores)
    x = tf.keras.layers.Multiply()([x, weights])
    x = tf.keras.layers.Lambda(lambda value: tf.reduce_sum(value, axis=1), name="temporal_pool")(x)
    x = tf.keras.layers.Dense(256, activation="relu")(x)
    x = tf.keras.layers.Dropout(0.35)(x)
    outputs = tf.keras.layers.Dense(classes, activation="softmax", name="gloss_probabilities")(x)
    return tf.keras.Model(inputs, outputs, name="SignBridge_WLASL_video_classifier")


def evaluate_model(model: Any, x: np.ndarray, y: np.ndarray, class_names: list[str],
                   ids: np.ndarray, work: Path) -> dict[str, Any]:
    from sklearn.metrics import accuracy_score, confusion_matrix, f1_score, precision_recall_fscore_support
    probabilities = model.predict(x, batch_size=64, verbose=1)
    top = np.argsort(probabilities, axis=1)[:, ::-1]
    pred = top[:, 0]
    per_class = precision_recall_fscore_support(y, pred, labels=np.arange(len(class_names)), zero_division=0)
    metrics = {
        "samples": int(len(y)),
        "labels": len(class_names),
        "top1_accuracy": float(accuracy_score(y, pred)),
        "top5_accuracy": float(np.mean([int(target) in ranks[:5] for target, ranks in zip(y, top)])),
        "macro_precision": float(np.mean(per_class[0])),
        "macro_recall": float(np.mean(per_class[1])),
        "macro_f1": float(f1_score(y, pred, labels=np.arange(len(class_names)), average="macro", zero_division=0)),
    }
    with (work / "per_class_metrics.csv").open("w", newline="", encoding="utf-8") as file:
        writer = csv.writer(file)
        writer.writerow(("gloss", "precision", "recall", "f1", "support"))
        for index, name in enumerate(class_names):
            writer.writerow((name, per_class[0][index], per_class[1][index], per_class[2][index], per_class[3][index]))
    matrix = confusion_matrix(y, pred, labels=np.arange(len(class_names)))
    np.savetxt(work / "confusion_matrix.csv", matrix, delimiter=",", fmt="%d")
    np.savez_compressed(work / "test_predictions.npz", video_ids=ids, y_true=y, y_pred=pred, top5=top[:, :5])
    return metrics


def train(args: argparse.Namespace, rows: list[dict[str, Any]], class_names: list[str],
          work: Path, epochs: int) -> None:
    import tensorflow as tf
    if not tf.config.list_physical_devices("GPU"):
        raise RuntimeError("A Kaggle GPU was requested but TensorFlow sees no GPU; stopping before training.")
    x_train, y_train, train_ids, train_hand_ratio = load_split(work, "train")
    x_val, y_val, val_ids, val_hand_ratio = load_split(work, "val")
    x_test, y_test, test_ids, test_hand_ratio = load_split(work, "test")
    if len(class_names) < 2 or min(len(y_train), len(y_val), len(y_test)) < 1:
        raise RuntimeError("Dataset has insufficient usable classes/splits")

    model = build_classifier(tf, len(class_names))
    optimizer = tf.keras.optimizers.Adam(learning_rate=1e-3, clipnorm=1.0)
    model.compile(optimizer=optimizer, loss="sparse_categorical_crossentropy", metrics=["accuracy"])
    checkpoint_dir = work / "checkpoints"
    checkpoint_dir.mkdir(parents=True, exist_ok=True)
    epoch_variable = tf.Variable(0, trainable=False, dtype=tf.int64, name="completed_epochs")
    checkpoint = tf.train.Checkpoint(model=model, optimizer=optimizer, epoch=epoch_variable)
    manager = tf.train.CheckpointManager(checkpoint, str(checkpoint_dir), max_to_keep=3)
    initial_epoch = 0
    if manager.latest_checkpoint:
        checkpoint.restore(manager.latest_checkpoint).expect_partial()
        initial_epoch = int(epoch_variable.numpy())
        print(f"[resume] restored {manager.latest_checkpoint}; next epoch={initial_epoch + 1}", flush=True)

    class CheckpointEveryEpoch(tf.keras.callbacks.Callback):
        def on_epoch_end(self, epoch: int, logs: dict[str, Any] | None = None) -> None:
            epoch_variable.assign(epoch + 1)
            path = manager.save(checkpoint_number=epoch + 1)
            (work / "latest_checkpoint.json").write_text(json.dumps({
                "checkpoint": str(Path(path).relative_to(work)),
                "completed_epoch": epoch + 1,
                "val_loss": None if logs is None else float(logs.get("val_loss", float("nan"))),
            }, indent=2))
            print(f"[checkpoint] saved epoch {epoch + 1} -> {path}", flush=True)

    best_path = work / "best.weights.h5"
    callbacks = [
        CheckpointEveryEpoch(),
        tf.keras.callbacks.ModelCheckpoint(best_path, monitor="val_accuracy", mode="max", save_best_only=True, save_weights_only=True, verbose=1),
        tf.keras.callbacks.CSVLogger(str(work / "training_log.csv"), append=initial_epoch > 0),
        tf.keras.callbacks.EarlyStopping(monitor="val_accuracy", mode="max", patience=10, restore_best_weights=True, verbose=1),
        tf.keras.callbacks.ReduceLROnPlateau(monitor="val_loss", factor=0.5, patience=4, min_lr=1e-5, verbose=1),
    ]
    counts = np.bincount(y_train, minlength=len(class_names)).astype(np.float32)
    weights = np.sqrt(max(float(counts.max()), 1.0) / np.maximum(counts, 1.0))
    class_weight = {i: float(min(weights[i], 4.0)) for i in range(len(class_names))}
    print(f"[train] GPU={tf.config.list_physical_devices('GPU')}; samples train/val/test={len(y_train)}/{len(y_val)}/{len(y_test)}; labels={len(class_names)}", flush=True)
    print(f"[train] input shape={x_train.shape[1:]}; output classes={len(class_names)}", flush=True)
    model.fit(
        x_train, y_train,
        validation_data=(x_val, y_val),
        batch_size=args.batch_size,
        epochs=epochs,
        initial_epoch=initial_epoch,
        class_weight=class_weight,
        shuffle=True,
        callbacks=callbacks,
        verbose=2,
    )
    if best_path.is_file():
        model.load_weights(best_path)

    # Static unrolling keeps the exported graph compatible with the app's
    # builtin-only TFLite interpreter while preserving the training weights.
    export_model = build_classifier(tf, len(class_names), unroll=True)
    export_model.set_weights(model.get_weights())
    model_path = work / "sign_bridge_wlasl_video.tflite"
    converter = tf.lite.TFLiteConverter.from_keras_model(export_model)
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
    model_path.write_bytes(converter.convert())
    interpreter = tf.lite.Interpreter(model_path=str(model_path))
    interpreter.allocate_tensors()
    input_detail = interpreter.get_input_details()[0]
    output_detail = interpreter.get_output_details()[0]
    sample = np.asarray(x_test[:1], dtype=np.float32)
    interpreter.set_tensor(input_detail["index"], sample)
    interpreter.invoke()
    tflite_output = interpreter.get_tensor(output_detail["index"])
    keras_output = export_model(sample, training=False).numpy()
    parity = {
        "input_shape": input_detail["shape"].tolist(),
        "output_shape": output_detail["shape"].tolist(),
        "max_absolute_error": float(np.max(np.abs(keras_output - tflite_output))),
        "mean_absolute_error": float(np.mean(np.abs(keras_output - tflite_output))),
        "top1_match": bool(np.argmax(keras_output[0]) == np.argmax(tflite_output[0])),
    }
    if not np.isfinite(tflite_output).all() or parity["max_absolute_error"] > 0.05:
        raise RuntimeError(f"TFLite export parity check failed: {parity}")
    (work / "tflite_validation.json").write_text(json.dumps(parity, indent=2) + "\n")
    metrics = evaluate_model(model, x_test, y_test, class_names, test_ids, work)
    (work / "labels.json").write_text(json.dumps({"names": class_names}, ensure_ascii=False, indent=2) + "\n")
    (work / "evaluation.json").write_text(json.dumps(metrics, indent=2) + "\n")
    (work / "model_metadata.json").write_text(json.dumps({
        "model": model_path.name,
        "task": "isolated WLASL gloss classification",
        "input": [1, FRAMES, LANDMARKS, COORDS],
        "output": [1, len(class_names)],
        "output_semantics": "softmax gloss probabilities",
        "labels_file": "labels.json",
        "dataset": f"WLASL{NSLT_SUBSET}",
        "classes": len(class_names),
        "test_metrics": metrics,
        "split_policy": "Official NSLT split; signer-disjointness is not assumed.",
        "preprocessing": "MediaPipe Holistic normalized image landmarks; right hand, left hand, pose indices 11..16, 132 selected face landmarks; per-frame wrist-center/max-absolute hand scale; resampled to 64 frames.",
        "note": "Raw WLASL clip recognition is isolated-word recognition, not continuous sentence translation.",
    }, indent=2) + "\n")
    print(f"[complete] TFLite saved: {model_path} ({model_path.stat().st_size:,} bytes)", flush=True)
    print("[complete] evaluation:", json.dumps(metrics, sort_keys=True), flush=True)


def main() -> None:
    args = args_parser()
    args.data_root = args.data_root.resolve()
    args.work_dir.mkdir(parents=True, exist_ok=True)
    if not (args.data_root / "videos").is_dir():
        candidates = [p.parent for p in Path("/kaggle/input").rglob("WLASL_v0.3.json")]
        candidates = [p for p in candidates if (p / "videos").is_dir()]
        if len(candidates) == 1:
            args.data_root = candidates[0]
        else:
            mounted = sorted(str(p) for p in Path("/kaggle/input").iterdir()) if Path("/kaggle/input").exists() else []
            raise FileNotFoundError(
                f"Could not locate WLASL videos. configured={args.data_root}, "
                f"candidate_roots={[str(p) for p in candidates]}, mounted_inputs={mounted}"
            )
    if not args.task_model.is_file():
        candidates = list(Path("/kaggle/input").rglob(TASK_FILENAME))
        if len(candidates) == 1:
            args.task_model = candidates[0]
        else:
            raise FileNotFoundError(
                f"Holistic task model missing at {args.task_model}; "
                f"candidates={[str(p) for p in candidates]}"
            )

    rows, class_names, summary = read_records(args.data_root)
    if args.mode == "preflight":
        rows, class_names = make_preflight_rows(rows, class_names)
        args.epochs = 1
        args.extract_chunk_size = 16
        print(f"[preflight] using {len(rows)} clips across {len(class_names)} glosses")
    summary["mode"] = args.mode
    summary["selected_examples_by_split"] = dict(Counter(row["split"] for row in rows))
    summary["classes_selected"] = len(class_names)
    summary["max_epochs"] = args.epochs
    summary["feature_schema"] = "signbridge.android_holistic180.v1"
    (args.work_dir / "dataset_summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    with (args.work_dir / "manifest.csv").open("w", newline="", encoding="utf-8") as manifest_file:
        writer = csv.DictWriter(manifest_file, fieldnames=(
            "video_id", "gloss", "split", "signer_id", "frame_start", "frame_end", "fps"))
        writer.writeheader()
        for row in rows:
            writer.writerow({key: row[key] for key in writer.fieldnames})
    (args.work_dir / "labels.json").write_text(json.dumps({"names": class_names}, ensure_ascii=False, indent=2) + "\n")
    print("[audit]", json.dumps({k: v for k, v in summary.items() if k != "class_names"}, sort_keys=True), flush=True)

    started = time.time()
    extract_chunks(rows, class_names, args.task_model, args.work_dir, args.extract_chunk_size, args.mode)
    (args.work_dir / "extraction_complete.json").write_text(json.dumps({
        "elapsed_seconds": time.time() - started,
        "chunks": {split: len(list((args.work_dir / "features" / split).glob("chunk_*.npz"))) for split in ("train", "val", "test")},
    }, indent=2) + "\n")
    if args.mode == "preflight":
        # Check the complete data/model/export path without spending time on a full run.
        import tensorflow as tf
        if not tf.config.list_physical_devices("GPU"):
            raise RuntimeError("Preflight requested GPU but TensorFlow sees no GPU")
        x_train, y_train, _, _ = load_split(args.work_dir, "train")
        x_val, y_val, _, _ = load_split(args.work_dir, "val")
        x_test, _, _, _ = load_split(args.work_dir, "test")
        model = build_classifier(tf, len(class_names))
        model.compile(optimizer="adam", loss="sparse_categorical_crossentropy", metrics=["accuracy"])
        model.fit(x_train, y_train, validation_data=(x_val, y_val), epochs=1, batch_size=4, verbose=2)
        path = args.work_dir / "preflight.tflite"
        export_model = build_classifier(tf, len(class_names), unroll=True)
        export_model.set_weights(model.get_weights())
        path.write_bytes(tf.lite.TFLiteConverter.from_keras_model(export_model).convert())
        interpreter = tf.lite.Interpreter(model_path=str(path))
        interpreter.allocate_tensors()
        input_shape = interpreter.get_input_details()[0]["shape"].tolist()
        output_shape = interpreter.get_output_details()[0]["shape"].tolist()
        if input_shape != [1, FRAMES, LANDMARKS, COORDS] or output_shape != [1, len(class_names)]:
            raise RuntimeError(f"Unexpected TFLite contract: {input_shape} -> {output_shape}")
        interpreter.set_tensor(interpreter.get_input_details()[0]["index"], np.asarray(x_test[:1], dtype=np.float32))
        interpreter.invoke()
        smoke_output = interpreter.get_tensor(interpreter.get_output_details()[0]["index"])
        if not np.isfinite(smoke_output).all():
            raise RuntimeError("Preflight TFLite inference produced non-finite values")
        print("[preflight] sample splits:", len(x_train), len(x_val), len(x_test), flush=True)
        print("[preflight] TFLite input/output:", input_shape, output_shape, flush=True)
        print("[preflight] PASS: video decode -> Holistic -> 64x180x3 -> GPU train -> TFLite export", flush=True)
        return
    train(args, rows, class_names, args.work_dir, args.epochs)


if __name__ == "__main__":
    main()
