# Sign Bridge

Sign Bridge is a Flutter prototype for **isolated ASL word recognition** and a small **word-animation demo**. It does not perform continuous ASL sentence recognition or unrestricted English-to-ASL translation.

## Current app paths

- **Sign to Text (Android):** camera frames → native MediaPipe Holistic → 180 selected landmarks per frame → 64-frame sequence preprocessing → local TFLite embedding model → nearest labels → user-accepted editable sentence text. The camera path is currently Android-only. Similarity is not a calibrated probability; predictions require a deliberate tap before entering the sentence.
- **Text to Sign:** plays a small set of avatar clips by matching words to named GLB animations. It reports unsupported words. This is a word-by-word animation demo; it does not translate English grammar into ASL grammar. The individual clips still require sign-language expert review.
- **Text to Sign · SiGML examples (Android):** locally plays a few bundled NGT SiGML examples on a CWASA avatar. It matches known lexicon entries; it is not full English-to-sign translation or ASL.
- **Rylo Translate · online:** opens Rylo's hosted text-to-sign page in a WebView. It requires internet, and the public page currently reports that its latest Sign models are unavailable.
- **Sign Test:** development screen for model inference.

## Local setup

Requirements: Flutter/Dart matching `pubspec.yaml` (Dart SDK `^3.10.1`), Android SDK for Android builds, and an Android camera device/emulator for live camera validation.

```bash
flutter pub get
flutter run
```

To build an Android debug APK:

```bash
flutter build apk --debug
```

To create a release APK for a teammate to install directly:

```bash
flutter build apk --release
```

Share `build/app/outputs/flutter-apk/app-release.apk` through a private team file share; it is generated locally and is not committed to Git. On Android, allow installation from the file manager used to open the APK, then install it. For a USB or wireless-debugging device, use `adb install -r build/app/outputs/flutter-apk/app-release.apk`. The APK is large because it bundles the on-device model and avatar assets. Android may show the standard unknown-source installation prompt.

### Teammate quick start

1. Install Flutter and Android Studio/Android SDK, then clone this repository.
2. In the repository root, run `flutter pub get`.
3. Connect an Android phone with USB debugging enabled (or use an emulator), then run `flutter run`.
4. Grant camera permission when prompted. On the home screen, choose **Sign to text** and wait for the camera/model status to become ready.
5. To rehearse with known examples, download WLASL separately under its C-UDA terms and build a local label-to-video reference CSV (see below). A reference clip is a rehearsal aid; it does not establish app accuracy.

For a signed APK, install from a team file share or build it locally with the commands above. Do not copy Kaggle credentials, checkpoints, or raw videos into the repository.

The Android permission prompt must be accepted for camera recognition. Training uses a separate Python/Kaggle workflow; Python credentials are never part of the mobile app.

## Development checks

```bash
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build apk --debug
```

See [docs/TEST_REPORT.md](docs/TEST_REPORT.md) for results from the current audit and its limitations.

## Model and data

The tracked TFLite recognizer expects `[1, 64, 180, 3]` and emits a 300-dimensional embedding ranked against the 351 vectors in `assets/ml/labels.json`. Do not replace this vocabulary or model with the separate untracked 100-word export unless its provenance and compatibility are validated.

The dataset and licensing record is in [docs/DATASET_AND_LICENSES.md](docs/DATASET_AND_LICENSES.md). The current model's prior evaluation report is [docs/model/Sign_Bridge_Model_Report.md](docs/model/Sign_Bridge_Model_Report.md); independent evaluation status and metric evidence are in [docs/MODEL_EVALUATION.md](docs/MODEL_EVALUATION.md).

The app provides **isolated-word** recognition. To learn what a label's example looks like before rehearsing, run the local WLASL clip-index tool after obtaining the dataset:

```bash
python3 scripts/build_wlasl_reference_index.py \
  --dataset "/path/to/wlasl-processed" \
  --output "$HOME/wlasl_rehearsal.csv"
```

Open the CSV in a spreadsheet and play `video_path` in a media player from the dataset directory. It lists at most one locally available reference per app label. The script indexes files only; it does not copy or redistribute videos. Ask a fluent ASL signer to confirm the sign before treating a clip or recognition result as ground truth.

## Text to sign

The home screen exposes the local GLB word demo, the local SiGML examples, and a **Rylo Translate · online** fallback. The SiGML screen serves its bundled player files from a loopback HTTP server and plays the sample `I take mug` phrase on the Pixel 6 Pro. The online route opens the official Rylo translation page inside the app; it requires internet and sends text entered there to Rylo. The public page currently states that its latest Sign models are not available to the public, so this is an entry point to the service, not a guarantee of generated sign output. See [docs/TEXT_TO_SIGN.md](docs/TEXT_TO_SIGN.md) and [docs/EVALUATOR_DEMO.md](docs/EVALUATOR_DEMO.md).

## Kaggle workflow

The reproducible trainer is [scripts/train_sign_bridge.py](scripts/train_sign_bridge.py); the self-contained GPU notebook source and metadata are generated in `kaggle/sign_bridge_fyp_reproducible/` by `python3 scripts/build_kaggle_training_notebook.py`. It expects the attached MuteMotion feature dataset and private checkpoint dataset described in [docs/KAGGLE_SETUP.md](docs/KAGGLE_SETUP.md), preserves the app's `[1,64,180,3] → [1,300]` model contract, writes held-out metrics, and validates the TFLite export. Checkpoint/dataset license and signer-disjoint evaluation limitations still apply.

## Project status

The reproducible Kaggle workflow completed an 80-epoch fine-tune and the improved 351-label TFLite export is integrated. Paired official-split testing improved top-1 from 23.93% to 26.79% and macro-F1 from 16.20% to 20.03%. The updated release was installed on a Pixel 6 Pro; camera/Holistic/model startup, manual sentence acceptance, SiGML playback, and the local avatar's supported word clips were checked. A controlled labeled sign attempt remains necessary to verify real-user recognition. The Rylo route opens, but its page currently says the public generation models are unavailable. This project is **not 100% complete** and does not yet provide unrestricted sentence-level translation in either direction. See [docs/MODEL_EVALUATION.md](docs/MODEL_EVALUATION.md), [docs/TEST_REPORT.md](docs/TEST_REPORT.md), and [docs/TEXT_TO_SIGN.md](docs/TEXT_TO_SIGN.md).
