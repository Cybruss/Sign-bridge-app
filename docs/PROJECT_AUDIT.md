# Sign Bridge project audit

Initial audit: 2026-10-17 (Asia/Karachi); follow-up verification: 2026-10-18.

## Repository and baseline

- The Flutter app is the nested Git repository `sign_bridge/` on branch `master`.
- Baseline `git status --short --branch`: branch clean except the existing untracked `assets/sign_bridge_export/` directory (100-word TFLite export, labels and H5 weights). It is preserved unchanged.
- Recent history contains the existing Evaluation 1 snapshot and subsequent GRU/TFLite, camera/Holistic and performance work. No history was rewritten.
- Flutter/Dart, Android Kotlin, MediaPipe Tasks Vision, `camera`, `tflite_flutter`, WebView and a 3D avatar renderer are used. There are no training scripts or notebooks tracked in this repo; the only tracked Python artifact is `kaggle_flex_free_export.py`.

## Components and status

| Component | Status | Evidence and caveats |
|---|---|---|
| Flutter application shell and navigation | Partial | `lib/main.dart`, `lib/home_screen.dart`; the main actions are reachable, but there are overlapping text-to-sign implementations and debug/test routes exposed from Home. |
| Live sign-to-text camera path | Implemented, device verification pending | Flutter camera stream + native Android Holistic task processor + rolling per-sign frame buffer + Dart TFLite interpreter. Android-only native bridge means iOS/web cannot use this pipeline as currently written. |
| Landmark schema | Implemented but training provenance not fully reproducible | 180×3 per frame: right hand (21), left hand (21), six upper-body pose points (11–16), 132 selected face points; 64-frame interpolation; wrist-centered hand normalization. Missing points are zero-filled. Face indices 468/473 may exceed the 468-point mobile mesh and therefore become zeros. |
| Recognition model | Artifact loads/inference verification pending | `assets/ml/sign_bridge.tflite` and `assets/ml/labels.json` describe an embedding retrieval model: `[1,64,180,3] → [1,300]`, 351 names and 351 300-D vectors. The report at `docs/model/Sign_Bridge_Model_Report.md` records claimed test Top-1 24.82%, Top-3 35.71%, Top-5 38.93%; raw logs/checkpoint and an independently reproduced evaluation are not in this repository. The on-device cosine score is a similarity, not a calibrated probability. |
| Training/evaluation | Missing from tracked source | A read-only Kaggle pull of `abdurrehmanzubair/sign-bridge` succeeded. Its notebook uses MuteMotion-derived `landmarks_V3.npz`, `labels.npz`, parsed annotation and `filtered_labels.txt`, plus a checkpoint/log dataset. Those inputs and the training checkpoint are not present locally. The Kaggle notebook has no saved cell outputs in the pulled copy. |
| Local WLASL material | Present, not yet matched to reported model | `/media/maan/New Volume/wlasl-processed/` has WLASL v0.3/nslt JSON, `missing.txt`, vocabulary and 11,980 MP4 files. NSLT split files report 2,038/5,118/13,174/21,095 annotations and 100/300/1,000/2,000 labels respectively. This is not evidence that those videos/features trained the checked-in 351-class model. |
| Text-to-sign | Partial prototype; natural-language translation missing | `AvatarPipelineScreen` maps a handful of English words to animation-name strings on a GLB avatar. The mapping does not provide ASL grammar or establish that matching sign animation clips exist. `TextToSignScreen` selects sign blocks from three bundled SiGML examples, but its required WebView/lexicon files are not declared as Flutter assets, and the bundled examples identify NGT content. Do not represent either path as unrestricted ASL translation. |
| Existing tests | Minimal and baseline pending | One unit test file for preprocessing/formatting and a starter widget smoke test. No camera, native bridge, model parity, training, or genuine text-to-sign integration tests. |

## Important implementation and deployment risks

1. The training artifacts and feature extraction implementation used for the published 351-class report are not fully reproducible from tracked files. The Kaggle notebook references a MuteMotion feature dataset and a separate checkpoint/log dataset. No model re-training is warranted until these inputs and provenance are verified.
2. WLASL is licensed under its Computational Use of Data Agreement (C-UDA). Local presence is not proof that redistribution or commercial use is allowed. See [DATASET_AND_LICENSES.md](DATASET_AND_LICENSES.md).
3. The current live segmenter predicts when the hand disappears after an active segment. It appends one word per segment above a cosine threshold; there is no sentence editor or explicit correction control at baseline.
4. The native camera pipeline is Android-only and camera orientation/front-camera mirroring require physical-device coverage. No real device/emulator result is inferred from source code.
5. Existing 100-word export files are untracked and may be ongoing user work. They are neither deleted nor silently installed over the tracked 351-word model.
6. The JAS assets include mixed licenses, including a visible CC BY-NC-ND notice and GPL code. Confirm redistribution/modification rights before packaging or publishing them.

## Kaggle inspection

- Supplied Python environment: `~/Desktop/pyvenv`; Python 3.12.3, Kaggle CLI 2.2.4, TensorFlow, MediaPipe, NumPy, OpenCV and scikit-learn are importable.
- `~/.kaggle/access_token` exists with mode `0600`; the secret was not displayed or copied.
- `kaggle kernels list -s sign-bridge --page-size 20` found `abdurrehmanzubair/sign-bridge` (last reported run 2026-08-03).
- `kaggle kernels pull abdurrehmanzubair/sign-bridge -p /tmp/sign_bridge_kaggle_audit` completed. This was read-only; no notebook run, edit, upload, or remote resource mutation was performed.
- CLI 2.2.4 does not support `kaggle auth status`; the attempted command is not a valid subcommand. A read-only `kaggle kernels list` request succeeded, which verifies authenticated API access without revealing the token.

## Prioritized plan

1. Preserve current artifacts and baseline; write reproducibility, dataset/license, Kaggle, text-to-sign, evaluation and test reports.
2. Run static analysis, unit tests, native Android build and direct TFLite input/output smoke validation; record actual exit status.
3. Improve live recognition sentence correction/editability and honest uncertainty/status messaging without changing the model contract.
4. Clearly scope text-to-sign to verified behavior; prevent the GLB word mapping from claiming language translation and document a lawful future integration boundary.
5. Add reproducible WLASL feature extraction/training only after reconciling the local NSLT source with the Kaggle MuteMotion features and validating licensing, splits, and exact feature parity.
6. Complete physical Android camera/model/latency verification and genuine visual text-to-sign verification on the target runtime.

## Current completion state

## Follow-up verification (2026-10-18)

- Added a private reproducible Kaggle notebook and standalone trainer, then ran version 1 to 80 epochs in a GPU runtime where two Tesla T4 devices were visible (the trainer did not set up mirrored multi-GPU execution). The run evaluated 2,770 train / 748 validation / 560 official test examples across 351 labels and emitted logs, curves, per-class metrics, a confusion matrix and TFLite export.
- Compared the previous app TFLite with the new export on the same held-out test feature sequences. Top-1 moved from 23.93% to 26.79%, top-5 from 37.50% to 40.89%, and macro-F1 from 16.20% to 20.03%. The new model was installed in `assets/ml/sign_bridge.tflite`; the original app model was saved to a temporary path outside the repository. New run evidence is in [MODEL_EVALUATION.md](MODEL_EVALUATION.md) and the ignored `artifacts/kaggle_run_2026-10-18/` folder.
- Rebuilt and installed the Android ARM64 release on a Pixel 6 Pro. The updated TFLite interpreter, camera/Holistic path and model-ready state were confirmed on device. A controlled labeled sign prediction and phone end-to-end latency have not been validated.
- Fixed and verified local avatar asset loading; “I want pizza” plays the named `ME`, `WANT`, `PIZZA` clips. Expert review of the actual signs is outstanding.
- Added the Rylo online WebView route and opened it on device. The upstream page states that public sign models are in research preview and unavailable; no generated sign translation is currently available to demonstrate.
- Flutter formatter, analyzer, six tests, Android debug/release builds and local TFLite smoke test pass. The pre-existing untracked 100-word export remains untouched.

**Overall status: IN PROGRESS.** The isolated-word camera pipeline, reproducible training/export workflow, and local clip demo have been materially advanced and verified within the stated scope. Full continuous sign-to-text, genuine unrestricted text-to-sign, labeled real-user accuracy, signer-disjoint evaluation, and redistribution rights remain unresolved. See [IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md) and [TEST_REPORT.md](TEST_REPORT.md).
