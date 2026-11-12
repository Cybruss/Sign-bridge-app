#!/usr/bin/env python3
"""Reproducible WLASL/MuteMotion landmark-sequence training and export.

The script preserves Sign Bridge's existing 64 x 180 x 3 -> 300-D embedding
contract. Inputs are the four files documented in docs/KAGGLE_SETUP.md.
"""

from __future__ import annotations

import argparse
import csv
import json
import math
import os
import random
import time
from pathlib import Path
from typing import Any

import numpy as np

DESIRED_FRAMES = 64
TOTAL_LANDMARKS = 180
COORDS = 3
OUTPUT_DIM = 300
HAND_INDICES = list(range(21))
POSE_INDICES = [11, 12, 13, 14, 15, 16]
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
LANDMARK_INDICES = (
    HAND_INDICES + [i + 21 for i in HAND_INDICES]
    + [i + 42 for i in POSE_INDICES]
    + [i + 75 for i in FACE_INDICES]
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--data-dir', type=Path, required=True)
    parser.add_argument('--output-dir', type=Path, required=True)
    parser.add_argument('--epochs', type=int, default=80)
    parser.add_argument('--batch-size', type=int, default=32)
    parser.add_argument('--seed', type=int, default=2026)
    parser.add_argument('--initial-weights', type=Path)
    parser.add_argument('--learning-rate', type=float, default=1e-3)
    parser.add_argument('--patience', type=int, default=20)
    parser.add_argument('--max-samples-per-split', type=int, default=0,
                        help='Optional smoke-run cap; 0 uses every eligible sample.')
    return parser.parse_args()


def normalize_sequence(sequence: np.ndarray) -> np.ndarray:
    seq = np.asarray(sequence, dtype=np.float32).copy()
    if seq.ndim != 3 or seq.shape[1:] != (TOTAL_LANDMARKS, COORDS):
        raise ValueError(f'Expected [frames,180,3], got {seq.shape}')
    if len(seq) == 0:
        raise ValueError('Sample has no frames')
    if not np.isfinite(seq).all():
        raise ValueError('Sample contains NaN or infinite coordinates')
    for frame in seq:
        for start, end in ((0, 21), (21, 42)):
            hand = frame[start:end]
            if np.any(hand != 0):
                hand -= hand[0].copy()
                hand /= max(float(np.max(np.abs(hand))), 1e-6)
    if len(seq) == DESIRED_FRAMES:
        return seq
    source_positions = np.linspace(0, len(seq) - 1, DESIRED_FRAMES)
    lower = np.floor(source_positions).astype(np.int32)
    upper = np.minimum(lower + 1, len(seq) - 1)
    alpha = (source_positions - lower).astype(np.float32)[:, None, None]
    return ((1 - alpha) * seq[lower] + alpha * seq[upper]).astype(np.float32)


def parse_dataset(data_dir: Path) -> tuple[list[dict[str, Any]], dict[str, np.ndarray]]:
    required = ('landmarks_V3.npz', 'labels.npz', 'WLASL_parsed_data.json',
                'filtered_labels.txt')
    missing = [name for name in required if not (data_dir / name).is_file()]
    if missing:
        raise FileNotFoundError(f'Missing required dataset files in {data_dir}: {missing}')
    if len(LANDMARK_INDICES) != TOTAL_LANDMARKS:
        raise AssertionError(f'Feature schema has {len(LANDMARK_INDICES)} indices, expected 180')

    with (data_dir / 'WLASL_parsed_data.json').open() as stream:
        annotations = json.load(stream)
    if not isinstance(annotations, list):
        raise ValueError('WLASL_parsed_data.json must be a list indexed by integer video id')
    allowed = {line.strip() for line in (data_dir / 'filtered_labels.txt').read_text().splitlines()
               if line.strip()}
    with np.load(data_dir / 'labels.npz', allow_pickle=True) as archive:
        vectors = {key: np.asarray(archive[key], dtype=np.float32).squeeze()
                   for key in archive.files}
    vectors = {key: value for key, value in vectors.items()
               if value.shape == (OUTPUT_DIM,) and np.isfinite(value).all()
               and np.linalg.norm(value) > 1e-8}
    if not vectors:
        raise ValueError('No valid 300-D label embeddings in labels.npz')

    records: list[dict[str, Any]] = []
    with np.load(data_dir / 'landmarks_V3.npz', allow_pickle=True) as archive:
        for key in archive.files:
            try:
                sample_id = int(key)
            except ValueError:
                continue
            if sample_id < 0 or sample_id >= len(annotations):
                continue
            item = annotations[sample_id]
            gloss = str(item.get('gloss', '')).strip()
            split = str(item.get('split', '')).strip().lower()
            if gloss not in allowed or gloss not in vectors or split not in ('train', 'val', 'test'):
                continue
            raw_shape = archive[key].shape
            if len(raw_shape) != 3 or raw_shape[1:] != (553, 3) or raw_shape[0] == 0:
                continue
            records.append({'key': key, 'id': sample_id, 'gloss': gloss, 'split': split})

    if not records:
        raise ValueError('No usable samples matched NPZ keys, annotation ids, splits and labels')
    id_splits: dict[int, set[str]] = {}
    for record in records:
        id_splits.setdefault(record['id'], set()).add(record['split'])
    duplicated = [sample_id for sample_id, splits in id_splits.items() if len(splits) > 1]
    if duplicated:
        raise ValueError(f'Sample ids appear in multiple splits: {duplicated[:10]}')
    return records, vectors


def make_feature_cache(data_dir: Path, out_dir: Path, records: list[dict[str, Any]],
                       vectors: dict[str, np.ndarray], cap: int) -> dict[str, tuple[Path, list[str]]]:
    randomizer = random.Random(2026)
    split_records: dict[str, list[dict[str, Any]]] = {}
    for split in ('train', 'val', 'test'):
        subset = [record for record in records if record['split'] == split]
        if cap > 0 and split == 'train':
            randomizer.shuffle(subset)
            subset = subset[:cap]
        elif cap > 0:
            subset = subset[:cap]
        split_records[split] = subset
    if any(not split_records[name] for name in ('train', 'val', 'test')):
        raise ValueError('Train, validation and test splits must all contain samples')

    cache_dir = out_dir / 'feature_cache'
    cache_dir.mkdir(parents=True, exist_ok=True)
    result = {}
    with np.load(data_dir / 'landmarks_V3.npz', allow_pickle=True) as archive:
        for split, subset in split_records.items():
            feature_path = cache_dir / f'{split}_x.npy'
            label_path = cache_dir / f'{split}_y.npy'
            glosses = [record['gloss'] for record in subset]
            if not feature_path.exists() or not label_path.exists():
                x_map = np.lib.format.open_memmap(
                    feature_path, mode='w+', dtype=np.float32,
                    shape=(len(subset), DESIRED_FRAMES, TOTAL_LANDMARKS, COORDS))
                y_map = np.lib.format.open_memmap(
                    label_path, mode='w+', dtype=np.float32,
                    shape=(len(subset), OUTPUT_DIM))
                for index, record in enumerate(subset):
                    raw = np.asarray(archive[record['key']], dtype=np.float32)
                    selected = raw[:, LANDMARK_INDICES, :]
                    x_map[index] = normalize_sequence(selected)
                    vector = vectors[record['gloss']]
                    y_map[index] = vector / np.linalg.norm(vector)
                x_map.flush()
                y_map.flush()
                del x_map, y_map
            else:
                x_shape = np.load(feature_path, mmap_mode='r').shape
                if x_shape != (len(subset), DESIRED_FRAMES, TOTAL_LANDMARKS, COORDS):
                    raise ValueError(f'Stale cache {feature_path}; remove cache and rerun')
            result[split] = (feature_path, glosses)
    return result


def build_model(tf: Any, unroll: bool = False) -> Any:
    inputs = tf.keras.Input((DESIRED_FRAMES, TOTAL_LANDMARKS, COORDS), name='landmarks')
    x = tf.keras.layers.Reshape((DESIRED_FRAMES, TOTAL_LANDMARKS * COORDS), name='reshape')(inputs)
    x = tf.keras.layers.TimeDistributed(tf.keras.layers.Dense(256, activation='relu'), name='frame_proj')(x)
    x = tf.keras.layers.TimeDistributed(tf.keras.layers.LayerNormalization(), name='frame_norm')(x)
    x = tf.keras.layers.Dropout(0.2, name='frame_drop')(x)
    x = tf.keras.layers.Bidirectional(
        tf.keras.layers.GRU(256, return_sequences=True, dropout=0.2,
                            recurrent_dropout=0.1, unroll=unroll), name='bigru_1')(x)
    x = tf.keras.layers.LayerNormalization(name='ln_1')(x)
    x = tf.keras.layers.Bidirectional(
        tf.keras.layers.GRU(128, return_sequences=True, dropout=0.2,
                            recurrent_dropout=0.1, unroll=unroll), name='bigru_2')(x)
    x = tf.keras.layers.LayerNormalization(name='ln_2')(x)
    scores = tf.keras.layers.TimeDistributed(tf.keras.layers.Dense(1), name='attn_score')(x)
    weights = tf.keras.layers.Softmax(axis=1, name='attn_weights')(scores)
    x = tf.keras.layers.Multiply(name='attn_apply')([x, weights])
    x = tf.keras.layers.Lambda(lambda value: tf.reduce_sum(value, axis=1), name='attn_pool')(x)
    x = tf.keras.layers.Dense(512, activation='relu', name='head_1')(x)
    x = tf.keras.layers.Dropout(0.4, name='drop_1')(x)
    x = tf.keras.layers.Dense(256, activation='relu', name='head_2')(x)
    x = tf.keras.layers.Dropout(0.3, name='drop_2')(x)
    x = tf.keras.layers.Dense(OUTPUT_DIM, name='output_vec')(x)
    outputs = tf.keras.layers.Lambda(
        lambda value: tf.math.l2_normalize(value, axis=-1), name='l2_norm')(x)
    return tf.keras.Model(inputs, outputs, name='SignBridge_GRU')


def evaluate(tf: Any, model: Any, x_path: Path, glosses: list[str],
             train_glosses: list[str], vectors: dict[str, np.ndarray], out_dir: Path) -> dict[str, Any]:
    from sklearn.metrics import confusion_matrix, precision_recall_fscore_support

    label_names = sorted(set(train_glosses))
    label_vectors = np.stack([vectors[name] / np.linalg.norm(vectors[name]) for name in label_names])
    x = np.load(x_path, mmap_mode='r')
    embeddings = model.predict(x, batch_size=32, verbose=1)
    scores = embeddings @ label_vectors.T
    top = np.argsort(scores, axis=1)[:, ::-1]
    y_true = np.asarray(glosses)
    y_pred = np.asarray(label_names, dtype=object)[top[:, 0]]
    known = np.isin(y_true, label_names)
    coverage = float(known.mean())
    y_true_known, y_pred_known = y_true[known], y_pred[known]
    labels_in_test = sorted(set(y_true_known))
    precision, recall, f1, support = precision_recall_fscore_support(
        y_true_known, y_pred_known, labels=labels_in_test, zero_division=0)
    per_class_path = out_dir / 'per_class_metrics.csv'
    with per_class_path.open('w', newline='') as stream:
        writer = csv.writer(stream)
        writer.writerow(('gloss', 'precision', 'recall', 'f1', 'support'))
        writer.writerows(zip(labels_in_test, precision, recall, f1, support))
    matrix = confusion_matrix(y_true_known, y_pred_known, labels=labels_in_test)
    np.savetxt(out_dir / 'confusion_matrix.csv', matrix, delimiter=',', fmt='%d')
    top5 = top[:, :min(5, len(label_names))]
    top1_accuracy = float(np.mean(y_pred_known == y_true_known)) if known.any() else 0.0
    top5_accuracy = float(np.mean([
        any(label_names[index] == target for index in ranks)
        for target, ranks in zip(y_true[known], top5[known])
    ])) if known.any() else 0.0
    result = {
        'samples': len(y_true), 'labels': len(label_names),
        'top1_accuracy': top1_accuracy, 'top5_accuracy': top5_accuracy,
        'top1_accuracy_all_test_samples': float(np.mean(y_pred == y_true)),
        'known_label_coverage': coverage,
        'macro_precision': float(np.mean(precision)) if len(precision) else 0.0,
        'macro_recall': float(np.mean(recall)) if len(recall) else 0.0,
        'macro_f1': float(np.mean(f1)) if len(f1) else 0.0,
    }
    return result


def main() -> None:
    args = parse_args()
    if args.epochs < 1 or args.batch_size < 1 or args.patience < 1:
        raise ValueError('epochs, batch-size and patience must be positive')
    args.output_dir.mkdir(parents=True, exist_ok=True)
    os.environ.setdefault('TF_DETERMINISTIC_OPS', '1')
    import tensorflow as tf

    random.seed(args.seed)
    np.random.seed(args.seed)
    tf.keras.utils.set_random_seed(args.seed)
    for gpu in tf.config.list_physical_devices('GPU'):
        tf.config.experimental.set_memory_growth(gpu, True)
    print(f'TensorFlow {tf.__version__}; GPU devices: {tf.config.list_physical_devices("GPU")}')
    records, vectors = parse_dataset(args.data_dir)
    split_counts = {s: sum(r['split'] == s for r in records)
                    for s in ('train', 'val', 'test')}
    with np.load(args.data_dir / 'landmarks_V3.npz', allow_pickle=True) as landmark_archive:
        total_feature_records = len(landmark_archive.files)
    class_counts = {
        split: {gloss: sum(r['split'] == split and r['gloss'] == gloss for r in records)
                for gloss in sorted({r['gloss'] for r in records if r['split'] == split})}
        for split in ('train', 'val', 'test')
    }
    print('Eligible samples by split:', split_counts)
    (args.output_dir / 'dataset_summary.json').write_text(json.dumps({
        'data_dir': str(args.data_dir), 'eligible_samples_by_split': split_counts,
        'classes_by_split': {split: len(counts) for split, counts in class_counts.items()},
        'class_counts': class_counts,
        'split_policy': 'Official split field from WLASL_parsed_data.json; signer-disjointness is not verified.',
        'feature_schema': 'signbridge.landmarks180.xyz.v1',
        'feature_shape': [DESIRED_FRAMES, TOTAL_LANDMARKS, COORDS],
        'normalization': 'Wrist-center and max-absolute-span normalize each hand per frame; linearly resample to 64 frames.',
        'discarded_samples': total_feature_records - len(records),
    }, indent=2) + '\n')
    cache = make_feature_cache(args.data_dir, args.output_dir, records, vectors,
                               args.max_samples_per_split)
    train_glosses = [r['gloss'] for r in records if r['split'] == 'train']
    model = build_model(tf)
    if args.initial_weights:
        if not args.initial_weights.is_file():
            raise FileNotFoundError(args.initial_weights)
        model.load_weights(args.initial_weights)
        print(f'Loaded initialization weights: {args.initial_weights}')

    def cosine_loss(y_true: Any, y_pred: Any) -> Any:
        return -tf.reduce_sum(y_true * y_pred, axis=-1)

    class CosineMetric(tf.keras.metrics.Metric):
        def __init__(self, name: str = 'cosine_sim', **kwargs: Any) -> None:
            super().__init__(name=name, **kwargs)
            self.total = self.add_weight(name='total', initializer='zeros')
            self.count = self.add_weight(name='count', initializer='zeros')

        def update_state(self, y_true: Any, y_pred: Any, sample_weight: Any = None) -> None:
            del sample_weight
            self.total.assign_add(tf.reduce_sum(tf.reduce_sum(y_true * y_pred, axis=-1)))
            self.count.assign_add(tf.cast(tf.shape(y_true)[0], tf.float32))

        def result(self) -> Any:
            return self.total / tf.maximum(self.count, 1.0)

        def reset_state(self) -> None:
            self.total.assign(0.0)
            self.count.assign(0.0)

    optimizer = tf.keras.optimizers.Adam(learning_rate=args.learning_rate)
    model.compile(optimizer=optimizer, loss=cosine_loss, metrics=[CosineMetric()])
    x_train = np.load(cache['train'][0], mmap_mode='r')
    y_train = np.load(cache['train'][0].with_name('train_y.npy'), mmap_mode='r')
    x_val = np.load(cache['val'][0], mmap_mode='r')
    y_val = np.load(cache['val'][0].with_name('val_y.npy'), mmap_mode='r')
    backup_dir = args.output_dir / 'training_backup'
    callbacks = [
        tf.keras.callbacks.BackupAndRestore(backup_dir=str(backup_dir)),
        tf.keras.callbacks.ModelCheckpoint(
            filepath=str(args.output_dir / 'best_signbridge.weights.h5'),
            monitor='val_cosine_sim', mode='max', save_best_only=True,
            save_weights_only=True, verbose=1),
        tf.keras.callbacks.CSVLogger(str(args.output_dir / 'training_log.csv'), append=True),
        tf.keras.callbacks.EarlyStopping(
            monitor='val_cosine_sim', mode='max', patience=args.patience,
            restore_best_weights=True, verbose=1),
        tf.keras.callbacks.ReduceLROnPlateau(
            monitor='val_loss', factor=0.5, patience=max(3, args.patience // 3),
            min_lr=1e-6, verbose=1),
    ]
    start = time.time()
    history = model.fit(
        x_train, y_train, validation_data=(x_val, y_val),
        epochs=args.epochs, batch_size=args.batch_size, shuffle=True,
        callbacks=callbacks, verbose=2)
    elapsed = time.time() - start
    try:
        import matplotlib.pyplot as plt
        figure, axes = plt.subplots(1, 2, figsize=(12, 4))
        for axis, metric, title in zip(axes, ('loss', 'cosine_sim'),
                                       ('Cosine loss', 'Cosine similarity')):
            axis.plot(history.history.get(metric, []), label='train')
            axis.plot(history.history.get(f'val_{metric}', []), label='validation')
            axis.set_title(title)
            axis.set_xlabel('Epoch')
            axis.legend()
            axis.grid(alpha=0.25)
        figure.tight_layout()
        figure.savefig(args.output_dir / 'training_curves.png', dpi=150)
        plt.close(figure)
    except ImportError:
        print('matplotlib unavailable; training_log.csv remains the curve source.')
    model.load_weights(args.output_dir / 'best_signbridge.weights.h5')
    test = evaluate(tf, model, cache['test'][0], cache['test'][1],
                    train_glosses, vectors, args.output_dir)
    test['training_seconds'] = elapsed
    test['epochs_completed'] = len(history.history.get('loss', []))
    (args.output_dir / 'evaluation.json').write_text(json.dumps(test, indent=2) + '\n')

    label_names = sorted(set(train_glosses))
    label_matrix = np.stack([vectors[name] / np.linalg.norm(vectors[name]) for name in label_names])
    (args.output_dir / 'labels.json').write_text(json.dumps({
        'names': label_names, 'vectors': label_matrix.tolist(),
    }, separators=(',', ':')) + '\n')
    export_model = build_model(tf, unroll=True)
    export_model.set_weights(model.get_weights())
    converter = tf.lite.TFLiteConverter.from_keras_model(export_model)
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
    converter.target_spec.supported_ops = [tf.lite.OpsSet.TFLITE_BUILTINS]
    tflite_bytes = converter.convert()
    model_path = args.output_dir / 'sign_bridge.tflite'
    model_path.write_bytes(tflite_bytes)
    interpreter = tf.lite.Interpreter(model_path=str(model_path))
    interpreter.allocate_tensors()
    input_info, output_info = interpreter.get_input_details()[0], interpreter.get_output_details()[0]
    if input_info['shape'].tolist() != [1, 64, 180, 3] or output_info['shape'].tolist() != [1, 300]:
        raise RuntimeError(f'Unexpected TFLite contract: {input_info["shape"]} -> {output_info["shape"]}')
    sample = np.asarray(x_val[:1], dtype=np.float32)
    expected = model(sample, training=False).numpy()
    interpreter.set_tensor(input_info['index'], sample)
    interpreter.invoke()
    actual = interpreter.get_tensor(output_info['index'])
    parity_error = float(np.max(np.abs(expected - actual)))
    latency_samples = []
    for _ in range(12):
        before = time.perf_counter()
        interpreter.set_tensor(input_info['index'], sample)
        interpreter.invoke()
        latency_samples.append((time.perf_counter() - before) * 1000)
    latency_samples = np.asarray(latency_samples[2:], dtype=np.float64)
    (args.output_dir / 'export_validation.json').write_text(json.dumps({
        'input_shape': input_info['shape'].tolist(),
        'output_shape': output_info['shape'].tolist(),
        'max_abs_error_on_validation_sample': parity_error,
        'tflite_bytes': len(tflite_bytes),
        'tflite_single_sample_latency_ms_median': float(np.median(latency_samples)),
        'tflite_single_sample_latency_ms_p95': float(np.percentile(latency_samples, 95)),
    }, indent=2) + '\n')
    if not np.isfinite(actual).all() or parity_error > 0.05:
        raise RuntimeError(f'TFLite parity validation failed: max absolute error {parity_error:.6f}')
    print('Test metrics:', json.dumps(test, indent=2))
    print(f'Validated TFLite export: {model_path} ({len(tflite_bytes):,} bytes; max parity error {parity_error:.6f})')


if __name__ == '__main__':
    main()
