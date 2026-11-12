# Implementation plan and progress

Updated 2026-11-05 (Asia/Karachi). Status reflects the release installed on the Pixel during this continuation.

| Milestone | Status | Deliverables / evidence | Remaining acceptance work |
|---|---|---|---|
| A. Baseline audit | PASS | [PROJECT_AUDIT.md](PROJECT_AUDIT.md); Git changes and pre-existing untracked 100-word export preserved. | Reconcile historical audit statements with future product decisions. |
| B. Data, licenses and Kaggle | PASS with license limits | [DATASET_AND_LICENSES.md](DATASET_AND_LICENSES.md), [KAGGLE_SETUP.md](KAGGLE_SETUP.md); authenticated private run used accessible inputs and saved official-split summary. | Establish checkpoint/derived-model redistribution rights; verify signer partitioning if data allows. |
| C. Training and evaluation | PASS for reproducible run/export | Standalone trainer, generated private notebook, 80-epoch Kaggle run, paired held-out comparison and TFLite export; [MODEL_EVALUATION.md](MODEL_EVALUATION.md). | Improve modest 351-class accuracy with signer-aware splits, data quality/imbalance analysis and expert review. |
| D. Live sign-to-text | PASS for app/device readiness; accuracy pending | Updated model/camera/Holistic pipeline installed on Pixel 6 Pro Android 16. Live view showed Holistic/model ready and landmarks. Sentence insertion now requires explicit acceptance to avoid silent false positives. | Perform controlled labeled signs; validate expected top-k, sentence editing, permission recovery and phone latency. |
| E. Text-to-sign | PARTIAL | Local GLB word clips play. Bundled CWASA/SiGML route displays the avatar and played `I take mug` on the Pixel; Rylo official page opens in the app. | Local paths have tiny coverage and are not ASL sentence translation. Rylo's public page says models are unavailable; generated online signs cannot be demonstrated. |
| F. App integration | PASS for current routes | Home includes sign camera, both local text-to-sign demos, online Rylo and Sign Test actions; SiGML route has a scope notice. | Full product UX depends on a genuinely available and licensed text-to-sign generator. |
| G. Regression and release | PASS for current ARM64 release | `flutter analyze` clean; ARM64 release built and installed on target Pixel; local SiGML example rendered and played. Prior 6 Flutter tests remain the latest unit-test run. See [TEST_REPORT.md](TEST_REPORT.md). | After this release, repeat final verification if code changes. |

## Local validation

```bash
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build apk --release --target-platform android-arm64
source ~/Desktop/pyvenv/bin/activate
python3 scripts/verify_tflite_model.py
```

For training, regenerate the notebook with `python3 scripts/build_kaggle_training_notebook.py` and follow [KAGGLE_SETUP.md](KAGGLE_SETUP.md). The MuteMotion 553-point features used in this run differ from the locally stored WLASL videos; do not treat the local videos as the features used for these metrics.

## Acceptance boundaries

- The installed recognizer is isolated-word ASL classification/retrieval; it does not recognize continuous signing or translate sentences.
- The local text animation is a small verified clip-name demo, not a linguistic translator.
- Rylo's public web interface currently reports that its latest models are research preview and unavailable. The in-app route cannot claim generated output until the service itself supplies it.
- The paired WLASL official split shows modest performance but does not establish signer-independent accuracy or real-world camera accuracy.
- Use [EVALUATOR_DEMO.md](EVALUATOR_DEMO.md) for a candid walkthrough and device preparation steps.
- Checkpoint dataset license is unknown. Keep local artifacts private and resolve rights before redistribution.
- Do not call the overall FYP complete until both pipeline scopes and their intended demonstration criteria are met with verified evidence.
