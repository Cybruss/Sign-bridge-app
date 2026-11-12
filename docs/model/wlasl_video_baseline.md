# WLASL video training run: completion report

## Result

The Kaggle kernel completed successfully on 2026-11-12. It extracted landmarks
from the locally available clips, trained on Kaggle GPUs, exported a TFLite
classifier, and passed the Keras-to-TFLite parity check. The 973-class model is
**not ready for app use**: evaluation on the official test split reached 3.63%
top-1 accuracy and 13.66% top-5 accuracy. Keep the app's existing embedding
recognizer unchanged.

Kaggle run: [Sign Bridge WLASL Video Pipeline](https://www.kaggle.com/code/abdurrehmanzubair/sign-bridge-wlasl-video-pipeline).
The exported model and reports are also included in
[`models/wlasl_video_baseline`](../../models/wlasl_video_baseline/README.md).

## Data and pipeline audit

The pipeline joined `nslt_2000.json`, `WLASL_v0.3.json`, and the attached video
files, preserving the official train/validation/test split. It found 6,578
available clips from 973 labels: 4,091 train, 1,330 validation, and 1,157 test.
There were 9 annotation join mismatches and 9,115 NSLT entries with no local
video file. Each available annotated interval was sampled to 64 frames; the
Sign Bridge Holistic task extracted 180 features per frame. Feature extraction
took about 5.34 hours on CPU because MediaPipe's GPU delegate could not
initialize EGL in the Kaggle notebook. TensorFlow saw two GPUs and used them
for classifier training.

The run stopped after 50 epochs (60 maximum) under early stopping. Training
accuracy reached 26.6%, but best validation accuracy was 5.04%. The test set
had 1,157 examples over 973 labels, with median support one; 793 labels had
only one test example. Official split use does not guarantee signer-disjoint
evaluation. These constraints make the run useful as an end-to-end pipeline
baseline, not as a dependable broad-vocabulary recognizer.

| Metric | Result |
| --- | ---: |
| Test examples | 1,157 |
| Labels | 973 |
| Top-1 accuracy | 3.63% (42/1,157) |
| Top-5 accuracy | 13.66% (158/1,157) |
| Macro precision | 1.84% |
| Macro recall | 3.63% |
| Macro F1 | 2.25% |
| TFLite input | `[1, 64, 180, 3]` |
| TFLite output | `[1, 973]` softmax |
| Max Keras/TFLite absolute difference | 0.00411 |

## App compatibility

The app currently expects a `[1, 64, 180, 3] → [1, 300]` embedding model and
ranks its output against 351 label vectors. This classifier instead emits 973
softmax scores. It is not wired into the app or packaged as an app asset; simply
replacing `assets/ml/sign_bridge.tflite` would fail the app's output-shape
check and its vector-scoring logic.

## What to improve next

1. Restore or source more of the WLASL videos. The current local intersection
   leaves too few examples per class; collecting a large vocabulary without
   enough examples per label does not create a useful model.
2. Select a smaller, explicitly reported vocabulary with adequate train,
   validation, and test support per label; enforce signer-disjoint evaluation
   where metadata allows.
3. Compare against a majority-class baseline and report per-class/support
   metrics before exporting an app candidate. Tune regularization and temporal
   sampling using validation only, then run the held-out test once.
4. Implement a separate softmax inference adapter only after the candidate
   meets an agreed evaluation target; keep user-visible predictions low-risk
   and easy to correct.

## Files

- `models/wlasl_video_baseline/sign_bridge_wlasl_video.tflite`: trained model.
- `models/wlasl_video_baseline/labels.json`: output-index to gloss mapping.
- `models/wlasl_video_baseline/evaluation.json`: aggregate held-out metrics.
- `models/wlasl_video_baseline/per_class_metrics.csv`: per-label results.
- `models/wlasl_video_baseline/training_log.csv`: 50-epoch history.
- `models/wlasl_video_baseline/tflite_validation.json`: export parity check.
- `models/wlasl_video_baseline/dataset_summary.json`: data availability and
  split audit.

Raw WLASL clips, the complete extracted feature cache, and TensorFlow resume
checkpoints remain in the completed Kaggle output and are not committed. The
model and selected evaluation artifacts listed above are copied into this
repository; no raw videos or feature sequences are included.
