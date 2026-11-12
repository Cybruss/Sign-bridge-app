# WLASL video baseline (experimental)

This is the TFLite output from the private Kaggle run at
`abdurrehmanzubair/sign-bridge-wlasl-video-pipeline`. It is a reproducible
research artifact, not the recognizer bundled into the app.

## Model contract

- Input: `[1, 64, 180, 3]` float32 Holistic landmark sequence.
- Output: `[1, 973]` softmax probabilities, mapped by `labels.json`.
- Task: isolated WLASL gloss classification, not continuous sign-language
  translation.
- `tflite_validation.json` records the export parity check against the Keras
  model: top-1 matched, maximum absolute difference `0.00411`.

The Android app's current recognizer emits a 300-dimensional embedding and
ranks 351 label vectors. Its runtime checks for `[1, 300]`; this model emits
973 class probabilities and cannot replace that app asset without a separate
inference implementation and UI integration.

## Evaluation

The official WLASL2000 split yielded 6,578 available clips across 973 labels:
4,091 train, 1,330 validation, and 1,157 test. 9,115 annotation entries had no
matching local video. Most test labels have only one clip (median support 1).
The model trained for 50 epochs and reached 26.6% training accuracy, 5.0% best
validation accuracy, and 3.63% test top-1 accuracy (42/1,157). Test top-5 was
13.66%; macro F1 was 2.25%. The gap indicates severe overfitting and inadequate
examples per label. Do not present this as a reliable general-purpose signer.

See `../../docs/model/wlasl_video_baseline.md` for the run audit, limitations,
and next data/training steps. `training_log.csv` and `per_class_metrics.csv`
are included for analysis. Raw videos, extracted feature chunks, and resume
checkpoints remain in the completed Kaggle output; they are not stored in this
repository.

## Dataset attribution

The model was trained from WLASL under its Computational Use of Data Agreement
(C-UDA). Review the [official WLASL terms](https://github.com/dxli94/WLASL)
before reuse. Cite Li et al., “Word-level Deep Sign Language Recognition from
Video: A New Large-scale Dataset and Methods Comparison,” WACV 2020.
