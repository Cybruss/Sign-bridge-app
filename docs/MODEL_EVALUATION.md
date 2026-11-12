# Model evaluation

Updated 2026-10-18 (Asia/Karachi).

## Integrated model and task

- Mobile model: `assets/ml/sign_bridge.tflite` (3,016,600 bytes; SHA-256 `6f6daaae1577be83476f039c75197f326e0ce4eee6cb3ff6b410ea8849995960`).
- Labels: `assets/ml/labels.json` (351 names and 300-D normalized FastText vectors; label ordering is unchanged from the previous app build).
- Input/output: `[1,64,180,3]` float landmarks → `[1,300]` normalized embedding, ranked by cosine similarity.
- Architecture: bidirectional GRU temporal encoder, attention pooling, embedding retrieval.
- Scope: isolated WLASL word recognition. This is not continuous ASL sentence translation.

## Reproducible Kaggle run

Private kernel `abdurrehmanzubair/sign-bridge-fyp-reproducible`, version 1, used the MuteMotion Kaggle features and initialized from the private `signbridge-checkpoint-v2` weights. Kaggle exposed two Tesla T4 GPUs; the trainer did not configure a mirrored strategy, so only GPU-backed training is claimed, not parallel use of both GPUs. It ran 80 epochs and restored the best validation checkpoint from epoch 69. `BackupAndRestore`, best-weight checkpointing, training log, curves, dataset summary, held-out evaluation, per-class metrics, confusion matrix, and TFLite export validation were produced.

The trainer accepts samples only when its numeric key maps to an annotation with an allowed gloss, an available 300-D gloss vector, an official `train`/`val`/`test` split, and a `[frames,553,3]` feature array. It retained 2,770 train, 748 validation, and 560 test examples across 351 labels. The archive contained 21,083 feature entries; 17,005 did not meet those combined eligibility filters. That count does not identify why each individual entry was excluded. The split is the dataset's official field; signer-disjointness is unverified.

### Held-out metrics

| Model/evaluation | Top-1 | Top-5 | Macro precision | Macro recall | Macro F1 |
|---|---:|---:|---:|---:|---:|
| Previously deployed app TFLite | 23.93% | 37.50% | 15.79% | 21.01% | 16.20% |
| Fine-tuned checkpoint, Keras evaluation | 26.25% | 40.89% | 19.53% | 23.15% | 19.41% |
| Fine-tuned exported TFLite, rerun locally | 26.79% | 40.89% | 20.09% | 23.72% | 20.03% |

Each result uses the same 560 cached held-out feature sequences, identical 351 labels in the same order, and true labels reconstructed from the saved target embeddings. The app TFLite and new TFLite were run with the same local XNNPACK interpreter loop; the original and fine-tuned Keras weights were also evaluated over the same samples. This shows a modest improvement on this split, not general ASL performance. Class imbalance, signer overlap, setup differences from phone inference, and small test counts limit conclusions. The fine-tuned TFLite is integrated because it improves all listed metrics over the previous app export under this paired comparison.

The detailed `evaluation.json`, `export_validation.json`, `dataset_summary.json`, `per_class_metrics.csv`, `confusion_matrix.csv`, `training_log.csv`, `training_curves.png`, initialization/fine-tuned checkpoint, and the previous app TFLite for rollback are saved locally under the gitignored `artifacts/kaggle_run_2026-10-18/`. No feature cache or dataset was copied into the repository. Checkpoint and fine-tuned model redistribution rights are not established; see the license note below.

## Export and mobile checks

- TFLite input/output: `[1,64,180,3]` → `[1,300]`.
- Maximum absolute Keras/TFLite parity error on a validation sample: `0.001083` (limit: `0.05`).
- Export size: 3,016,600 bytes.
- Kaggle CPU XNNPACK latency: median `9.65 ms`, p95 `9.94 ms` for one model invocation. This is not camera-to-text or phone latency.
- Local deterministic TFLite smoke test: three synthetic inputs returned finite unit-normalized embeddings; 351-label metadata validated.
- Pixel 6 Pro: release app successfully initialized the Holistic GPU processor and live landmarks after the model update. This does not prove a labeled real sign is correctly recognized.

## Reproduction

From the project root:

```bash
python3 scripts/build_kaggle_training_notebook.py
source ~/Desktop/pyvenv/bin/activate
python3 scripts/verify_tflite_model.py
python3 scripts/verify_tflite_model.py \
  --model /path/to/sign_bridge.tflite --labels /path/to/labels.json
```

For the real training run, follow [`KAGGLE_SETUP.md`](KAGGLE_SETUP.md). Kaggle kernel version 1 is private and remains available in the account. The original public notebook was not modified.

## Provenance and limits

The feature dataset is MuteMotion's WLASL-derived landmark export. WLASL source video use is governed by its Computational Use of Data Agreement. The initialization checkpoint dataset is private and declares an unknown license; its rights and any restrictions on derived weights have not been established. The integrated model is therefore retained as a local FYP artifact and should not be redistributed until provenance and rights are confirmed. The generated export is not a model trained from scratch; it fine-tunes the supplied checkpoint. No human-subject signer-stratified evaluation or confusion-driven remediation has been completed.

The previous project model report's top-k figures remain historical project-reported values; they differ from the paired evaluation performed above and are not used as the current metric.
